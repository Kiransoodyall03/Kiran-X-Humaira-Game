extends SceneTree
## Headless smoke test for the heroine's attacks, sword forms and katana dodge, in the
## sandbox with the real input actions. Checks that both forms damage the training dummy
## through its hurtbox (once per swing), the greatsword combo chains from buffered
## presses, switch_form mid-combo continues the combo in the katana, the HUD follows the
## form, the katana can't block, katana dodges make the dummy's attacks (perilous ones
## too) come back DODGED, the greatsword can't dodge, a staggered heroine can't attack,
## and a defeated dummy is revived by SandboxRules. Also checks, in open ground: form speed
## multipliers, dodge distance and backward direction, lunge distance, no dodge in
## startup, no attack in the air, greatsword block-cancel out of recovery, a posture
## break cancelling a swing, hits going through the best hurtbox, and a greatsword block
## tap still parrying unless a switch to the katana or a swing forced the guard down.
## Fails on any engine/script error, and on a frame-budget timeout instead of hanging.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/forms_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
## Press dodge this many frames before the dummy's hit lands (inside the i-frames).
const DODGE_LEAD_FRAMES: int = 5
const ATTACK_WAIT_FRAMES: int = 600
const MAX_RUN_FRAMES: int = 20000

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _player: PlayerController
var _combat: PlayerCombat
var _player_c: Combatant
var _dummy: TrainingDummy
var _dummy_c: Combatant
var _hud: CombatHud
var _rules: SandboxRules
## Results of the heroine's swings on the dummy.
var _landed: Array[HitResult] = []
## Results of the dummy's attacks on the heroine.
var _defended: Array[HitResult] = []
var _started: Array[AttackData] = []
var _self_hits: int = 0
## Katana top walking speed, compared with the greatsword's.
var _katana_speed: float = 0.0


func _initialize() -> void:
	OS.add_logger(_errors)
	physics_frame.connect(_watchdog)
	_run.call_deferred()


func _run() -> void:
	var level: Node = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(level)
	_player = level.get_node("Heroine") as PlayerController
	_combat = _player.combat
	_player_c = _player.combatant
	_dummy = level.get_node("TrainingDummy") as TrainingDummy
	_dummy_c = _dummy.get_combatant()
	_hud = level.get_node("CombatHud") as CombatHud
	_rules = level.get_node("SandboxRules") as SandboxRules
	_expect(_combat != null, "the heroine has a PlayerCombat")
	_expect(_dummy.get_node_or_null("Hurtbox") is Hurtbox, "the dummy has a Hurtbox")
	_combat.attack_landed.connect(func(r: HitResult, _t: Combatant, _h: Hurtbox) -> void: _landed.append(r))
	_combat.attack_started.connect(func(a: AttackData, _s: int) -> void: _started.append(a))
	_player_c.attack_resolved.connect(func(r: HitResult, attacker: Combatant) -> void:
		_defended.append(r)
		if attacker == _player_c:
			_self_hits += 1)

	_dummy.attacking_enabled = false
	await _physics_frames(10)
	_place_player()

	await _test_greatsword_hits()
	await _test_greatsword_combo_chains()
	await _test_switch_mid_combo()
	await _test_katana_cannot_block()
	await _test_katana_dodges()
	await _test_katana_movement()
	await _test_greatsword_cannot_dodge()
	await _test_greatsword_movement_and_block_cancel()
	await _test_staggered_cannot_attack()
	await _test_stagger_cancels_swing()
	await _test_best_hurtbox()
	await _test_forced_guard_drop_closes_parry()
	await _test_dummy_dies_and_revives()
	_expect(_self_hits == 0, "her swings never hit her own hurtbox")
	_finish()


