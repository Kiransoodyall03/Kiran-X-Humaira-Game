@tool
class_name PainterlyEffect
extends CompositorEffect
## Painterly post-process: a generalized Kuwahara filter (shaders/painterly_kuwahara.glsl)
## that flattens the image into soft brush-stroke patches while keeping edges, plus
## optional ink-like edge darkening and a saturation push.
##
## The tuned instance lives in data/rendering/painterly.tres and is used by the Compositor
## on the heroine's Camera3D (ThirdPersonCamera.painterly_enabled turns it off per camera).
## Every parameter can be changed live in the inspector (the script is @tool, so the editor
## viewport shows it too) and is clamped to a safe range.
##
## Forward+ only. On Mobile (its color buffer is not a storage image), Compatibility or the
## headless dummy renderer it does nothing and never errors: see is_supported().
##
## GPU cost is per pixel and grows with radius^2. Measure it windowed with
## tests/perf/painterly_gpu_probe.gd before raising the radius.

const SHADER_PATH: String = "res://shaders/painterly_kuwahara.glsl"
const CONTEXT: StringName = &"painterly"
const SCRATCH: StringName = &"scratch"
const GROUP_SIZE: int = 8

const RADIUS_MIN: int = 1
const RADIUS_MAX: int = 6 # keep equal to MAX_RADIUS in the shader
const SHARPNESS_MIN: float = 1.0
const SHARPNESS_MAX: float = 18.0
const HARDNESS_MIN: float = 1.0
const HARDNESS_MAX: float = 100.0
const SATURATION_MAX: float = 2.0

## Kernel radius in pixels. Bigger = broader brush strokes, but GPU cost grows with
## radius^2 (about 3 r^2 samples per pixel). Measured at 1080p on an RTX 3050 Laptop
## (Forward+): r1 1.2 ms, r2 1.8 ms, r3 3.1 ms, r5 6.4 ms, r6 8.5 ms. Keep it at 2 (the
## shipped value) for a 60 fps budget; 3+ is for look tests. Check with the GPU probe.
@export_range(RADIUS_MIN, RADIUS_MAX, 1, "suffix:px") var radius: int = 2:
	set(value):
		radius = clampi(value, RADIUS_MIN, RADIUS_MAX)
## How strongly the flattest neighbouring patch wins. Low = soft and blurry, high = crisp
## stroke edges.
@export_range(SHARPNESS_MIN, SHARPNESS_MAX, 0.1) var sharpness: float = 8.0:
	set(value):
		sharpness = clampf(value, SHARPNESS_MIN, SHARPNESS_MAX)
## How much colour variation counts as "busy". Higher = more detail gets smoothed away.
@export_range(HARDNESS_MIN, HARDNESS_MAX, 0.5) var hardness: float = 8.0:
	set(value):
		hardness = clampf(value, HARDNESS_MIN, HARDNESS_MAX)
## Mix with the unfiltered image: 0 = off, 1 = fully painted.
@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(value):
		strength = clampf(value, 0.0, 1.0)
## Darkens strong edges like an ink outline. 0 = off.
@export_range(0.0, 1.0, 0.01) var edge_darkening: float = 0.3:
	set(value):
		edge_darkening = clampf(value, 0.0, 1.0)
## Brightness contrast an edge needs before it darkens. Raise it to outline only silhouettes.
@export_range(0.0, 1.0, 0.01) var edge_threshold: float = 0.15:
	set(value):
		edge_threshold = clampf(value, 0.0, 1.0)
## 1 = unchanged, below 1 desaturates, above 1 pushes colour.
@export_range(0.0, SATURATION_MAX, 0.01) var saturation: float = 1.1:
	set(value):
		saturation = clampf(value, 0.0, SATURATION_MAX)

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
## Set after a failed shader setup so the error is reported once, not every frame.
var _init_failed: bool = false
## Set when the scene color buffer turns out not to be a storage image.
var _unusable_target: bool = false

## Test hook: SUPPORT_AUTO detects the renderer; smoke tests set SUPPORT_FORCE_ON/OFF so
## the camera toggle can be checked on the headless renderer. Never set it in game code.
const SUPPORT_AUTO: int = -1
const SUPPORT_FORCE_OFF: int = 0
const SUPPORT_FORCE_ON: int = 1
static var support_override: int = SUPPORT_AUTO


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null and _shader.is_valid():
		_rd.free_rid(_shader) # frees the dependent pipeline too


