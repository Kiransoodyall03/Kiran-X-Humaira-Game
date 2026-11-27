class_name HeroineAnimTree
extends RefCounted
## Builds the heroine's AnimationTree root (an AnimationNodeStateMachine) from her forms
## and HeroineAnimConfig. The saved copy is data/animation/heroine_anim_tree.tres; rebuild
## it after adding or renaming an attack (see docs/ANIMATION_CLIPS.md). Unit tests check
## the saved copy still matches the forms.
##
## Layout: one state per HeroineClips state plus one per attack (named after the
## AttackData id). "locomotion" is a BlendSpace1D on ground speed (idle/walk/run/sprint),
## "dodge" a discrete BlendSpace2D on the dodge direction relative to her facing. Every
## state has a transition to every other state (immediate, cross-faded), so
## AnimationNodeStateMachinePlayback.travel() always goes straight to the target.
## The tree only drives visuals; HeroineAnimationDriver picks the state from gameplay.
##
## One-shot states use a custom timeline stretched to the gameplay length (attack frames,
## dodge, heal, deathblow, reactions), so a clip of any length lines up with the frame
## data. The driver refreshes those lengths from the live data at start-up.

const LOCOMOTION_BLEND: String = "parameters/locomotion/blend_position"
const DODGE_BLEND: String = "parameters/dodge/blend_position"
const PLAYBACK: String = "parameters/playback"
const LOCOMOTION_POINT_NAMES: Array[String] = ["idle", "walk", "run", "sprint"]
const DODGE_POINT_NAMES: Array[String] = ["forward", "back", "left", "right"]

## States that loop (cross-fade with loop_xfade_frames into them).
const LOOP_STATES: Array[StringName] = [HeroineClips.LOCOMOTION, HeroineClips.GUARD, HeroineClips.FALL, HeroineClips.STAGGER]


## Builds the state machine. `heal_frames` / `deathblow_frames` / `dodge_frames` are the
## gameplay lengths of those one-shots (HealConfig.use_frames, DeathblowConfig.recovery_frames,
## FormConfig.dodge_duration_frames).
static func build(forms: Array[FormConfig], config: HeroineAnimConfig, heal_frames: int,
		deathblow_frames: int, dodge_frames: int) -> AnimationNodeStateMachine:
	var sm: AnimationNodeStateMachine = AnimationNodeStateMachine.new()
	sm.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_ROOT
	sm.allow_transition_to_self = false

	var loco: AnimationNodeBlendSpace1D = AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = maxf(config.sprint_blend_speed, 1.0)
	loco.value_label = "m/s"
	var speeds: Array[float] = [0.0, config.walk_blend_speed, config.run_blend_speed, config.sprint_blend_speed]
	for i: int in HeroineClips.LOCOMOTION_CLIPS.size():
		loco.add_blend_point(_clip_node(HeroineClips.LOCOMOTION_CLIPS[i], 0), speeds[i], -1, StringName(LOCOMOTION_POINT_NAMES[i]))
	sm.add_node(HeroineClips.LOCOMOTION, loco, Vector2(0, 0))

	var dodge: AnimationNodeBlendSpace2D = AnimationNodeBlendSpace2D.new()
	dodge.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_DISCRETE
	dodge.min_space = Vector2(-1.0, -1.0)
	dodge.max_space = Vector2(1.0, 1.0)
	dodge.x_label = "right"
	dodge.y_label = "forward"
	for i: int in HeroineClips.DODGE_CLIPS.size():
		dodge.add_blend_point(_clip_node(HeroineClips.DODGE_CLIPS[i], dodge_frames), HeroineClips.DODGE_POINTS[i], -1,
				StringName(DODGE_POINT_NAMES[i]))
	sm.add_node(HeroineClips.DODGE, dodge, Vector2(400, 300))

	var one_shot_frames: Dictionary[StringName, int] = {
		HeroineClips.JUMP: config.jump_frames,
		HeroineClips.LAND: config.land_frames,
		HeroineClips.GUARD_HIT: config.guard_hit_frames,
		HeroineClips.PARRY: config.parry_frames,
		HeroineClips.HIT_REACT: config.hit_react_frames,
		HeroineClips.DEATHBLOW: deathblow_frames,
		HeroineClips.HEAL: heal_frames,
		HeroineClips.REST: config.rest_frames,
		HeroineClips.DEATH: config.death_frames,
	}
	var column: int = 0
	for state: StringName in HeroineClips.STATE_CLIPS:
		var clip: StringName = HeroineClips.STATE_CLIPS[state]
		var frames: int = one_shot_frames.get(state, 0) if not HeroineClips.is_loop(clip) else 0
		sm.add_node(state, _clip_node(clip, frames), Vector2(column % 4 * 220 - 300, -250 - floori(column / 4.0) * 120))
		column += 1
	var attacks: Array[AttackData] = HeroineClips.attacks_of(forms)
	for i: int in attacks.size():
		var attack: AttackData = attacks[i]
		sm.add_node(HeroineClips.attack_state(attack), _clip_node(HeroineClips.attack_clip(attack), attack.total_frames()),
				Vector2(i % 3 * 220 + 300, floori(i / 3.0) * 120 - 120))

	var start: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", HeroineClips.LOCOMOTION, start)
	var states: Array[StringName] = HeroineClips.all_states(forms)
	for from: StringName in states:
		for to: StringName in states:
			if from == to:
				continue
			var t: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
			t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			var frames: int = config.loop_xfade_frames if LOOP_STATES.has(to) else config.action_xfade_frames
			t.xfade_time = HeroineAnimConfig.seconds(frames)
			sm.add_transition(from, to, t)
	return sm


