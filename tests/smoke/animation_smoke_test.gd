extends SceneTree
## Headless smoke test for the heroine's AnimationTree (HeroineAnimationDriver), in the
## sandbox with the real input actions. Checks the state machine travels to the right
## state for idle/move (locomotion blend follows her speed, sprint blends past run), jump →
## fall → land, guard, parry and blocked-hit reactions, the greatsword combo steps,
## a hit react, a katana dodge (blend direction), stagger, heal, deathblow, death and
## revive, and shrine rest; that a second hit react / blocked hit restarts its clip; and
## that the placeholder clips really move the capsule's BodyMesh. Then, on a heroine whose
## tree has no clips at all but one (named without its "-loop" suffix), checks every missing
## clip gets a stand-in and move, jump, guard, attack, dodge and stagger still travel with
## no errors. Last, on a heroine with a stale saved tree and a tuned HeroineAnimConfig,
## checks start-up re-times every one-shot state from the live data.
## Fails on any engine/script error, and on a frame-budget timeout instead of hanging.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/animation_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
const HEROINE: String = "res://scenes/actors/heroine.tscn"
const PLAIN_ATTACK: String = "res://data/attacks/dummy_overhead.tres"
const STATE_WAIT_FRAMES: int = 120
const MAX_RUN_FRAMES: int = 12000

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _level: Node
var _player: PlayerController
var _combat: PlayerCombat
var _player_c: Combatant
var _driver: HeroineAnimationDriver
var _tree: AnimationTree
var _mesh: Node3D
var _dummy: TrainingDummy
var _dummy_c: Combatant
## Every state the playback was in, in order (consecutive repeats dropped).
var _seen: Array[StringName] = []


func _initialize() -> void:
	OS.add_logger(_errors)
	physics_frame.connect(_on_physics_frame)
	_run.call_deferred()


func _run() -> void:
	_level = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(_level)
	_bind(_level.get_node("Heroine") as PlayerController)
	_dummy = _level.get_node("TrainingDummy") as TrainingDummy
	_dummy_c = _dummy.get_combatant()
	_dummy.attacking_enabled = false
	await _physics_frames(10)

	await _test_setup()
	await _test_locomotion()
	await _test_jump()
	await _test_guard_parry_and_block()
	await _test_attacks()
	await _test_hit_react()
	await _test_dodge()
	await _test_stagger()
	await _test_heal()
	await _test_deathblow()
	await _test_death_and_revive()
	await _test_rest()
	await _test_missing_clips()
	await _test_live_timelines()
	_finish()


func _bind(player: PlayerController) -> void:
	_player = player
	_combat = player.combat
	_player_c = player.combatant
	_driver = player.get_node("AnimationDriver") as HeroineAnimationDriver
	_tree = player.get_node("AnimationTree") as AnimationTree
	_mesh = player.get_node("Visual/BodyMesh") as Node3D


func _test_setup() -> void:
	_expect(_driver != null and _tree != null, "the heroine has an AnimationTree and an AnimationDriver")
	_expect(_tree.active, "the AnimationTree is active at runtime")
	_expect(_tree.tree_root is AnimationNodeStateMachine, "the tree root is a state machine")
	_expect(_driver.missing_clips().is_empty(), "the placeholder library has every clip (missing: %s)" % [_driver.missing_clips()])
	await _place_open()
	_expect(await _wait_state(HeroineClips.LOCOMOTION), "standing still: locomotion")
	var blend: float = _tree.get(HeroineAnimTree.LOCOMOTION_BLEND) as float
	_expect(blend < 0.2, "standing still: locomotion blend near idle (%.2f)" % blend)


func _test_locomotion() -> void:
	await _place_open()
	var rest: Transform3D = _mesh.transform
	Input.action_press(&"move_forward")
	await _physics_frames(30)
	var moving_blend: float = _tree.get(HeroineAnimTree.LOCOMOTION_BLEND) as float
	_expect(_driver.current_state() == HeroineClips.LOCOMOTION, "walking: locomotion (%s)" % _driver.current_state())
	_expect(moving_blend > _driver.config.walk_blend_speed, "running: blend past walk (%.2f)" % moving_blend)
	_expect(not _mesh.transform.is_equal_approx(rest), "the run clip moves the capsule's BodyMesh")
	Input.action_press(&"sprint")
	await _physics_frames(40)
	var sprint_blend: float = _tree.get(HeroineAnimTree.LOCOMOTION_BLEND) as float
	_expect(sprint_blend > _driver.config.run_blend_speed + 1.0, "sprinting: blend toward sprint (%.2f)" % sprint_blend)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await _physics_frames(40)
	var stop_blend: float = _tree.get(HeroineAnimTree.LOCOMOTION_BLEND) as float
	_expect(stop_blend < 0.2, "stopped: blend back to idle (%.2f)" % stop_blend)


