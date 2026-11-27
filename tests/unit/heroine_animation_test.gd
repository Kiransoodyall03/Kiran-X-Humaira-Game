extends GdUnitTestSuite
## The heroine's animation contract: clip names, the saved AnimationTree state machine and
## placeholder library staying in sync with her forms and data, and the driver's state
## priority rules (HeroineAnimationDriver.choose_state). Runtime behaviour in the sandbox
## is tests/smoke/animation_smoke_test.gd.

const HEROINE: String = "res://scenes/actors/heroine.tscn"
const CONFIG: String = "res://data/animation/heroine_anim.tres"
const TREE: String = "res://data/animation/heroine_anim_tree.tres"
const LIBRARY: String = "res://data/animation/heroine_placeholder_anims.tres"
## The banned-term list is read from rule 5 of the naming sheet at runtime, so the terms
## themselves never appear in code.
const NAMING_DOC: String = "res://docs/NAMING.md"
const BANNED_MARKER: String = "**Banned (Bleach terms):**"
## Folders the project-wide name scan skips: third-party code, engine cache, test reports, builds.
const SCAN_SKIP_DIRS: Array[String] = ["addons", ".godot", "reports", "builds"]
const SCAN_EXTENSIONS: Array[String] = ["gd", "tres", "tscn"]

var _forms: Array[FormConfig] = []
var _heal: HealConfig
var _deathblow_frames: int = 0
var _config: HeroineAnimConfig


func before() -> void:
	var heroine: Node = (load(HEROINE) as PackedScene).instantiate()
	var combat: PlayerCombat = heroine.get_node(^"PlayerCombat") as PlayerCombat
	_forms = combat.forms.duplicate()
	_heal = (heroine.get_node(^"Healing") as PlayerHealing).config
	_deathblow_frames = combat.deathblow.recovery_frames
	heroine.free()
	_config = load(CONFIG) as HeroineAnimConfig


func test_clip_names_follow_the_naming_rules() -> void:
	var banned: Array[String] = _banned_terms()
	assert_array(banned).override_failure_message("no banned-term list found in %s (rule 5, %s)" % [NAMING_DOC, BANNED_MARKER]).is_not_empty()
	var clips: Array[StringName] = HeroineClips.all_clips(_forms)
	var unique: Dictionary[StringName, bool] = {}
	for clip: StringName in clips:
		unique[clip] = true
		assert_str(String(clip)).starts_with("A_heroine_")
		for word: String in banned:
			assert_bool(String(clip).to_lower().contains(word)).override_failure_message("%s uses a banned term" % clip).is_false()
	assert_int(unique.size()).is_equal(clips.size())
	# 4 locomotion + jump/fall/land + guard/guard_hit/parry + 4 dodges + hit react, stagger,
	# deathblow, heal, rest, death + one per attack.
	assert_int(clips.size()).is_equal(20 + HeroineClips.attacks_of(_forms).size())
	assert_int(HeroineClips.attacks_of(_forms).size()).is_equal(6)


## The list parsed from the naming sheet: every comma-separated term, lower case, plus a
## macron-free spelling of each term that has one.
func test_banned_terms_are_read_from_the_naming_sheet() -> void:
	var banned: Array[String] = _banned_terms()
	assert_array(banned).override_failure_message("no banned-term list found in %s (rule 5, %s)" % [NAMING_DOC, BANNED_MARKER]).is_not_empty()
	assert_int(banned.size()).is_greater_equal(8)
	for term: String in banned:
		assert_str(term).is_equal(term.strip_edges().to_lower())
		assert_bool(term.is_empty() or term.contains(".") or term.contains("*")).override_failure_message("bad term '%s'" % term).is_false()
	assert_array(_parse_banned_terms("no list here")).is_empty()
	assert_array(_parse_banned_terms(BANNED_MARKER + " .")).is_empty()
	assert_array(_parse_banned_terms("5. " + BANNED_MARKER + " Foo Bar, bāz. Other text, here.")).is_equal(["foo bar", "bāz", "baz"])


