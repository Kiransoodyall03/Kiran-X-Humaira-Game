class_name Duelist
extends EnemyBody
## Capsule duelist: a humanoid sword enemy driven by its attack table (DuelistConfig +
## AttackData rows) and DuelistBrain. docs/COMBAT_SPEC.md, "Duelist".
##
## Behaviour: waits at its home point until the target comes within aggro_radius, then
## circles at mid range, then picks the attack it goes for (by weight among rows off
## cooldown) and walks in to that row's range (NavigationAgent3D path if the map has a
## navmesh, else straight at the target), winds up with a tell colour, swings,
## and stands in recovery (the punish window). It blocks or parries the target's swings
## with configurable odds, using its own Guard. Unguarded hits build up a flinch that
## cancels its wind-up (a flinch never shortens its punish window). Posture break staggers it (a deathblow window opens); it dies on
## the deathblow (1 life). If the target leaves leash_radius around home it walks home; if
## it falls below fall_reset_height it is put back at home. Resting at a shrine respawns it
## (group "respawn_on_rest"): revived at home, idle.
## Timing runs on combat frames (paused during hit-stop).
##
## Hits: during active frames a box (AttackData.hit_width × hit_height × reach) in front of
## it is queried on the hurtbox layer; only the target's Combatant is hit, once per swing.
##
## Expected children: Visual/BodyMesh (MeshInstance3D), CollisionShape3D, Combatant,
## Hurtbox, LockOnPoint; optional NavigationAgent3D.

enum State { IDLE, RETURN, APPROACH, CIRCLE, STARTUP, ACTIVE, RECOVERY, FLINCH, STAGGERED, DEAD }

signal state_changed(state: State, attack: AttackData)
## It decided how to answer one of the target's swings.
signal defense_chosen(defense: DuelistBrain.Defense, attack: AttackData)
## One of its swings reached the target.
signal attack_landed(result: HitResult)

const NEVER: int = DuelistAttackEntry.NEVER

@export var config: DuelistConfig

@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh

var brain: DuelistBrain
var state: State = State.IDLE
var current_attack: AttackData
## Row of the attack table in use, or -1.
var current_index: int = -1
## Row it decided to go for when it stopped circling (it walks in to that row's range), or -1.
var planned_index: int = -1
var _frames_in_state: int = 0
var _circle_frames_left: int = 0
var _strafe_sign: float = 1.0
var _hit_landed: bool = false
## How long the current FLINCH lasts (combat frames): config.flinch_frames, or longer if
## the flinch interrupted a swing or its recovery, so it can't shorten the punish window.
var _flinch_length: int = 0
var _base_color: Color = Color(0.3, 0.28, 0.34)
var _target_combat: PlayerCombat
## Scheduled guard press (parry), guard release, both combat frames or NEVER.
var _guard_press_at: int = NEVER
var _guard_release_at: int = NEVER


func _ready() -> void:
	assert(config != null, "Duelist needs a DuelistConfig")
	_setup_enemy(_visual)
	brain = DuelistBrain.new(config)
	var source: Material = _body_mesh.get_active_material(0)
	_material = (source.duplicate() as StandardMaterial3D) if source is StandardMaterial3D else StandardMaterial3D.new()
	_base_color = _material.albedo_color
	_body_mesh.material_override = _material
	_combatant.posture_broken.connect(_on_posture_broken)
	_combatant.stagger_ended.connect(_on_stagger_ended)
	_combatant.died.connect(_on_died)
	_combatant.revived.connect(_on_revived)
	_combatant.attack_resolved.connect(_on_attack_resolved)


func _physics_process(delta: float) -> void:
	_begin_tick(config.fall_reset_height)
	_connect_target()
	if not HitStopService.is_frozen():
		_frames_in_state += 1
		_tick_guard()
		_step_state(delta)
	var lunging: bool = state == State.STARTUP or state == State.ACTIVE
	var still: bool = state in [State.RECOVERY, State.FLINCH, State.STAGGERED, State.DEAD, State.IDLE]
	_move_body(delta, config.acceleration, lunging, still)
	_update_color()


## True while it is engaged with the target (not idle, walking home or dead).
func is_engaged() -> bool:
	return state != State.IDLE and state != State.RETURN and state != State.DEAD


# --- state machine -------------------------------------------------------------------------

