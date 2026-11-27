extends SceneTree
## Painterly post-process smoke test. Checks that data/rendering/painterly.tres loads as a
## PainterlyEffect with in-range values, that every parameter clamps, that the push
## constants match the Params block parsed from the .glsl source (and RADIUS_MAX matches
## the shader's MAX_RADIUS), that the shader's import is not stale and compiles, that the
## heroine's camera (in the sandbox and in Zone01) carries a Compositor using the tuned
## effect, that the camera drops it on a renderer that can't run it (headless), that
## painterly_enabled off/on removes and restores it (support forced on for that check), and
## that the sandbox runs without any engine/script error.
## Headless can't render, so this can't see GPU cost or the picture: for those run the
## windowed probe tests/perf/painterly_gpu_probe.gd.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/painterly_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const EFFECT_PATH: String = "res://data/rendering/painterly.tres"
const HEROINE: String = "res://scenes/actors/heroine.tscn"
const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
const ZONE: String = "res://scenes/levels/zone01/Zone01.tscn"
const CAMERA_PATH: NodePath = ^"CameraRig/PitchPivot/Camera3D"
const RUN_FRAMES: int = 120
const MAX_RUN_FRAMES: int = 2000

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false


func _initialize() -> void:
	OS.add_logger(_errors)
	physics_frame.connect(_watchdog)
	_run.call_deferred()


func _run() -> void:
	var effect: PainterlyEffect = load(EFFECT_PATH) as PainterlyEffect
	_expect(effect != null, "painterly.tres loads as a PainterlyEffect")
	if effect == null:
		_finish()
		return
	_check_tuned_values(effect)
	_check_clamping()
	_check_push_constants(effect)
	_check_shader_source(effect)
	_check_import_fresh()
	_check_shader()
	_check_scene_wiring(HEROINE, effect, "heroine.tscn")
	_check_zone_wiring(effect)
	await _check_sandbox_run(effect)
	_finish()


func _check_tuned_values(e: PainterlyEffect) -> void:
	_expect(e.enabled, "effect is enabled in the data file")
	_expect(e.effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT,
			"effect runs post-transparent (before tonemapping)")
	_expect(e.radius >= PainterlyEffect.RADIUS_MIN and e.radius <= PainterlyEffect.RADIUS_MAX, "radius %d in range" % e.radius)
	_expect(e.sharpness >= PainterlyEffect.SHARPNESS_MIN and e.sharpness <= PainterlyEffect.SHARPNESS_MAX, "sharpness %.1f in range" % e.sharpness)
	_expect(e.hardness >= PainterlyEffect.HARDNESS_MIN and e.hardness <= PainterlyEffect.HARDNESS_MAX, "hardness %.1f in range" % e.hardness)
	_expect(e.strength > 0.0 and e.strength <= 1.0, "strength %.2f is on and in range" % e.strength)
	_expect(e.edge_darkening >= 0.0 and e.edge_darkening <= 1.0, "edge darkening %.2f in range" % e.edge_darkening)
	_expect(e.saturation >= 0.0 and e.saturation <= PainterlyEffect.SATURATION_MAX, "saturation %.2f in range" % e.saturation)


func _check_clamping() -> void:
	var e: PainterlyEffect = PainterlyEffect.new()
	e.radius = 0
	_expect(e.radius == PainterlyEffect.RADIUS_MIN, "radius clamps up to %d (got %d)" % [PainterlyEffect.RADIUS_MIN, e.radius])
	e.radius = 999
	_expect(e.radius == PainterlyEffect.RADIUS_MAX, "radius clamps down to %d (got %d)" % [PainterlyEffect.RADIUS_MAX, e.radius])
	e.sharpness = -3.0
	_expect(is_equal_approx(e.sharpness, PainterlyEffect.SHARPNESS_MIN), "sharpness clamps up")
	e.sharpness = 100.0
	_expect(is_equal_approx(e.sharpness, PainterlyEffect.SHARPNESS_MAX), "sharpness clamps down")
	e.hardness = 0.0
	_expect(is_equal_approx(e.hardness, PainterlyEffect.HARDNESS_MIN), "hardness clamps up")
	e.hardness = 1000.0
	_expect(is_equal_approx(e.hardness, PainterlyEffect.HARDNESS_MAX), "hardness clamps down")
	e.strength = -1.0
	_expect(is_zero_approx(e.strength), "strength clamps to 0")
	e.strength = 2.0
	_expect(is_equal_approx(e.strength, 1.0), "strength clamps to 1")
	e.edge_darkening = 5.0
	_expect(is_equal_approx(e.edge_darkening, 1.0), "edge darkening clamps to 1")
	e.edge_threshold = -0.5
	_expect(is_zero_approx(e.edge_threshold), "edge threshold clamps to 0")
	e.saturation = 9.0
	_expect(is_equal_approx(e.saturation, PainterlyEffect.SATURATION_MAX), "saturation clamps to %.1f" % PainterlyEffect.SATURATION_MAX)
	e.saturation = -1.0
	_expect(is_zero_approx(e.saturation), "saturation clamps to 0")