func _test_greatsword_hits() -> void:
	var gs: FormConfig = _combat.current_form()
	_expect(gs.id == &"greatsword", "she starts in the greatsword form")
	await _hud_refresh()
	_expect(_hud.form_text() == "GREATSWORD", "HUD shows the greatsword form (%s)" % _hud.form_text())
	var health: float = _dummy_c.health
	var before: int = _landed.size()
	await _tap(&"attack")
	_expect(_combat.is_attacking(), "attack starts a swing")
	await _wait_idle()
	var a: AttackData = gs.light_combo[0]
	_expect(_landed.size() - before == 1, "one swing lands exactly once (%d results)" % (_landed.size() - before))
	_expect(is_equal_approx(health - _dummy_c.health, a.damage), "greatsword light 1 dealt %.0f health damage (dealt %.1f)" % [a.damage, health - _dummy_c.health])
	_expect(_dummy_c.posture.value > 0.0, "the hit filled some of the dummy's posture")


## Buffered presses during each swing chain the whole 3-hit combo; sprint can't speed it up.
func _test_greatsword_combo_chains() -> void:
	await _physics_frames(60) # let the combo window close
	_place_player()
	_started.clear()
	var before: int = _landed.size()
	Input.action_press(&"sprint")
	await _tap(&"attack")
	var max_speed: float = 0.0
	for step: int in 2:
		# Wait for swing `step` to reach recovery, then press to buffer the next step.
		for i: int in 200:
			if _started.size() == step + 1 and _combat.combo.phase() == ComboRunner.Phase.RECOVERY:
				break
			await physics_frame
			max_speed = maxf(max_speed, Vector2(_player.velocity.x, _player.velocity.z).length())
		await _tap(&"attack")
	await _wait_idle()
	Input.action_release(&"sprint")
	var ids: Array[StringName] = []
	for a: AttackData in _started:
		ids.append(a.id)
	_expect(ids == [&"greatsword_light_1", &"greatsword_light_2", &"greatsword_light_3"], "buffered presses chain the greatsword combo (%s)" % [ids])
	_expect(_landed.size() - before == 3, "each of the 3 swings hit the dummy once (%d)" % (_landed.size() - before))
	_expect(max_speed < _player.config.walk_speed, "no sprinting while attacking (top speed %.2f m/s)" % max_speed)


## Greatsword swing → switch_form in its recovery → the next press is katana step 2.
func _test_switch_mid_combo() -> void:
	await _physics_frames(60)
	_place_player()
	_started.clear()
	var forms_seen: Array[StringName] = []
	_combat.form_changed.connect(func(f: FormConfig) -> void: forms_seen.append(f.id), CONNECT_ONE_SHOT)
	await _tap(&"attack")
	for i: int in 200:
		if _combat.combo.phase() == ComboRunner.Phase.RECOVERY:
			break
		await physics_frame
	_expect(_combat.combo.phase() == ComboRunner.Phase.RECOVERY, "greatsword swing reached recovery")
	await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"katana", "switch_form mid-combo changes to the katana")
	_expect(forms_seen == [&"katana"], "form_changed fired once with the katana")
	_expect(not _combat.is_attacking(), "the switch cancelled the greatsword recovery")
	await _physics_frames(2)
	await _hud_refresh()
	_expect(_hud.form_text() == "KATANA", "HUD shows the katana form (%s)" % _hud.form_text())
	var health: float = _dummy_c.health
	await _tap(&"attack")
	await _wait_idle()
	var ids: Array[StringName] = []
	for a: AttackData in _started:
		ids.append(a.id)
	_expect(ids == [&"greatsword_light_1", &"katana_light_2"], "the combo continues in the katana (%s)" % [ids])
	var dealt: float = health - _dummy_c.health
	_expect(is_equal_approx(dealt, _combat.current_form().light_combo[1].damage), "katana light 2 damaged the dummy (%.1f)" % dealt)


