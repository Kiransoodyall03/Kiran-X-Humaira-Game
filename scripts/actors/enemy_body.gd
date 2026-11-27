class_name EnemyBody
extends CharacterBody3D
## What the AI enemies (Duelist, LargeMonster) share: the target, home point and leash,
## the fall reset, shrine respawn, walking (navmesh path or straight), turning, movement
## and the once-per-swing hit query on the hurtbox layer. Each subclass runs its own state
## machine and calls _setup_enemy() from _ready().
## Expected children: Combatant, optional NavigationAgent3D.

## Only set a new navmesh goal once the old one is this far off (m): every new goal asks
## the server for a new path.
const REPATH_DISTANCE: float = 0.5

## What it fights. If unset, the first node in the "player" group.
@export var target: Node3D
## Off: it stands still and never attacks or guards (tests, cutscenes).
@export var ai_enabled: bool = true

@onready var _combatant: Combatant = $Combatant
@onready var _nav: NavigationAgent3D = get_node_or_null(^"NavigationAgent3D") as NavigationAgent3D

## Where it waits and walks back to (its start position).
var home: Vector3
var _home_yaw: float = 0.0
## The node that turns to face things (its Visual, or the whole body).
var _facing_node: Node3D
var _material: StandardMaterial3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _desired_velocity: Vector3 = Vector3.ZERO
var _nav_goal: Vector3 = Vector3.INF
var _box: BoxShape3D = BoxShape3D.new()
var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()


func _setup_enemy(facing_node: Node3D) -> void:
	add_to_group(CorruptionMeter.HOSTILE_GROUP)
	add_to_group(PlayerRest.RESPAWN_GROUP) # a shrine rest respawns it
	_facing_node = facing_node
	home = global_position
	_home_yaw = facing_node.global_rotation.y
	_query.shape = _box
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_query.collision_mask = Hurtbox.LAYER_MASK


## Start of every physics tick: find the target, put it back home if it fell off the level.
func _begin_tick(fall_reset_height: float) -> void:
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Node3D
	if global_position.y < fall_reset_height and not _combatant.is_dead:
		_reset_to_home()


func get_combatant() -> Combatant:
	return _combatant


## Shrine rest: revived (full health, empty posture, all lives) at its home point, idle.
func respawn() -> void:
	_combatant.revive() # -> the subclass's revived handler -> _reset_to_home()


## The direction it faces, on the ground plane.
func get_forward() -> Vector3:
	return _flat(_facing_node.global_basis.z).normalized()


## Current body colour (tell colours during wind-ups).
func body_color() -> Color:
	return _material.albedo_color


## Ground-plane distance from its origin to the target (INF without one).
func distance_to_target() -> float:
	if target == null:
		return INF
	return _flat(target.global_position - global_position).length()


## True if it walks along a navmesh path (its map has a navigation region).
func uses_navigation() -> bool:
	if _nav == null or not is_inside_tree():
		return false
	var map: RID = _nav.get_navigation_map()
	return map.is_valid() and not NavigationServer3D.map_get_regions(map).is_empty()


## Back to its home point and facing, standing still. Subclasses extend it to go idle.
func _reset_to_home() -> void:
	global_position = home
	_facing_node.global_rotation.y = _home_yaw
	velocity = Vector3.ZERO
	_desired_velocity = Vector3.ZERO
	_nav_goal = Vector3.INF
	reset_physics_interpolation()


func _should_engage(aggro_radius: float, leash_radius: float) -> bool:
	if not ai_enabled or not _target_alive():
		return false
	return distance_to_target() <= aggro_radius and _target_within_leash(leash_radius)


func _still_engaged(leash_radius: float) -> bool:
	return ai_enabled and _target_alive() and _target_within_leash(leash_radius)


func _target_alive() -> bool:
	if target == null:
		return false
	var c: Combatant = Combatant.find_on(target)
	return c == null or not c.is_dead


func _target_within_leash(leash_radius: float) -> bool:
	return _flat(target.global_position - home).length() <= leash_radius


## Ground-plane direction to walk toward `goal`: along the navmesh path if there is one,
## else straight at it.
func _path_direction(goal: Vector3) -> Vector3:
	var next: Vector3 = goal
	if uses_navigation():
		if _nav_goal.distance_squared_to(goal) > REPATH_DISTANCE * REPATH_DISTANCE:
			_nav_goal = goal
			_nav.target_position = goal
		if not _nav.is_navigation_finished():
			next = _nav.get_next_path_position()
	var dir: Vector3 = _flat(next - global_position)
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO


func _turn_toward(point: Vector3, speed_degrees: float, delta: float) -> void:
	var offset: Vector3 = _flat(point - global_position)
	if offset.length_squared() < 0.0001:
		return
	var target_yaw: float = atan2(offset.x, offset.z)
	_facing_node.global_rotation.y = rotate_toward(_facing_node.global_rotation.y, target_yaw, deg_to_rad(speed_degrees) * delta)


## Gravity plus horizontal movement toward _desired_velocity. `exact`: take it at once
## (lunges); `still`: stand still, no slide; else accelerate toward it.
func _move_body(delta: float, acceleration: float, exact: bool, still: bool) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var desired: Vector3 = _desired_velocity if not HitStopService.is_frozen() else horizontal
	if exact:
		horizontal = desired
	elif still:
		horizontal = Vector3.ZERO
	else:
		horizontal = horizontal.move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()


## Hits the target with `attack` if its hurtbox overlaps a box of `size` at `xf` (hurtbox
## layer). Null if nothing was hit: no target, dead, jumped over a low attack, or out of
## the box.
func _hit_target(attack: AttackData, xf: Transform3D, size: Vector3) -> HitResult:
	if target == null or attack == null:
		return null
	var defender: Combatant = Combatant.find_on(target)
	if defender == null or defender.is_dead:
		return null
	if attack.misses_airborne and target is CharacterBody3D and not (target as CharacterBody3D).is_on_floor():
		return null # jumped over it
	_box.size = size
	_query.transform = xf
	var candidates: Array[Hurtbox] = []
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(_query, 32):
		var hurtbox: Hurtbox = hit.get("collider") as Hurtbox
		if hurtbox != null and hurtbox.combatant == defender:
			candidates.append(hurtbox)
	var best: Array[Hurtbox] = Hurtbox.best_per_combatant(candidates)
	if best.is_empty():
		return null
	return best[0].receive_hit(attack, _combatant)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