func _check_push_constants(e: PainterlyEffect) -> void:
	var push: PackedFloat32Array = e.build_push_constants(Vector2i(640, 360), 0)
	_expect(push.to_byte_array().size() == 48, "push constants are 48 bytes (12 floats, 16-byte aligned)")
	_expect(push[0] == 640.0 and push[1] == 360.0, "push constants start with the image size")
	_expect(push[2] == float(e.radius) and is_equal_approx(push[5], e.strength) and is_equal_approx(push[8], e.saturation), "push constants carry the tuned values")
	_expect(e.build_push_constants(Vector2i(1, 1), 1)[9] == 1.0, "copy pass sets mode 1")


## Parses the push-constant block and MAX_RADIUS from the .glsl so a change on either side
## that the other doesn't follow fails here, not as GPU errors in a windowed run.
func _check_shader_source(e: PainterlyEffect) -> void:
	var source: String = FileAccess.get_file_as_string(PainterlyEffect.SHADER_PATH)
	_expect(not source.is_empty(), "shader source is readable")
	var start: int = source.find("uniform Params")
	var open: int = source.find("{", start)
	var close: int = source.find("} params;", open)
	_expect(start >= 0 and open > start and close > open, "shader has a Params push-constant block")
	if start < 0 or open < 0 or close < 0:
		return
	var sizes: Dictionary[String, int] = {"float": 4, "int": 4, "uint": 4, "vec2": 8, "vec3": 12, "vec4": 16}
	var bytes: int = 0
	var unknown: Array[String] = []
	for raw: String in source.substr(open + 1, close - open - 1).split("\n"):
		var line: String = raw.split("//")[0].strip_edges()
		if line.is_empty():
			continue
		var type_name: String = line.split(" ", false)[0]
		if not sizes.has(type_name):
			unknown.append(type_name)
			continue
		# std430 alignment: scalars 4, vec2 8, vec3/vec4 16.
		var align: int = 4 if sizes[type_name] == 4 else (8 if type_name == "vec2" else 16)
		bytes = ceili(bytes / float(align)) * align + sizes[type_name]
	_expect(unknown.is_empty(), "Params block uses only known types (unknown: %s)" % [unknown])
	var push_bytes: int = e.build_push_constants(Vector2i(8, 8), 0).to_byte_array().size()
	_expect(bytes == push_bytes, "shader Params block is %d bytes, script pushes %d" % [bytes, push_bytes])
	var regex: RegEx = RegEx.create_from_string("#define\\s+MAX_RADIUS\\s+(\\d+)")
	var found: RegExMatch = regex.search(source)
	var shader_max: int = found.get_string(1).to_int() if found != null else -1
	_expect(shader_max == PainterlyEffect.RADIUS_MAX,
			"shader MAX_RADIUS %d == PainterlyEffect.RADIUS_MAX %d" % [shader_max, PainterlyEffect.RADIUS_MAX])


## --script runs never reimport, so after an outside edit to the .glsl the imported SPIR-V
## would be stale and _check_shader would test the old shader.
func _check_import_fresh() -> void:
	var import_cfg: ConfigFile = ConfigFile.new()
	var err: Error = import_cfg.load(PainterlyEffect.SHADER_PATH + ".import")
	_expect(err == OK, "shader .import file loads")
	if err != OK:
		return
	var imported: String = str(import_cfg.get_value("remap", "path", ""))
	var md5_text: String = FileAccess.get_file_as_string(imported.get_basename() + ".md5")
	var regex: RegEx = RegEx.create_from_string("source_md5=\"([0-9a-f]+)\"")
	var found: RegExMatch = regex.search(md5_text)
	var imported_md5: String = found.get_string(1) if found != null else "<missing>"
	var source_md5: String = FileAccess.get_md5(PainterlyEffect.SHADER_PATH)
	_expect(imported_md5 == source_md5,
			"shader import is fresh (if stale: run godot --headless --path . --import, then rerun)")


