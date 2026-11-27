extends SceneTree
## Headless deathblow + hit-stop smoke test in the sandbox, using the real input actions.
## The heroine parries the training dummy until its posture breaks; the HUD shows the
## DEATHBLOW prompt; attack while facing away does a normal swing, attack while facing it
## lands a deathblow that takes one of the dummy's two lives (it gets back up). Then a big
## hit takes its health to 0: it doesn't die (requires_deathblow) but waits, staggered,
## past the normal stagger time, until a second deathblow kills it; SandboxRules revives
## it with both lives. Hit-stop fires on parry, landed hit, posture break and deathblow,
## pauses the combat clock and every per-tick combat timer (the dummy's attack phase, the
## heroine's swing, a stagger started earlier, SandboxRules' revive countdown), and Engine.time_scale is back to 1.0 afterwards, including
## after a scene change in the middle of a freeze.
## Fails on any engine/script error, and on a frame-budget timeout instead of hanging.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/deathblow_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
## Press guard this many frames before the hit lands (inside the 12-frame window).
const PARRY_LEAD_FRAMES: int = 6
const ATTACK_WAIT_FRAMES: int = 600
const MAX_RUN_FRAMES: int = 20000
## A test freeze far longer than the ticks waited inside it.
const FREEZE_TEST_MS: int = 2000
const FROZEN_TICKS: int = 6

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _level: Node
var _player: PlayerController
var _combat: PlayerCombat
var _player_c: Combatant
var _dummy: TrainingDummy
var _dummy_c: Combatant
var _hud: CombatHud
var _rules: SandboxRules
var _hit_stop: HitStopService
## Kinds of hit-stop started, in order.
var _stops: Array[HitStopService.Kind] = []
var _lowest_time_scale: float = 1.0
var _deathblows: Array[int] = []
var _dummy_broken: bool = false


func _initialize() -> void:
	OS.add_logger(_errors)
	physics_frame.connect(_watchdog)
	_run.call_deferred()


func _run() -> void:
	_hit_stop = HitStopService.instance()
	_expect(_hit_stop != null, "the HitStop autoload is running")
	if _hit_stop == null:
		_finish()
		return
	_hit_stop.started.connect(func(kind: HitStopService.Kind, _ms: int) -> void: _stops.append(kind))
	_level = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(_level)
	_player = _level.get_node("Heroine") as PlayerController
	_combat = _player.combat
	_player_c = _player.combatant
	_dummy = _level.get_node("TrainingDummy") as TrainingDummy
	_dummy_c = _dummy.get_combatant()
	_hud = _level.get_node("CombatHud") as CombatHud
	_rules = _level.get_node("SandboxRules") as SandboxRules
	_dummy_c.posture_broken.connect(func() -> void: _dummy_broken = true)
	_dummy_c.deathblow_landed.connect(func(left: int) -> void: _deathblows.append(left))

	_expect(_dummy_c.lives_left == 2, "the dummy starts with 2 lives")
	await _hud_refresh()
	_expect(_hud.opponent_life_pips() == Vector2i(2, 2), "HUD shows 2 of 2 life pips (%s)" % _hud.opponent_life_pips())
	_expect(not _hud.deathblow_prompt_visible(), "no deathblow prompt at the start")
	await _physics_frames(10)
	_place_player()

	await _test_parry_break_and_first_deathblow()
	await _test_zero_health_waits_for_deathblow()
	await _test_hit_landing_hit_stop()
	await _test_dummy_phase_pauses_during_freeze()
	await _test_swing_pauses_during_freeze()
	await _test_stagger_pauses_during_freeze()
	await _test_time_scale_restored()
	await _test_scene_change_restores_time_scale()
	_finish()


