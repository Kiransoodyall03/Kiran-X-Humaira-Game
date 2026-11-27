extends SceneTree
## Headless smoke test for the corruption meter v0 in the sandbox, with the real input
## actions. Checks that the katana raises corruption at its rate (and the HUD bar
## follows), the greatsword drains it at its in-combat rate next to the dummy and faster
## far from it once the in-combat linger runs out, a swing on the dummy puts her back in
## combat, a dead dummy in range doesn't count as a hostile (a living one does), a hit
## she takes puts her in combat for the linger, reaching 100% starts a rampage that refuses the katana dodge (HUD says so),
## the rampage ends when the greatsword drains the meter to the exit value or when her
## health turns critical, the input-hijack stub leaves movement alone,
## reset_at_shrine() empties the meter, and the meter is paused (no change at all) during
## hit-stop and while she is dead, then runs again once the freeze ends / she revives.
## Fails on any engine/script error, and on a frame-budget timeout instead of hanging.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/corruption_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
const MAX_RUN_FRAMES: int = 8000
## Combat frames each rate is measured over.
const MEASURE_FRAMES: int = 120

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _player: PlayerController
var _combat: PlayerCombat
var _player_c: Combatant
var _meter: CorruptionMeter
var _dummy: TrainingDummy
var _hud: CombatHud
var _cfg: CorruptionConfig
var _rampage_starts: int = 0
var _rampage_ends: Array[Corruption.RampageEnd] = []
var _reached: Array[float] = []


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
	_meter = _player.get_node_or_null("CorruptionMeter") as CorruptionMeter
	_dummy = level.get_node("TrainingDummy") as TrainingDummy
	_hud = level.get_node("CombatHud") as CombatHud
	_expect(_meter != null, "the heroine has a CorruptionMeter")
	if _meter == null:
		_finish()
		return
	_cfg = _meter.config
	_meter.rampage_started.connect(func() -> void: _rampage_starts += 1)
	_meter.rampage_ended.connect(func(r: Corruption.RampageEnd) -> void: _rampage_ends.append(r))
	_meter.threshold_reached.connect(func(t: float) -> void: _reached.append(t))
	_dummy.attacking_enabled = false
	await _physics_frames(10)

	await _test_katana_rises()
	await _test_greatsword_drains_in_combat()
	await _test_greatsword_drains_faster_out_of_combat()
	await _test_attack_puts_her_in_combat()
	await _test_dead_hostile_does_not_count()
	await _test_hit_taken_puts_her_in_combat()
	await _test_rampage_locks_dodge_and_drains_out()
	await _test_rampage_ends_at_critical_health()
	await _test_shrine_reset()
	await _test_paused_during_hitstop_and_death()
	_finish()


func _test_katana_rises() -> void:
	_place_near()
	_expect(_combat.current_form().id == &"greatsword", "she starts in the greatsword form")
	_expect(is_zero_approx(_meter.value()), "corruption starts at 0 (%.2f)" % _meter.value())
	await _hud_refresh()
	_expect(_hud.corruption_bar_value() >= 0.0, "the HUD shows a corruption bar")
	await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"katana", "switched to the katana")
	var katana: FormConfig = _combat.current_form()
	var start: float = _meter.value()
	await _combat_frames(MEASURE_FRAMES)
	var expected: float = katana.corruption_per_second * MEASURE_FRAMES / 60.0
	var rose: float = _meter.value() - start
	_expect(rose > 0.0, "the katana raises corruption")
	_expect(absf(rose - expected) < 0.15, "katana: +%.2f over %d frames (got %+.2f)" % [expected, MEASURE_FRAMES, rose])
	_expect(_meter.in_combat, "next to the dummy she is in combat")
	await _physics_frames(1)
	await _hud_refresh()
	_expect(absf(_hud.corruption_bar_value() - _meter.value()) < 0.1, "the HUD bar follows the meter (%.2f vs %.2f)" % [_hud.corruption_bar_value(), _meter.value()])
	_expect(_hud.corruption_text().begins_with("Corruption"), "the HUD shows a corruption line (%s)" % _hud.corruption_text())


