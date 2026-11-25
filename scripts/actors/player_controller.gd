class_name PlayerController
extends CharacterBody3D
## Week-1 capsule player: camera-relative movement, sprint, step-up, jump with coyote time,
## jump buffering and variable height, and a visual that turns to face the movement direction.
## Origin is at the feet (docs/ART_SPEC.md). The Visual child faces +Z.
##
## Expected children: Visual (Node3D), CollisionShape3D

signal jumped
signal landed

@export var config: PlayerMovementConfig
## Camera used to make movement camera-relative. If unset, movement is world-relative.
@export var camera_rig: ThirdPersonCamera
## Health, posture and guard. Guard input is ignored if unset.
@export var combatant: Combatant

@onready var _visual: Node3D = $Visual

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _jump_cut_available: bool = false
var _was_on_floor: bool = true


func _ready() -> void:
	assert(config != null, "PlayerController needs a PlayerMovementConfig")
	add_to_group(&"player")
	# Read input before other physics nodes this frame, so a guard pressed on the same
	# frame an enemy's hit lands still counts.
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	_handle_guard_input()
	var can_act: bool = combatant == null or combatant.can_act()
	var move_direction: Vector3 = get_move_direction() if can_act else Vector3.ZERO
	_update_jump_timers(delta)
	if not can_act:
		_jump_buffer_timer = 0.0
	_apply_gravity(delta)
	_try_jump()
	_apply_horizontal_movement(move_direction, delta)
	_try_step_up(delta)
	move_and_slide()
	_face_direction(move_direction, delta)
	_check_landing()


## Movement input as a world-space direction on the ground plane (length 0–1).
func get_move_direction() -> Vector3:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = Vector3(input.x, 0.0, input.y)
	if camera_rig != null:
		direction = direction.rotated(Vector3.UP, camera_rig.get_view_yaw())
	return direction


## World-space yaw (radians) the visual is facing. 0 = facing world +Z.
func get_facing_yaw() -> float:
	return _visual.global_rotation.y


func is_guarding() -> bool:
	return combatant != null and combatant.is_guarding()


func is_staggered() -> bool:
	return combatant != null and combatant.is_staggered()


func is_dead() -> bool:
	return combatant != null and combatant.is_dead


## Press = guard up with a fresh parry window. The guard's held state then follows the
## button, so a press and release inside one physics tick can't leave it stuck on, and a
## button held through a stagger raises the guard again (without a parry) once she recovers.
func _handle_guard_input() -> void:
	if combatant == null:
		return
	if Input.is_action_just_pressed("block"):
		combatant.guard_press()
	var held: bool = Input.is_action_pressed("block")
	if not held and combatant.guard.is_held:
		combatant.guard_release()
	elif held and not combatant.guard.is_held:
		combatant.guard_hold()


func _update_jump_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = config.coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = config.jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var multiplier: float = config.rise_gravity_multiplier if velocity.y > 0.0 else config.fall_gravity_multiplier
	velocity.y = maxf(velocity.y - _gravity * multiplier * delta, -config.max_fall_speed)
	# Variable jump height: letting go of jump while rising cuts the rise, once per jump.
	if _jump_cut_available and velocity.y > 0.0 and not Input.is_action_pressed("jump"):
		_cut_jump()


func _try_jump() -> void:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = config.jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_cut_available = true
		# A buffered tap may already have been released before take-off.
		if not Input.is_action_pressed("jump"):
			_cut_jump()
		jumped.emit()


func _cut_jump() -> void:
	velocity.y *= config.jump_cut_multiplier
	_jump_cut_available = false


func _apply_horizontal_movement(move_direction: Vector3, delta: float) -> void:
	var top_speed: float = config.walk_speed
	if is_guarding():
		top_speed *= config.guard_speed_multiplier
	elif Input.is_action_pressed("sprint"):
		top_speed = config.sprint_speed
	var target_velocity: Vector3 = move_direction * top_speed
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = config.acceleration if move_direction != Vector3.ZERO else config.deceleration
	if not is_on_floor():
		rate *= config.air_control
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Lifts the body onto ledges up to max_step_height (stairs, kerbs) without a jump.
## Wall in the way → test the same move from higher up → if clear and there is walkable
## floor below, raise the body; move_and_slide then carries it over the edge.
func _try_step_up(delta: float) -> void:
	if not is_on_floor() or config.max_step_height <= 0.0:
		return
	var motion: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length_squared() < 0.000001:
		return
	var hit: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit):
		return
	if hit.get_normal().angle_to(Vector3.UP) <= floor_max_angle:
		return # A walkable slope: move_and_slide handles it.
	var lift: Vector3 = Vector3.UP * config.max_step_height
	if test_move(global_transform, lift):
		return # Ceiling in the way.
	var raised: Transform3D = global_transform.translated(lift)
	# Probe far enough ahead that the capsule's rounded bottom lands flat on the step top,
	# not on its edge (which would report a partial height).
	var ahead: Vector3 = motion.normalized() * maxf(motion.length(), config.step_probe_distance)
	if test_move(raised, ahead):
		return # Still blocked up there: too tall to step.
	var landing: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(raised.translated(ahead), -lift, landing):
		return # Nothing to stand on.
	if landing.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return
	var rise: float = config.max_step_height - landing.get_travel().length()
	if rise > 0.01:
		global_position.y += rise


func _face_direction(move_direction: Vector3, delta: float) -> void:
	if move_direction.length_squared() < 0.0001:
		return
	var target_yaw: float = atan2(move_direction.x, move_direction.z)
	var step: float = deg_to_rad(config.turn_speed_degrees) * delta
	_visual.global_rotation.y = rotate_toward(_visual.global_rotation.y, target_yaw, step)


func _check_landing() -> void:
	var on_floor: bool = is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit()
	_was_on_floor = on_floor
