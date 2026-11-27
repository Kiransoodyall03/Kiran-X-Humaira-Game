class_name HeroineAnimationDriver
extends Node
## Maps the heroine's gameplay state (PlayerController, PlayerCombat, Combatant,
## PlayerHealing, PlayerRest) onto her AnimationTree. Visual only: it reads state and never
## changes it. A child of the heroine named "AnimationDriver"; runs after the controller
## each physics tick (process_physics_priority 10).
##
## Priority (first match wins): death → stagger → deathblow → dodge → attack (the state
## named after the swing's AttackData id) → heal → hard reaction (hit_react, guard_hit,
## parry, for their frames) → jump / fall (airborne) → soft one-shot (land, rest; cut short
## by moving) → guard → locomotion (BlendSpace1D on ground speed).
##
## Clips: at start-up every library on the AnimationTree is merged into its default ("")
## library, so Humaira's glb AnimationLibraries plug in by swapping the tree's libraries in
## heroine.tscn (docs/ANIMATION_CLIPS.md). A clip name also matches with or without the
## "-loop" suffix. Any clip the tree needs that no library has gets an empty stand-in of the
## right length, so a missing clip never errors; missing_clips() lists them.
## One-shot timelines are refreshed from the live gameplay data (AttackData frames, dodge,
## heal, deathblow, HeroineAnimConfig), so tuning a frame count re-times its clip.

@export var config: HeroineAnimConfig
## The heroine's AnimationTree. If unset, the sibling named "AnimationTree".
@export var animation_tree: AnimationTree

var body: PlayerController
var combat: PlayerCombat
var combatant: Combatant
var healing: PlayerHealing
var rest: PlayerRest
var playback: AnimationNodeStateMachinePlayback
var state_machine: AnimationNodeStateMachine

## The state chosen on the last tick.
var requested_state: StringName = HeroineClips.LOCOMOTION
## Clips the tree needs that no library had (filled with empty stand-ins).
var _missing: Array[StringName] = []
## Event one-shot in progress (hit_react, guard_hit, parry, land, rest) and frames left.
var _event_state: StringName = &""
var _event_frames_left: int = 0
## An event asked to restart its state even if it is already playing (a new swing of the
## same attack, a second hit react).
var _restart: bool = false
## Fastest fall speed (m/s) since she left the ground.
var _fall_speed: float = 0.0


## Snapshot of what the driver reads, for choose_state() (pure, unit tested).
class Inputs:
	extends RefCounted
	var dead: bool = false
	var staggered: bool = false
	var deathblow: bool = false
	var dodging: bool = false
	## The swing in progress (null when not attacking).
	var attack: AttackData
	## The tree has a state for `attack`.
	var attack_known: bool = true
	var healing: bool = false
	var on_floor: bool = true
	var vertical_speed: float = 0.0
	var guarding: bool = false
	var ground_speed: float = 0.0
	## Event one-shot in progress (&"" for none).
	var event_state: StringName = &""


func _ready() -> void:
	assert(config != null, "HeroineAnimationDriver needs a HeroineAnimConfig")
	process_physics_priority = 10
	body = get_parent() as PlayerController
	assert(body != null, "HeroineAnimationDriver must be a child of the heroine (PlayerController)")
	if animation_tree == null:
		animation_tree = body.get_node_or_null(^"AnimationTree") as AnimationTree
	assert(animation_tree != null, "HeroineAnimationDriver needs an AnimationTree")
	combat = body.combat
	combatant = body.combatant
	healing = body.healing
	rest = body.get_node_or_null(^"Rest") as PlayerRest
	state_machine = animation_tree.tree_root as AnimationNodeStateMachine
	assert(state_machine != null, "the heroine's AnimationTree root must be an AnimationNodeStateMachine")
	install_clips()
	refresh_timelines()
	playback = animation_tree.get(HeroineAnimTree.PLAYBACK) as AnimationNodeStateMachinePlayback
	animation_tree.active = true
	body.landed.connect(_on_landed)
	if combatant != null:
		combatant.attack_resolved.connect(_on_attack_resolved)
		combatant.revived.connect(_clear_event)
	if combat != null:
		combat.attack_started.connect(func(_a: AttackData, _s: int) -> void: _restart = true)
		combat.dodge_started.connect(_on_dodge_started)
		combat.deathblow_performed.connect(func(_t: Combatant, _l: int) -> void: _restart = true)
	if healing != null:
		healing.heal_started.connect(func() -> void: _restart = true)
	if rest != null:
		rest.rested.connect(func(_s: Node3D) -> void: _start_event(HeroineClips.REST, config.rest_frames))
		rest.respawned.connect(func(_s: Node3D) -> void: _clear_event())