func _check_shader() -> void:
	var file: RDShaderFile = load(PainterlyEffect.SHADER_PATH) as RDShaderFile
	_expect(file != null, "compute shader imports as an RDShaderFile")
	if file == null:
		return
	var spirv: RDShaderSPIRV = file.get_spirv()
	_expect(spirv != null and spirv.compile_error_compute.is_empty() and not spirv.bytecode_compute.is_empty(),
			"compute shader compiles (%s)" % (spirv.compile_error_compute if spirv != null else "no SPIR-V"))


## Before _ready, the scene's camera holds the Compositor from the file.
func _check_scene_wiring(path: String, effect: PainterlyEffect, label: String) -> void:
	var heroine: Node = (load(path) as PackedScene).instantiate()
	_check_camera_compositor(heroine, effect, label)
	heroine.free()


func _check_zone_wiring(effect: PainterlyEffect) -> void:
	var zone: Node = (load(ZONE) as PackedScene).instantiate()
	var heroine: Node = zone.find_child("Heroine", true, false)
	_expect(heroine != null, "Zone01 has the heroine")
	if heroine != null:
		_check_camera_compositor(heroine, effect, "Zone01 heroine")
	zone.free()


func _check_camera_compositor(heroine: Node, effect: PainterlyEffect, label: String) -> void:
	var cam: Camera3D = heroine.get_node_or_null(CAMERA_PATH) as Camera3D
	var comp: Compositor = cam.compositor if cam != null else null
	_expect(comp != null and comp.compositor_effects.size() == 1 and comp.compositor_effects[0] == effect,
			"%s camera has a Compositor using painterly.tres" % label)


func _check_sandbox_run(effect: PainterlyEffect) -> void:
	var level: Node = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(level)
	var player: PlayerController = level.get_node("Heroine") as PlayerController
	var rig: ThirdPersonCamera = player.camera_rig
	var cam: Camera3D = rig.get_camera()
	var supported: bool = PainterlyEffect.is_supported()
	print("  info rendering device available: ", supported)
	_expect(rig.painterly_enabled, "painterly is on by default for the heroine's camera")
	_expect(rig.is_painterly_active() == supported,
			"camera keeps the Compositor only where compute runs (supported=%s, active=%s)" % [supported, rig.is_painterly_active()])
	await _physics_frames(RUN_FRAMES / 2)
	# Force "supported" so the toggle is really exercised (headless would drop it anyway).
	PainterlyEffect.support_override = PainterlyEffect.SUPPORT_FORCE_ON
	rig.painterly_enabled = false
	rig.painterly_enabled = true
	_expect(cam.compositor != null and cam.compositor.compositor_effects[0] == effect,
			"with support forced on, painterly_enabled = true gives the camera the tuned Compositor")
	rig.painterly_enabled = false
	_expect(cam.compositor == null, "painterly_enabled = false removes the Compositor")
	await _physics_frames(5)
	rig.painterly_enabled = true
	_expect(cam.compositor != null and cam.compositor.compositor_effects[0] == effect,
			"painterly_enabled = true restores the same Compositor")
	PainterlyEffect.support_override = PainterlyEffect.SUPPORT_AUTO
	rig.painterly_enabled = true
	_expect(rig.is_painterly_active() == supported, "back on auto, the camera keeps it only where supported")
	await _physics_frames(RUN_FRAMES / 2)
	_expect(_errors.errors == 0, "sandbox ran %d frames (effect %s) with no errors" % [
			RUN_FRAMES, "attached" if supported else "dropped, renderer can't run it"])
	level.queue_free()
	await _physics_frames(2)


func _physics_frames(count: int) -> void:
	for i: int in count:
		await physics_frame


func _watchdog() -> void:
	_frames_run += 1
	if _frames_run > MAX_RUN_FRAMES and not _finished:
		_expect(false, "finished within %d frames (watchdog)" % MAX_RUN_FRAMES)
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_expect(_errors.errors == 0, "no engine/script errors (%d; first: %s)" % [_errors.errors, _errors.first_error])
	print("PAINTERLY SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)