func _test_katana_cannot_block() -> void:
	await _hud_refresh()
	_expect(_hud.dodge_text() == "Dodge: ready", "HUD shows the dodge is ready (%s)" % _hud.dodge_text())
	_player_c.revive()
	_dummy_c.revive()
	_place_player()
	_dummy.attacking_enabled = true
	var a: AttackData = await _next_attack()
	while a != null and not a.blockable:
		a = await _next_attack()
	var before: int = _defended.size()
	Input.action_press(&"block")
	await _physics_frames(2)
	_expect(not _player.is_guarding(), "holding block in katana form raises no guard")
	var r: HitResult = await _result_for_this_swing(a, before)
	Input.action_release(&"block")
	_expect_outcome(r, HitResult.Outcome.HIT, "a held block does nothing in katana form (%s)" % (a.id if a != null else &""))


## Dodge (forward, into the dummy, so she stays in reach) through five attacks in a row,
## which covers the thrust and sweep.
func _test_katana_dodges() -> void:
	_player_c.revive()
	_place_player()
	_player.camera_rig.set_view_yaw(0.0) # move_forward = world -Z = toward the dummy
	var perilous_dodged: int = 0
	var dodged: int = 0
	var dodge_starts: Array[int] = [0]
	var on_dodge: Callable = func(_d: Vector3) -> void: dodge_starts[0] += 1
	_combat.dodge_started.connect(on_dodge)
	for i: int in 5:
		var a: AttackData = await _next_attack()
		if a == null:
			break
		var before: int = _defended.size()
		var health: float = _player_c.health
		await _physics_frames(a.startup_frames - DODGE_LEAD_FRAMES)
		Input.action_press(&"move_forward")
		await _tap(&"dodge")
		_expect(_combat.is_dodging(), "katana dodge started before %s" % a.id)
		Input.action_release(&"move_forward")
		await _hud_refresh()
		_expect(_hud.dodge_text() != "Dodge: ready", "HUD shows the dodge cooling down (%s)" % _hud.dodge_text())
		var r: HitResult = await _result_for_this_swing(a, before)
		_expect_outcome(r, HitResult.Outcome.DODGED, "dodge through %s" % a.id)
		_expect(is_equal_approx(_player_c.health, health), "no damage through the i-frames")
		if r != null and r.outcome == HitResult.Outcome.DODGED:
			dodged += 1
			if a.perilous != AttackData.Perilous.NONE:
				perilous_dodged += 1
		_place_player()
	_combat.dodge_started.disconnect(on_dodge)
	_expect(dodge_starts[0] == 5, "five dodges started (%d)" % dodge_starts[0])
	_expect(perilous_dodged >= 2, "perilous attacks are dodged too (%d)" % perilous_dodged)
	_dummy.attacking_enabled = false
	await _physics_frames(60)


func _test_greatsword_cannot_dodge() -> void:
	await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"greatsword", "switch_form toggles back to the greatsword")
	await _tap(&"dodge")
	_expect(not _combat.is_dodging(), "the greatsword has no dodge")
	_expect(not _player_c.is_invulnerable(), "…and no i-frames")
	await _hud_refresh()
	_expect(_hud.dodge_text().begins_with("Dodge: —"), "HUD shows no dodge in greatsword form (%s)" % _hud.dodge_text())


func _test_staggered_cannot_attack() -> void:
	_player_c.revive()
	_player_c.take_posture_damage(10000.0)
	_expect(_player_c.is_staggered(), "a full posture bar staggers her")
	await _tap(&"attack")
	_expect(not _combat.is_attacking(), "a staggered heroine can't attack")
	await _combat_frames(_player_c.config.posture.break_stagger_frames + 2)
	_expect(not _player_c.is_staggered(), "the stagger ends")


