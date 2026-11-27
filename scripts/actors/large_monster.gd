class_name LargeMonster
extends EnemyBody
## A large monster (size class L/XL): one whole-body Combatant (health, posture, lives) and
## several MonsterParts, each with its own hurtbox, lock-on point and part posture bar.
## docs/COMBAT_SPEC.md, "Large monsters".
##
## Behaviour: waits at home until the target comes within aggro_radius (and inside its
## leash), then CHASEs: turns slowly toward her and walks in (NavigationAgent3D path if the
## map has a navmesh, else straight at her) until preferred_distance. After a short think
## pause it picks an attack for where she stands round its body (front / side / rear, and
## distance; MonsterBrain), winds up with a tell colour (STARTUP), hits (ACTIVE, a box in its
## own frame, moving with any lunge) and stands in a long RECOVERY (the punish window).
## No flinching from ordinary hits: only a part break (stagger, no deathblow window) or a
## whole-body posture break (stagger + deathblow window) stops it. Broken parts can disable
## or weaken attacks. With 2 lives + requires_deathblow it takes two deathblows to kill.
## Leaving the leash sends it home; a shrine rest (group "respawn_on_rest") revives it at
## home with every part whole. The whole body turns (rotation about Y), so parts, hurtboxes
## and lock-on points turn with it. Timing runs on combat frames (paused during hit-stop).
##
## Expected children: CollisionShape3D (keep it round: the body turns), Visual (meshes),
## Combatant, MonsterParts anywhere below it, optional NavigationAgent3D.

enum State { IDLE, RETURN, CHASE, STARTUP, ACTIVE, RECOVERY, STAGGERED, DEAD }

signal state_changed(state: State, attack: AttackData)
## One of its attacks reached the target.
signal attack_landed(result: HitResult)
## A part broke (the whole body is staggered).
signal part_broken(part: MonsterPart)

const NEVER: int = MonsterAttackEntry.NEVER

@export var config: LargeMonsterConfig

var brain: MonsterBrain
var state: State = State.IDLE
## The attack in use (a weakened copy if a broken part weakens it), or null.
var current_attack: AttackData
## Its attack-table row, or null.
var current_entry: MonsterAttackEntry
## Row index in use, or -1.
var current_index: int = -1
var parts: Array[MonsterPart] = []
var _frames_in_state: int = 0
var _think_frames_left: int = 0
var _hit_landed: bool = false
var _broken_material: StandardMaterial3D
var _base_color: Color = Color(0.32, 0.24, 0.2)


func _ready() -> void:
	assert(config != null, "LargeMonster needs a LargeMonsterConfig")
	_setup_enemy(self) # the whole body turns
	brain = MonsterBrain.new(config)
	for node: Node in find_children("*", "MonsterPart", true, false):
		var part: MonsterPart = node as MonsterPart
		parts.append(part)
		part.broken.connect(_on_part_broken)
		if part.lock_point != null:
			part.lock_point.target_size = config.target_size
	_setup_materials()
	_combatant.posture_broken.connect(_on_staggered)
	_combatant.staggered.connect(func(_frames: int) -> void: _on_staggered())
	_combatant.stagger_ended.connect(_on_stagger_ended)
	_combatant.died.connect(_on_died)
	_combatant.revived.connect(_on_revived)


func _physics_process(delta: float) -> void:
	_begin_tick(config.fall_reset_height)
	if not HitStopService.is_frozen():
		_frames_in_state += 1
		_step_state(delta)
	# Lunges (ACTIVE) are exact; it plants its feet, no slide, except while walking.
	var still: bool = state in [State.IDLE, State.STARTUP, State.RECOVERY, State.STAGGERED, State.DEAD]
	_move_body(delta, config.acceleration, state == State.ACTIVE, still)
	_update_color()


## The part with `part_id`, or null.
func get_part(part_id: StringName) -> MonsterPart:
	for p: MonsterPart in parts:
		if p.part_id() == part_id:
			return p
	return null


