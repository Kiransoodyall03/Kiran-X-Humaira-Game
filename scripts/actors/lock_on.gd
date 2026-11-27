class_name LockOn
extends Node
## The heroine's lock-on. A child of the player body named "LockOn".
##
## lock_on toggles: it picks the best LockOnPoint (in front of the camera, in range, in
## sight, nearest the screen centre; see LockOnTargeting). While locked, lock_cycle_next /
## lock_cycle_prev (mouse wheel), a right-stick flick or a fast horizontal mouse flick
## switch point: first the other parts of the same target, then other targets.
## While locked the ThirdPersonCamera tracks the point and pulls back for big targets, the
## PlayerController turns her to face it (movement stays camera-relative, so it strafes),
## and PlayerCombat aims each swing at it.
##
## The lock breaks when the target dies, the point leaves break range, line of sight is
## blocked for LockOnConfig.lost_sight_frames combat frames, the point is removed or
## disabled (another part of the same target takes over if there is one), or she dies.
## While she can't act (defeated or staggered) lock_on can't pick up a new lock.
## Reads input in _physics_process before the PlayerController (priority -11).

signal locked(point: LockOnPoint)
## Cycling (or a disabled part) moved the lock to another point.
signal switched(point: LockOnPoint)
signal unlocked(reason: BreakReason)

enum BreakReason { MANUAL, TARGET_DIED, OUT_OF_RANGE, LOST_SIGHT, POINT_GONE, SELF_DEFEATED }

@export var config: LockOnConfig
## The camera that tracks the target and whose view picks it. If unset, the body's
## "CameraRig" child.
@export var camera_rig: ThirdPersonCamera
## Off = ignore lock_on / cycle input (scripted moments). The API still works.
@export var input_enabled: bool = true

var body: Node3D
var combatant: Combatant
## Why the last lock ended (MANUAL before any lock ended).
var last_break_reason: BreakReason = BreakReason.MANUAL
var _point: LockOnPoint
## A lock is held (_point may since have been freed with its target).
var _locked: bool = false
## Keys of the current target's parts locked since landing on it.
var _visited: Dictionary[int, bool] = {}
var _blocked_frames: int = 0
var _last_frame: int = -1
var _flick_armed: bool = true
var _mouse_flick: float = 0.0
## Right-stick x from the last joypad event on camera_left / camera_right (−1…1).
var _stick_x: float = 0.0
var _ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	assert(config != null, "LockOn needs a LockOnConfig")
	body = get_parent() as Node3D
	assert(body != null, "LockOn must be a child of the player body")
	combatant = Combatant.find_on(body)
	if camera_rig == null:
		camera_rig = body.get_node_or_null(^"CameraRig") as ThirdPersonCamera
	process_physics_priority = -11
	_ray.collision_mask = config.line_of_sight_mask
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	if body is CollisionObject3D:
		_ray.exclude = [(body as CollisionObject3D).get_rid()]
	if combatant != null:
		combatant.died.connect(func() -> void: unlock(BreakReason.SELF_DEFEATED))


func _input(event: InputEvent) -> void:
	# Flicks read only the joypad axis bound to camera_left / camera_right, so the arrow
	# keys bound to the same actions keep turning the camera when unlocked but never
	# switch target.
	if event is InputEventJoypadMotion and (event.is_action(&"camera_left") or event.is_action(&"camera_right")):
		_stick_x = event.get_action_strength(&"camera_right") - event.get_action_strength(&"camera_left")


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_locked() or config.mouse_flick_pixels <= 0.0:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_flick += (event as InputEventMouseMotion).relative.x
		if absf(_mouse_flick) >= config.mouse_flick_pixels:
			cycle(1 if _mouse_flick > 0.0 else -1)
			_mouse_flick = 0.0


func _physics_process(delta: float) -> void:
	_mouse_flick *= exp(-config.mouse_flick_decay * delta)
	if _locked and not is_instance_valid(_point):
		unlock(BreakReason.POINT_GONE) # freed with its target
	if input_enabled:
		_read_input()
	if is_locked():
		_check_break()


func is_locked() -> bool:
	return _locked and is_instance_valid(_point)


## The locked point, or null.
func current_point() -> LockOnPoint:
	return _point if is_locked() else null


## The Combatant of the locked point, or null.
func current_target() -> Combatant:
	return _point.combatant if is_locked() else null


## World position of the locked point (Vector3.ZERO if not locked).
func target_position() -> Vector3:
	return _point.global_position if is_locked() else Vector3.ZERO


## Ground-plane direction from the body to the locked point (zero if not locked).
func direction_to_target() -> Vector3:
	if not is_locked():
		return Vector3.ZERO
	var offset: Vector3 = target_position() - body.global_position
	offset.y = 0.0
	return offset.normalized() if offset.length_squared() > 0.000001 else Vector3.ZERO


## Lock if unlocked (returns true if a point was found), unlock if locked (returns false).
func toggle() -> bool:
	if is_locked():
		unlock(BreakReason.MANUAL)
		return false
	return lock_best()


## She can pick up a new lock: not defeated and able to act (not staggered).
func can_acquire() -> bool:
	return combatant == null or combatant.can_act()


## Locks onto the best point in view. Returns false if there is none, or if she can't
## act (defeated or staggered: see can_acquire()).
func lock_best() -> bool:
	if not can_acquire():
		return false
	var candidates: Array[LockOnCandidate] = gather_candidates()
	var i: int = LockOnTargeting.pick_best(candidates, config)
	if i == -1:
		return false
	_visited.clear()
	_set_point(candidates[i].point)
	locked.emit(_point)
	return true