func _test_jump() -> void:
	await _place_open()
	_seen.clear()
	await _tap(&"jump", 20)
	_expect(await _wait_state(HeroineClips.FALL), "jump → fall")
	_expect(await _wait_state(HeroineClips.LOCOMOTION, 240), "back to locomotion after landing")
	_expect(_ordered([HeroineClips.JUMP, HeroineClips.FALL, HeroineClips.LAND, HeroineClips.LOCOMOTION]),
			"states went jump → fall → land → locomotion (%s)" % [_seen])


func _test_guard_parry_and_block() -> void:
	await _place_open()
	_expect(_combat.current_form().id == &"greatsword", "in the greatsword form")
	var attack: AttackData = load(PLAIN_ATTACK) as AttackData
	Input.action_press(&"block")
	await _physics_frames(2) # the press frame and one more, so the controller has read it
	_expect(_player_c.guard.frames_since_press(Combatant.current_frame()) >= 0, "the block press opened a parry window")
	var parried: HitResult = _player_c.receive_attack(attack, null)
	_expect(parried.outcome == HitResult.Outcome.PARRIED, "a fresh guard press parries (%s)" % parried.outcome_name())
	_expect(await _wait_state(HeroineClips.PARRY), "parry → parry state")
	_expect(await _wait_state(HeroineClips.GUARD), "after the parry: guard (block held)")
	await _physics_frames(40) # past the parry window
	var blocked: HitResult = _player_c.receive_attack(attack, null)
	_expect(blocked.outcome == HitResult.Outcome.BLOCKED, "a held guard blocks (%s)" % blocked.outcome_name())
	_expect(await _wait_state(HeroineClips.GUARD_HIT), "block → guard_hit state")
	# A second blocked hit while guard_hit plays restarts its clip from the top.
	await _physics_frames(_driver.config.guard_hit_frames / 2)
	var before: float = _play_position()
	_expect(_driver.current_state() == HeroineClips.GUARD_HIT and before > 0.05,
			"guard_hit partway through (%.3f s)" % before)
	var blocked_again: HitResult = _player_c.receive_attack(attack, null)
	_expect(blocked_again.outcome == HitResult.Outcome.BLOCKED, "a second hit is blocked (%s)" % blocked_again.outcome_name())
	_expect(await _wait_restarted(HeroineClips.GUARD_HIT, before), "a second blocked hit restarts the guard_hit clip")
	_expect(await _wait_state(HeroineClips.GUARD), "after the blocked hit: back to guard")
	Input.action_release(&"block")
	_expect(await _wait_state(HeroineClips.LOCOMOTION), "guard released → locomotion")
	_player_c.restore()


func _test_attacks() -> void:
	await _place_open()
	var rest: Transform3D = _mesh.transform
	var combo: Array[AttackData] = _combat.current_form().light_combo
	await _tap(&"attack")
	_expect(await _wait_state(HeroineClips.attack_state(combo[0])), "attack → %s" % combo[0].id)
	await _physics_frames(combo[0].startup_frames - 4)
	_expect(not _mesh.transform.is_equal_approx(rest), "the swing clip moves the capsule's BodyMesh")
	for i: int in 200:
		if _combat.combo.phase() == ComboRunner.Phase.RECOVERY:
			break
		await physics_frame
	await _tap(&"attack") # buffer step 2
	_expect(await _wait_state(HeroineClips.attack_state(combo[1]), 200), "buffered attack → %s" % combo[1].id)
	_expect(await _wait_state(HeroineClips.LOCOMOTION, 300), "combo over → locomotion")