## Greatsword swings until the dummy dies; then SandboxRules revives it.
func _test_dummy_dies_and_revives() -> void:
	_player_c.revive()
	_dummy_c.revive()
	_place_player()
	await _physics_frames(30)
	for i: int in 30:
		if _dummy_c.is_dead:
			break
		_place_player()
		await _tap(&"attack")
		await _wait_idle()
	_expect(_dummy_c.is_dead, "enough greatsword swings defeat the dummy")
	_expect(_dummy.phase == TrainingDummy.Phase.DEAD, "the dummy is in its DEAD phase")
	await _physics_frames(_rules.dummy_revive_delay_frames + 2)
	_expect(not _dummy_c.is_dead and is_equal_approx(_dummy_c.health, _dummy_c.config.max_health), "SandboxRules revives the dummy at full health")
	_expect(_dummy.phase == TrainingDummy.Phase.IDLE, "the revived dummy is idle again")


## Katana in open ground (dummy idle, 10 m away): speed, dodge distance, backward dodge,
## no dodge during startup, lunge distance, no attack while airborne.
func _test_katana_movement() -> void:
	var katana: FormConfig = _combat.current_form()
	_expect(katana.id == &"katana", "still in the katana form")
	_katana_speed = await _top_walk_speed()
	var expected: float = _player.config.walk_speed * katana.move_speed_multiplier
	_expect(absf(_katana_speed - expected) < 0.05, "katana walks at %.2f m/s (%.2f)" % [expected, _katana_speed])

	# No move input: the dodge goes backward from her facing, and stops at its distance.
	await _place_open()
	await _wait_dodge_ready()
	var start: Vector3 = _player.global_position
	await _tap(&"dodge")
	_expect(_combat.is_dodging(), "no-input dodge started")
	for i: int in 120:
		if not _combat.is_dodging():
			break
		await physics_frame
	await _physics_frames(30) # any slide after the dash would show up here
	var moved: Vector3 = _player.global_position - start
	moved.y = 0.0
	_expect(moved.normalized().dot(_player.get_facing_direction()) < -0.95, "a no-input dodge goes backward (moved %s)" % moved)
	_expect(absf(moved.length() - katana.dodge_distance) < 0.15, "dodge covers %.2f m (%.2f m)" % [katana.dodge_distance, moved.length()])

	# Dodge is refused during a swing's startup.
	await _place_open()
	await _wait_dodge_ready()
	await _physics_frames(40) # let the combo window close
	_started.clear()
	start = _player.global_position
	Input.action_press(&"attack")
	for i: int in 5:
		await physics_frame
		if _combat.is_attacking():
			break
	Input.action_release(&"attack")
	_expect(_combat.combo.phase() == ComboRunner.Phase.STARTUP, "the swing is in startup (phase %d, frame %d)" % [_combat.combo.phase(), _combat.combo.swing_frame])
	await _tap(&"dodge", 1)
	_expect(not _combat.is_dodging() and _combat.is_attacking(), "dodge pressed in startup is refused")
	# The lunge of this swing: lunge_distance forward over startup + active frames.
	await _wait_idle()
	await _physics_frames(10)
	var a: AttackData = _started[0] if not _started.is_empty() else null
	_expect(a != null, "the katana swing started")
	if a != null:
		var lunge: float = (_player.global_position - start).dot(_player.get_facing_direction())
		_expect(absf(lunge - a.lunge_distance) < 0.05, "%s lunges %.2f m forward (%.2f m)" % [a.id, a.lunge_distance, lunge])

	# No attack while airborne.
	await _place_open()
	await _physics_frames(40)
	await _tap(&"jump")
	for i: int in 20:
		if not _player.is_on_floor():
			break
		await physics_frame
	_expect(not _player.is_on_floor(), "the jump left the ground")
	await _tap(&"attack")
	_expect(not _combat.is_attacking(), "no attack starts in the air")
	for i: int in 200:
		if _player.is_on_floor():
			break
		await physics_frame
	await _physics_frames(10)