func _step_state(delta: float) -> void:
	_desired_velocity = Vector3.ZERO
	match state:
		State.IDLE:
			if _should_engage(config.aggro_radius, config.leash_radius):
				_engage()
		State.RETURN:
			if _should_engage(config.aggro_radius, config.leash_radius):
				_engage()
			elif _flat(home - global_position).length() <= config.home_tolerance:
				_enter(State.IDLE)
			else:
				_desired_velocity = _path_direction(home) * config.walk_speed
				_turn_toward(global_position + _desired_velocity, config.turn_speed_degrees, delta)
		State.CIRCLE:
			if not _still_engaged(config.leash_radius):
				_enter(State.RETURN)
				return
			_turn_toward(target.global_position, config.turn_speed_degrees, delta)
			_circle_frames_left -= 1
			if _circle_frames_left <= 0 and not _is_defending():
				# Decide what to go for (by weight, ignoring distance), then swing now if it
				# is in range, else walk in to its range.
				planned_index = brain.plan_next_attack(Combatant.current_frame())
				if planned_index < 0:
					_start_circling() # everything is cooling down
					return
				if _try_planned_attack():
					return
				_enter(State.APPROACH)
				return
			_circle_move()
		State.APPROACH:
			if not _still_engaged(config.leash_radius):
				_enter(State.RETURN)
				return
			_turn_toward(target.global_position, config.turn_speed_degrees, delta)
			if planned_index < 0 or planned_index >= config.attacks.size():
				_start_circling()
				return
			if not _is_defending() and _try_planned_attack():
				return
			var row: DuelistAttackEntry = config.attacks[planned_index]
			var d: float = distance_to_target()
			if d > row.max_range:
				_desired_velocity = _path_direction(target.global_position) * config.walk_speed
			elif d < row.min_range:
				# Too close for the plan: switch to any attack valid here, else back off.
				var now: int = brain.pick_attack(d, Combatant.current_frame())
				if now >= 0 and not _is_defending():
					planned_index = now
					_try_planned_attack()
					return
				_desired_velocity = -_flat(target.global_position - global_position).normalized() * config.retreat_speed
		State.STARTUP:
			if target != null:
				_turn_toward(target.global_position, config.startup_turn_speed_degrees, delta)
			_desired_velocity = get_forward() * _lunge_speed()
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
				_start_circling()
		State.FLINCH:
			if _frames_in_state >= _flinch_length:
				_start_circling()
		State.STAGGERED, State.DEAD:
			pass # left by stagger_ended / revived


func _enter(new_state: State) -> void:
	state = new_state
	_frames_in_state = 0
	if new_state != State.STARTUP and new_state != State.ACTIVE and new_state != State.RECOVERY:
		current_attack = null
		current_index = -1
	if not _can_guard_in(new_state):
		_drop_guard()
	state_changed.emit(state, current_attack)


func _engage() -> void:
	_start_circling()


func _start_circling() -> void:
	planned_index = -1
	_circle_frames_left = brain.roll_circle_frames()
	_strafe_sign = brain.roll_strafe_sign()
	_enter(State.CIRCLE)


## Starts the planned row's wind-up if it is valid at the current distance.
func _try_planned_attack() -> bool:
	if planned_index < 0 or planned_index >= config.attacks.size():
		return false
	var frame: int = Combatant.current_frame()
	var row: DuelistAttackEntry = config.attacks[planned_index]
	if not row.is_available(distance_to_target(), frame, brain.last_used.get(planned_index, NEVER) as int):
		return false
	var index: int = planned_index
	planned_index = -1
	brain.note_attack(index, frame)
	current_index = index
	current_attack = config.attacks[index].attack
	_enter(State.STARTUP)
	return true


## Circling: strafe round the target, stepping in or out to stay in the distance band.
func _circle_move() -> void:
	var to_target: Vector3 = _flat(target.global_position - global_position)
	var d: float = to_target.length()
	if d < 0.001:
		return
	var dir: Vector3 = to_target / d
	var side: Vector3 = dir.cross(Vector3.UP) * _strafe_sign
	var radial: Vector3 = Vector3.ZERO
	if d > config.circle_max_distance:
		radial = _path_direction(target.global_position) * config.walk_speed
	elif d < config.circle_min_distance:
		radial = -dir * config.retreat_speed
	_desired_velocity = side * config.strafe_speed + radial
	if get_slide_collision_count() > 0 and is_on_wall():
		_strafe_sign = -_strafe_sign # bumped into something: strafe the other way


func _lunge_speed() -> float:
	if current_attack == null or current_attack.lunge_distance <= 0.0:
		return 0.0
	var frames: int = maxi(current_attack.startup_frames + current_attack.active_frames, 1)
	return current_attack.lunge_distance / (float(frames) / float(Engine.physics_ticks_per_second))


## A box (hit_width × hit_height × reach) in front of it; lands once per swing.
func _try_hit() -> void:
	if _hit_landed or current_attack == null:
		return
	var attack: AttackData = current_attack
	var forward: Vector3 = get_forward()
	var center: Vector3 = global_position + Vector3.UP * (attack.hit_height * 0.5) + forward * (attack.reach * 0.5)
	var xf: Transform3D = Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), center)
	var result: HitResult = _hit_target(attack, xf, Vector3(attack.hit_width, attack.hit_height, attack.reach))
	if result != null:
		_hit_landed = true
		attack_landed.emit(result)


# --- guard ---------------------------------------------------------------------------------