## No script, resource or scene outside addons/ uses a banned term anywhere in its text.
func test_no_project_file_uses_a_banned_term() -> void:
	var banned: Array[String] = _banned_terms()
	assert_array(banned).override_failure_message("no banned-term list found in %s (rule 5, %s)" % [NAMING_DOC, BANNED_MARKER]).is_not_empty()
	var files: Array[String] = []
	_collect_files("res://", files)
	assert_int(files.size()).is_greater(10)
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path).to_lower()
		for word: String in banned:
			assert_bool(text.contains(word)).override_failure_message("%s uses a banned term" % path).is_false()


func test_loop_flags_come_from_the_name() -> void:
	assert_bool(HeroineClips.is_loop(HeroineClips.IDLE_CLIP)).is_true()
	assert_bool(HeroineClips.is_loop(HeroineClips.GUARD_CLIP)).is_true()
	assert_bool(HeroineClips.is_loop(&"A_heroine_idle_loop")).is_true()
	assert_bool(HeroineClips.is_loop(HeroineClips.JUMP_CLIP)).is_false()
	assert_bool(HeroineClips.is_loop(&"A_heroine_greatsword_light_1")).is_false()
	assert_str(HeroineClips.base_name(HeroineClips.RUN_CLIP)).is_equal("A_heroine_run")
	assert_str(HeroineClips.base_name(HeroineClips.DEATH_CLIP)).is_equal("A_heroine_death")


func test_attack_clips_are_named_after_the_attack_data() -> void:
	for attack: AttackData in HeroineClips.attacks_of(_forms):
		assert_str(String(HeroineClips.attack_clip(attack))).is_equal("A_heroine_" + String(attack.id))
		assert_str(String(HeroineClips.attack_state(attack))).is_equal(String(attack.id))


func test_saved_tree_has_every_state_and_clip() -> void:
	var sm: AnimationNodeStateMachine = load(TREE) as AnimationNodeStateMachine
	assert_object(sm).is_not_null()
	for state: StringName in HeroineClips.all_states(_forms):
		assert_bool(sm.has_node(state)).override_failure_message("tree has no state %s: rebuild it" % state).is_true()
	var referenced: Array[StringName] = HeroineAnimTree.referenced_clips(sm)
	var expected: Array[StringName] = HeroineClips.all_clips(_forms)
	referenced.sort()
	expected.sort()
	assert_array(referenced).is_equal(expected)


func test_saved_tree_attack_timelines_match_the_frame_data() -> void:
	var sm: AnimationNodeStateMachine = load(TREE) as AnimationNodeStateMachine
	for attack: AttackData in HeroineClips.attacks_of(_forms):
		var node: AnimationNodeAnimation = sm.get_node(HeroineClips.attack_state(attack)) as AnimationNodeAnimation
		assert_str(String(node.animation)).is_equal(String(HeroineClips.attack_clip(attack)))
		assert_bool(node.use_custom_timeline).is_true()
		assert_bool(node.stretch_time_scale).is_true()
		assert_float(node.timeline_length).is_equal_approx(attack.total_frames() / 60.0, 0.0001)
	var heal: AnimationNodeAnimation = sm.get_node(HeroineClips.HEAL) as AnimationNodeAnimation
	assert_float(heal.timeline_length).is_equal_approx(_heal.use_frames / 60.0, 0.0001)
	var deathblow: AnimationNodeAnimation = sm.get_node(HeroineClips.DEATHBLOW) as AnimationNodeAnimation
	assert_float(deathblow.timeline_length).is_equal_approx(_deathblow_frames / 60.0, 0.0001)
	var guard: AnimationNodeAnimation = sm.get_node(HeroineClips.GUARD) as AnimationNodeAnimation
	assert_bool(guard.use_custom_timeline).is_false() # loops play at their own length