## Parries until the dummy's posture breaks, then lands the first deathblow.
func _test_parry_break_and_first_deathblow() -> void:
	for i: int in 16:
		if _dummy_broken:
			break
		var a: AttackData = await _next_attack()
		if a == null:
			break
		await _combat_frames(a.startup_frames - PARRY_LEAD_FRAMES)
		await _tap(&"block" if a.deflectable else &"jump", 2 if a.deflectable else 10)
		await _combat_frames(a.active_frames + 2)
	_expect(_stops.has(HitStopService.Kind.PARRY), "a parry starts a hit-stop")
	_expect(_dummy_broken, "parrying broke the dummy's posture")
	_expect(_stops.has(HitStopService.Kind.POSTURE_BREAK), "the posture break starts a hit-stop")
	_expect(_lowest_time_scale < 1.0, "hit-stop lowered Engine.time_scale (lowest %.2f)" % _lowest_time_scale)
	_expect(_dummy.phase == TrainingDummy.Phase.STAGGERED, "the dummy is staggered")
	_expect(_dummy_c.is_deathblow_available(), "a deathblow is available on the staggered dummy")
	await _physics_frames(2)
	await _hud_refresh()
	_expect(_hud.deathblow_prompt_visible(), "HUD shows the DEATHBLOW prompt")

	# Facing away: attack is a normal swing, not a deathblow.
	_place_player()
	_player.set_facing_direction(Vector3.BACK)
	await _physics_frames(1)
	_expect(_combat.deathblow_target() == null, "no deathblow target when facing away")
	await _hud_refresh()
	_expect(_hud.deathblow_prompt_text().contains("get close"), "prompt asks to get close (%s)" % _hud.deathblow_prompt_text())
	await _tap(&"attack")
	_expect(_deathblows.is_empty() and _combat.is_attacking(), "facing away, attack swings instead of a deathblow")
	await _wait_idle()

	# Out of reach: no target either.
	_player.global_position = _dummy.global_position + Vector3(0.0, 0.0, 4.0)
	_player.set_facing_direction(Vector3.FORWARD)
	_player.reset_physics_interpolation()
	await _physics_frames(2)
	_expect(_combat.deathblow_target() == null, "no deathblow target out of reach")

	# In reach and facing it: deathblow.
	_place_player()
	await _physics_frames(1)
	_expect(_dummy_c.is_deathblow_available(), "the deathblow window is still open")
	_expect(_combat.deathblow_target() == _dummy_c, "the dummy is the deathblow target in reach")
	await _hud_refresh()
	_expect(_hud.deathblow_prompt_text().contains("press Attack"), "prompt says press Attack (%s)" % _hud.deathblow_prompt_text())
	var stops_before: int = _stops.size()
	Input.action_press(&"attack")
	await _physics_frames(2) # physics_frame fires before nodes step: the 2nd one has run the tick
	Input.action_release(&"attack")
	_expect(_deathblows.size() == 1 and _deathblows[0] == 1, "the deathblow landed and took one life (%s)" % [_deathblows])
	_expect(_stops.slice(stops_before).has(HitStopService.Kind.DEATHBLOW), "the deathblow starts a hit-stop")
	_expect(HitStopService.is_active() and Engine.time_scale < 1.0, "time is slowed right after the deathblow")
	var frame: int = Combatant.current_frame()
	await _physics_frames(3)
	_expect(Combatant.current_frame() == frame, "the combat clock pauses during the hit-stop")
	_expect(_combat.is_performing_deathblow(), "the heroine is locked in her deathblow")
	_expect(not _dummy_c.is_dead and _dummy_c.lives_left == 1, "with a life left the dummy doesn't die")
	_expect(is_equal_approx(_dummy_c.health, _dummy_c.config.max_health) and is_zero_approx(_dummy_c.posture.value),
			"…and gets back up with full health and empty posture")
	_expect(_dummy.phase == TrainingDummy.Phase.IDLE, "the dummy is idle for its next life")
	await _hud_refresh()
	_expect(not _hud.deathblow_prompt_visible(), "the prompt is gone")
	_expect(_hud.opponent_life_pips() == Vector2i(1, 2), "HUD shows 1 of 2 life pips (%s)" % _hud.opponent_life_pips())

	# DeathblowConfig.invulnerable: hits are DODGED through her deathblow's recovery frames.
	var poke: AttackData = AttackData.new()
	poke.id = &"test_poke_on_heroine"
	poke.damage = 1.0
	poke.posture_damage = 0.0
	_expect(_combat.deathblow.invulnerable, "the heroine's deathblow is set to be invulnerable")
	var during: HitResult.Outcome = _player_c.receive_attack(poke, null).outcome
	_expect(during == HitResult.Outcome.DODGED, "a hit during her deathblow is DODGED (%s)" % HitResult.Outcome.keys()[during])
	await _combat_frames(frame + _combat.deathblow.recovery_frames - Combatant.current_frame())
	var after: HitResult.Outcome = _player_c.receive_attack(poke, null).outcome
	_expect(after != HitResult.Outcome.DODGED, "after recovery_frames a hit lands again (%s)" % HitResult.Outcome.keys()[after])
	await _wait_idle()


