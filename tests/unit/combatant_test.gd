extends GdUnitTestSuite
## Combatant behaviour (scripts/combat/combatant.gd): applying results to both sides,
## guard break, the parry-can't-break rule, stagger and death. Frames are passed in
## explicitly, so nothing depends on real time.


func _config(max_posture: float = 100.0, health: float = 100.0) -> CombatantConfig:
	var pc: PostureConfig = PostureConfig.new()
	pc.max_posture = max_posture
	pc.regen_delay_frames = 1000
	pc.break_stagger_frames = 60
	var gc: GuardConfig = GuardConfig.new()
	gc.parry_window_frames = 12
	gc.parry_self_posture_multiplier = 0.25
	gc.parry_attacker_posture_multiplier = 1.0
	gc.block_health_multiplier = 0.0
	gc.hit_posture_multiplier = 0.5
	var c: CombatantConfig = CombatantConfig.new()
	c.max_health = health
	c.posture = pc
	c.guard = gc
	return c


func _combatant(cfg: CombatantConfig) -> Combatant:
	var c: Combatant = auto_free(Combatant.new()) as Combatant
	c.setup(cfg)
	return c


func _attack(damage: float, posture_damage: float) -> AttackData:
	var a: AttackData = AttackData.new()
	a.damage = damage
	a.posture_damage = posture_damage
	return a


func test_parry_hurts_the_attackers_posture() -> void:
	var defender: Combatant = _combatant(_config())
	var attacker: Combatant = _combatant(_config())
	defender.guard_press(100)
	var r: HitResult = defender.receive_attack(_attack(20.0, 40.0), attacker, 105)
	assert_int(r.outcome).is_equal(HitResult.Outcome.PARRIED)
	assert_float(attacker.posture.value).is_equal(40.0)
	assert_float(defender.posture.value).is_equal(10.0)
	assert_float(defender.health).is_equal(100.0)


func test_enough_parries_break_the_attacker() -> void:
	var defender: Combatant = _combatant(_config())
	var attacker: Combatant = _combatant(_config())
	var broke: Array[int] = [0]
	attacker.posture_broken.connect(func() -> void: broke[0] += 1)
	for i: int in 3:
		var f: int = 100 + i * 100
		defender.guard_press(f)
		defender.receive_attack(_attack(20.0, 40.0), attacker, f + 3)
	assert_int(broke[0]).is_equal(1)
	assert_bool(attacker.is_staggered()).is_true()


func test_parry_never_breaks_the_defenders_own_posture() -> void:
	var defender: Combatant = _combatant(_config())
	defender.take_posture_damage(99.0)
	defender.guard_press(100)
	var r: HitResult = defender.receive_attack(_attack(20.0, 100.0), null, 100)
	assert_int(r.outcome).is_equal(HitResult.Outcome.PARRIED)
	assert_bool(r.broke_defender_posture).is_false()
	assert_bool(defender.is_staggered()).is_false()


func test_blocks_that_fill_posture_break_the_guard() -> void:
	var defender: Combatant = _combatant(_config())
	defender.guard_press(0)
	var first: HitResult = defender.receive_attack(_attack(20.0, 60.0), null, 100)
	var second: HitResult = defender.receive_attack(_attack(20.0, 60.0), null, 200)
	assert_int(first.outcome).is_equal(HitResult.Outcome.BLOCKED)
	assert_int(second.outcome).is_equal(HitResult.Outcome.GUARD_BROKEN)
	assert_bool(defender.is_staggered()).is_true()
	assert_bool(defender.guard.is_held).is_false()


func test_staggered_defender_cannot_guard_or_parry() -> void:
	var defender: Combatant = _combatant(_config())
	defender.take_posture_damage(100.0)
	assert_bool(defender.is_staggered()).is_true()
	defender.guard_press(300)
	var r: HitResult = defender.receive_attack(_attack(20.0, 10.0), null, 302)
	assert_int(r.outcome).is_equal(HitResult.Outcome.HIT)
	assert_float(defender.health).is_equal(80.0)


func test_stagger_ends_and_posture_resets() -> void:
	var c: Combatant = _combatant(_config())
	var ended: Array[int] = [0]
	c.stagger_ended.connect(func() -> void: ended[0] += 1)
	c.take_posture_damage(100.0)
	c.step(59)
	assert_bool(c.is_staggered()).is_true()
	c.step(1)
	assert_bool(c.is_staggered()).is_false()
	assert_int(ended[0]).is_equal(1)
	assert_float(c.posture.value).is_equal(0.0)


func test_health_reaching_zero_dies_once() -> void:
	var c: Combatant = _combatant(_config(100.0, 30.0))
	var deaths: Array[int] = [0]
	c.died.connect(func() -> void: deaths[0] += 1)
	c.receive_attack(_attack(20.0, 0.0), null, 10)
	c.receive_attack(_attack(20.0, 0.0), null, 20)
	var after: HitResult = c.receive_attack(_attack(20.0, 0.0), null, 30)
	assert_bool(c.is_dead).is_true()
	assert_int(deaths[0]).is_equal(1)
	assert_int(after.outcome).is_equal(HitResult.Outcome.MISSED)
	assert_float(c.health).is_equal(0.0)


