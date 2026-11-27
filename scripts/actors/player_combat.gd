class_name PlayerCombat
extends Node
## The heroine's attacks, sword forms and dodge. A child of PlayerController named
## "PlayerCombat"; the controller calls physics_update() once per physics tick (before it
## moves), so input order is fixed. Timing lives in ComboRunner and Dodge (pure, unit
## tested); this node reads input, applies i-frames, and runs the hit query.
##
## Hits: during a swing's active frames a box (AttackData.hit_width × hit_height × reach)
## in front of her is queried on the hurtbox layer. Each Combatant is hit at most once per
## swing, through its best hurtbox (highest damage multiplier).
##
## Deathblow: attack pressed while an enemy's deathblow window is open and it is within
## DeathblowConfig reach and facing cone lands a deathblow instead of a swing.
## Hit-stop: a swing that connects requests HitStopService.Kind.HIT; swing timers and hit
## queries wait while hit-stop is frozen.
##
## Lock-on: while the body's "LockOn" child holds a lock, each swing starts facing the
## locked point (instead of the move direction).
##
## It only knows its parent as a CharacterBody3D with a Visual child and a Combatant child
## (no typed reference back to PlayerController, which would make the two scripts cyclic).

signal form_changed(form: FormConfig)
signal attack_started(attack: AttackData, step: int)
signal attack_landed(result: HitResult, target: Combatant, hurtbox: Hurtbox)
signal dodge_started(direction: Vector3)
## Attack was pressed with a deathblow target in reach: the deathblow landed on `target`.
signal deathblow_performed(target: Combatant, lives_left: int)

## Forms in switch order. switch_form cycles through them (two today: greatsword, katana).
@export var forms: Array[FormConfig] = []
@export_range(0, 8, 1) var starting_form: int = 0
## Deathblow reach, facing cone and lock-out. No deathblows if unset.
@export var deathblow: DeathblowConfig

var body: CharacterBody3D
var combatant: Combatant
## The body's "LockOn" child, or null.
var lock_on: LockOn
var _visual: Node3D
var combo: ComboRunner
var dodge: Dodge = Dodge.new()
var _form_index: int = 0
var _move_direction: Vector3 = Vector3.ZERO
## Instance ids of combatants already hit by the swing in progress.
var _hit_this_swing: Dictionary[int, bool] = {}
var _box: BoxShape3D = BoxShape3D.new()
var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _sphere: SphereShape3D = SphereShape3D.new()
var _deathblow_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
## Combat frame the last deathblow landed on, or NEVER.
var _deathblow_frame: int = NEVER
## Set by the corruption meter during a rampage: no dodge.
var _dodge_locked: bool = false

const NEVER: int = -1_000_000


func _ready() -> void:
	body = get_parent() as CharacterBody3D
	assert(body != null, "PlayerCombat must be a child of the player's CharacterBody3D")
	assert(not forms.is_empty(), "PlayerCombat needs at least one FormConfig")
	_visual = body.get_node(^"Visual") as Node3D
	combatant = Combatant.find_on(body)
	lock_on = body.get_node_or_null(^"LockOn") as LockOn
	_form_index = clampi(starting_form, 0, forms.size() - 1)
	combo = ComboRunner.new(forms[_form_index])
	combo.swing_started.connect(_on_swing_started)
	if combatant != null:
		combatant.posture_broken.connect(interrupt)
		combatant.died.connect(interrupt)
	_query.shape = _box
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_query.collision_mask = Hurtbox.LAYER_MASK
	_deathblow_query.shape = _sphere
	_deathblow_query.collide_with_areas = true
	_deathblow_query.collide_with_bodies = false
	_deathblow_query.collision_mask = Hurtbox.LAYER_MASK


func current_form() -> FormConfig:
	return combo.form


## Reads attack / switch_form / dodge input and advances timers. Called by the controller.
## During hit-stop input is still read, but swing timers and hit queries wait.
## `read_input` false (e.g. while she heals): timers advance but no input is read.
func physics_update(move_direction: Vector3, read_input: bool = true) -> void:
	_move_direction = Vector3(move_direction.x, 0.0, move_direction.z)
	var frozen: bool = HitStopService.is_frozen()
	if not frozen:
		combo.step_frame()
	if not read_input:
		return
	if combatant != null and not combatant.can_act():
		return
	if is_performing_deathblow():
		return
	if Input.is_action_just_pressed(&"switch_form"):
		switch_form()
	if Input.is_action_just_pressed(&"dodge"):
		try_dodge(_move_direction)
	if Input.is_action_just_pressed(&"attack"):
		if not try_deathblow():
			try_attack()
	if combo.is_active() and not frozen:
		_query_hits()


