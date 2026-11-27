extends GdUnitTestSuite
## Deathblow and lives on Combatant (scripts/combat/combatant.gd): the deathblow window
## opened by a posture break, lives/phases, and the requires_deathblow rule (0 health
## staggers instead of killing). Frames are passed in explicitly via step().

const BREAK_FRAMES: int = 60


func _config(lives: int = 1, can_be_deathblown: bool = true, requires_deathblow: bool = false) -> CombatantConfig:
	var pc: PostureConfig = PostureConfig.new()
	pc.max_posture = 100.0
	pc.regen_delay_frames = 1000
	pc.break_stagger_frames = BREAK_FRAMES
	var gc: GuardConfig = GuardConfig.new()
	gc.hit_posture_multiplier = 0.5
	var c: CombatantConfig = CombatantConfig.new()
	c.max_health = 100.0
	c.posture = pc
	c.guard = gc
	c.lives = lives
	c.can_be_deathblown = can_be_deathblown
	c.requires_deathblow = requires_deathblow
	return c


func _combatant(cfg: CombatantConfig) -> Combatant:
	var c: Combatant = auto_free(Combatant.new()) as Combatant
	c.setup(cfg)
	return c


func _hit(damage: float, posture_damage: float = 0.0) -> AttackData:
	var a: AttackData = AttackData.new()
	a.damage = damage
	a.posture_damage = posture_damage
	return a


func test_defaults_one_life_no_deathblow() -> void:
	var cfg: CombatantConfig = CombatantConfig.new()
	assert_int(cfg.lives).is_equal(1)
	assert_bool(cfg.can_be_deathblown).is_false()
	assert_bool(cfg.requires_deathblow).is_false()


func test_no_deathblow_without_posture_break() -> void:
	var c: Combatant = _combatant(_config())
	assert_bool(c.is_deathblow_available()).is_false()
	assert_bool(c.receive_deathblow()).is_false()
	assert_int(c.lives_left).is_equal(1)
	assert_bool(c.is_dead).is_false()


func test_posture_break_opens_the_window_once() -> void:
	var c: Combatant = _combatant(_config())
	var opened: Array[int] = [0]
	c.deathblow_available.connect(func() -> void: opened[0] += 1)
	c.take_posture_damage(100.0)
	assert_bool(c.is_deathblow_available()).is_true()
	c.take_posture_damage(50.0) # already broken: no second window
	assert_int(opened[0]).is_equal(1)


func test_heroine_style_config_never_offers_a_deathblow() -> void:
	var c: Combatant = _combatant(_config(1, false))
	c.take_posture_damage(100.0)
	assert_bool(c.is_staggered()).is_true()
	assert_bool(c.is_deathblow_available()).is_false()
	assert_bool(c.receive_deathblow()).is_false()
	assert_bool(c.is_dead).is_false()


func test_deathblow_on_last_life_kills() -> void:
	var c: Combatant = _combatant(_config())
	var landed: Array[int] = [-1]
	var deaths: Array[int] = [0]
	c.deathblow_landed.connect(func(left: int) -> void: landed[0] = left)
	c.died.connect(func() -> void: deaths[0] += 1)
	c.take_posture_damage(100.0)
	assert_bool(c.receive_deathblow()).is_true()
	assert_int(landed[0]).is_equal(0)
	assert_int(c.lives_left).is_equal(0)
	assert_bool(c.is_dead).is_true()
	assert_int(deaths[0]).is_equal(1)
	assert_float(c.health).is_equal(0.0)
	assert_bool(c.is_deathblow_available()).is_false()
	assert_bool(c.receive_deathblow()).is_false() # can't deathblow the dead


func test_window_closes_when_the_stagger_ends() -> void:
	var c: Combatant = _combatant(_config())
	var closed: Array[int] = [0]
	c.deathblow_unavailable.connect(func() -> void: closed[0] += 1)
	c.take_posture_damage(100.0)
	c.step(BREAK_FRAMES - 1)
	assert_bool(c.is_deathblow_available()).is_true()
	c.step(1)
	assert_bool(c.is_deathblow_available()).is_false()
	assert_int(closed[0]).is_equal(1)
	assert_bool(c.receive_deathblow()).is_false()
	assert_bool(c.is_dead).is_false()
	assert_int(c.lives_left).is_equal(1)