func _physics_process(_delta: float) -> void:
	if HitStopService.is_frozen():
		return # hold the event timers; the tree itself slows with Engine.time_scale
	if _event_frames_left > 0:
		_event_frames_left -= 1
		if _event_frames_left <= 0:
			_event_state = &""
	if not body.is_on_floor():
		_fall_speed = maxf(_fall_speed, -body.velocity.y)
	update_tree()


## Picks the state from gameplay and sends the tree there. Also sets the blend positions.
func update_tree() -> void:
	var inputs: Inputs = read_inputs()
	var state: StringName = choose_state(inputs, config)
	requested_state = state
	animation_tree.set(HeroineAnimTree.LOCOMOTION_BLEND, inputs.ground_speed)
	if playback == null:
		playback = animation_tree.get(HeroineAnimTree.PLAYBACK) as AnimationNodeStateMachinePlayback
		if playback == null:
			return
	var current: StringName = playback.get_current_node()
	if state == current:
		if _restart and _is_restartable(state):
			playback.start(state, true)
	else:
		playback.travel(state)
	_restart = false


## The current tree state (what the playback is in or fading into).
func current_state() -> StringName:
	return playback.get_current_node() if playback != null else &""


## Clips the tree needs that no library had.
func missing_clips() -> Array[StringName]:
	return _missing.duplicate()


## Reads the heroine's gameplay state.
func read_inputs() -> Inputs:
	var i: Inputs = Inputs.new()
	i.dead = body.is_dead()
	i.staggered = body.is_staggered()
	i.healing = body.is_healing()
	i.guarding = body.is_guarding()
	i.on_floor = body.is_on_floor()
	i.vertical_speed = body.velocity.y
	i.ground_speed = Vector2(body.velocity.x, body.velocity.z).length()
	i.event_state = _event_state
	if combat != null:
		i.deathblow = combat.is_performing_deathblow()
		i.dodging = combat.is_dodging()
		if combat.is_attacking():
			i.attack = combat.combo.attack
			i.attack_known = state_machine.has_node(HeroineClips.attack_state(i.attack))
	return i


## The state for `i` (see the class notes for the priority order).
static func choose_state(i: Inputs, p_config: HeroineAnimConfig) -> StringName:
	if i.dead:
		return HeroineClips.DEATH
	if i.staggered:
		return HeroineClips.STAGGER
	if i.deathblow:
		return HeroineClips.DEATHBLOW
	if i.dodging:
		return HeroineClips.DODGE
	if i.attack != null and i.attack_known:
		return HeroineClips.attack_state(i.attack)
	if i.healing:
		return HeroineClips.HEAL
	if is_hard_event(i.event_state):
		return i.event_state
	if not i.on_floor:
		return HeroineClips.JUMP if i.vertical_speed > p_config.jump_min_rise_speed else HeroineClips.FALL
	if i.event_state != &"" and i.ground_speed <= p_config.soft_cancel_speed:
		return i.event_state
	if i.guarding:
		return HeroineClips.GUARD
	return HeroineClips.LOCOMOTION


## Reactions that hold their state for their frames even while moving or airborne.
static func is_hard_event(state: StringName) -> bool:
	return state == HeroineClips.HIT_REACT or state == HeroineClips.GUARD_HIT or state == HeroineClips.PARRY


## Merges every library on the tree into its default library and fills any clip the tree
## needs that is missing with an empty stand-in. Called from _ready; call again after
## changing the tree's libraries at runtime.
func install_clips() -> void:
	var merged: AnimationLibrary = AnimationLibrary.new()
	# Default library first, so its clips win over same-named clips in other libraries.
	var names: Array[StringName] = animation_tree.get_animation_library_list()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return a == &"" and b != &"")
	for lib_name: StringName in names:
		var lib: AnimationLibrary = animation_tree.get_animation_library(lib_name)
		for clip: StringName in lib.get_animation_list():
			if not merged.has_animation(clip):
				merged.add_animation(clip, lib.get_animation(clip))
	_missing.clear()
	for clip: StringName in HeroineAnimTree.referenced_clips(state_machine):
		if merged.has_animation(clip):
			continue
		var alias: StringName = _find_alias(merged, clip)
		if alias != &"":
			var copy: Animation = merged.get_animation(alias).duplicate() as Animation
			copy.loop_mode = Animation.LOOP_LINEAR if HeroineClips.is_loop(clip) else Animation.LOOP_NONE
			merged.add_animation(clip, copy)
			continue
		_missing.append(clip)
		merged.add_animation(clip, _stand_in(clip))
	if animation_tree.has_animation_library(&""):
		animation_tree.remove_animation_library(&"")
	animation_tree.add_animation_library(&"", merged)