## Attack pressed: starts the next combo step or buffers it. Not while dodging, staggered,
## dead or airborne. Returns true if a swing started or was buffered.
func try_attack() -> bool:
	if is_dodging() or is_performing_deathblow() or not body.is_on_floor():
		return false
	if combatant != null and not combatant.can_act():
		return false
	return combo.press()


## Toggles to the next form, at any time (also mid-combo; see ComboRunner).
func switch_form() -> void:
	if forms.size() < 2:
		return
	_form_index = (_form_index + 1) % forms.size()
	combo.switch_form(forms[_form_index])
	if combatant != null and not combo.form.can_guard:
		combatant.cancel_guard() # no block, and no parry window carried over from the last form
	form_changed.emit(combo.form)


## Dodge in `direction` (or backward from her facing if zero). Katana only. Allowed when
## idle or in attack recovery (it cancels the recovery), on the ground, off cooldown.
func try_dodge(direction: Vector3) -> bool:
	var form: FormConfig = combo.form
	var frame: int = Combatant.current_frame()
	if not form.can_dodge or _dodge_locked or not body.is_on_floor() or is_performing_deathblow():
		return false
	if combo.phase() == ComboRunner.Phase.STARTUP or combo.phase() == ComboRunner.Phase.ACTIVE:
		return false
	if combatant != null and not combatant.can_act():
		return false
	var dir: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.0001:
		dir = -facing_direction()
	if not dodge.start(frame, form, dir):
		return false
	combo.cancel()
	if combatant != null:
		combatant.cancel_guard()
		combatant.set_invulnerable(Dodge.iframe_first(frame, form), form.dodge_iframe_frames)
	dodge_started.emit(dodge.direction)
	return true


## Stops any swing or dodge (stagger, death).
func interrupt() -> void:
	combo.cancel()
	dodge.cancel(Combatant.current_frame())
	if combatant != null:
		combatant.clear_invulnerability()


func is_attacking() -> bool:
	return combo.is_busy()


func is_dodging() -> bool:
	return dodge.is_dodging(Combatant.current_frame())


## Attacking, dodging or in a deathblow: the controller hands horizontal movement to
## motion_velocity().
func is_busy() -> bool:
	return is_attacking() or is_dodging() or is_performing_deathblow()


## Attack pressed: if a deathblow target is in reach and in front of her, the deathblow
## lands now (cancelling any swing) and she is locked for DeathblowConfig.recovery_frames.
## Returns true if it landed.
func try_deathblow() -> bool:
	if combatant != null and not combatant.can_act():
		return false
	if is_dodging() or is_performing_deathblow() or not body.is_on_floor():
		return false
	var target: Combatant = deathblow_target()
	if target == null:
		return false
	combo.cancel()
	var frame: int = Combatant.current_frame()
	_deathblow_frame = frame
	var target_body: Node3D = target.get_parent() as Node3D
	if target_body != null:
		set_facing_direction(target_body.global_position - body.global_position)
	if combatant != null:
		combatant.cancel_guard()
		if deathblow.invulnerable:
			combatant.set_invulnerable(frame, deathblow.recovery_frames)
	target.receive_deathblow(combatant)
	deathblow_performed.emit(target, target.lives_left)
	return true


## In a deathblow's lock-out frames.
func is_performing_deathblow() -> bool:
	if deathblow == null or _deathblow_frame == NEVER:
		return false
	var since: int = Combatant.current_frame() - _deathblow_frame
	return since >= 0 and since < deathblow.recovery_frames


## The Combatant an attack press would deathblow right now, or null: its deathblow window
## is open, its body is within DeathblowConfig.reach of hers on the ground plane and within
## the facing cone. The nearest one wins. For a body with a deathblow_nearest_point() method
## (a large monster) reach and facing are measured to the nearest point of its body or parts.
func deathblow_target() -> Combatant:
	if deathblow == null or body == null or not body.is_inside_tree():
		return null
	_sphere.radius = deathblow.reach + 1.0 # hurtboxes have thickness; the real check is below
	_deathblow_query.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3.UP)
	var hits: Array[Dictionary] = body.get_world_3d().direct_space_state.intersect_shape(_deathblow_query, 32)
	var forward: Vector3 = facing_direction()
	var max_angle: float = deg_to_rad(deathblow.facing_half_angle_degrees)
	var best: Combatant = null
	var best_distance: float = INF
	for hit: Dictionary in hits:
		var hurtbox: Hurtbox = hit.get("collider") as Hurtbox
		if hurtbox == null or hurtbox.combatant == null or hurtbox.combatant == combatant:
			continue
		var target: Combatant = hurtbox.combatant
		if not target.is_deathblow_available():
			continue
		var target_body: Node3D = target.get_parent() as Node3D
		if target_body == null:
			continue
		var offset: Vector3 = _deathblow_aim_point(target_body, body.global_position) - body.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > deathblow.reach or distance >= best_distance:
			continue
		if distance > 0.01 and forward.angle_to(offset / distance) > max_angle:
			continue
		best = target
		best_distance = distance
	return best