## Greatsword walks slower than the katana; a block press in recovery cancels into guard.
func _test_greatsword_movement_and_block_cancel() -> void:
	var gs: FormConfig = _combat.current_form()
	_expect(gs.id == &"greatsword", "back in the greatsword form")
	var speed: float = await _top_walk_speed()
	var expected: float = _player.config.walk_speed * gs.move_speed_multiplier
	_expect(absf(speed - expected) < 0.05, "greatsword walks at %.2f m/s (%.2f)" % [expected, speed])
	_expect(_katana_speed > speed * 1.1, "the katana is faster (%.2f vs %.2f m/s)" % [_katana_speed, speed])

	await _place_open()
	await _physics_frames(40)
	await _tap(&"attack")
	for i: int in 200:
		if _combat.combo.phase() == ComboRunner.Phase.RECOVERY:
			break
		await physics_frame
	_expect(_combat.combo.phase() == ComboRunner.Phase.RECOVERY, "greatsword swing reached recovery")
	Input.action_press(&"block")
	await _physics_frames(2)
	_expect(not _combat.is_attacking(), "block in recovery cancels the swing")
	_expect(_player.is_guarding(), "block in recovery raises the guard")
	Input.action_release(&"block")
	await _physics_frames(10)


## A posture break during a swing's startup cancels it.
func _test_stagger_cancels_swing() -> void:
	_player_c.revive()
	await _place_open()
	await _physics_frames(40)
	await _tap(&"attack")
	_expect(_combat.is_attacking(), "swing started before the posture break")
	_player_c.take_posture_damage(10000.0)
	_expect(_player_c.is_staggered(), "posture broken mid-swing")
	_expect(not _combat.is_attacking(), "the posture break cancels the swing")
	await _combat_frames(_player_c.config.posture.break_stagger_frames + 2)
	_player_c.revive()


## With two hurtboxes on the dummy, a swing hits it once, through the one with the
## higher damage multiplier, whichever that is.
func _test_best_hurtbox() -> void:
	var original: Hurtbox = _dummy.get_node("Hurtbox") as Hurtbox
	var extra: Hurtbox = Hurtbox.new()
	extra.name = "ExtraHurtbox"
	extra.part_id = &"head"
	var shape: CollisionShape3D = (original.get_child(0) as CollisionShape3D).duplicate() as CollisionShape3D
	extra.add_child(shape)
	extra.transform = original.transform
	_dummy.add_child(extra)
	await _physics_frames(2)
	for multiplier: float in [2.0, 0.5]:
		extra.damage_multiplier = multiplier
		_dummy_c.revive()
		_player_c.revive()
		await _physics_frames(40)
		_place_player()
		var health: float = _dummy_c.health
		var before: int = _landed.size()
		_started.clear()
		await _tap(&"attack")
		await _wait_idle()
		var a: AttackData = _started[0] if not _started.is_empty() else null
		var best: float = maxf(multiplier, original.damage_multiplier)
		_expect(_landed.size() - before == 1, "two hurtboxes: one hit (%d)" % (_landed.size() - before))
		_expect(a != null, "the swing started")
		if a != null:
			_expect(is_equal_approx(health - _dummy_c.health, a.damage * best), "hit goes through the x%.1f hurtbox (dealt %.1f)" % [best, health - _dummy_c.health])
	_dummy.remove_child(extra)
	extra.free()
	await _physics_frames(2)