## 0 health doesn't kill the dummy (requires_deathblow): it waits for a deathblow.
func _test_zero_health_waits_for_deathblow() -> void:
	_dummy.attacking_enabled = false
	await _wait_hit_stop_over()
	var big: AttackData = AttackData.new()
	big.id = &"test_big_hit"
	big.damage = 10000.0
	_dummy_c.receive_attack(big, _player_c)
	_expect(is_zero_approx(_dummy_c.health), "a big hit empties the dummy's health")
	_expect(not _dummy_c.is_dead, "…but it doesn't die without a deathblow")
	_expect(_dummy_c.is_awaiting_deathblow() and _dummy.phase == TrainingDummy.Phase.STAGGERED, "it's staggered, waiting for a deathblow")
	await _combat_frames(_dummy_c.config.posture.break_stagger_frames * 2)
	_expect(_dummy_c.is_deathblow_available() and not _dummy_c.is_dead, "it still waits after twice the normal stagger time")
	await _hud_refresh()
	_expect(_hud.deathblow_prompt_visible(), "the DEATHBLOW prompt is still up")
	_place_player()
	await _physics_frames(1)
	await _tap(&"attack")
	_expect(_deathblows.size() == 2 and _deathblows[1] == 0, "the second deathblow takes the last life (%s)" % [_deathblows])
	_expect(_dummy_c.is_dead and _dummy.phase == TrainingDummy.Phase.DEAD, "the dummy dies")
	await _hud_refresh()
	_expect(_hud.opponent_life_pips() == Vector2i(0, 2), "HUD shows 0 of 2 life pips (%s)" % _hud.opponent_life_pips())
	await _test_revive_countdown_pauses_during_freeze()
	await _combat_frames(_rules.dummy_revive_delay_frames + 2)
	_expect(not _dummy_c.is_dead and _dummy_c.lives_left == 2, "SandboxRules revives the dummy with both lives")
	await _hud_refresh()
	_expect(_hud.opponent_life_pips() == Vector2i(2, 2), "HUD shows 2 of 2 life pips again (%s)" % _hud.opponent_life_pips())


## SandboxRules' revive countdown for the dead dummy doesn't tick during a freeze, and
## ticks again after.
func _test_revive_countdown_pauses_during_freeze() -> void:
	await _wait_hit_stop_over()
	_expect(_rules.frames_until_revive(_dummy_c) > FROZEN_TICKS + 4,
			"a revive is pending with frames left to test with (%d)" % _rules.frames_until_revive(_dummy_c))
	_hit_stop.freeze_ms(FREEZE_TEST_MS)
	await physics_frame # the requesting tick itself still runs (by design)
	var left: int = _rules.frames_until_revive(_dummy_c)
	await _physics_frames(FROZEN_TICKS)
	_expect(HitStopService.is_frozen() and _rules.frames_until_revive(_dummy_c) == left,
			"the revive countdown doesn't tick during a freeze (%d -> %d)" % [left, _rules.frames_until_revive(_dummy_c)])
	_hit_stop.end_now()
	await _physics_frames(3)
	_expect(_rules.frames_until_revive(_dummy_c) < left, "the revive countdown ticks again after the freeze")
	_expect(_dummy_c.is_dead, "the dummy is still down until the countdown ends")


## A swing that connects starts a (short) hit-stop.
func _test_hit_landing_hit_stop() -> void:
	await _wait_idle()
	await _wait_hit_stop_over()
	_place_player()
	await _physics_frames(1)
	var before: int = _stops.size()
	var health: float = _dummy_c.health
	await _tap(&"attack")
	await _wait_idle()
	_expect(_dummy_c.health < health, "the swing hit the dummy")
	_expect(_stops.slice(before).has(HitStopService.Kind.HIT), "a landed hit starts a hit-stop")


## The dummy's attack phase counter doesn't move during a freeze, and moves again after.
func _test_dummy_phase_pauses_during_freeze() -> void:
	await _wait_idle()
	await _wait_hit_stop_over()
	_place_player()
	_dummy.attacking_enabled = true
	var a: AttackData = await _next_attack()
	if a == null:
		return
	_hit_stop.freeze_ms(FREEZE_TEST_MS)
	await physics_frame # the requesting tick itself still runs (by design)
	var frames: int = _dummy._frames_in_phase
	await _physics_frames(FROZEN_TICKS)
	_expect(HitStopService.is_frozen(), "the test freeze is still running")
	_expect(_dummy.phase == TrainingDummy.Phase.STARTUP and _dummy._frames_in_phase == frames,
			"the dummy's wind-up doesn't advance during a freeze (%d -> %d)" % [frames, _dummy._frames_in_phase])
	_hit_stop.end_now()
	await _physics_frames(3)
	_expect(_dummy.phase != TrainingDummy.Phase.STARTUP or _dummy._frames_in_phase > frames,
			"the dummy's wind-up advances again after the freeze")
	_dummy.attacking_enabled = false
	await _wait_idle()
	await _wait_hit_stop_over()
	for i: int in ATTACK_WAIT_FRAMES:
		if _dummy.phase == TrainingDummy.Phase.IDLE:
			break
		await physics_frame