func _test_greatsword_drains_in_combat() -> void:
	await _tap(&"switch_form")
	var gs: FormConfig = _combat.current_form()
	_expect(gs.id == &"greatsword", "switched back to the greatsword")
	_meter.corruption.set_value(40.0)
	var start: float = _meter.value()
	await _combat_frames(MEASURE_FRAMES)
	var expected: float = gs.corruption_per_second * MEASURE_FRAMES / 60.0
	var change: float = _meter.value() - start
	_expect(change < 0.0, "the greatsword drains corruption")
	_expect(absf(change - expected) < 0.15, "greatsword in combat: %.2f over %d frames (got %.2f)" % [expected, MEASURE_FRAMES, change])


func _test_greatsword_drains_faster_out_of_combat() -> void:
	await _place_far()
	_expect(not _meter.hostile_in_range(), "far from the dummy no hostile is in range")
	# Wait out any linger from earlier combat.
	await _combat_frames(_cfg.combat_linger_frames + 2)
	_expect(not _meter.in_combat, "away from the dummy she leaves combat")
	await _hud_refresh()
	_expect(_hud.corruption_text().contains("out of combat"), "the HUD says out of combat (%s)" % _hud.corruption_text())
	var gs: FormConfig = _combat.current_form()
	_meter.corruption.set_value(40.0)
	var start: float = _meter.value()
	await _combat_frames(MEASURE_FRAMES)
	var expected: float = gs.corruption_per_second * gs.corruption_out_of_combat_multiplier * MEASURE_FRAMES / 60.0
	var change: float = _meter.value() - start
	_expect(absf(change - expected) < 0.15, "greatsword out of combat: %.2f over %d frames (got %.2f)" % [expected, MEASURE_FRAMES, change])
	_expect(change < gs.corruption_per_second * MEASURE_FRAMES / 60.0 - 0.5, "it drains faster out of combat")


## Out of range of the dummy, a swing that lands on it puts her in combat (linger).
func _test_attack_puts_her_in_combat() -> void:
	_expect(not _meter.in_combat, "out of combat before the swing")
	var old_radius: float = _cfg.combat_radius
	_cfg.combat_radius = 0.5 # so only the linger rule can say "in combat"
	_place_near()
	await _physics_frames(40)
	_expect(not _meter.in_combat, "with a tiny radius she is out of combat next to the dummy")
	var landed: Array[int] = [0]
	var on_land: Callable = func(_r: HitResult, _t: Combatant, _h: Hurtbox) -> void: landed[0] += 1
	_combat.attack_landed.connect(on_land)
	await _tap(&"attack")
	await _wait_idle()
	_combat.attack_landed.disconnect(on_land)
	_expect(landed[0] == 1, "the swing landed on the dummy")
	_expect(_meter.in_combat, "landing an attack puts her in combat")
	_cfg.combat_radius = old_radius
	_dummy.get_combatant().revive()


## Only a LIVING hostile in range counts: a dead dummy next to her doesn't keep her in
## combat, and reviving it does.
func _test_dead_hostile_does_not_count() -> void:
	_place_near()
	var dummy_c: Combatant = _dummy.get_combatant()
	await _physics_frames(2)
	_expect(_meter.hostile_in_range(), "a living dummy next to her is a hostile in range")
	dummy_c.is_dead = true
	_expect(not _meter.hostile_in_range(), "a dead dummy next to her is not a hostile in range")
	# Wait out the linger from the earlier swing.
	await _combat_frames(_cfg.combat_linger_frames + 2)
	_expect(not _meter.in_combat, "next to a dead dummy she leaves combat")
	dummy_c.revive()
	await _physics_frames(2)
	_expect(_meter.hostile_in_range(), "the revived dummy is a hostile in range again")
	_expect(_meter.in_combat, "next to the revived dummy she is in combat again")


## Far from any hostile, a hit she takes puts her in combat for the linger, then she leaves.
func _test_hit_taken_puts_her_in_combat() -> void:
	await _place_far()
	await _combat_frames(_cfg.combat_linger_frames + 2)
	_expect(not _meter.hostile_in_range() and not _meter.in_combat, "far away and out of combat before the hit")
	var hit: AttackData = AttackData.new()
	hit.id = &"smoke_small_hit"
	hit.damage = 1.0
	hit.posture_damage = 0.0
	var r: HitResult = _player_c.receive_attack(hit, _dummy.get_combatant())
	_expect(r.outcome == HitResult.Outcome.HIT, "the small hit landed on her (%s)" % r.outcome_name())
	await _physics_frames(2)
	_expect(_meter.in_combat, "taking a hit puts her in combat")
	_expect(not _meter.hostile_in_range(), "with no hostile in range (only the hit counts)")
	await _combat_frames(_cfg.combat_linger_frames - 10)
	_expect(_meter.in_combat, "still in combat inside the linger after the hit")
	await _combat_frames(12)
	_expect(not _meter.in_combat, "out of combat once the linger after the hit runs out")
	_player_c.revive()