## Turns it to face `direction` at once (ground plane).
func set_forward(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.000001:
		return
	global_rotation.y = atan2(direction.x, direction.z)


## Engaged with the target (not idle, walking home or dead).
func is_engaged() -> bool:
	return state != State.IDLE and state != State.RETURN and state != State.DEAD


## Where the target stands round its body now.
func target_zone() -> MonsterBrain.Zone:
	if target == null:
		return MonsterBrain.Zone.FRONT
	return brain.zone_for(get_forward(), target.global_position - global_position)


## The point of its body nearest `from` on the ground plane (y = from.y): its round body
## (config.body_radius round its origin) or any part hurtbox's shape (head, limbs, tail).
## Her deathblow reach and facing are measured to this point (PlayerCombat), so a long body
## can be finished from in front of its head or behind its tail. `from` itself if inside.
func deathblow_nearest_point(from: Vector3) -> Vector3:
	var flat_from: Vector3 = Vector3(from.x, 0.0, from.z)
	var best: Vector3 = _nearest_on_circle(flat_from, global_position, config.body_radius)
	var best_d: float = flat_from.distance_squared_to(best)
	for p: MonsterPart in parts:
		if p.hurtbox == null:
			continue
		for node: Node in p.hurtbox.get_children():
			var cs: CollisionShape3D = node as CollisionShape3D
			if cs == null or cs.shape == null or cs.disabled:
				continue
			var q: Vector3 = _nearest_on_shape(flat_from, cs)
			var d: float = flat_from.distance_squared_to(q)
			if d < best_d:
				best = q
				best_d = d
	return Vector3(best.x, from.y, best.z)


## Attack ids a broken part has disabled, as a set.
func disabled_attacks() -> Dictionary[StringName, bool]:
	var out: Dictionary[StringName, bool] = {}
	var states: Array[MonsterPartState] = _part_states()
	for e: MonsterAttackEntry in config.attacks:
		if e != null and e.attack != null and MonsterPartState.is_attack_disabled(states, e.attack.id):
			out[e.attack.id] = true
	return out


## Damage scale of `attack_id` from broken parts (1 = full, 0 = disabled).
func attack_scale(attack_id: StringName) -> float:
	return MonsterPartState.attack_scale(_part_states(), attack_id)


# --- state machine -------------------------------------------------------------------------

func _step_state(delta: float) -> void:
	_desired_velocity = Vector3.ZERO
	match state:
		State.IDLE:
			if _should_engage(config.aggro_radius, config.leash_radius):
				_start_chase()
		State.RETURN:
			if _should_engage(config.aggro_radius, config.leash_radius):
				_start_chase()
			elif _flat(home - global_position).length() <= config.home_tolerance:
				_enter(State.IDLE)
			else:
				_desired_velocity = _path_direction(home) * config.walk_speed
				_turn_toward(global_position + _desired_velocity, config.turn_speed_degrees, delta)
		State.CHASE:
			if not _still_engaged(config.leash_radius):
				_enter(State.RETURN)
				return
			_turn_toward(target.global_position, config.turn_speed_degrees, delta)
			_think_frames_left -= 1
			if _think_frames_left <= 0 and _try_attack():
				return
			if distance_to_target() > config.preferred_distance:
				_desired_velocity = _path_direction(target.global_position) * config.walk_speed
		State.STARTUP:
			if target != null and current_entry.tracks_target:
				_turn_toward(target.global_position, config.startup_turn_speed_degrees, delta)
			var t: float = float(_frames_in_state) / float(maxi(current_attack.startup_frames, 1))
			_material.albedo_color = _base_color.lerp(current_attack.tell_color, clampf(t, 0.0, 1.0))
			if _frames_in_state >= current_attack.startup_frames:
				_hit_landed = false
				_enter(State.ACTIVE)
				_try_hit() # the first active frame can hit
		State.ACTIVE:
			_desired_velocity = get_forward() * _lunge_speed()
			_try_hit()
			if _frames_in_state >= current_attack.active_frames:
				_enter(State.RECOVERY)
		State.RECOVERY:
			if _frames_in_state >= current_attack.recovery_frames:
				_start_chase()
		State.STAGGERED, State.DEAD:
			pass # left by stagger_ended / revived


func _enter(new_state: State) -> void:
	state = new_state
	_frames_in_state = 0
	if new_state != State.STARTUP and new_state != State.ACTIVE and new_state != State.RECOVERY:
		current_attack = null
		current_entry = null
		current_index = -1
	state_changed.emit(state, current_attack)


func _start_chase() -> void:
	_think_frames_left = brain.roll_think_frames()
	_enter(State.CHASE)


## Picks an attack for her zone and distance and starts its wind-up. False if none is valid.
func _try_attack() -> bool:
	var frame: int = Combatant.current_frame()
	var index: int = brain.pick_attack(target_zone(), distance_to_target(), frame, disabled_attacks())
	if index < 0:
		return false
	brain.note_attack(index, frame)
	current_index = index
	current_entry = config.attacks[index]
	current_attack = _scaled_attack(current_entry.attack)
	_enter(State.STARTUP)
	return true


## `attack`, or a weaker copy of it if broken parts weaken it.
func _scaled_attack(attack: AttackData) -> AttackData:
	var scale: float = attack_scale(attack.id)
	if is_equal_approx(scale, 1.0):
		return attack
	var weak: AttackData = attack.duplicate() as AttackData
	weak.damage = attack.damage * scale
	weak.posture_damage = attack.posture_damage * scale
	return weak


## Lunge speed during the active frames (AttackData.lunge_distance over active_frames).
func _lunge_speed() -> float:
	if current_attack == null or current_attack.lunge_distance <= 0.0:
		return 0.0
	var frames: int = maxi(current_attack.active_frames, 1)
	return current_attack.lunge_distance / (float(frames) / float(Engine.physics_ticks_per_second))


func _try_hit() -> void:
	if _hit_landed or current_attack == null or current_entry == null:
		return
	var yaw: Basis = Basis(Vector3.UP, global_rotation.y)
	var xf: Transform3D = Transform3D(yaw, global_position + yaw * current_entry.hit_center)
	var result: HitResult = _hit_target(current_attack, xf, current_entry.hit_size)
	if result != null:
		_hit_landed = true
		attack_landed.emit(result)


# --- reactions -----------------------------------------------------------------------------

## A part broke: whole-body posture damage (may break posture: deathblow window), else a
## whole-body stagger (no deathblow window). Either cancels the attack in progress.
func _on_part_broken(part: MonsterPart) -> void:
	if _combatant.is_dead:
		return
	part_broken.emit(part)
	_combatant.take_posture_damage(part.config.body_posture_on_break)
	_combatant.stagger(part.config.break_stagger_frames) # extends a running part-break stagger
	if _combatant.is_staggered() and not _combatant.is_break_staggered() and is_inside_tree():
		HitStopService.trigger(HitStopService.Kind.POSTURE_BREAK)
	_refresh_part_materials()


func _on_staggered() -> void:
	if state != State.DEAD:
		_enter(State.STAGGERED)


func _on_stagger_ended() -> void:
	if state != State.DEAD and not _combatant.is_dead:
		_start_chase()


func _on_died() -> void:
	_enter(State.DEAD)
	_refresh_part_materials()


func _on_revived() -> void:
	brain.reset()
	for p: MonsterPart in parts:
		p.reset()
	_refresh_part_materials()
	_reset_to_home()


func _reset_to_home() -> void:
	super._reset_to_home()
	_enter(State.IDLE)


# --- helpers -------------------------------------------------------------------------------

func _part_states() -> Array[MonsterPartState]:
	var out: Array[MonsterPartState] = []
	for p: MonsterPart in parts:
		if p.state != null:
			out.append(p.state)
	return out


func _setup_materials() -> void:
	var meshes: Array[MeshInstance3D] = _all_meshes()
	var source: Material = meshes[0].get_active_material(0) if not meshes.is_empty() else null
	_material = (source.duplicate() as StandardMaterial3D) if source is StandardMaterial3D else StandardMaterial3D.new()
	_base_color = _material.albedo_color
	_broken_material = _material.duplicate() as StandardMaterial3D
	_broken_material.albedo_color = config.broken_part_color
	for m: MeshInstance3D in meshes:
		m.material_override = _material
	_refresh_part_materials()


## Broken parts' meshes take the broken colour (except while dead).
func _refresh_part_materials() -> void:
	for p: MonsterPart in parts:
		var mat: StandardMaterial3D = _broken_material if p.is_broken() and state != State.DEAD else _material
		for m: MeshInstance3D in p.meshes():
			m.material_override = mat


func _all_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		out.append(node as MeshInstance3D)
	return out


func _update_color() -> void:
	match state:
		State.STARTUP:
			pass # set in _step_state (tell colour ramp)
		State.ACTIVE:
			_material.albedo_color = current_attack.tell_color
		State.STAGGERED:
			_material.albedo_color = config.stagger_color
		State.DEAD:
			_material.albedo_color = config.dead_color
		_:
			_material.albedo_color = _base_color


## Ground-plane point of `cs`'s shape nearest `flat_from` (y 0): exact for boxes (turned
## only about Y), round shapes use their radius round the shape's centre.
static func _nearest_on_shape(flat_from: Vector3, cs: CollisionShape3D) -> Vector3:
	var xf: Transform3D = cs.global_transform
	if cs.shape is BoxShape3D:
		var half: Vector3 = (cs.shape as BoxShape3D).size * 0.5
		var local: Vector3 = xf.affine_inverse() * Vector3(flat_from.x, xf.origin.y, flat_from.z)
		local = Vector3(clampf(local.x, -half.x, half.x), 0.0, clampf(local.z, -half.z, half.z))
		return _flat(xf * local)
	var radius: float = 0.0
	if cs.shape is SphereShape3D:
		radius = (cs.shape as SphereShape3D).radius
	elif cs.shape is CapsuleShape3D:
		radius = (cs.shape as CapsuleShape3D).radius
	elif cs.shape is CylinderShape3D:
		radius = (cs.shape as CylinderShape3D).radius
	return _nearest_on_circle(flat_from, xf.origin, radius)


## Ground-plane point of a circle (centre `center`, `radius`) nearest `flat_from`.
static func _nearest_on_circle(flat_from: Vector3, center: Vector3, radius: float) -> Vector3:
	var c: Vector3 = _flat(center)
	var offset: Vector3 = flat_from - c
	var length: float = offset.length()
	if length <= radius:
		return flat_from
	return c + offset / length * radius