## The heroine's swing (combo timer) doesn't move during a freeze, and moves again after.
func _test_swing_pauses_during_freeze() -> void:
	await _wait_idle()
	await _wait_hit_stop_over()
	_place_player()
	_player.set_facing_direction(Vector3.BACK) # swing at the air: no hit-stop of its own
	await _physics_frames(1)
	await _tap(&"attack")
	_expect(_combat.is_attacking(), "the heroine is mid-swing")
	_hit_stop.freeze_ms(FREEZE_TEST_MS)
	await physics_frame # the requesting tick itself still runs (by design)
	var swing: int = _combat.combo.swing_frame
	await _physics_frames(FROZEN_TICKS)
	_expect(HitStopService.is_frozen() and _combat.combo.swing_frame == swing,
			"the swing doesn't advance during a freeze (%d -> %d)" % [swing, _combat.combo.swing_frame])
	_hit_stop.end_now()
	await _physics_frames(3)
	_expect(_combat.combo.swing_frame != swing, "the swing advances again after the freeze")
	await _wait_idle()


## A stagger caused earlier doesn't tick down during a later, unrelated freeze.
func _test_stagger_pauses_during_freeze() -> void:
	await _wait_hit_stop_over()
	_dummy_c.take_posture_damage(_dummy_c.config.posture.max_posture * 2.0)
	_expect(_dummy_c.is_staggered(), "a big posture hit staggers the dummy")
	await _wait_hit_stop_over()
	await _physics_frames(2)
	_expect(_dummy_c._stagger_frames_left > FROZEN_TICKS + 4,
			"the stagger has frames left to test with (%d)" % _dummy_c._stagger_frames_left)
	_hit_stop.freeze_ms(FREEZE_TEST_MS)
	await physics_frame # the requesting tick itself still runs (by design)
	var left: int = _dummy_c._stagger_frames_left
	await _physics_frames(FROZEN_TICKS)
	_expect(HitStopService.is_frozen() and _dummy_c._stagger_frames_left == left,
			"the stagger doesn't tick down during a freeze (%d -> %d)" % [left, _dummy_c._stagger_frames_left])
	_hit_stop.end_now()
	await _physics_frames(3)
	_expect(_dummy_c._stagger_frames_left < left, "the stagger ticks down again after the freeze")
	await _combat_frames(left + 2)
	_expect(not _dummy_c.is_staggered(), "the dummy recovers from the stagger")


func _test_time_scale_restored() -> void:
	await _wait_hit_stop_over()
	_expect(not HitStopService.is_active(), "every hit-stop ended")
	_expect(Engine.time_scale == 1.0, "Engine.time_scale is back to 1.0 (%.3f)" % Engine.time_scale)


## A freeze running when the scene changes is ended at once.
func _test_scene_change_restores_time_scale() -> void:
	_hit_stop.freeze_ms(5000)
	_expect(Engine.time_scale < 1.0, "a long freeze is running")
	var empty: PackedScene = PackedScene.new()
	var blank: Node = Node.new()
	empty.pack(blank)
	blank.free()
	root.remove_child(_level)
	_level.free()
	change_scene_to_packed(empty)
	await scene_changed
	await process_frame
	_expect(not HitStopService.is_active() and Engine.time_scale == 1.0,
			"changing scene mid-freeze restores Engine.time_scale (%.3f)" % Engine.time_scale)


func _place_player() -> void:
	# Stand 2 m in front (+Z) of the dummy, facing it.
	_player.global_position = _dummy.global_position + Vector3(0.0, 0.0, 2.0)
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3.FORWARD)
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


func _wait_idle() -> void:
	for i: int in 600:
		if not _combat.is_busy():
			return
		await physics_frame
	_expect(false, "the heroine was idle again within 600 frames")


func _wait_hit_stop_over() -> void:
	for i: int in 600:
		if not HitStopService.is_active():
			return
		await physics_frame
	_expect(false, "hit-stop ended within 600 frames")


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
	_lowest_time_scale = minf(_lowest_time_scale, Engine.time_scale)
	if _frames_run > MAX_RUN_FRAMES and not _finished:
		_expect(false, "finished within %d frames (watchdog)" % MAX_RUN_FRAMES)
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_expect(_errors.errors == 0, "no engine/script errors (%d; first: %s)" % [_errors.errors, _errors.first_error])
	print("DEATHBLOW SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
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