func test_saved_tree_connects_every_pair_of_states() -> void:
	var sm: AnimationNodeStateMachine = load(TREE) as AnimationNodeStateMachine
	var states: Array[StringName] = HeroineClips.all_states(_forms)
	for from: StringName in states:
		for to: StringName in states:
			if from != to:
				assert_bool(sm.has_transition(from, to)).override_failure_message("no transition %s → %s" % [from, to]).is_true()
	assert_bool(sm.has_transition(&"Start", HeroineClips.LOCOMOTION)).is_true()


func test_locomotion_blend_points_follow_the_config() -> void:
	var sm: AnimationNodeStateMachine = load(TREE) as AnimationNodeStateMachine
	var loco: AnimationNodeBlendSpace1D = sm.get_node(HeroineClips.LOCOMOTION) as AnimationNodeBlendSpace1D
	assert_int(loco.get_blend_point_count()).is_equal(4)
	var speeds: Array[float] = [0.0, _config.walk_blend_speed, _config.run_blend_speed, _config.sprint_blend_speed]
	for i: int in 4:
		assert_float(loco.get_blend_point_position(i)).is_equal_approx(speeds[i], 0.001)
		var node: AnimationNodeAnimation = loco.get_blend_point_node(i) as AnimationNodeAnimation
		assert_str(String(node.animation)).is_equal(String(HeroineClips.LOCOMOTION_CLIPS[i]))
	var dodge: AnimationNodeBlendSpace2D = sm.get_node(HeroineClips.DODGE) as AnimationNodeBlendSpace2D
	assert_int(dodge.get_blend_point_count()).is_equal(4)


func test_saved_placeholder_library_has_every_clip_with_the_right_length() -> void:
	var lib: AnimationLibrary = load(LIBRARY) as AnimationLibrary
	assert_object(lib).is_not_null()
	for clip: StringName in HeroineClips.all_clips(_forms):
		assert_bool(lib.has_animation(clip)).override_failure_message("placeholder library has no %s: rebuild it" % clip).is_true()
		var anim: Animation = lib.get_animation(clip)
		var loops: bool = anim.loop_mode != Animation.LOOP_NONE
		assert_bool(loops).override_failure_message("%s loop flag" % clip).is_equal(HeroineClips.is_loop(clip))
	for attack: AttackData in HeroineClips.attacks_of(_forms):
		assert_float(lib.get_animation(HeroineClips.attack_clip(attack)).length).is_equal_approx(attack.total_frames() / 60.0, 0.0001)
	assert_float(lib.get_animation(HeroineClips.HEAL_CLIP).length).is_equal_approx(_heal.use_frames / 60.0, 0.0001)
	assert_bool(lib.has_animation(&"RESET")).is_true()


func test_placeholder_clips_only_animate_the_body_mesh() -> void:
	var lib: AnimationLibrary = HeroinePlaceholderAnims.build(_forms, _config, _heal, _deathblow_frames)
	for clip: StringName in lib.get_animation_list():
		var anim: Animation = lib.get_animation(clip)
		assert_int(anim.get_track_count()).is_greater(0)
		for t: int in anim.get_track_count():
			assert_str(String(anim.track_get_path(t))).is_equal("Visual/BodyMesh")


func test_placeholder_attack_strikes_on_the_active_frames() -> void:
	var lib: AnimationLibrary = HeroinePlaceholderAnims.build(_forms, _config, _heal, _deathblow_frames)
	var attack: AttackData = _forms[0].light_combo[0]
	var anim: Animation = lib.get_animation(HeroineClips.attack_clip(attack))
	var rot: int = anim.find_track(^"Visual/BodyMesh", Animation.TYPE_ROTATION_3D)
	var wind_up: Quaternion = anim.rotation_track_interpolate(rot, attack.startup_frames / 60.0)
	var strike: Quaternion = anim.rotation_track_interpolate(rot, (attack.startup_frames + attack.active_frames) / 60.0)
	# Wound back (top toward -Z) at the end of startup, leaning forward (+Z) at the end of active.
	assert_float((Basis(wind_up) * Vector3.UP).z).is_less(0.0)
	assert_float((Basis(strike) * Vector3.UP).z).is_greater(0.0)


