extends SceneTree
## Headless combat smoke test: the heroine spars with the training dummy in the sandbox
## using the real input actions. Checks that a timed tap parries, an early hold blocks,
## the thrust can't be blocked, the sweep can be jumped, parrying breaks the dummy's
## posture and it recovers, long blocking breaks the heroine's guard, a held block comes
## back after the stagger, a same-tick tap doesn't stick, and a defeated heroine can't move.
## Fails on any engine/script error, and on a frame-budget timeout instead of hanging.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/combat_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
## Press guard this many frames before the hit lands (inside the 12-frame window).
const PARRY_LEAD_FRAMES: int = 6
## Longest wait for the dummy's next wind-up before failing.
const ATTACK_WAIT_FRAMES: int = 600
## Whole-run watchdog.
const MAX_RUN_FRAMES: int = 20000

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _player: PlayerController
var _player_c: Combatant
var _dummy: TrainingDummy
var _dummy_c: Combatant
var _results: Array[HitResult] = []
var _dummy_broken: bool = false


func _initialize() -> void:
	OS.add_logger(_errors)
	physics_frame.connect(_watchdog)
	_run.call_deferred()


func _run() -> void:
	var level: Node = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(level)
	_player = level.get_node("Heroine") as PlayerController
	_player_c = _player.combatant
	_dummy = level.get_node("TrainingDummy") as TrainingDummy
	_dummy_c = _dummy.get_combatant()
	_player_c.attack_resolved.connect(func(r: HitResult, _a: Combatant) -> void: _results.append(r))
	_dummy_c.posture_broken.connect(func() -> void: _dummy_broken = true)

	_expect(_player_c != null and _dummy_c != null, "heroine and dummy both have a Combatant")
	await _physics_frames(10)
	_place_player()

	# Attack 1: overhead → tap guard just before it lands → parry.
	var a: AttackData = await _next_attack()
	var before: int = _results.size()
	_expect(a != null and a.id == &"dummy_overhead", "first attack is the overhead")
	await _physics_frames(a.startup_frames - PARRY_LEAD_FRAMES)
	await _tap(&"block", 2)
	var r: HitResult = await _result_for_this_swing(a, before)
	_expect_outcome(r, HitResult.Outcome.PARRIED, "timed tap parries the overhead")
	_expect(is_equal_approx(_dummy_c.posture.value, a.posture_damage), "parry dealt %.0f posture to the dummy (has %.1f)" % [a.posture_damage, _dummy_c.posture.value])
	_expect(is_equal_approx(_player_c.health, _player_c.config.max_health), "parry costs no health")

	# Attack 2: overhead → hold guard from the start of the wind-up → block.
	a = await _next_attack()
	before = _results.size()
	Input.action_press(&"block")
	await _physics_frames(1)
	_expect(_player.is_guarding(), "holding block raises the guard")
	var r2: HitResult = await _result_for_this_swing(a, before)
	Input.action_release(&"block")
	await _physics_frames(1)
	_expect_outcome(r2, HitResult.Outcome.BLOCKED, "early hold blocks the overhead")
	_expect(_player_c.posture.value > 0.0, "blocking filled some of the heroine's posture")
	_expect(not _player.is_guarding(), "releasing block lowers the guard")

	# Attack 3: thrust (perilous) → holding guard does not stop it.
	a = await _next_attack()
	before = _results.size()
	_expect(a != null and a.id == &"dummy_thrust", "third attack is the thrust")
	Input.action_press(&"block")
	var r3: HitResult = await _result_for_this_swing(a, before)
	Input.action_release(&"block")
	_expect_outcome(r3, HitResult.Outcome.HIT, "a held guard can't block the thrust")

	# Attack 4: overhead, undefended → hit.
	a = await _next_attack()
	before = _results.size()
	var r4: HitResult = await _result_for_this_swing(a, before)
	_expect_outcome(r4, HitResult.Outcome.HIT, "undefended overhead hits")

	# Attack 5: sweep → jump over it → no hit at all.
	a = await _next_attack()
	before = _results.size()
	var health_before_sweep: float = _player_c.health
	_expect(a != null and a.id == &"dummy_sweep", "fifth attack is the sweep")
	await _physics_frames(a.startup_frames - PARRY_LEAD_FRAMES)
	await _tap(&"jump", 10)
	var r5: HitResult = await _result_for_this_swing(a, before)
	_expect(r5 == null and is_equal_approx(_player_c.health, health_before_sweep), "jumping clears the sweep")

	# Keep answering correctly until the dummy's posture breaks.
	for i: int in 12:
		if _dummy_broken:
			break
		a = await _next_attack()
		if a == null:
			break
		await _physics_frames(a.startup_frames - PARRY_LEAD_FRAMES)
		await _tap(&"block" if a.deflectable else &"jump", 2 if a.deflectable else 10)
		await _physics_frames(a.active_frames + 2)
	_expect(_dummy_broken, "parrying broke the dummy's posture")
	_expect(_dummy.phase == TrainingDummy.Phase.STAGGERED, "the dummy is staggered after its posture broke")

	# The dummy recovers after its stagger and attacks again.
	await _combat_frames(_dummy_c.config.posture.break_stagger_frames + 2)
	_expect(_dummy.phase == TrainingDummy.Phase.IDLE and is_zero_approx(_dummy_c.posture.value), "dummy recovers from the stagger with empty posture")
	_expect(await _next_attack() != null, "dummy attacks again after recovering")

	await _test_same_tick_tap()
	await _test_guard_break_and_hold_through()
	await _test_defeated_cannot_move()
	_finish()