func _test_rampage_locks_dodge_and_drains_out() -> void:
	await _place_far()
	await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"katana", "katana for the rampage")
	_reached.clear()
	_meter.corruption.set_value(_cfg.max_corruption - 0.5)
	for i: int in 60:
		if _meter.is_rampaging():
			break
		await physics_frame
	_expect(_meter.is_rampaging(), "reaching 100% starts a rampage")
	_expect(_rampage_starts == 1, "rampage_started fired once (%d)" % _rampage_starts)
	_expect(_reached.has(_cfg.max_corruption), "threshold %.0f fired (%s)" % [_cfg.max_corruption, _reached])
	_expect(_combat.is_dodge_locked() and not _combat.dodge_ready(), "the rampage locks the dodge")
	await _physics_frames(2)
	await _hud_refresh()
	_expect(_hud.corruption_text().contains("RAMPAGE"), "the HUD shows RAMPAGE (%s)" % _hud.corruption_text())
	_expect(_hud.dodge_text().contains("locked"), "the HUD shows the dodge locked (%s)" % _hud.dodge_text())
	await _tap(&"dodge")
	_expect(not _combat.is_dodging(), "katana dodge is refused during the rampage")
	# Input hijack is a stub: movement still follows her input.
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_forward")
	await _physics_frames(30)
	Input.action_release(&"move_forward")
	_expect((_player.global_position - start).z < -1.0, "she still moves where the input says during a rampage")
	_expect(_meter.hijack_chance() > 0.0, "the hijack chance is above 0 at full corruption (stub)")

	await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"greatsword", "greatsword to drain out of it")
	_meter.corruption.set_value(_cfg.rampage_exit_corruption + 0.5)
	_expect(_meter.is_rampaging(), "still rampaging just above the exit value")
	for i: int in 120:
		if not _meter.is_rampaging():
			break
		await physics_frame
	_expect(not _meter.is_rampaging(), "the rampage ends when corruption drains to %.0f" % _cfg.rampage_exit_corruption)
	_expect(_rampage_ends == [Corruption.RampageEnd.DRAINED], "ended by draining (%s)" % [_rampage_ends])
	await _tap(&"switch_form")
	await _physics_frames(1)
	_expect(not _combat.is_dodge_locked() and _combat.dodge_ready(), "the dodge works again after the rampage")
	await _tap(&"dodge")
	_expect(_combat.is_dodging(), "katana dodge works again")
	await _physics_frames(40)


func _test_rampage_ends_at_critical_health() -> void:
	_rampage_ends.clear()
	_player_c.revive()
	_expect(_combat.current_form().id == &"katana", "still in the katana")
	_meter.corruption.set_value(_cfg.max_corruption - 0.1)
	await _physics_frames(5)
	_expect(_meter.is_rampaging(), "rampage again at 100%")
	var hit: AttackData = AttackData.new()
	hit.id = &"smoke_critical_hit"
	hit.damage = _player_c.config.max_health * (1.0 - _cfg.rampage_exit_health_ratio) + 1.0
	hit.posture_damage = 0.0
	var r: HitResult = _player_c.receive_attack(hit)
	_expect(r.outcome == HitResult.Outcome.HIT, "the hit landed (%s)" % r.outcome_name())
	_expect(_player_c.health_ratio() <= _cfg.rampage_exit_health_ratio, "her health is critical (%.2f)" % _player_c.health_ratio())
	_expect(not _meter.is_rampaging(), "critical health ends the rampage")
	_expect(_rampage_ends == [Corruption.RampageEnd.CRITICAL_HEALTH], "ended by critical health (%s)" % [_rampage_ends])
	_expect(not _combat.is_dodge_locked(), "a critical-health rampage end unlocks the dodge")
	await _physics_frames(30)
	_expect(not _meter.is_rampaging(), "no new rampage while the meter stays at max")
	_player_c.revive()


