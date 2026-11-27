class_name HeroineClips
extends RefCounted
## The heroine's AnimationTree contract: state names and clip names
## (docs/ANIMATION_CLIPS.md). Clip names follow docs/ART_SPEC.md: A_heroine_<action>,
## with "-loop" on looping clips (Godot's import suffix that turns looping on).
## Attack states are named after the AttackData id (e.g. "greatsword_light_1") and play
## the clip "A_heroine_<attack id>", so a new attack row only needs its clip.

const PREFIX: String = "A_heroine_"
const LOOP_SUFFIX: String = "-loop"

# State machine states (besides one per attack).
const LOCOMOTION: StringName = &"locomotion"
const JUMP: StringName = &"jump"
const FALL: StringName = &"fall"
const LAND: StringName = &"land"
const GUARD: StringName = &"guard"
const GUARD_HIT: StringName = &"guard_hit"
const PARRY: StringName = &"parry"
const DODGE: StringName = &"dodge"
const HIT_REACT: StringName = &"hit_react"
const STAGGER: StringName = &"stagger"
const DEATHBLOW: StringName = &"deathblow"
const HEAL: StringName = &"heal"
const REST: StringName = &"rest"
const DEATH: StringName = &"death"

# Clips.
const IDLE_CLIP: StringName = &"A_heroine_idle-loop"
const WALK_CLIP: StringName = &"A_heroine_walk-loop"
const RUN_CLIP: StringName = &"A_heroine_run-loop"
const SPRINT_CLIP: StringName = &"A_heroine_sprint-loop"
const JUMP_CLIP: StringName = &"A_heroine_jump"
const FALL_CLIP: StringName = &"A_heroine_fall-loop"
const LAND_CLIP: StringName = &"A_heroine_land"
const GUARD_CLIP: StringName = &"A_heroine_guard-loop"
const GUARD_HIT_CLIP: StringName = &"A_heroine_guard_hit"
const PARRY_CLIP: StringName = &"A_heroine_parry"
const DODGE_FORWARD_CLIP: StringName = &"A_heroine_dodge_forward"
const DODGE_BACK_CLIP: StringName = &"A_heroine_dodge_back"
const DODGE_LEFT_CLIP: StringName = &"A_heroine_dodge_left"
const DODGE_RIGHT_CLIP: StringName = &"A_heroine_dodge_right"
const HIT_REACT_CLIP: StringName = &"A_heroine_hit_react"
const STAGGER_CLIP: StringName = &"A_heroine_stagger-loop"
const DEATHBLOW_CLIP: StringName = &"A_heroine_deathblow"
const HEAL_CLIP: StringName = &"A_heroine_heal"
const REST_CLIP: StringName = &"A_heroine_rest"
const DEATH_CLIP: StringName = &"A_heroine_death"

## Locomotion BlendSpace1D clips, slowest first.
const LOCOMOTION_CLIPS: Array[StringName] = [IDLE_CLIP, WALK_CLIP, RUN_CLIP, SPRINT_CLIP]
## Dodge BlendSpace2D clips and their blend points (x = right, y = forward, relative to
## where she faces).
const DODGE_CLIPS: Array[StringName] = [DODGE_FORWARD_CLIP, DODGE_BACK_CLIP, DODGE_LEFT_CLIP, DODGE_RIGHT_CLIP]
const DODGE_POINTS: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(0.0, -1.0), Vector2(-1.0, 0.0), Vector2(1.0, 0.0)]

## Single-clip states → clip.
const STATE_CLIPS: Dictionary[StringName, StringName] = {
	JUMP: JUMP_CLIP,
	FALL: FALL_CLIP,
	LAND: LAND_CLIP,
	GUARD: GUARD_CLIP,
	GUARD_HIT: GUARD_HIT_CLIP,
	PARRY: PARRY_CLIP,
	HIT_REACT: HIT_REACT_CLIP,
	STAGGER: STAGGER_CLIP,
	DEATHBLOW: DEATHBLOW_CLIP,
	HEAL: HEAL_CLIP,
	REST: REST_CLIP,
	DEATH: DEATH_CLIP,
}


## State name of an attack (its AttackData id).
static func attack_state(attack: AttackData) -> StringName:
	return attack.id


## Clip name of an attack: A_heroine_<attack id>.
static func attack_clip(attack: AttackData) -> StringName:
	return StringName(PREFIX + String(attack.id))


## Every attack in the forms' light combos, each once, in form and combo order.
static func attacks_of(forms: Array[FormConfig]) -> Array[AttackData]:
	var out: Array[AttackData] = []
	var seen: Dictionary[StringName, bool] = {}
	for form: FormConfig in forms:
		if form == null:
			continue
		for attack: AttackData in form.light_combo:
			if attack == null or seen.has(attack.id):
				continue
			seen[attack.id] = true
			out.append(attack)
	return out


## Every non-attack state, in a fixed order.
static func base_states() -> Array[StringName]:
	var out: Array[StringName] = [LOCOMOTION, DODGE]
	for state: StringName in STATE_CLIPS:
		out.append(state)
	return out


## Every state of the tree for these forms.
static func all_states(forms: Array[FormConfig]) -> Array[StringName]:
	var out: Array[StringName] = base_states()
	for attack: AttackData in attacks_of(forms):
		out.append(attack_state(attack))
	return out


## Every non-attack clip.
static func base_clips() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(LOCOMOTION_CLIPS)
	out.append_array(DODGE_CLIPS)
	for state: StringName in STATE_CLIPS:
		out.append(STATE_CLIPS[state])
	return out


## Every clip the tree plays for these forms.
static func all_clips(forms: Array[FormConfig]) -> Array[StringName]:
	var out: Array[StringName] = base_clips()
	for attack: AttackData in attacks_of(forms):
		out.append(attack_clip(attack))
	return out


## Looping clips end in "-loop" (or "_loop", Godot's other import spelling).
static func is_loop(clip: StringName) -> bool:
	var s: String = String(clip)
	return s.ends_with(LOOP_SUFFIX) or s.ends_with("_loop")


## The clip name without a loop suffix, for matching "A_heroine_idle" to "A_heroine_idle-loop".
static func base_name(clip: StringName) -> String:
	var s: String = String(clip)
	if s.ends_with(LOOP_SUFFIX) or s.ends_with("_loop"):
		return s.substr(0, s.length() - LOOP_SUFFIX.length())
	return s
