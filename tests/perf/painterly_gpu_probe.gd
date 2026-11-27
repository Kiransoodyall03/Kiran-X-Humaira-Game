extends SceneTree
## Windowed GPU-cost probe for the painterly post-process (PainterlyEffect). Not a headless
## test: it needs a real Forward+ window, and the numbers depend on the GPU. It loads the
## sandbox, turns vsync off, and for each 3D render height measures the viewport's GPU time
## (RenderingServer.viewport_get_measured_render_time_gpu, averaged) with painterly off and
## on. The render height is set with scaling_3d_scale on a 960x540 window, so 1080p works
## on any screen. Fails (exit 1) when the effect's added cost at 1080p is over the budget.
## Run from the project folder (not --headless):
##   godot --path . --script res://tests/perf/painterly_gpu_probe.gd
## Optional user args after `--`: radius=<n> to try a radius instead of painterly.tres,
## budget=<ms> to change the 1080p budget, shots=<absolute folder> to save on/off PNGs.
## Exits 0 when within budget (or when the renderer can't run the effect, reported as SKIPPED).

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
const WINDOW_SIZE: Vector2i = Vector2i(960, 540)
const HEIGHTS: Array[int] = [540, 648, 1080]
## Added GPU time the effect may cost at 1080p (ms). A 60 fps frame is 16.7 ms.
const DEFAULT_BUDGET_MS: float = 3.0
const WARMUP_FRAMES: int = 30
const SAMPLE_FRAMES: int = 90

var _budget_ms: float = DEFAULT_BUDGET_MS
var _radius: int = -1
var _shots_dir: String = ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("radius="):
			_radius = arg.trim_prefix("radius=").to_int()
		elif arg.begins_with("budget="):
			_budget_ms = arg.trim_prefix("budget=").to_float()
		elif arg.begins_with("shots="):
			_shots_dir = arg.trim_prefix("shots=")
	_run.call_deferred()


func _run() -> void:
	if not PainterlyEffect.is_supported():
		print("PAINTERLY GPU PROBE SKIPPED (renderer '%s' can't run the effect)" % RenderingServer.get_current_rendering_method())
		quit(0)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = WINDOW_SIZE
	var level: Node = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(level)
	var player: PlayerController = level.get_node("Heroine") as PlayerController
	var rig: ThirdPersonCamera = player.camera_rig
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var effect: PainterlyEffect = rig.get_camera().compositor.compositor_effects[0] as PainterlyEffect
	if _radius > 0:
		effect.radius = _radius
	print("  info GPU: %s, renderer %s, radius %d, budget %.2f ms at 1080p" % [
			RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
			effect.radius, _budget_ms])
	var vp: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)

	var cost_1080: float = 0.0
	for height: int in HEIGHTS:
		root.scaling_3d_scale = float(height) / float(WINDOW_SIZE.y)
		rig.painterly_enabled = false
		var off_ms: float = await _measure(vp)
		if not _shots_dir.is_empty() and height == 1080:
			_save_shot("painterly_off.png")
		rig.painterly_enabled = true
		var on_ms: float = await _measure(vp)
		if not _shots_dir.is_empty() and height == 1080:
			_save_shot("painterly_on.png")
		var cost: float = on_ms - off_ms
		print("  %4dp  off %6.2f ms  on %6.2f ms  effect %6.2f ms" % [height, off_ms, on_ms, cost])
		if height == 1080:
			cost_1080 = cost
	level.queue_free()
	var passed: bool = cost_1080 <= _budget_ms
	print("PAINTERLY GPU PROBE ", "PASSED" if passed else "FAILED",
			" (1080p effect cost %.2f ms, budget %.2f ms)" % [cost_1080, _budget_ms])
	quit(0 if passed else 1)


func _measure(vp: RID) -> float:
	for i: int in WARMUP_FRAMES:
		await process_frame
	var total: float = 0.0
	for i: int in SAMPLE_FRAMES:
		await process_frame
		total += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return total / float(SAMPLE_FRAMES)


func _save_shot(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	var image: Image = root.get_texture().get_image()
	image.save_png(_shots_dir.path_join(file_name))
	print("  info saved ", _shots_dir.path_join(file_name))
