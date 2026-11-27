class_name ThirdPersonCamera
extends Node3D
## Orbit camera rig: this node yaws, the PitchPivot child pitches, and the Camera3D sits on
## the pivot's +Z axis. The rig is top-level so it does not inherit the player's rotation.
## Everything (rotation, follow, wall collision) updates once per rendered frame, so the
## camera never lags its own collision check. Expected children: PitchPivot/Camera3D
##
## Lock-on (LockOn calls lock_onto / release_lock): while tracking a point, yaw and pitch
## ease toward it (LockOnConfig sharpness and pitch offset/limits), look input is ignored,
## and the camera distance eases out by LockOnConfig.pullback_for(target_size) so large
## targets stay framed.

@export var config: ThirdPersonCameraConfig
## The node to orbit around (normally the player body).
@export var target: Node3D
## Physics layers the camera is pushed in front of.
@export_flags_3d_physics var collision_mask: int = 1
## Capture the mouse on start. Esc (ui_cancel) releases it, a left/right click recaptures it.
@export var capture_mouse_on_ready: bool = true
## Use the painterly post-process (the Compositor on PitchPivot/Camera3D, configured in
## data/rendering/painterly.tres). Off, or on a renderer that can't run it
## (Mobile, Compatibility, headless), the camera renders plainly. Can be toggled at runtime.
@export var painterly_enabled: bool = true:
	set(value):
		painterly_enabled = value
		if is_node_ready():
			_apply_painterly()

@onready var _pitch_pivot: Node3D = $PitchPivot
@onready var _camera: Camera3D = $PitchPivot/Camera3D

var _yaw: float = 0.0
var _pitch: float = 0.0
var _current_distance: float = 0.0
## Unobstructed camera distance right now: config.distance plus any lock-on pull-back.
var _goal_distance: float = 0.0
var _lock_target: Node3D
var _lock_config: LockOnConfig
var _lock_size: float = 0.0
## How fast _goal_distance eases (kept after release so the camera eases back in).
var _distance_sharpness: float = 4.0
var _probe_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
## The Compositor the scene gave the camera, kept so painterly_enabled can restore it.
var _scene_compositor: Compositor


func _ready() -> void:
	assert(config != null, "ThirdPersonCamera needs a ThirdPersonCameraConfig")
	top_level = true
	# Moved manually in _process from the target's interpolated transform.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = config.fov
	_scene_compositor = _camera.compositor
	_apply_painterly()
	_current_distance = config.distance
	_goal_distance = config.distance

	var probe: SphereShape3D = SphereShape3D.new()
	probe.radius = config.collision_radius
	_probe_query.shape = probe
	_probe_query.collision_mask = collision_mask
	if target is CollisionObject3D:
		_probe_query.exclude = [(target as CollisionObject3D).get_rid()]

	_pitch = clampf(deg_to_rad(config.start_pitch_degrees),
			deg_to_rad(config.min_pitch_degrees), deg_to_rad(config.max_pitch_degrees))
	if target != null:
		# Start behind the target: target faces +Z, the camera looks along the rig's -Z.
		_yaw = wrapf(target.global_rotation.y + PI, -PI, PI)
		global_position = _pivot_point()
	_apply_rotation()
	if capture_mouse_on_ready:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed and button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_tracking():
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		add_look(-motion.relative.x * config.mouse_sensitivity, -motion.relative.y * config.mouse_sensitivity)


func _process(delta: float) -> void:
	if is_tracking():
		_track_lock_target(delta) # the right stick flicks between targets instead
	else:
		var stick: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
		if stick != Vector2.ZERO:
			add_look(-stick.x * config.stick_sensitivity * delta, -stick.y * config.stick_sensitivity * delta)
	_apply_rotation()
	if target != null:
		var weight: float = 1.0 - exp(-config.follow_sharpness * delta)
		global_position = global_position.lerp(_pivot_point(), weight)
	var wanted: float = config.distance
	if is_tracking():
		wanted += _lock_config.pullback_for(_lock_size)
	_goal_distance = lerpf(_goal_distance, wanted, 1.0 - exp(-_distance_sharpness * delta))
	_update_camera_distance(delta)


## Rotates the view. Positive yaw turns left; positive pitch looks up. Values in degrees.
func add_look(yaw_degrees: float, pitch_degrees: float) -> void:
	if config.invert_y:
		pitch_degrees = -pitch_degrees
	_yaw = wrapf(_yaw + deg_to_rad(yaw_degrees), -PI, PI)
	_pitch = clampf(_pitch + deg_to_rad(pitch_degrees),
			deg_to_rad(config.min_pitch_degrees), deg_to_rad(config.max_pitch_degrees))