func test_revive_restores_everything() -> void:
	var c: Combatant = _combatant(_config(100.0, 30.0))
	c.receive_attack(_attack(50.0, 100.0), null, 10)
	c.revive()
	assert_bool(c.is_dead).is_false()
	assert_bool(c.is_staggered()).is_false()
	assert_float(c.health).is_equal(30.0)
	assert_float(c.posture.value).is_equal(0.0)


func test_keeping_posture_after_a_break_still_recovers_and_can_break_again() -> void:
	var cfg: CombatantConfig = _config()
	cfg.posture.reset_after_break = false
	cfg.posture.regen_delay_frames = 10
	cfg.posture.regen_per_second = 60.0
	var c: Combatant = _combatant(cfg)
	c.take_posture_damage(100.0)
	c.step(60)
	assert_bool(c.is_staggered()).is_false()
	assert_bool(c.posture.is_broken).is_false()
	assert_float(c.posture.value).is_greater(99.0) # kept, just below max
	c.step(30)
	assert_float(c.posture.value).is_less(90.0) # recovering again
	assert_bool(c.take_posture_damage(100.0)).is_true() # and can break again


func test_dead_cannot_act_or_guard() -> void:
	var c: Combatant = _combatant(_config(100.0, 10.0))
	c.receive_attack(_attack(50.0, 0.0), null, 10)
	assert_bool(c.can_act()).is_false()
	c.guard_press(20)
	c.guard_hold()
	assert_bool(c.guard.is_held).is_false()


func test_guard_hold_blocks_without_a_parry_window() -> void:
	var c: Combatant = _combatant(_config())
	c.guard_hold()
	var r: HitResult = c.receive_attack(_attack(20.0, 10.0), null, 100)
	assert_int(r.outcome).is_equal(HitResult.Outcome.BLOCKED)



func test_tap_released_guard_still_parries() -> void:
	var c: Combatant = _combatant(_config())
	c.guard_press(100)
	c.guard_release()
	var r: HitResult = c.receive_attack(_attack(20.0, 10.0), null, 105)
	assert_int(r.outcome).is_equal(HitResult.Outcome.PARRIED)


func test_cancel_guard_closes_the_parry_window() -> void:
	var c: Combatant = _combatant(_config())
	c.guard_press(100)
	c.cancel_guard() # e.g. switched to a form without guard, or started a swing
	assert_bool(c.guard.is_held).is_false()
	var r: HitResult = c.receive_attack(_attack(20.0, 10.0), null, 104)
	assert_int(r.outcome).is_equal(HitResult.Outcome.HIT)
	assert_float(c.health).is_equal(80.0)


func test_cancel_guard_after_a_tap_release_closes_the_window() -> void:
	var c: Combatant = _combatant(_config())
	c.guard_press(100)
	c.guard_release()
	c.cancel_guard()
	var r: HitResult = c.receive_attack(_attack(20.0, 10.0), null, 104)
	assert_int(r.outcome).is_equal(HitResult.Outcome.HIT)


func test_a_short_stagger_closes_the_parry_window() -> void:
	var c: Combatant = _combatant(_config())
	c.guard_press(100)
	assert_bool(c.stagger(3)).is_true()
	c.step(3)
	assert_bool(c.is_staggered()).is_false()
	# Still inside the 12-frame window of the press, but the stagger knocked the guard away.
	var r: HitResult = c.receive_attack(_attack(20.0, 10.0), null, 106)
	assert_int(r.outcome).is_equal(HitResult.Outcome.HIT)

# Real physics frames tick here and _physics_process is driven by hand, so a hit that wrongly
# marks its frame as "skip the step" (_skip_step_frame) would stretch the stagger.
func test_hits_during_a_stagger_do_not_lengthen_it() -> void:
	var c: Combatant = _combatant(_config(1000.0)) # hits never break posture
	assert_bool(c.stagger(30)).is_true()
	var frames: int = 0
	while c.is_staggered() and frames < 100:
		await get_tree().physics_frame
		c.receive_attack(_attack(0.0, 10.0), null) # posture damage while staggered
		c._physics_process(0.0)
		frames += 1
	assert_int(frames).is_equal(30)


func test_posture_damage_during_a_posture_break_does_not_lengthen_it() -> void:
	var c: Combatant = _combatant(_config())
	c.take_posture_damage(100.0) # breaks: 60-frame stagger
	var frames: int = 0
	while c.is_staggered() and frames < 200:
		await get_tree().physics_frame
		c.take_posture_damage(5.0)
		c._physics_process(0.0)
		frames += 1
	assert_int(frames).is_equal(60)


func test_sandbox_tuning_files_load() -> void:
	for path: String in ["res://data/combat/heroine_combatant.tres", "res://data/combat/dummy_combatant.tres"]:
		var cfg: CombatantConfig = load(path) as CombatantConfig
		assert_object(cfg).is_not_null()
		assert_object(cfg.posture).is_not_null()
		assert_object(cfg.guard).is_not_null()