func _test_hit_react() -> void:
	await _place_open()
	var attack: AttackData = AttackData.new()
	attack.damage = 5.0
	attack.posture_damage = 5.0
	var r: HitResult = _player_c.receive_attack(attack, null)
	_expect(r.outcome == HitResult.Outcome.HIT, "an unguarded hit lands (%s)" % r.outcome_name())
	_expect(await _wait_state(HeroineClips.HIT_REACT), "hit → hit_react")
	# A second hit while the reaction plays restarts its clip from the top.
	await _physics_frames(_driver.config.hit_react_frames / 2)
	var before: float = _play_position()
	_expect(_driver.current_state() == HeroineClips.HIT_REACT and before > 0.05,
			"hit react partway through (%.3f s)" % before)
	_player_c.receive_attack(attack, null)
	_expect(await _wait_restarted(HeroineClips.HIT_REACT, before), "a second hit restarts the hit_react clip")
	_expect(await _wait_state(HeroineClips.LOCOMOTION), "hit react over → locomotion")
	_player_c.restore()


func _test_dodge() -> void:
	await _place_open()
	await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"katana", "switched to the katana")
	await _physics_frames(40) # dodge cooldown from any earlier use
	Input.action_press(&"move_right")
	await _tap(&"dodge")
	Input.action_release(&"move_right")
	_expect(_combat.is_dodging(), "katana dodge started")
	_expect(await _wait_state(HeroineClips.DODGE), "dodge → dodge state")
	var dir: Vector2 = _tree.get(HeroineAnimTree.DODGE_BLEND) as Vector2
	# Facing world -Z with camera yaw 0, move_right (world +X) is her right.
	_expect(dir.x > 0.7, "dodge blend points to her right (%s)" % dir)
	_expect(await _wait_state(HeroineClips.LOCOMOTION), "dodge over → locomotion")
	await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"greatsword", "back to the greatsword")


func _test_stagger() -> void:
	await _place_open()
	_player_c.take_posture_damage(_player_c.config.posture.max_posture * 2.0)
	_expect(_player_c.is_staggered(), "a full posture bar staggers her")
	_expect(await _wait_state(HeroineClips.STAGGER), "posture break → stagger")
	_expect(await _wait_state(HeroineClips.LOCOMOTION, 400), "stagger over → locomotion")


func _test_heal() -> void:
	await _place_open()
	_player_c.health = _player_c.config.max_health * 0.5
	await _tap(&"heal")
	_expect(_player.is_healing(), "a heal started")
	_expect(await _wait_state(HeroineClips.HEAL), "heal → heal state")
	_expect(await _wait_state(HeroineClips.LOCOMOTION, 200), "heal over → locomotion")
	_player_c.restore()


func _test_deathblow() -> void:
	_dummy_c.revive()
	_player.global_position = _dummy.global_position + Vector3(0.0, 0.0, 2.0)
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3.FORWARD)
	_player.reset_physics_interpolation()
	await _physics_frames(3)
	_dummy_c.take_posture_damage(_dummy_c.config.posture.max_posture * 2.0)
	await _physics_frames(2)
	_expect(_combat.deathblow_target() == _dummy_c, "the staggered dummy is a deathblow target")
	await _tap(&"attack")
	_expect(_combat.is_performing_deathblow(), "attack lands a deathblow")
	_expect(await _wait_state(HeroineClips.DEATHBLOW), "deathblow → deathblow state")
	_expect(await _wait_state(HeroineClips.LOCOMOTION, 200), "deathblow over → locomotion")
	_dummy_c.revive()


func _test_death_and_revive() -> void:
	await _place_open()
	var fatal: AttackData = AttackData.new()
	fatal.damage = 100000.0
	_player_c.receive_attack(fatal, null)
	_expect(_player_c.is_dead, "a fatal hit kills her")
	_expect(await _wait_state(HeroineClips.DEATH), "death → death state")
	# SandboxRules revives her (she has no shrine respawn point yet).
	_expect(await _wait_state(HeroineClips.LOCOMOTION, 400), "revived → locomotion")
	_expect(not _player_c.is_dead, "she was revived")


func _test_rest() -> void:
	await _place_open()
	var shrine: Node3D = _level.get_node("Shrine") as Node3D
	(_player.get_node("Rest") as PlayerRest).rest(shrine, _player.global_transform)
	_expect(await _wait_state(HeroineClips.REST), "shrine rest → rest state")
	Input.action_press(&"move_forward")
	_expect(await _wait_state(HeroineClips.LOCOMOTION, 60), "moving cuts the rest short → locomotion")
	Input.action_release(&"move_forward")
	await _physics_frames(20)