## The target started a swing: maybe parry or block it.
func _on_target_swing(attack: AttackData, _step: int) -> void:
	if not ai_enabled or not _can_guard_in(state) or not _combatant.can_act() or target == null:
		return
	var offset: Vector3 = _flat(global_position - target.global_position)
	if offset.length() > attack.reach + attack.lunge_distance + config.guard_reach_margin:
		return
	if _target_combat != null and offset.length_squared() > 0.0001:
		var facing: Vector3 = _target_combat.facing_direction()
		if facing.angle_to(offset.normalized()) > deg_to_rad(config.guard_facing_degrees):
			return
	var defense: DuelistBrain.Defense = brain.roll_defense()
	defense_chosen.emit(defense, attack)
	var frame: int = Combatant.current_frame()
	var hit_end: int = frame + attack.startup_frames + attack.active_frames + config.block_hold_extra_frames
	match defense:
		DuelistBrain.Defense.PARRY:
			_guard_press_at = DuelistBrain.parry_press_frame(frame, attack.startup_frames, config.parry_lead_frames)
			_guard_release_at = hit_end
			if _guard_press_at <= frame:
				_press_guard_now()
		DuelistBrain.Defense.BLOCK:
			_combatant.guard_hold()
			_guard_release_at = hit_end
		_:
			pass


func _tick_guard() -> void:
	var frame: int = Combatant.current_frame()
	if not _can_guard_in(state) or not _combatant.can_act():
		_drop_guard()
		return
	if _guard_press_at != NEVER and frame >= _guard_press_at:
		_press_guard_now()
	if _guard_release_at != NEVER and frame >= _guard_release_at and _guard_press_at == NEVER:
		_drop_guard()


func _press_guard_now() -> void:
	_guard_press_at = NEVER
	_combatant.guard_press()


func _drop_guard() -> void:
	_guard_press_at = NEVER
	_guard_release_at = NEVER
	if _combatant != null:
		_combatant.guard_release()


## True while it is waiting to parry or holding a block.
func _is_defending() -> bool:
	return _guard_press_at != NEVER or _guard_release_at != NEVER


func _can_guard_in(s: State) -> bool:
	return s == State.IDLE or s == State.RETURN or s == State.APPROACH or s == State.CIRCLE


# --- reactions -----------------------------------------------------------------------------

func _on_attack_resolved(result: HitResult, _attacker: Combatant) -> void:
	if state == State.DEAD or state == State.STAGGERED or _combatant.is_staggered():
		return
	match result.outcome:
		HitResult.Outcome.HIT:
			if brain.add_hit(result.defender_posture_damage, Combatant.current_frame()):
				var armored: bool = config.perilous_super_armor and current_attack != null \
						and current_attack.perilous != AttackData.Perilous.NONE \
						and (state == State.STARTUP or state == State.ACTIVE)
				if not armored:
					_flinch_length = maxi(config.flinch_frames, _guard_locked_frames_left())
					_enter(State.FLINCH)
		HitResult.Outcome.BLOCKED, HitResult.Outcome.PARRIED:
			if state == State.CIRCLE:
				_circle_frames_left = mini(_circle_frames_left, config.counter_frames)
		_:
			pass


## Combat frames until the current swing (active + recovery, the punish window) or flinch
## would let it guard again; 0 in other states. A flinch lasts at least this long.
func _guard_locked_frames_left() -> int:
	match state:
		State.ACTIVE:
			if current_attack != null:
				return maxi(current_attack.active_frames - _frames_in_state, 0) + current_attack.recovery_frames
		State.RECOVERY:
			if current_attack != null:
				return maxi(current_attack.recovery_frames - _frames_in_state, 0)
		State.FLINCH:
			return maxi(_flinch_length - _frames_in_state, 0)
		_:
			pass
	return 0


func _on_posture_broken() -> void:
	if state != State.DEAD:
		_enter(State.STAGGERED)


func _on_stagger_ended() -> void:
	if state != State.DEAD and not _combatant.is_dead:
		_start_circling()


func _on_died() -> void:
	_enter(State.DEAD)


func _on_revived() -> void:
	brain.reset()
	_reset_to_home()


## Back to its home point and facing, idle (on revive, or after falling below
## fall_reset_height).
func _reset_to_home() -> void:
	super._reset_to_home()
	planned_index = -1
	_drop_guard()
	_enter(State.IDLE)


# --- helpers -------------------------------------------------------------------------------

func _connect_target() -> void:
	if _target_combat != null or target == null:
		return
	_target_combat = target.get_node_or_null(^"PlayerCombat") as PlayerCombat
	if _target_combat != null:
		_target_combat.attack_started.connect(_on_target_swing)


func _update_color() -> void:
	match state:
		State.STARTUP:
			pass # set in _step_state (tell colour ramp)
		State.ACTIVE:
			_material.albedo_color = current_attack.tell_color
		State.FLINCH:
			_material.albedo_color = config.flinch_color
		State.STAGGERED:
			_material.albedo_color = config.stagger_color
		State.DEAD:
			_material.albedo_color = config.dead_color
		_:
			_material.albedo_color = config.guard_color if _combatant.guard.is_held else _base_color