## A press and release inside one physics tick must not leave the guard stuck on.
func _test_same_tick_tap() -> void:
	_dummy.attacking_enabled = false
	_player_c.revive()
	await _physics_frames(5)
	var press: InputEventAction = InputEventAction.new()
	press.action = &"block"
	press.pressed = true
	var release: InputEventAction = InputEventAction.new()
	release.action = &"block"
	release.pressed = false
	Input.parse_input_event(press)
	Input.parse_input_event(release)
	await _physics_frames(3)
	_expect(not _player_c.guard.is_held, "a same-tick tap doesn't leave the guard stuck on")
	var since: int = _player_c.guard.frames_since_press(Combatant.current_frame())
	_expect(since >= 0 and since < 6, "…but it still opened a parry window (pressed %d frames ago)" % since)


## Holding block against the dummy's swings fills posture until the guard breaks; a
## button still held after the stagger raises the guard again.
func _test_guard_break_and_hold_through() -> void:
	_player_c.revive()
	_dummy_c.revive()
	_dummy.attacking_enabled = true
	_place_player()
	var broke: Array[bool] = [false]
	var on_broken: Callable = func() -> void: broke[0] = true
	_player_c.posture_broken.connect(on_broken)
	Input.action_press(&"block")
	for i: int in 10:
		if broke[0] or _player_c.is_dead:
			break
		var a: AttackData = await _next_attack()
		if a == null:
			break
		await _physics_frames(a.startup_frames + a.active_frames + 1)
	_expect(broke[0], "holding block long enough breaks the heroine's guard")
	_expect(_player_c.is_staggered(), "a guard break staggers the heroine")
	_expect(not _player.is_guarding(), "no guard while staggered")
	_dummy.attacking_enabled = false
	await _combat_frames(_player_c.config.posture.break_stagger_frames + 3)
	_expect(not _player_c.is_staggered(), "the stagger ends")
	_expect(_player.is_guarding(), "block held through the stagger comes back up afterwards")
	Input.action_release(&"block")
	_player_c.posture_broken.disconnect(on_broken)
	await _physics_frames(2)


## A defeated heroine can't move until revived.
func _test_defeated_cannot_move() -> void:
	_dummy.attacking_enabled = false
	_player_c.revive()
	var killer: AttackData = AttackData.new()
	killer.damage = 1000.0
	_player_c.receive_attack(killer)
	_expect(_player_c.is_dead, "a big hit defeats the heroine")
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_forward")
	await _physics_frames(30)
	Input.action_release(&"move_forward")
	var moved: float = (_player.global_position - start).length()
	_expect(moved < 0.05, "a defeated heroine can't move (moved %.2f m)" % moved)
	await _physics_frames(120)
	_expect(not _player_c.is_dead, "the sandbox revives her")


func _place_player() -> void:
	# Stand 2 m in front of the dummy.
	_player.global_position = _dummy.global_position + Vector3(0.0, 0.0, 2.0)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


## Waits (up to ATTACK_WAIT_FRAMES) for the dummy to start its next wind-up.
func _next_attack() -> AttackData:
	var last: TrainingDummy.Phase = _dummy.phase
	for i: int in ATTACK_WAIT_FRAMES:
		await physics_frame
		if _dummy.phase == TrainingDummy.Phase.STARTUP and last != TrainingDummy.Phase.STARTUP:
			return _dummy.current_attack
		last = _dummy.phase
	_expect(false, "dummy started a new attack within %d frames" % ATTACK_WAIT_FRAMES)
	return null


## Waits until the current swing's active frames are over; returns the result it
## produced on the heroine since `before`, or null if it never connected.
func _result_for_this_swing(attack: AttackData, before: int) -> HitResult:
	if attack == null:
		return null
	for i: int in ATTACK_WAIT_FRAMES:
		if _dummy.phase != TrainingDummy.Phase.STARTUP and _dummy.phase != TrainingDummy.Phase.ACTIVE:
			break
		await physics_frame
	await _physics_frames(1)
	for i: int in range(before, _results.size()):
		if _results[i].attack == attack:
			return _results[i]
	return null


func _tap(action: StringName, hold_frames: int) -> void:
	Input.action_press(action)
	await _physics_frames(hold_frames)
	Input.action_release(action)


func _physics_frames(count: int) -> void:
	for i: int in count:
		await physics_frame


## Waits `count` combat frames (physics ticks frozen by hit-stop don't count).
func _combat_frames(count: int) -> void:
	var target: int = Combatant.current_frame() + count
	for i: int in count + 600:
		if Combatant.current_frame() >= target:
			return
		await physics_frame


func _watchdog() -> void:
	_frames_run += 1
	if _frames_run > MAX_RUN_FRAMES and not _finished:
		_expect(false, "finished within %d frames (watchdog)" % MAX_RUN_FRAMES)
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_expect(_errors.errors == 0, "no engine/script errors (%d; first: %s)" % [_errors.errors, _errors.first_error])
	print("COMBAT SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect_outcome(r: HitResult, outcome: HitResult.Outcome, message: String) -> void:
	var got: String = "nothing" if r == null else r.outcome_name()
	_expect(r != null and r.outcome == outcome, "%s (got %s)" % [message, got])


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)