## True when the running renderer can execute this effect: Forward+ only (its scene color
## is a storage image). False on Mobile, Compatibility and the headless dummy renderer.
static func is_supported() -> bool:
	if support_override != SUPPORT_AUTO:
		return support_override == SUPPORT_FORCE_ON
	return is_supported_on(RenderingServer.get_current_rendering_method(), RenderingServer.get_rendering_device() != null)


## Pure form of is_supported() for tests: the renderer name and whether it has a RenderingDevice.
static func is_supported_on(rendering_method: String, has_rendering_device: bool) -> bool:
	return has_rendering_device and rendering_method == "forward_plus"


## The push-constant block the shader reads (12 floats, 16-byte aligned).
## `mode` 0 = filter, 1 = copy back.
func build_push_constants(size: Vector2i, mode: int) -> PackedFloat32Array:
	return PackedFloat32Array([
		float(size.x), float(size.y), float(radius), sharpness,
		hardness, strength, edge_darkening, edge_threshold,
		saturation, float(mode), 0.0, 0.0,
	])


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or strength <= 0.0 or _unusable_target:
		return
	if not _ensure_pipeline():
		return
	var buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size: Vector2i = buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var view_count: int = buffers.get_view_count()
	_ensure_scratch(buffers, size, view_count)

	var groups: Vector2i = Vector2i(ceili(size.x / float(GROUP_SIZE)), ceili(size.y / float(GROUP_SIZE)))
	var filter_bytes: PackedByteArray = build_push_constants(size, 0).to_byte_array()
	var copy_bytes: PackedByteArray = build_push_constants(size, 1).to_byte_array()
	for view: int in view_count:
		var color: RID = buffers.get_color_layer(view)
		if not _is_storage_image(color):
			return
		var scratch: RID = buffers.get_texture_slice(CONTEXT, SCRATCH, view, 0, 1, 1)
		_dispatch(color, scratch, filter_bytes, groups)
		_dispatch(scratch, color, copy_bytes, groups)


func _dispatch(src: RID, dst: RID, push: PackedByteArray, groups: Vector2i) -> void:
	var src_u: RDUniform = RDUniform.new()
	src_u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	src_u.binding = 0
	src_u.add_id(src)
	var dst_u: RDUniform = RDUniform.new()
	dst_u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	dst_u.binding = 1
	dst_u.add_id(dst)
	var uniform_set: RID = UniformSetCacheRD.get_cache(_shader, 0, [src_u, dst_u])
	var list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
	_rd.compute_list_end()


## False (warned once, then the effect stays off) when the color buffer is not a storage image.
func _is_storage_image(texture: RID) -> bool:
	var format: RDTextureFormat = _rd.texture_get_format(texture)
	if format != null and (format.usage_bits & RenderingDevice.TEXTURE_USAGE_STORAGE_BIT) != 0:
		return true
	_unusable_target = true
	push_warning("PainterlyEffect: the scene color buffer is not a storage image on this renderer; effect disabled.")
	return false


## Builds the compute pipeline on first use (render thread). False if it can't run here.
func _ensure_pipeline() -> bool:
	if _pipeline.is_valid():
		return true
	if _init_failed:
		return false
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		_init_failed = true
		return false
	var file: RDShaderFile = load(SHADER_PATH) as RDShaderFile
	var spirv: RDShaderSPIRV = file.get_spirv() if file != null else null
	if spirv == null or not spirv.compile_error_compute.is_empty():
		_init_failed = true
		push_error("PainterlyEffect: can't compile %s: %s" % [SHADER_PATH, spirv.compile_error_compute if spirv != null else "missing"])
		return false
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		_init_failed = true
		return false
	_pipeline = _rd.compute_pipeline_create(_shader)
	return _pipeline.is_valid()


## (Re)creates the per-viewport scratch image when missing or resized.
func _ensure_scratch(buffers: RenderSceneBuffersRD, size: Vector2i, view_count: int) -> void:
	if buffers.has_texture(CONTEXT, SCRATCH):
		var current: Vector2i = buffers.get_texture_slice_size(CONTEXT, SCRATCH, 0)
		if current == size:
			return
		buffers.clear_context(CONTEXT)
	var usage: int = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	buffers.create_texture(CONTEXT, SCRATCH, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage,
			RenderingDevice.TEXTURE_SAMPLES_1, size, view_count, 1, true, false)