## Locks onto a given point (scripted moments, tests).
func lock_onto(point: LockOnPoint) -> void:
	if point == null:
		return
	var was_locked: bool = is_locked()
	if not was_locked or point.target_key() != _point.target_key():
		_visited.clear()
	_set_point(point)
	if was_locked:
		switched.emit(_point)
	else:
		locked.emit(_point)


## Switches to the next point: +1 = next / right on screen, −1 = previous / left.
## Returns false if not locked or there is nothing else to switch to.
func cycle(direction: int) -> bool:
	if not is_locked():
		return false
	var candidates: Array[LockOnCandidate] = gather_candidates()
	var i: int = LockOnTargeting.next_index(candidates, _point.get_instance_id(), _visited, direction, config)
	if i == -1 or candidates[i].point == _point:
		return false
	var next: LockOnPoint = candidates[i].point
	if next.target_key() != _point.target_key():
		_visited.clear()
	_set_point(next)
	switched.emit(_point)
	return true


func unlock(reason: BreakReason = BreakReason.MANUAL) -> void:
	if not _locked:
		return
	_locked = false
	_point = null
	_visited.clear()
	_blocked_frames = 0
	last_break_reason = reason
	if camera_rig != null:
		camera_rig.release_lock()
	unlocked.emit(reason)


## Every LockOnPoint within break range (not her own), as seen from the camera now.
func gather_candidates() -> Array[LockOnCandidate]:
	var out: Array[LockOnCandidate] = []
	if body == null or not body.is_inside_tree():
		return out
	var cam: Camera3D = _camera()
	var view: Transform3D = cam.global_transform if cam != null else body.global_transform.rotated_local(Vector3.UP, PI)
	var inverse: Transform3D = view.affine_inverse()
	for node: Node in get_tree().get_nodes_in_group(LockOnPoint.GROUP):
		var p: LockOnPoint = node as LockOnPoint
		if p == null or not p.is_inside_tree():
			continue
		if combatant != null and p.combatant == combatant:
			continue
		var pos: Vector3 = p.global_position
		var distance: float = pos.distance_to(body.global_position)
		if distance > config.break_range:
			continue
		var c: LockOnCandidate = LockOnCandidate.new()
		c.point = p
		c.key = p.get_instance_id()
		c.target_key = p.target_key()
		c.part_id = p.part_id
		c.priority = p.priority
		c.distance = distance
		c.alive = p.is_lockable()
		c.has_los = has_line_of_sight(p)
		var local: Vector3 = inverse * pos
		c.in_front = local.z < -0.01
		if c.in_front:
			c.screen = Vector2(local.x, local.y) / -local.z
		else:
			c.screen = Vector2(1000.0 if local.x >= 0.0 else -1000.0, 0.0)
		out.append(c)
	return out


## Nothing on config.line_of_sight_mask between her eye and the point.
func has_line_of_sight(point: Node3D) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	_ray.from = body.global_position + Vector3.UP * config.eye_height
	_ray.to = point.global_position
	return body.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## Combat frames in a row the locked point has been out of sight.
func blocked_frames() -> int:
	return _blocked_frames


func _read_input() -> void:
	if Input.is_action_just_pressed(&"lock_on"):
		toggle()
	if not is_locked():
		_flick_armed = true
		return
	if Input.is_action_just_pressed(&"lock_cycle_next"):
		cycle(1)
	elif Input.is_action_just_pressed(&"lock_cycle_prev"):
		cycle(-1)
	var stick: float = _stick_x
	if absf(stick) < config.flick_reset:
		_flick_armed = true
	elif _flick_armed and absf(stick) >= config.flick_threshold:
		_flick_armed = false
		cycle(1 if stick > 0.0 else -1)


func _check_break() -> void:
	if not _point.is_inside_tree():
		_fall_back_or_unlock(BreakReason.POINT_GONE)
		return
	if _point.combatant != null and _point.combatant.is_dead:
		unlock(BreakReason.TARGET_DIED)
		return
	if not _point.enabled:
		_fall_back_or_unlock(BreakReason.POINT_GONE)
		return
	if _point.global_position.distance_to(body.global_position) > config.break_range:
		unlock(BreakReason.OUT_OF_RANGE)
		return
	var frame: int = Combatant.current_frame()
	if frame == _last_frame:
		return # hit-stop: the sight timer waits with the combat clock
	_last_frame = frame
	if has_line_of_sight(_point):
		_blocked_frames = 0
	else:
		_blocked_frames += 1
		if _blocked_frames >= config.lost_sight_frames:
			unlock(BreakReason.LOST_SIGHT)


## A part went away: move to another part of the same target if one can be locked.
func _fall_back_or_unlock(reason: BreakReason) -> void:
	var key: int = _point.target_key()
	var best: LockOnPoint = null
	var best_score: float = INF
	for c: LockOnCandidate in gather_candidates():
		if c.point == _point or c.target_key != key or not LockOnTargeting.is_cyclable_part(c, config):
			continue
		var s: float = LockOnTargeting.score(c, config)
		if s < best_score:
			best = c.point
			best_score = s
	if best == null:
		unlock(reason)
		return
	_set_point(best)
	switched.emit(_point)


func _set_point(point: LockOnPoint) -> void:
	_point = point
	_locked = true
	_visited[point.get_instance_id()] = true
	_blocked_frames = 0
	_flick_armed = false # a held stick must come back before it flicks again
	if camera_rig != null:
		camera_rig.lock_onto(point, config, point.target_size)


func _camera() -> Camera3D:
	if camera_rig != null:
		return camera_rig.get_camera()
	return get_viewport().get_camera_3d() if is_inside_tree() else null