## The saved tree and placeholder library are exactly what a rebuild from the current data
## would write: states, clip nodes and timelines, blend spaces and points, every transition's
## cross-fade and modes, and every placeholder clip's length, tracks and keyframes. Fails
## when HeroineAnimConfig, a form or a placeholder pose changed without running
## scripts/animation/rebuild_heroine_anims.gd.
func test_build_matches_the_saved_resources() -> void:
	var dodge_frames: int = HeroinePlaceholderAnims._dodge_frames(_forms)
	var built: AnimationNodeStateMachine = HeroineAnimTree.build(_forms, _config, _heal.use_frames, _deathblow_frames, dodge_frames)
	var saved: AnimationNodeStateMachine = load(TREE) as AnimationNodeStateMachine
	_assert_same_lines(_describe_tree(saved), _describe_tree(built), "saved tree")
	var built_lib: AnimationLibrary = HeroinePlaceholderAnims.build(_forms, _config, _heal, _deathblow_frames)
	var saved_lib: AnimationLibrary = load(LIBRARY) as AnimationLibrary
	_assert_same_lines(_describe_library(saved_lib), _describe_library(built_lib), "saved placeholder library")


## The comparison above catches a stale cross-fade, timeline or placeholder pose.
func test_build_comparison_spots_stale_values() -> void:
	var dodge_frames: int = HeroinePlaceholderAnims._dodge_frames(_forms)
	var base: Array[String] = _describe_tree(HeroineAnimTree.build(_forms, _config, _heal.use_frames, _deathblow_frames, dodge_frames))
	var tuned: HeroineAnimConfig = _config.duplicate() as HeroineAnimConfig
	tuned.action_xfade_frames += 1
	assert_array(_describe_tree(HeroineAnimTree.build(_forms, tuned, _heal.use_frames, _deathblow_frames, dodge_frames))).is_not_equal(base)
	assert_array(_describe_tree(HeroineAnimTree.build(_forms, _config, _heal.use_frames, _deathblow_frames, dodge_frames + 1))).is_not_equal(base)
	var lib: Array[String] = _describe_library(HeroinePlaceholderAnims.build(_forms, _config, _heal, _deathblow_frames))
	var posed: AnimationLibrary = HeroinePlaceholderAnims.build(_forms, _config, _heal, _deathblow_frames)
	var guard: Animation = posed.get_animation(HeroineClips.GUARD_CLIP)
	var rot: int = guard.find_track(^"Visual/BodyMesh", Animation.TYPE_ROTATION_3D)
	guard.track_set_key_value(rot, 1, Quaternion(Vector3.UP, 0.3))
	assert_array(_describe_library(posed)).is_not_equal(lib)


func test_stand_ins_and_aliases() -> void:
	var lib: AnimationLibrary = AnimationLibrary.new()
	lib.add_animation(&"A_heroine_idle", Animation.new())
	assert_str(String(HeroineAnimationDriver._find_alias(lib, HeroineClips.IDLE_CLIP))).is_equal("A_heroine_idle")
	assert_str(String(HeroineAnimationDriver._find_alias(lib, HeroineClips.RUN_CLIP))).is_empty()
	assert_int(HeroineAnimationDriver._stand_in(HeroineClips.FALL_CLIP).loop_mode).is_equal(Animation.LOOP_LINEAR)
	assert_int(HeroineAnimationDriver._stand_in(HeroineClips.LAND_CLIP).loop_mode).is_equal(Animation.LOOP_NONE)