## Sets every one-shot's timeline from the live gameplay data.
func refresh_timelines() -> void:
	var frames: Dictionary[StringName, int] = {
		HeroineClips.JUMP: config.jump_frames,
		HeroineClips.LAND: config.land_frames,
		HeroineClips.GUARD_HIT: config.guard_hit_frames,
		HeroineClips.PARRY: config.parry_frames,
		HeroineClips.HIT_REACT: config.hit_react_frames,
		HeroineClips.REST: config.rest_frames,
		HeroineClips.DEATH: config.death_frames,
	}
	if healing != null:
		frames[HeroineClips.HEAL] = healing.config.use_frames
	if combat != null:
		if combat.deathblow != null:
			frames[HeroineClips.DEATHBLOW] = combat.deathblow.recovery_frames
		for form: FormConfig in combat.forms:
			if form == null:
				continue
			for attack: AttackData in form.light_combo:
				if attack != null:
					frames[HeroineClips.attack_state(attack)] = attack.total_frames()
	for state: StringName in frames:
		if state_machine.has_node(state):
			HeroineAnimTree.set_node_frames(state_machine.get_node(state) as AnimationNodeAnimation, frames[state])


func _is_restartable(state: StringName) -> bool:
	return state != HeroineClips.LOCOMOTION and state != HeroineClips.GUARD and state != HeroineClips.FALL \
			and state != HeroineClips.STAGGER and state != HeroineClips.DEATH


func _start_event(state: StringName, frames: int) -> void:
	_event_state = state
	_event_frames_left = maxi(frames, 1)
	_restart = true


func _clear_event() -> void:
	_event_state = &""
	_event_frames_left = 0


func _on_landed() -> void:
	if _fall_speed >= config.land_min_fall_speed and _event_state == &"":
		_start_event(HeroineClips.LAND, config.land_frames)
	_fall_speed = 0.0


func _on_dodge_started(direction: Vector3) -> void:
	_restart = true
	# Dodge direction relative to her facing: x = right (her right is -X when facing +Z).
	var forward: Vector3 = combat.facing_direction()
	var right: Vector3 = forward.cross(Vector3.UP)
	var local: Vector2 = Vector2(direction.dot(right), direction.dot(forward))
	if local.length_squared() < 0.0001:
		local = Vector2(0.0, -1.0)
	animation_tree.set(HeroineAnimTree.DODGE_BLEND, local.normalized())
	var dodge_node: AnimationNode = state_machine.get_node(HeroineClips.DODGE) if state_machine.has_node(HeroineClips.DODGE) else null
	var frames: int = combat.dodge.config.dodge_duration_frames if combat.dodge.config != null else 0
	for clip_node: AnimationNodeAnimation in HeroineAnimTree.clip_nodes_of(dodge_node):
		HeroineAnimTree.set_node_frames(clip_node, frames)


func _on_attack_resolved(result: HitResult, _attacker: Combatant) -> void:
	match result.outcome:
		HitResult.Outcome.HIT:
			_start_event(HeroineClips.HIT_REACT, config.hit_react_frames)
		HitResult.Outcome.BLOCKED:
			_start_event(HeroineClips.GUARD_HIT, config.guard_hit_frames)
		HitResult.Outcome.PARRIED:
			_start_event(HeroineClips.PARRY, config.parry_frames)


## A same-named clip with the other loop spelling ("A_heroine_idle" for "A_heroine_idle-loop").
static func _find_alias(lib: AnimationLibrary, clip: StringName) -> StringName:
	var base: String = HeroineClips.base_name(clip)
	for candidate: StringName in [StringName(base), StringName(base + HeroineClips.LOOP_SUFFIX), StringName(base + "_loop")]:
		if candidate != clip and lib.has_animation(candidate):
			return candidate
	return &""


## An empty clip standing in for a missing one: no tracks, loop flag from its name.
static func _stand_in(clip: StringName) -> Animation:
	var anim: Animation = Animation.new()
	anim.length = 1.0
	anim.loop_mode = Animation.LOOP_LINEAR if HeroineClips.is_loop(clip) else Animation.LOOP_NONE
	return anim