## Starts tracking `point` (lock-on). `target_size` (meters) sets the pull-back.
func lock_onto(point: Node3D, lock_config: LockOnConfig, target_size: float) -> void:
	_lock_target = point
	_lock_config = lock_config
	_lock_size = target_size
	if lock_config != null:
		_distance_sharpness = lock_config.distance_sharpness


## Stops tracking; the view stays where it is and the distance eases back.
func release_lock() -> void:
	_lock_target = null
	_lock_config = null
	_lock_size = 0.0


## Tracking a lock-on point.
func is_tracking() -> bool:
	return _lock_target != null and is_instance_valid(_lock_target) and _lock_target.is_inside_tree() and _lock_config != null


## The Camera3D this rig moves.
func get_camera() -> Camera3D:
	return _camera if _camera != null else get_node_or_null(^"PitchPivot/Camera3D") as Camera3D


## True when the camera is rendering with the painterly Compositor right now.
func is_painterly_active() -> bool:
	var cam: Camera3D = get_camera()
	return cam != null and cam.compositor != null


## Unobstructed camera distance it is easing toward (config.distance + lock-on pull-back).
func get_goal_distance() -> float:
	return _goal_distance


## Points the view along a world yaw (radians).
func set_view_yaw(yaw: float) -> void:
	_yaw = wrapf(yaw, -PI, PI)


## World-space yaw (radians) the camera is looking along. Used for camera-relative movement.
func get_view_yaw() -> float:
	return _yaw


## Pitch in radians. Negative = camera above the pivot, looking down.
func get_view_pitch() -> float:
	return _pitch


## Gives the camera its scene Compositor only when enabled and the renderer can run it.
func _apply_painterly() -> void:
	var cam: Camera3D = get_camera()
	if cam == null:
		return
	cam.compositor = pick_compositor(_scene_compositor, painterly_enabled, PainterlyEffect.is_supported())


## The Compositor the camera should render with: the scene's one only when painterly is
## enabled and the renderer can run it, otherwise none.
static func pick_compositor(scene_compositor: Compositor, enabled: bool, supported: bool) -> Compositor:
	return scene_compositor if enabled and supported else null


func _apply_rotation() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_pivot.rotation = Vector3(_pitch, 0.0, 0.0)


## Sweeps a sphere from the pivot toward the camera and pulls the camera in front of
## anything it hits. Snaps in immediately, eases back out.
func _update_camera_distance(delta: float) -> void:
	var origin: Vector3 = _pitch_pivot.global_position
	_probe_query.transform = Transform3D(Basis.IDENTITY, origin)
	_probe_query.motion = _pitch_pivot.global_basis.z * _goal_distance
	var fractions: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(_probe_query)
	var safe_distance: float = _goal_distance
	if fractions.size() == 2:
		safe_distance = _goal_distance * fractions[0]
	if safe_distance < _current_distance:
		_current_distance = safe_distance
	else:
		_current_distance = lerpf(_current_distance, safe_distance, 1.0 - exp(-config.return_sharpness * delta))
	_camera.position = Vector3(0.0, 0.0, _current_distance)


## Eases yaw and pitch toward the lock-on point (frame-rate independent).
func _track_lock_target(delta: float) -> void:
	var to: Vector3 = _lock_target.global_position - global_position
	var flat: float = Vector2(to.x, to.z).length()
	if flat > _lock_config.hold_yaw_within: # nearly overhead: hold yaw, or it flips as she passes under
		var desired_yaw: float = atan2(-to.x, -to.z)
		_yaw = wrapf(lerp_angle(_yaw, desired_yaw, 1.0 - exp(-_lock_config.yaw_sharpness * delta)), -PI, PI)
	var desired_pitch: float = atan2(to.y, maxf(flat, 0.1)) + deg_to_rad(_lock_config.pitch_offset_degrees)
	desired_pitch = clampf(desired_pitch,
			deg_to_rad(maxf(_lock_config.min_pitch_degrees, config.min_pitch_degrees)),
			deg_to_rad(minf(_lock_config.max_pitch_degrees, config.max_pitch_degrees)))
	_pitch = lerpf(_pitch, desired_pitch, 1.0 - exp(-_lock_config.pitch_sharpness * delta))


func _pivot_point() -> Vector3:
	var origin: Vector3 = target.get_global_transform_interpolated().origin
	var right: Vector3 = Vector3.RIGHT.rotated(Vector3.UP, _yaw)
	return origin + Vector3.UP * config.pivot_height + right * config.shoulder_offset