## Where her deathblow reach and facing are measured to: for a big body with a
## deathblow_nearest_point() method (LargeMonster: its body or part shapes) the point of it
## nearest her, else its origin.
static func _deathblow_aim_point(target_body: Node3D, from: Vector3) -> Vector3:
	if target_body.has_method(&"deathblow_nearest_point"):
		return target_body.call(&"deathblow_nearest_point", from) as Vector3
	return target_body.global_position


## Guard is allowed in the current form and nothing blocks it right now.
func allows_guard() -> bool:
	return combo.form.can_guard and not is_busy()


## Guard pressed during recovery may cancel it (greatsword deflect-cancel).
func can_cancel_into_guard() -> bool:
	return combo.form.can_guard and combo.phase() == ComboRunner.Phase.RECOVERY


func dodge_ready() -> bool:
	return combo.form.can_dodge and not _dodge_locked and dodge.is_ready(Combatant.current_frame())


## Locks or unlocks the dodge (the corruption rampage locks it). While locked try_dodge
## refuses and dodge_ready() is false.
func set_dodge_locked(locked: bool) -> void:
	_dodge_locked = locked


func is_dodge_locked() -> bool:
	return _dodge_locked


## 0 = ready, 1 = just used. 0 when the form has no dodge.
func dodge_cooldown_ratio() -> float:
	var form: FormConfig = combo.form
	if not form.can_dodge:
		return 0.0
	var full: int = maxi(form.dodge_duration_frames + form.dodge_cooldown_frames, 1)
	return clampf(float(dodge.frames_until_ready(Combatant.current_frame())) / float(full), 0.0, 1.0)


## Horizontal velocity while busy: dodge dash, attack lunge, or standing still in recovery.
func motion_velocity() -> Vector3:
	if is_dodging():
		return dodge.direction * dodge.config.dodge_speed()
	if is_performing_deathblow():
		return Vector3.ZERO
	var a: AttackData = combo.attack
	if a == null or a.lunge_distance <= 0.0:
		return Vector3.ZERO
	var phase: ComboRunner.Phase = combo.phase()
	if phase != ComboRunner.Phase.STARTUP and phase != ComboRunner.Phase.ACTIVE:
		return Vector3.ZERO
	var frames: int = maxi(a.startup_frames + a.active_frames, 1)
	return facing_direction() * (a.lunge_distance / (float(frames) / 60.0))


## Unit vector on the ground plane the body's Visual faces (+Z of the Visual).
func facing_direction() -> Vector3:
	var yaw: float = _visual.global_rotation.y
	return Vector3(sin(yaw), 0.0, cos(yaw))


## Turns the Visual to face `direction` at once.
func set_facing_direction(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length_squared() < 0.000001:
		return
	_visual.global_rotation.y = atan2(direction.x, direction.z)


func _on_swing_started(attack: AttackData, step: int) -> void:
	_hit_this_swing.clear()
	if lock_on != null and lock_on.is_locked():
		set_facing_direction(lock_on.direction_to_target()) # aim at the locked target
	elif _move_direction.length_squared() > 0.0001:
		set_facing_direction(_move_direction)
	if combatant != null:
		combatant.cancel_guard()
	attack_started.emit(attack, step)


func _query_hits() -> void:
	var attack: AttackData = combo.attack
	var forward: Vector3 = facing_direction()
	_box.size = Vector3(attack.hit_width, attack.hit_height, attack.reach)
	var center: Vector3 = body.global_position + Vector3.UP * (attack.hit_height * 0.5) + forward * (attack.reach * 0.5)
	_query.transform = Transform3D(Basis(Vector3.UP, _visual.global_rotation.y), center)
	var hits: Array[Dictionary] = body.get_world_3d().direct_space_state.intersect_shape(_query, 32)
	var candidates: Array[Hurtbox] = []
	for hit: Dictionary in hits:
		var hurtbox: Hurtbox = hit.get("collider") as Hurtbox
		if hurtbox == null or hurtbox.combatant == null or hurtbox.combatant == combatant:
			continue
		if _hit_this_swing.has(hurtbox.combatant.get_instance_id()):
			continue
		candidates.append(hurtbox)
	for hurtbox: Hurtbox in Hurtbox.best_per_combatant(candidates):
		_hit_this_swing[hurtbox.combatant.get_instance_id()] = true
		var result: HitResult = hurtbox.receive_hit(attack, combatant)
		if result.outcome == HitResult.Outcome.HIT or result.outcome == HitResult.Outcome.BLOCKED \
				or result.outcome == HitResult.Outcome.GUARD_BROKEN:
			HitStopService.trigger(HitStopService.Kind.HIT)
		attack_landed.emit(result, hurtbox.combatant, hurtbox)