func test_choose_state_priority() -> void:
	var attack: AttackData = _forms[0].light_combo[1]
	var i: HeroineAnimationDriver.Inputs = HeroineAnimationDriver.Inputs.new()
	assert_str(String(_choose(i))).is_equal("locomotion")
	i.guarding = true
	assert_str(String(_choose(i))).is_equal("guard")
	i.event_state = HeroineClips.LAND
	assert_str(String(_choose(i))).is_equal("land") # a soft one-shot standing still beats guard
	i.ground_speed = 3.0
	assert_str(String(_choose(i))).is_equal("guard") # moving cuts it short
	i.on_floor = false
	i.vertical_speed = 4.0
	assert_str(String(_choose(i))).is_equal("jump")
	i.vertical_speed = -1.0
	assert_str(String(_choose(i))).is_equal("fall")
	i.event_state = HeroineClips.HIT_REACT
	assert_str(String(_choose(i))).is_equal("hit_react") # hard reactions hold in the air too
	i.healing = true
	assert_str(String(_choose(i))).is_equal("heal")
	i.attack = attack
	assert_str(String(_choose(i))).is_equal(String(attack.id))
	i.attack_known = false
	assert_str(String(_choose(i))).is_equal("heal") # an attack with no state falls through
	i.dodging = true
	assert_str(String(_choose(i))).is_equal("dodge")
	i.deathblow = true
	assert_str(String(_choose(i))).is_equal("deathblow")
	i.staggered = true
	assert_str(String(_choose(i))).is_equal("stagger")
	i.dead = true
	assert_str(String(_choose(i))).is_equal("death")


func _banned_terms() -> Array[String]:
	return _parse_banned_terms(FileAccess.get_file_as_string(NAMING_DOC))


