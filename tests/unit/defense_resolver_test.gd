extends GdUnitTestSuite
## Defence rules (scripts/combat/defense_resolver.gd): parry > block > hit, and how
## perilous attacks change that.


func _config() -> GuardConfig:
	var c: GuardConfig = GuardConfig.new()
	c.parry_window_frames = 12
	c.parry_self_posture_multiplier = 0.25
	c.parry_attacker_posture_multiplier = 1.0
	c.block_posture_multiplier = 1.0
	c.block_health_multiplier = 0.1
	c.hit_posture_multiplier = 0.5
	return c


func _attack(blockable: bool = true, deflectable: bool = true) -> AttackData:
	var a: AttackData = AttackData.new()
	a.damage = 20.0
	a.posture_damage = 40.0
	a.blockable = blockable
	a.deflectable = deflectable
	return a


func _guard(cfg: GuardConfig, press_frame: int, held: bool) -> Guard:
	var g: Guard = Guard.new(cfg)
	if press_frame >= 0:
		g.press(press_frame)
	if not held:
		g.release()
	return g


func test_unguarded_is_a_hit() -> void:
	var cfg: GuardConfig = _config()
	var r: HitResult = DefenseResolver.resolve(_attack(), _guard(cfg, -1, false), 100, cfg)
	assert_int(r.outcome).is_equal(HitResult.Outcome.HIT)
	assert_float(r.health_damage).is_equal(20.0)
	assert_float(r.defender_posture_damage).is_equal(20.0)
	assert_float(r.attacker_posture_damage).is_equal(0.0)


func test_held_guard_outside_window_blocks() -> void:
	var cfg: GuardConfig = _config()
	var r: HitResult = DefenseResolver.resolve(_attack(), _guard(cfg, 50, true), 100, cfg)
	assert_int(r.outcome).is_equal(HitResult.Outcome.BLOCKED)
	assert_float(r.health_damage).is_equal_approx(2.0, 0.001)
	assert_float(r.defender_posture_damage).is_equal(40.0)
	assert_float(r.attacker_posture_damage).is_equal(0.0)


func test_press_inside_window_parries() -> void:
	var cfg: GuardConfig = _config()
	var r: HitResult = DefenseResolver.resolve(_attack(), _guard(cfg, 95, true), 100, cfg)
	assert_int(r.outcome).is_equal(HitResult.Outcome.PARRIED)
	assert_float(r.health_damage).is_equal(0.0)
	assert_float(r.defender_posture_damage).is_equal(10.0)
	assert_float(r.attacker_posture_damage).is_equal(40.0)


func test_tapped_and_released_still_parries() -> void:
	var cfg: GuardConfig = _config()
	var r: HitResult = DefenseResolver.resolve(_attack(), _guard(cfg, 95, false), 100, cfg)
	assert_int(r.outcome).is_equal(HitResult.Outcome.PARRIED)


func test_tapped_too_early_and_released_is_a_hit() -> void:
	var cfg: GuardConfig = _config()
	var r: HitResult = DefenseResolver.resolve(_attack(), _guard(cfg, 50, false), 100, cfg)
	assert_int(r.outcome).is_equal(HitResult.Outcome.HIT)


func test_thrust_cannot_be_blocked_but_can_be_parried() -> void:
	var cfg: GuardConfig = _config()
	var thrust: AttackData = _attack(false, true)
	assert_int(DefenseResolver.resolve(thrust, _guard(cfg, 50, true), 100, cfg).outcome).is_equal(HitResult.Outcome.HIT)
	assert_int(DefenseResolver.resolve(thrust, _guard(cfg, 95, true), 100, cfg).outcome).is_equal(HitResult.Outcome.PARRIED)


func test_sweep_cannot_be_blocked_or_parried() -> void:
	var cfg: GuardConfig = _config()
	var sweep: AttackData = _attack(false, false)
	assert_int(DefenseResolver.resolve(sweep, _guard(cfg, 95, true), 100, cfg).outcome).is_equal(HitResult.Outcome.HIT)


func test_blockable_but_not_deflectable_only_blocks() -> void:
	var cfg: GuardConfig = _config()
	var heavy: AttackData = _attack(true, false)
	assert_int(DefenseResolver.resolve(heavy, _guard(cfg, 95, true), 100, cfg).outcome).is_equal(HitResult.Outcome.BLOCKED)


func test_cannot_defend_while_staggered() -> void:
	var cfg: GuardConfig = _config()
	var r: HitResult = DefenseResolver.resolve(_attack(), _guard(cfg, 95, true), 100, cfg, false)
	assert_int(r.outcome).is_equal(HitResult.Outcome.HIT)