## Sets a one-shot clip node's timeline to `frames` (stretching the clip to fit).
## 0 frames = use the clip's own length (loops).
static func set_node_frames(node: AnimationNodeAnimation, frames: int) -> void:
	if node == null:
		return
	if frames <= 0:
		node.use_custom_timeline = false
		return
	node.use_custom_timeline = true
	node.timeline_length = HeroineAnimConfig.seconds(frames)
	node.stretch_time_scale = true
	node.loop_mode = Animation.LOOP_NONE


## Every clip name the tree references (state nodes and blend-space points).
static func referenced_clips(sm: AnimationNodeStateMachine) -> Array[StringName]:
	var out: Array[StringName] = []
	for state: StringName in sm.get_node_list():
		var node: AnimationNode = sm.get_node(state)
		for clip_node: AnimationNodeAnimation in clip_nodes_of(node):
			if not out.has(clip_node.animation):
				out.append(clip_node.animation)
	return out


## The AnimationNodeAnimation(s) a state is made of.
static func clip_nodes_of(node: AnimationNode) -> Array[AnimationNodeAnimation]:
	var out: Array[AnimationNodeAnimation] = []
	if node is AnimationNodeAnimation:
		out.append(node as AnimationNodeAnimation)
	elif node is AnimationNodeBlendSpace1D:
		var bs1: AnimationNodeBlendSpace1D = node as AnimationNodeBlendSpace1D
		for i: int in bs1.get_blend_point_count():
			out.append_array(clip_nodes_of(bs1.get_blend_point_node(i)))
	elif node is AnimationNodeBlendSpace2D:
		var bs2: AnimationNodeBlendSpace2D = node as AnimationNodeBlendSpace2D
		for i: int in bs2.get_blend_point_count():
			out.append_array(clip_nodes_of(bs2.get_blend_point_node(i)))
	return out


static func _clip_node(clip: StringName, frames: int) -> AnimationNodeAnimation:
	var node: AnimationNodeAnimation = AnimationNodeAnimation.new()
	node.animation = clip
	set_node_frames(node, frames)
	return node