## A heroine whose tree has only "A_heroine_idle" (no "-loop"): every other clip is missing.
func _test_missing_clips() -> void:
	_level.queue_free()
	await _physics_frames(2)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	world.add_child(floor_body)
	var heroine: PlayerController = (load(HEROINE) as PackedScene).instantiate() as PlayerController
	var tree: AnimationTree = heroine.get_node("AnimationTree") as AnimationTree
	for lib_name: StringName in tree.get_animation_library_list():
		tree.remove_animation_library(lib_name)
	var only_idle: AnimationLibrary = AnimationLibrary.new()
	var idle: Animation = Animation.new()
	idle.length = 2.0
	only_idle.add_animation(&"A_heroine_idle", idle)
	tree.add_animation_library(&"", only_idle)
	world.add_child(heroine)
	_bind(heroine)
	await _physics_frames(5)

	var needed: Array[StringName] = HeroineAnimTree.referenced_clips(_tree.tree_root as AnimationNodeStateMachine)
	var missing: Array[StringName] = _driver.missing_clips()
	_expect(missing.size() == needed.size() - 1, "every clip but idle is reported missing (%d of %d)" % [missing.size(), needed.size()])
	_expect(not missing.has(HeroineClips.IDLE_CLIP), "A_heroine_idle stands in for A_heroine_idle-loop")
	var lib: AnimationLibrary = _tree.get_animation_library(&"")
	var all_there: bool = true
	for clip: StringName in needed:
		all_there = all_there and lib.has_animation(clip)
	_expect(all_there, "the tree's library has every clip after the stand-ins")
	_expect(lib.get_animation(HeroineClips.IDLE_CLIP).loop_mode == Animation.LOOP_LINEAR, "the aliased idle loops")
	_expect(lib.get_animation(HeroineClips.JUMP_CLIP).loop_mode == Animation.LOOP_NONE, "a one-shot stand-in doesn't loop")

	_expect(await _wait_state(HeroineClips.LOCOMOTION), "no clips: locomotion")
	Input.action_press(&"move_forward")
	await _physics_frames(20)
	Input.action_release(&"move_forward")
	_expect(_driver.current_state() == HeroineClips.LOCOMOTION, "no clips: moving stays in locomotion")
	await _physics_frames(20)
	await _tap(&"jump", 20)
	_expect(await _wait_state(HeroineClips.FALL), "no clips: jump → fall")
	_expect(await _wait_state(HeroineClips.LOCOMOTION, 240), "no clips: landed → locomotion")
	Input.action_press(&"block")
	_expect(await _wait_state(HeroineClips.GUARD), "no clips: guard")
	Input.action_release(&"block")
	await _physics_frames(10)
	await _tap(&"attack")
	_expect(await _wait_state(HeroineClips.attack_state(_combat.current_form().light_combo[0])), "no clips: attack")
	_expect(await _wait_state(HeroineClips.LOCOMOTION, 200), "no clips: attack over")
	await _tap(&"switch_form")
	await _physics_frames(30)
	await _tap(&"dodge")
	_expect(await _wait_state(HeroineClips.DODGE), "no clips: dodge")
	_expect(await _wait_state(HeroineClips.LOCOMOTION), "no clips: dodge over")
	_player_c.take_posture_damage(_player_c.config.posture.max_posture * 2.0)
	_expect(await _wait_state(HeroineClips.STAGGER), "no clips: stagger")
	world.queue_free()
	await _physics_frames(2)