func test_two_lives_first_deathblow_starts_the_next_phase() -> void:
	var c: Combatant = _combatant(_config(2))
	var ended: Array[int] = [0]
	c.stagger_ended.connect(func() -> void: ended[0] += 1)
	c.receive_attack(_hit(40.0))
	c.take_posture_damage(100.0)
	assert_bool(c.receive_deathblow()).is_true()
	assert_int(c.lives_left).is_equal(1)
	assert_bool(c.is_dead).is_false()
	assert_float(c.health).is_equal(100.0)
	assert_float(c.posture.value).is_equal(0.0)
	assert_bool(c.is_staggered()).is_false()
	assert_bool(c.can_act()).is_true()
	assert_int(ended[0]).is_equal(1)
	# Second phase: break again, deathblow again → dead.
	c.take_posture_damage(100.0)
	assert_bool(c.receive_deathblow()).is_true()
	assert_int(c.lives_left).is_equal(0)
	assert_bool(c.is_dead).is_true()


func test_requires_deathblow_zero_health_staggers_instead_of_dying() -> void:
	var c: Combatant = _combatant(_config(1, true, true))
	var broke: Array[int] = [0]
	var deaths: Array[int] = [0]
	c.posture_broken.connect(func() -> void: broke[0] += 1)
	c.died.connect(func() -> void: deaths[0] += 1)
	c.receive_attack(_hit(150.0))
	assert_float(c.health).is_equal(0.0)
	assert_bool(c.is_dead).is_false()
	assert_int(deaths[0]).is_equal(0)
	assert_bool(c.is_awaiting_deathblow()).is_true()
	assert_bool(c.is_staggered()).is_true()
	assert_int(broke[0]).is_equal(1)
	assert_bool(c.is_deathblow_available()).is_true()
	# No time limit: it waits for the deathblow.
	c.step(BREAK_FRAMES * 20)
	assert_bool(c.is_deathblow_available()).is_true()
	# More hits don't kill it either.
	c.receive_attack(_hit(50.0))
	assert_bool(c.is_dead).is_false()
	assert_bool(c.receive_deathblow()).is_true()
	assert_bool(c.is_dead).is_true()
	assert_int(deaths[0]).is_equal(1)


func test_zero_health_during_a_break_keeps_it_waiting() -> void:
	var c: Combatant = _combatant(_config(1, true, true))
	c.take_posture_damage(100.0)
	c.receive_attack(_hit(150.0)) # staggered → unguarded hit
	assert_bool(c.is_awaiting_deathblow()).is_true()
	c.step(BREAK_FRAMES * 2)
	assert_bool(c.is_staggered()).is_true()
	assert_bool(c.is_deathblow_available()).is_true()


func test_requires_deathblow_with_lives_left_gets_back_up() -> void:
	var c: Combatant = _combatant(_config(2, true, true))
	c.receive_attack(_hit(150.0))
	assert_bool(c.receive_deathblow()).is_true()
	assert_bool(c.is_dead).is_false()
	assert_int(c.lives_left).is_equal(1)
	assert_float(c.health).is_equal(100.0)
	assert_bool(c.is_awaiting_deathblow()).is_false()
	assert_bool(c.can_act()).is_true()


func test_without_requires_deathblow_zero_health_kills_outright() -> void:
	var c: Combatant = _combatant(_config(2, true, false))
	c.receive_attack(_hit(150.0))
	assert_bool(c.is_dead).is_true()
	assert_int(c.lives_left).is_equal(0)


func test_requires_deathblow_needs_can_be_deathblown() -> void:
	var c: Combatant = _combatant(_config(1, false, true))
	c.receive_attack(_hit(150.0))
	assert_bool(c.is_dead).is_true()


func test_revive_restores_lives() -> void:
	var c: Combatant = _combatant(_config(2))
	var changes: Array[int] = []
	c.lives_changed.connect(func(left: int, _max: int) -> void: changes.append(left))
	c.take_posture_damage(100.0)
	c.receive_deathblow()
	c.take_posture_damage(100.0)
	c.receive_deathblow()
	assert_bool(c.is_dead).is_true()
	c.revive()
	assert_int(c.lives_left).is_equal(2)
	assert_bool(c.is_dead).is_false()
	assert_bool(c.is_deathblow_available()).is_false()
	assert_array(changes).contains_exactly([1, 0, 2])


func test_sandbox_tuning() -> void:
	var dummy: CombatantConfig = load("res://data/combat/dummy_combatant.tres") as CombatantConfig
	assert_int(dummy.lives).is_equal(2)
	assert_bool(dummy.can_be_deathblown).is_true()
	assert_bool(dummy.requires_deathblow).is_true()
	var heroine: CombatantConfig = load("res://data/combat/heroine_combatant.tres") as CombatantConfig
	assert_bool(heroine.can_be_deathblown).is_false()
	var db: DeathblowConfig = load("res://data/combat/heroine_deathblow.tres") as DeathblowConfig
	assert_float(db.reach).is_equal(2.6)
	assert_float(db.facing_half_angle_degrees).is_equal(75.0)
	assert_int(db.recovery_frames).is_equal(50)
	assert_bool(db.invulnerable).is_true()