## A tapped (pressed and released) greatsword block still parries a hit landing inside its
## window, but switching to the katana or starting a swing right after the tap closes that
## window: no parry in katana form or mid-swing.
func _test_forced_guard_drop_closes_parry() -> void:
	var attacking: bool = _dummy.attacking_enabled
	_dummy.attacking_enabled = false
	var hit: AttackData = load("res://data/attacks/duelist_quick_slash.tres") as AttackData
	_expect(hit != null and hit.deflectable and hit.blockable, "test attack is deflectable and blockable")
	_expect(_combat.current_form().id == &"greatsword", "forced guard drop test starts in the greatsword")
	_player_c.revive()
	await _place_open()
	await _combat_frames(40)

	await _tap(&"block")
	await _physics_frames(1) # the controller sees the release
	_expect(not _player_c.guard.is_held, "tapped block is released")
	_expect_outcome(_player_c.receive_attack(hit), HitResult.Outcome.PARRIED, "a tapped greatsword block parries inside its window")
	await _combat_frames(40)

	await _tap(&"block")
	await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"katana", "switched to the katana right after the block tap")
	var since: int = _player_c.guard.frames_since_press(Combatant.current_frame())
	_expect(since >= 0 and since < _player_c.guard.current_window(), "still inside the press's parry window (%d frames)" % since)
	_expect_outcome(_player_c.receive_attack(hit), HitResult.Outcome.HIT, "no parry in katana form from a greatsword block press")
	await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"greatsword", "back to the greatsword")
	_player_c.revive()
	await _combat_frames(40)

	await _tap(&"block")
	await _tap(&"attack")
	_expect(_combat.is_attacking(), "swing started right after the block tap")
	since = _player_c.guard.frames_since_press(Combatant.current_frame())
	_expect(since >= 0 and since < _player_c.guard.current_window(), "still inside the press's parry window (%d frames)" % since)
	var r: HitResult = _player_c.receive_attack(hit)
	_expect(r != null and r.outcome != HitResult.Outcome.PARRIED, "no parry while attacking (got %s)" % (r.outcome_name() if r != null else "nothing"))
	await _wait_idle()
	_player_c.revive()
	await _combat_frames(40)
	_dummy.attacking_enabled = attacking


## Holds move_forward (world -Z) for a second from open ground; returns the speed reached.
func _top_walk_speed() -> float:
	await _place_open()
	Input.action_press(&"move_forward")
	await _physics_frames(60)
	var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	Input.action_release(&"move_forward")
	await _physics_frames(30)
	return speed


## Open ground 10 m in front (+Z) of the dummy, facing it, camera yaw 0, on the floor.
func _place_open() -> void:
	_player.global_position = _dummy.global_position + Vector3(0.0, 0.0, 10.0)
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3.FORWARD)
	_player.camera_rig.set_view_yaw(0.0)
	_player.reset_physics_interpolation()
	await _physics_frames(3)


func _wait_dodge_ready() -> void:
	for i: int in 200:
		if _combat.dodge_ready():
			return
		await physics_frame


func _place_player() -> void:
	# Stand 2 m in front (+Z) of the dummy, facing it.
	_player.global_position = _dummy.global_position + Vector3(0.0, 0.0, 2.0)
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3.FORWARD)
	_player.reset_physics_interpolation()


func _wait_idle() -> void:
	for i: int in 400:
		if not _combat.is_busy():
			return
		await physics_frame
	_expect(false, "the swing finished within 400 frames")


func _next_attack() -> AttackData:
	var last: TrainingDummy.Phase = _dummy.phase
	for i: int in ATTACK_WAIT_FRAMES:
		await physics_frame
		if _dummy.phase == TrainingDummy.Phase.STARTUP and last != TrainingDummy.Phase.STARTUP:
			return _dummy.current_attack
		last = _dummy.phase
	_expect(false, "dummy started a new attack within %d frames" % ATTACK_WAIT_FRAMES)
	return null


func _result_for_this_swing(attack: AttackData, before: int) -> HitResult:
	if attack == null:
		return null
	for i: int in ATTACK_WAIT_FRAMES:
		if _dummy.phase != TrainingDummy.Phase.STARTUP and _dummy.phase != TrainingDummy.Phase.ACTIVE:
			break
		await physics_frame
	await _physics_frames(1)
	for i: int in range(before, _defended.size()):
		if _defended[i].attack == attack:
			return _defended[i]
	return null


func _tap(action: StringName, hold_frames: int = 2) -> void:
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
	print("FORMS SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
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


## CombatHud refreshes its widgets in _process, and physics_frame waits don't promise a
## process frame ran after them (several physics ticks can run in one frame). Its
## `refreshed` signal fires at the end of that _process, so a read right after it sees the
## latest physics tick, with no tick (and no camera/body move) in between.
func _hud_refresh() -> void:
	await _hud.refreshed