## A heroine whose saved tree has stale one-shot timelines and whose HeroineAnimConfig was
## tuned after the last rebuild: at start-up the driver re-times every one-shot state from
## the live data (refresh_timelines).
func _test_live_timelines() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var heroine: PlayerController = (load(HEROINE) as PackedScene).instantiate() as PlayerController
	var tree: AnimationTree = heroine.get_node("AnimationTree") as AnimationTree
	var saved: AnimationNodeStateMachine = tree.tree_root as AnimationNodeStateMachine
	var stale: AnimationNodeStateMachine = saved.duplicate(true) as AnimationNodeStateMachine
	_expect(stale.get_node(HeroineClips.JUMP) != saved.get_node(HeroineClips.JUMP), "the stale tree is a deep copy")
	for state: StringName in stale.get_node_list():
		for clip_node: AnimationNodeAnimation in HeroineAnimTree.clip_nodes_of(stale.get_node(state)):
			if clip_node.use_custom_timeline:
				clip_node.timeline_length = 0.5 # 30 frames: matches none of the gameplay lengths
	tree.tree_root = stale
	var driver: HeroineAnimationDriver = heroine.get_node("AnimationDriver") as HeroineAnimationDriver
	var tuned: HeroineAnimConfig = driver.config.duplicate() as HeroineAnimConfig
	tuned.hit_react_frames += 7
	tuned.parry_frames += 5
	driver.config = tuned
	world.add_child(heroine)
	_bind(heroine)
	await _physics_frames(2)

	var combat: PlayerCombat = heroine.combat
	var expected: Dictionary[StringName, int] = {
		HeroineClips.JUMP: tuned.jump_frames,
		HeroineClips.LAND: tuned.land_frames,
		HeroineClips.GUARD_HIT: tuned.guard_hit_frames,
		HeroineClips.PARRY: tuned.parry_frames,
		HeroineClips.HIT_REACT: tuned.hit_react_frames,
		HeroineClips.REST: tuned.rest_frames,
		HeroineClips.DEATH: tuned.death_frames,
		HeroineClips.HEAL: heroine.healing.config.use_frames,
		HeroineClips.DEATHBLOW: combat.deathblow.recovery_frames,
	}
	for attack: AttackData in HeroineClips.attacks_of(combat.forms):
		expected[HeroineClips.attack_state(attack)] = attack.total_frames()
	var sm: AnimationNodeStateMachine = _tree.tree_root as AnimationNodeStateMachine
	var wrong: Array[String] = []
	for state: StringName in expected:
		var node: AnimationNodeAnimation = sm.get_node(state) as AnimationNodeAnimation
		var want: float = expected[state] / 60.0
		if node == null or not node.use_custom_timeline or absf(node.timeline_length - want) > 0.0001:
			wrong.append("%s %.3f≠%.3f" % [state, node.timeline_length if node != null else -1.0, want])
	_expect(wrong.is_empty(), "start-up re-times every one-shot from the live data (wrong: %s)" % [wrong])
	world.queue_free()
	await _physics_frames(2)


## Open ground 10 m in front (+Z) of the dummy, facing it, camera yaw 0, on the floor.
func _place_open() -> void:
	_player.global_position = _dummy.global_position + Vector3(0.0, 0.0, 10.0)
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3.FORWARD)
	_player.camera_rig.set_view_yaw(0.0)
	_player.reset_physics_interpolation()
	await _physics_frames(3)


## Waits up to `frames` physics frames for the tree to be in `state`.
func _wait_state(state: StringName, frames: int = STATE_WAIT_FRAMES) -> bool:
	for i: int in frames:
		if _driver.current_state() == state:
			return true
		await physics_frame
	printerr("    (state is %s, driver wants %s)" % [_driver.current_state(), _driver.requested_state])
	return false


## Where the playback is in the current state's clip (seconds).
func _play_position() -> float:
	return _driver.playback.get_current_play_position() if _driver.playback != null else 0.0


## Waits for `state`'s clip to jump back before `before` (it was restarted) without
## leaving `state`. A hit-stop may hold the driver for a few frames first.
func _wait_restarted(state: StringName, before: float, frames: int = 30) -> bool:
	for i: int in frames:
		await physics_frame
		if _driver.current_state() != state:
			break
		if _play_position() < before - 0.02:
			return true
	printerr("    (state %s, position %.3f, was %.3f)" % [_driver.current_state(), _play_position(), before])
	return false


## `order` appears in _seen as a subsequence.
func _ordered(order: Array[StringName]) -> bool:
	var at: int = 0
	for s: StringName in _seen:
		if at < order.size() and s == order[at]:
			at += 1
	return at == order.size()


func _tap(action: StringName, hold_frames: int = 2) -> void:
	Input.action_press(action)
	await _physics_frames(hold_frames)
	Input.action_release(action)


func _physics_frames(count: int) -> void:
	for i: int in count:
		await physics_frame


func _on_physics_frame() -> void:
	if _driver != null and is_instance_valid(_driver) and _driver.is_inside_tree():
		var s: StringName = _driver.current_state()
		if _seen.is_empty() or _seen[-1] != s:
			_seen.append(s)
	_frames_run += 1
	if _frames_run > MAX_RUN_FRAMES and not _finished:
		_expect(false, "finished within %d frames (watchdog)" % MAX_RUN_FRAMES)
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_expect(_errors.errors == 0, "no engine/script errors (%d; first: %s)" % [_errors.errors, _errors.first_error])
	print("ANIMATION SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)
