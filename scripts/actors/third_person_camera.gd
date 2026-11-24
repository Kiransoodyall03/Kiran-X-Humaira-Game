class_name ThirdPersonCamera
extends Node3D
## Orbit camera rig: this node yaws, the PitchPivot child pitches, and the Camera3D sits on
## the pivot's +Z axis. The rig is top-level so it does not inherit the player's rotation.
## Everything (rotation, follow, wall collision) updates once per rendered frame, so the
## camera never lags its own collision check. Expected children: PitchPivot/Camera3D

@export var config: ThirdPersonCameraConfig
## The node to orbit around (normally the player body).
@export var target: Node3D
## Physics layers the camera is pushed in front of.
@export_flags_3d_physics var collision_mask: int = 1
## Capture the mouse on start. Esc (ui_cancel) releases it, a left/right click recaptures it.
@export var capture_mouse_on_ready: bool = true

@onready var _pitch_pivot: Node3D = $PitchPivot
@onready var _camera: Camera3D = $PitchPivot/Camera3D

var _yaw: float = 0.0
var _pitch: float = 0.0
var _current_distance: float = 0.0
var _probe_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	assert(config != null, "ThirdPersonCamera needs a ThirdPersonCameraConfig")
	top_level = true
	# Moved manually in _process from the target's interpolated transform.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = config.fov
	_current_distance = config.distance

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
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		add_look(-motion.relative.x * config.mouse_sensitivity, -motion.relative.y * config.mouse_sensitivity)


func _process(delta: float) -> void:
	var stick: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if stick != Vector2.ZERO:
		add_look(-stick.x * config.stick_sensitivity * delta, -stick.y * config.stick_sensitivity * delta)
	_apply_rotation()
	if target != null:
		var weight: float = 1.0 - exp(-config.follow_sharpness * delta)
		global_position = global_position.lerp(_pivot_point(), weight)
	_update_camera_distance(delta)


## Rotates the view. Positive yaw turns left; positive pitch looks up. Values in degrees.
func add_look(yaw_degrees: float, pitch_degrees: float) -> void:
	if config.invert_y:
		pitch_degrees = -pitch_degrees
	_yaw = wrapf(_yaw + deg_to_rad(yaw_degrees), -PI, PI)
	_pitch = clampf(_pitch + deg_to_rad(pitch_degrees),
			deg_to_rad(config.min_pitch_degrees), deg_to_rad(config.max_pitch_degrees))


## Points the view along a world yaw (radians). Lock-on will use this.
func set_view_yaw(yaw: float) -> void:
	_yaw = wrapf(yaw, -PI, PI)


## World-space yaw (radians) the camera is looking along. Used for camera-relative movement.
func get_view_yaw() -> float:
	return _yaw


## Pitch in radians. Negative = camera above the pivot, looking down.
func get_view_pitch() -> float:
	return _pitch


func _apply_rotation() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_pivot.rotation = Vector3(_pitch, 0.0, 0.0)


## Sweeps a sphere from the pivot toward the camera and pulls the camera in front of
## anything it hits. Snaps in immediately, eases back out.
func _update_camera_distance(delta: float) -> void:
	var origin: Vector3 = _pitch_pivot.global_position
	_probe_query.transform = Transform3D(Basis.IDENTITY, origin)
	_probe_query.motion = _pitch_pivot.global_basis.z * config.distance
	var fractions: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(_probe_query)
	var safe_distance: float = config.distance
	if fractions.size() == 2:
		safe_distance = config.distance * fractions[0]
	if safe_distance < _current_distance:
		_current_distance = safe_distance
	else:
		_current_distance = lerpf(_current_distance, safe_distance, 1.0 - exp(-config.return_sharpness * delta))
	_camera.position = Vector3(0.0, 0.0, _current_distance)


func _pivot_point() -> Vector3:
	var origin: Vector3 = target.get_global_transform_interpolated().origin
	var right: Vector3 = Vector3.RIGHT.rotated(Vector3.UP, _yaw)
	return origin + Vector3.UP * config.pivot_height + right * config.shoulder_offset