func _test_shrine_reset() -> void:
	# Rise from below to max again (health is full) so the shrine ends a live rampage.
	_rampage_ends.clear()
	_meter.corruption.set_value(60.0)
	_meter.corruption.set_value(_cfg.max_corruption)
	_expect(_meter.is_rampaging() and _combat.is_dodge_locked(), "rampaging with the dodge locked before the shrine")
	_expect(_meter.value() > 50.0, "corruption is high before the shrine (%.1f)" % _meter.value())
	_meter.reset_at_shrine()
	_expect(is_zero_approx(_meter.value()), "reset_at_shrine empties the meter")
	_expect(not _meter.is_rampaging(), "no rampage after the shrine")
	_expect(_rampage_ends == [Corruption.RampageEnd.SHRINE], "ended by the shrine (%s)" % [_rampage_ends])
	_expect(not _combat.is_dodge_locked(), "a shrine rampage end unlocks the dodge")
	await _physics_frames(2)
	await _hud_refresh()
	_expect(_hud.corruption_bar_value() < 0.5, "the HUD bar empties (%.2f)" % _hud.corruption_bar_value())


## The meter does not step during hit-stop or while she is dead (katana in combat, so
## every step it did take would raise it), and steps again afterwards.
func _test_paused_during_hitstop_and_death() -> void:
	_place_near()
	if _combat.current_form().id != &"katana":
		await _tap(&"switch_form")
	_expect(_combat.current_form().id == &"katana", "katana for the pause checks")
	_meter.corruption.set_value(40.0)
	await _physics_frames(3)
	_expect(_meter.in_combat, "next to the dummy she is in combat (pause checks)")
	_expect(_meter.current_rate() > 0.0, "the katana is raising corruption (%.2f/s)" % _meter.current_rate())

	# Hit-stop: a long freeze, measured only over ticks that are really frozen.
	var service: HitStopService = HitStopService.instance()
	_expect(service != null, "the HitStop autoload is present")
	if service == null:
		return
	_expect(service.freeze_ms(2000), "a 2 s hit-stop started")
	# The requesting tick still runs normally (HitStopService.is_frozen); the test resumes
	# on physics_frame, before the nodes' _physics_process, so start measuring one tick on.
	await physics_frame
	var before: float = _meter.value()
	var frozen_ticks: int = 0
	for i: int in 60:
		await physics_frame
		if not HitStopService.is_frozen():
			break
		frozen_ticks += 1
		if frozen_ticks >= 30:
			break
	var during_freeze: float = _meter.value()
	service.end_now()
	_expect(frozen_ticks >= 30, "the freeze lasted 30 frozen ticks (%d)" % frozen_ticks)
	_expect(during_freeze == before, "corruption is paused during hit-stop (%.3f -> %.3f over %d frozen ticks)" % [before, during_freeze, frozen_ticks])
	await _physics_frames(10)
	_expect(_meter.value() > during_freeze + 0.2, "corruption runs again after the hit-stop (%.3f -> %.3f)" % [during_freeze, _meter.value()])

	# Dead: no change while is_dead, whatever form/combat state she is in.
	_player_c.is_dead = true
	await _physics_frames(1)
	before = _meter.value()
	await _physics_frames(30)
	var while_dead: float = _meter.value()
	_expect(while_dead == before, "corruption is paused while she is dead (%.3f -> %.3f over 30 ticks)" % [before, while_dead])
	_player_c.revive()
	await _physics_frames(10)
	_expect(not _player_c.is_dead, "she is alive again")
	_expect(_meter.value() > while_dead + 0.2, "corruption runs again after she revives (%.3f -> %.3f)" % [while_dead, _meter.value()])


## 2 m in front (+Z) of the dummy, facing it.
func _place_near() -> void:
	_player.global_position = _dummy.global_position + Vector3(0.0, 0.0, 2.0)
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3.FORWARD)
	_player.reset_physics_interpolation()


## Open ground well outside the combat radius, camera yaw 0 (move_forward = world -Z).
func _place_far() -> void:
	_player.global_position = Vector3(-20.0, 0.0, 22.0)
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3.FORWARD)
	_player.camera_rig.set_view_yaw(0.0)
	_player.reset_physics_interpolation()
	await _physics_frames(3)


func _wait_idle() -> void:
	for i: int in 400:
		if not _combat.is_busy():
			return
		await physics_frame
	_expect(false, "the swing finished within 400 frames")


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
	print("CORRUPTION SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


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
