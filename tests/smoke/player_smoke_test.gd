extends SceneTree
## Headless smoke test for the week-1 capsule player. Loads the sandbox, drives the input
## actions and checks movement in all four directions, facing, sprint, stopping, step-up,
## jumping (full, cut, buffered, coyote), landing, camera framing and pitch clamping.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/player_smoke_test.gd
## Exits 0 on pass, 1 on failure. (Move to gdUnit4 once it is installed.)

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
const ALL_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint"]

var _failures: int = 0
var _player: PlayerController
var _camera: ThirdPersonCamera
var _cam_node: Camera3D
var _cfg: PlayerMovementConfig
var _jump_count: int = 0
var _land_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(level)
	_player = level.get_node("Heroine") as PlayerController
	_camera = _player.get_node("CameraRig") as ThirdPersonCamera
	_cam_node = _camera.get_node("PitchPivot/Camera3D") as Camera3D
	_cfg = _player.config
	_player.jumped.connect(func() -> void: _jump_count += 1)
	_player.landed.connect(func() -> void: _land_count += 1)

	await _physics_frames(30)
	await _test_spawn()
	await _test_walk_and_facing()
	await _test_sprint()
	await _test_camera_relative_turn()
	await _test_stop()
	await _test_strafe_and_back()
	await _test_step_up()
	await _test_full_jump()
	await _test_jump_cut()
	await _test_buffered_tap()
	await _test_coyote()
	await _test_pitch_clamp()

	print("SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


# --- steps -------------------------------------------------------------------

func _test_spawn() -> void:
	_expect(_player.is_on_floor(), "player starts on the floor")
	_expect(absf(_player.global_position.y) < 0.05, "feet at y≈0 (origin at feet), got %.3f" % _player.global_position.y)
	var to_camera: Vector3 = _cam_node.global_position - _player.global_position
	_expect(to_camera.dot(_view_forward()) < -1.0, "camera starts behind the player")
	_expect(_view_forward().dot(Vector3.BACK) > 0.95, "camera starts looking along +Z (the way she faces)")


func _test_walk_and_facing() -> void:
	var start: Vector3 = _player.global_position
	var view_forward: Vector3 = _view_forward()
	Input.action_press("move_forward")
	await _physics_frames(60)
	var moved: Vector3 = _player.global_position - start
	_expect(moved.length() > 3.0, "walked forward >3 m in 1 s, got %.2f m" % moved.length())
	_expect(moved.normalized().dot(view_forward) > 0.95, "moved along the camera's real forward")
	_expect(is_equal_approx(snappedf(_horizontal_speed(), 0.01), _cfg.walk_speed),
			"reached walk speed %.2f, got %.2f" % [_cfg.walk_speed, _horizontal_speed()])
	_expect(_facing().dot(view_forward) > 0.95, "visual faces movement")


func _test_sprint() -> void:
	Input.action_press("sprint")
	await _physics_frames(30)
	_expect(is_equal_approx(snappedf(_horizontal_speed(), 0.01), _cfg.sprint_speed),
			"reached sprint speed %.2f, got %.2f" % [_cfg.sprint_speed, _horizontal_speed()])
	Input.action_release("sprint")


func _test_camera_relative_turn() -> void:
	var facing_before: float = _player.get_facing_yaw()
	_camera.add_look(90.0, 0.0)
	await _physics_frames(45)
	var view_forward: Vector3 = _view_forward()
	_expect(_horizontal_velocity().normalized().dot(view_forward) > 0.95, "movement follows the rotated camera")
	_expect(_facing().dot(view_forward) > 0.95, "visual turned to follow the rotated camera")
	_expect(absf(angle_difference(facing_before, _player.get_facing_yaw())) > deg_to_rad(80.0), "facing actually changed")
	Input.action_release("move_forward")


func _test_stop() -> void:
	await _physics_frames(30)
	_expect(_horizontal_speed() < 0.01, "stops when input released, speed %.3f" % _horizontal_speed())


func _test_strafe_and_back() -> void:
	var view_forward: Vector3 = _view_forward()
	var view_right: Vector3 = view_forward.cross(Vector3.UP)
	Input.action_press("move_right")
	await _physics_frames(45)
	_expect(_horizontal_velocity().normalized().dot(view_right) > 0.95, "move_right goes to the camera's right")
	Input.action_release("move_right")
	await _physics_frames(30)
	Input.action_press("move_back")
	await _physics_frames(45)
	_expect(_horizontal_velocity().normalized().dot(-view_forward) > 0.95, "move_back goes toward the camera")
	Input.action_release("move_back")
	await _physics_frames(30)


func _test_step_up() -> void:
	# Step_0_35m spans x -7..-5, z 5..7. Walk into it from z = 3 along +Z.
	await _teleport(Vector3(-6.0, 0.0, 3.0))
	Input.action_press("move_forward")
	await _physics_frames(40) # ~3 m: onto the step, not off its far side
	_expect(_player.global_position.z > 5.3, "walked onto the step (z=%.2f)" % _player.global_position.z)
	Input.action_release("move_forward")
	await _physics_frames(5)
	_expect(_player.is_on_floor() and absf(_player.global_position.y - 0.35) < 0.05,
			"walked up the 0.35 m step (y=%.2f)" % _player.global_position.y)

	# LowClimb_1_0m spans x -3..-1, z 5..7: too tall to step, she must stop at it.
	await _teleport(Vector3(-2.0, 0.0, 3.0))
	Input.action_press("move_forward")
	await _physics_frames(90)
	Input.action_release("move_forward")
	await _physics_frames(5)
	_expect(_player.global_position.y < 0.05 and _player.global_position.z < 5.0,
			"blocked by the 1.0 m ledge (y=%.2f, z=%.2f)" % [_player.global_position.y, _player.global_position.z])


func _test_full_jump() -> void:
	await _teleport(Vector3(0.0, 0.0, -2.0))
	var jumps: int = _jump_count
	var lands: int = _land_count
	Input.action_press("jump")
	var apex: float = await _measure_apex(90)
	Input.action_release("jump")
	var expected: float = _expected_full_apex()
	_expect(apex > expected * 0.85 and apex < expected * 1.15, "full jump apex ≈ %.2f m, got %.2f m" % [expected, apex])
	_expect(_player.is_on_floor(), "landed again")
	_expect(_jump_count - jumps == 1, "jumped signal fired once")
	_expect(_land_count - lands == 1, "landed signal fired once, got %d" % (_land_count - lands))


func _test_jump_cut() -> void:
	await _physics_frames(10)
	Input.action_press("jump")
	await _physics_frames(1)
	Input.action_release("jump")
	var apex: float = await _measure_apex(90)
	_expect(apex < _expected_full_apex() * 0.7, "a tap gives a short hop (%.2f m)" % apex)


func _test_buffered_tap() -> void:
	await _physics_frames(10)
	var jumps: int = _jump_count
	Input.action_press("jump")
	await _physics_frames(5)
	Input.action_release("jump")
	# Wait until falling just above the floor, then tap jump in the air.
	for i: int in 120:
		await _physics_frames(1)
		if _player.velocity.y < 0.0 and _player.global_position.y < 0.2:
			break
	Input.action_press("jump")
	await _physics_frames(1)
	Input.action_release("jump")
	var apex: float = await _measure_apex(120)
	_expect(_jump_count - jumps == 2, "jump pressed just before landing fires on landing")
	_expect(apex < _expected_full_apex() * 0.7, "a buffered tap is also a short hop (%.2f m)" % apex)


func _test_coyote() -> void:
	# HighClimb_2_2m top spans x 1..3, z 5..7 at y = 2.2. Walk off its +Z edge.
	await _teleport(Vector3(2.0, 2.2, 6.0))
	var jumps: int = _jump_count
	Input.action_press("move_forward")
	for i: int in 120:
		await _physics_frames(1)
		if not _player.is_on_floor():
			break
	await _physics_frames(3) # 0.05 s late, inside the 0.1 s coyote window
	Input.action_press("jump")
	await _physics_frames(2)
	Input.action_release("jump")
	Input.action_release("move_forward")
	_expect(_jump_count - jumps == 1, "jump still works just after walking off a ledge")
	await _physics_frames(120)


func _test_pitch_clamp() -> void:
	var cam_cfg: ThirdPersonCameraConfig = _camera.config
	var upper: float = deg_to_rad(cam_cfg.min_pitch_degrees if cam_cfg.invert_y else cam_cfg.max_pitch_degrees)
	var lower: float = deg_to_rad(cam_cfg.max_pitch_degrees if cam_cfg.invert_y else cam_cfg.min_pitch_degrees)
	_camera.add_look(0.0, 1000.0)
	await process_frame
	_expect(is_equal_approx(_camera.get_view_pitch(), upper), "pitch clamps at the upper limit")
	_camera.add_look(0.0, -1000.0)
	await process_frame
	_expect(is_equal_approx(_camera.get_view_pitch(), lower), "pitch clamps at the lower limit")


# --- helpers -----------------------------------------------------------------

## Forward direction of the actual Camera3D, flattened to the ground plane.
func _view_forward() -> Vector3:
	var f: Vector3 = -_cam_node.global_basis.z
	f.y = 0.0
	return f.normalized()


func _facing() -> Vector3:
	return Vector3.BACK.rotated(Vector3.UP, _player.get_facing_yaw())


func _horizontal_velocity() -> Vector3:
	return Vector3(_player.velocity.x, 0.0, _player.velocity.z)


func _horizontal_speed() -> float:
	return _horizontal_velocity().length()


func _expected_full_apex() -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
	return _cfg.jump_velocity * _cfg.jump_velocity / (2.0 * g * _cfg.rise_gravity_multiplier)


## Highest height above the starting y reached in the next `frames` physics frames.
func _measure_apex(frames: int) -> float:
	var ground_y: float = _player.global_position.y
	var peak: float = ground_y
	for i: int in frames:
		await _physics_frames(1)
		peak = maxf(peak, _player.global_position.y)
	return peak - ground_y


## Puts the player at `pos` facing +Z with the camera behind, and lets her settle.
func _teleport(pos: Vector3) -> void:
	for action: StringName in ALL_ACTIONS:
		Input.action_release(action)
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_camera.set_view_yaw(PI)
	await _physics_frames(20)


func _physics_frames(count: int) -> void:
	for i: int in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)