## Terms after BANNED_MARKER up to the first full stop, split on commas. Empty when the
## marker is missing or nothing follows it.
func _parse_banned_terms(text: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in text.split("
"):
		var at: int = line.find(BANNED_MARKER)
		if at == -1:
			continue
		var rest: String = line.substr(at + BANNED_MARKER.length())
		var end: int = rest.find(".")
		if end != -1:
			rest = rest.substr(0, end)
		for raw: String in rest.split(","):
			var term: String = raw.strip_edges().to_lower()
			if term.is_empty():
				continue
			out.append(term)
			var plain: String = _strip_macrons(term)
			if plain != term:
				out.append(plain)
		break
	return out


func _strip_macrons(term: String) -> String:
	return term.replace("ā", "a").replace("ē", "e").replace("ī", "i").replace("ō", "o").replace("ū", "u")


func _collect_files(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if sub in SCAN_SKIP_DIRS or sub.begins_with("."):
			continue
		_collect_files(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.get_extension() in SCAN_EXTENSIONS:
			out.append(dir_path.path_join(file))


func _choose(i: HeroineAnimationDriver.Inputs) -> StringName:
	return HeroineAnimationDriver.choose_state(i, _config)


func _assert_same_lines(saved: Array[String], built: Array[String], what: String) -> void:
	for i: int in mini(saved.size(), built.size()):
		if saved[i] != built[i]:
			assert_str(saved[i]).override_failure_message(
					"%s is stale (rebuild it): saved '%s', rebuild gives '%s'" % [what, saved[i], built[i]]).is_equal(built[i])
			return
	assert_int(saved.size()).override_failure_message("%s is stale (rebuild it): %d vs %d entries" % [what, saved.size(), built.size()]).is_equal(built.size())


## One line per state, clip node, blend point and transition, sorted.
func _describe_tree(sm: AnimationNodeStateMachine) -> Array[String]:
	var out: Array[String] = []
	out.append("type %d self %s" % [sm.state_machine_type, sm.allow_transition_to_self])
	for state: StringName in sm.get_node_list():
		var node: AnimationNode = sm.get_node(state)
		out.append("state %s %s" % [state, node.get_class()])
		if node is AnimationNodeBlendSpace1D:
			var bs1: AnimationNodeBlendSpace1D = node as AnimationNodeBlendSpace1D
			out.append("state %s space %s..%s" % [state, _fmt(bs1.min_space), _fmt(bs1.max_space)])
			for i: int in bs1.get_blend_point_count():
				out.append("state %s point %d at %s: %s" % [state, i, _fmt(bs1.get_blend_point_position(i)),
						_describe_clip_node(bs1.get_blend_point_node(i) as AnimationNodeAnimation)])
		elif node is AnimationNodeBlendSpace2D:
			var bs2: AnimationNodeBlendSpace2D = node as AnimationNodeBlendSpace2D
			out.append("state %s mode %d space %s..%s" % [state, bs2.blend_mode, _fmt(bs2.min_space), _fmt(bs2.max_space)])
			for i: int in bs2.get_blend_point_count():
				out.append("state %s point %d at %s: %s" % [state, i, _fmt(bs2.get_blend_point_position(i)),
						_describe_clip_node(bs2.get_blend_point_node(i) as AnimationNodeAnimation)])
		elif node is AnimationNodeAnimation:
			out.append("state %s: %s" % [state, _describe_clip_node(node as AnimationNodeAnimation)])
	for i: int in sm.get_transition_count():
		var t: AnimationNodeStateMachineTransition = sm.get_transition(i)
		out.append("transition %s -> %s xfade %s switch %d advance %d" % [sm.get_transition_from(i), sm.get_transition_to(i),
				_fmt(t.xfade_time), t.switch_mode, t.advance_mode])
	out.sort()
	return out


func _describe_clip_node(node: AnimationNodeAnimation) -> String:
	if node == null:
		return "<not a clip>"
	if not node.use_custom_timeline:
		return "%s own length" % node.animation
	return "%s timeline %s stretch %s loop %d" % [node.animation, _fmt(node.timeline_length), node.stretch_time_scale, node.loop_mode]


## One line per clip and per keyframe, sorted by clip.
func _describe_library(lib: AnimationLibrary) -> Array[String]:
	var out: Array[String] = []
	var clips: Array[StringName] = lib.get_animation_list()
	clips.sort()
	for clip: StringName in clips:
		var anim: Animation = lib.get_animation(clip)
		out.append("%s length %s loop %d step %s tracks %d" % [clip, _fmt(anim.length), anim.loop_mode, _fmt(anim.step), anim.get_track_count()])
		for t: int in anim.get_track_count():
			out.append("%s track %d %s type %d interp %d keys %d" % [clip, t, anim.track_get_path(t), anim.track_get_type(t),
					anim.track_get_interpolation_type(t), anim.track_get_key_count(t)])
			for k: int in anim.track_get_key_count(t):
				out.append("%s track %d key %d at %s = %s" % [clip, t, k, _fmt(anim.track_get_key_time(t, k)),
						_fmt(anim.track_get_key_value(t, k))])
	return out


## Rounds floats and float vectors to 4 decimals so the text round trip of a .tres compares equal.
func _fmt(v: Variant) -> String:
	match typeof(v):
		TYPE_FLOAT:
			return _num(v as float)
		TYPE_VECTOR2:
			var v2: Vector2 = v as Vector2
			return "(%s, %s)" % [_num(v2.x), _num(v2.y)]
		TYPE_VECTOR3:
			var v3: Vector3 = v as Vector3
			return "(%s, %s, %s)" % [_num(v3.x), _num(v3.y), _num(v3.z)]
		TYPE_QUATERNION:
			var q: Quaternion = v as Quaternion
			return "(%s, %s, %s, %s)" % [_num(q.x), _num(q.y), _num(q.z), _num(q.w)]
	return str(v)


func _num(x: float) -> String:
	return "%.4f" % (snappedf(x, 0.0001) + 0.0) # + 0.0 turns -0.0 into 0.0
