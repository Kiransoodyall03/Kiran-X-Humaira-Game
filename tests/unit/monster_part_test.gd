extends GdUnitTestSuite
## Large-monster parts (scripts/combat/monster_part_state.gd, monster_part_config.gd): the
## part posture bar, breaking, the broken damage multiplier, and what broken parts do to
## attacks. Plus Combatant.stagger() (the whole-body stagger a part break causes: no
## deathblow window) and sanity checks on monster #1's real part data.

const PARTS: Array[String] = ["head", "left_forelimb", "right_forelimb", "tail", "body"]
const AI: String = "res://data/combat/monster01_ai.tres"


func _part_config(max_posture: float = 100.0, breakable: bool = true) -> MonsterPartConfig:
	var c: MonsterPartConfig = MonsterPartConfig.new()
	c.part_id = &"left_forelimb"
	if breakable:
		var p: PostureConfig = PostureConfig.new()
		p.max_posture = max_posture
		p.regen_per_second = 60.0
		p.regen_delay_frames = 100
		p.low_health_regen_multiplier = 1.0
		c.posture = p
	c.damage_multiplier = 1.1
	c.part_posture_multiplier = 2.0
	c.broken_damage_multiplier = 1.5
	return c


func _broken_state(id: StringName, disables: Array[StringName], weakens: Array[StringName], scale: float) -> MonsterPartState:
	var c: MonsterPartConfig = _part_config(10.0)
	c.part_id = id
	c.disables_attacks = disables
	c.weakens_attacks = weakens
	c.weakened_scale = scale
	var s: MonsterPartState = MonsterPartState.new(c)
	s.add_hit(100.0)
	return s


# --- part posture -----------------------------------------------------------------------

func test_a_hit_fills_the_part_bar_by_its_multiplier() -> void:
	var s: MonsterPartState = MonsterPartState.new(_part_config())
	assert_bool(s.add_hit(15.0)).is_false()
	assert_float(s.value()).is_equal_approx(30.0, 0.001) # 15 whole-body posture × 2
	assert_float(s.ratio()).is_equal_approx(0.3, 0.001)
	assert_bool(s.is_broken()).is_false()


func test_the_part_breaks_once_when_its_bar_fills() -> void:
	var s: MonsterPartState = MonsterPartState.new(_part_config())
	var breaks: Array[int] = [0]
	s.broken.connect(func() -> void: breaks[0] += 1)
	assert_bool(s.add_hit(20.0)).is_false() # 40
	assert_bool(s.add_hit(20.0)).is_false() # 80
	assert_bool(s.add_hit(10.0)).is_true() # 100: breaks
	assert_bool(s.is_broken()).is_true()
	assert_int(breaks[0]).is_equal(1)
	assert_bool(s.add_hit(50.0)).is_false() # already broken: no second break
	assert_int(breaks[0]).is_equal(1)


func test_just_below_max_does_not_break() -> void:
	var s: MonsterPartState = MonsterPartState.new(_part_config())
	assert_bool(s.add_hit(49.9)).is_false()
	assert_bool(s.is_broken()).is_false()


func test_a_broken_part_takes_more_damage() -> void:
	var s: MonsterPartState = MonsterPartState.new(_part_config())
	assert_float(s.damage_multiplier()).is_equal_approx(1.1, 0.0001)
	s.add_hit(50.0)
	assert_float(s.damage_multiplier()).is_equal_approx(1.65, 0.0001)


func test_part_posture_recovers_after_the_delay_but_a_break_stays() -> void:
	var s: MonsterPartState = MonsterPartState.new(_part_config())
	s.add_hit(20.0) # 40
	s.tick(99)
	assert_float(s.value()).is_equal_approx(40.0, 0.001) # delay is 100 frames
	s.tick(31) # past the delay: this step recovers 31 frames at 60/s = 31
	assert_float(s.value()).is_equal_approx(9.0, 0.01)
	s.add_hit(50.0) # breaks
	s.tick(1000)
	assert_bool(s.is_broken()).is_true()
	assert_float(s.value()).is_equal_approx(100.0, 0.001)


func test_reset_mends_the_part() -> void:
	var s: MonsterPartState = MonsterPartState.new(_part_config())
	s.add_hit(50.0)
	s.reset()
	assert_bool(s.is_broken()).is_false()
	assert_float(s.value()).is_equal(0.0)
	assert_float(s.damage_multiplier()).is_equal_approx(1.1, 0.0001)


func test_an_unbreakable_part_never_breaks() -> void:
	var s: MonsterPartState = MonsterPartState.new(_part_config(100.0, false))
	assert_bool(s.is_breakable()).is_false()
	assert_bool(s.add_hit(1000.0)).is_false()
	assert_bool(s.is_broken()).is_false()
	assert_float(s.value()).is_equal(0.0)
	assert_float(s.damage_multiplier()).is_equal_approx(1.1, 0.0001)
	s.tick(100) # no bar: nothing to recover, no crash


# --- broken parts and attacks -------------------------------------------------------------

func test_whole_parts_change_nothing() -> void:
	var c: MonsterPartConfig = _part_config()
	c.disables_attacks = [&"swipe"] as Array[StringName]
	var parts: Array[MonsterPartState] = [MonsterPartState.new(c)]
	assert_bool(MonsterPartState.is_attack_disabled(parts, &"swipe")).is_false()
	assert_float(MonsterPartState.attack_scale(parts, &"swipe")).is_equal(1.0)


func test_a_broken_part_disables_its_attacks() -> void:
	var parts: Array[MonsterPartState] = [_broken_state(&"right", [&"swipe"] as Array[StringName], [] as Array[StringName], 0.5)]
	assert_bool(MonsterPartState.is_attack_disabled(parts, &"swipe")).is_true()
	assert_float(MonsterPartState.attack_scale(parts, &"swipe")).is_equal(0.0)
	assert_bool(MonsterPartState.is_attack_disabled(parts, &"stomp")).is_false()
	assert_float(MonsterPartState.attack_scale(parts, &"stomp")).is_equal(1.0)


func test_broken_parts_weaken_attacks_multiplicatively() -> void:
	var a: MonsterPartState = _broken_state(&"left", [] as Array[StringName], [&"swipe"] as Array[StringName], 0.5)
	var b: MonsterPartState = _broken_state(&"head", [] as Array[StringName], [&"swipe", &"charge"] as Array[StringName], 0.6)
	var parts: Array[MonsterPartState] = [a]
	assert_float(MonsterPartState.attack_scale(parts, &"swipe")).is_equal_approx(0.5, 0.0001)
	parts.append(b)
	assert_float(MonsterPartState.attack_scale(parts, &"swipe")).is_equal_approx(0.3, 0.0001)
	assert_float(MonsterPartState.attack_scale(parts, &"charge")).is_equal_approx(0.6, 0.0001)
	assert_bool(MonsterPartState.is_attack_disabled(parts, &"swipe")).is_false()


# --- whole-body stagger (Combatant.stagger) -----------------------------------------------

func _combatant() -> Combatant:
	var pc: PostureConfig = PostureConfig.new()
	pc.max_posture = 100.0
	pc.regen_delay_frames = 1000
	pc.break_stagger_frames = 90
	var c: CombatantConfig = CombatantConfig.new()
	c.max_health = 100.0
	c.posture = pc
	c.guard = GuardConfig.new()
	c.lives = 2
	c.can_be_deathblown = true
	c.requires_deathblow = true
	var combatant: Combatant = auto_free(Combatant.new()) as Combatant
	combatant.setup(c)
	return combatant


func test_stagger_stops_acting_without_a_deathblow_window() -> void:
	var c: Combatant = _combatant()
	var opened: Array[int] = [0]
	var ended: Array[int] = [0]
	c.deathblow_available.connect(func() -> void: opened[0] += 1)
	c.stagger_ended.connect(func() -> void: ended[0] += 1)
	assert_bool(c.stagger(60)).is_true()
	assert_bool(c.is_staggered()).is_true()
	assert_bool(c.can_act()).is_false()
	assert_bool(c.is_break_staggered()).is_false()
	assert_bool(c.is_deathblow_available()).is_false()
	assert_bool(c.receive_deathblow()).is_false()
	assert_int(opened[0]).is_equal(0)
	c.step(59)
	assert_bool(c.is_staggered()).is_true()
	assert_int(ended[0]).is_equal(0)
	c.step(1)
	assert_bool(c.is_staggered()).is_false()
	assert_bool(c.can_act()).is_true()
	assert_int(ended[0]).is_equal(1)


func test_a_posture_break_during_a_stagger_opens_the_deathblow_window() -> void:
	var c: Combatant = _combatant()
	c.stagger(60)
	c.take_posture_damage(100.0)
	assert_bool(c.is_break_staggered()).is_true()
	assert_int(c.hit_stagger_frames_left()).is_equal(0) # the posture break took over
	assert_bool(c.is_deathblow_available()).is_true()
	assert_bool(c.receive_deathblow()).is_true()
	assert_int(c.lives_left).is_equal(1)
	assert_bool(c.is_staggered()).is_false()


func test_stagger_does_nothing_when_dead_or_already_break_staggered() -> void:
	var c: Combatant = _combatant()
	c.take_posture_damage(100.0)
	assert_bool(c.stagger(60)).is_false()
	assert_int(c.hit_stagger_frames_left()).is_equal(0)
	var d: Combatant = _combatant()
	d.config.requires_deathblow = false
	d.receive_attack(_hit(500.0))
	assert_bool(d.is_dead).is_true()
	assert_bool(d.stagger(60)).is_false()


func test_a_longer_stagger_extends_a_running_one() -> void:
	var c: Combatant = _combatant()
	c.stagger(30)
	c.step(20)
	c.stagger(40)
	assert_int(c.hit_stagger_frames_left()).is_equal(40)
	c.stagger(5)
	assert_int(c.hit_stagger_frames_left()).is_equal(40)


func test_posture_does_not_recover_while_staggered() -> void:
	var c: Combatant = _combatant()
	c.config.posture.regen_delay_frames = 0
	c.take_posture_damage(50.0)
	c.stagger(60)
	c.step(30)
	assert_float(c.posture.value).is_equal_approx(50.0, 0.001)


func test_revive_clears_a_stagger() -> void:
	var c: Combatant = _combatant()
	c.stagger(60)
	c.revive()
	assert_bool(c.is_staggered()).is_false()
	c.stagger(60)
	c.restore()
	assert_bool(c.is_staggered()).is_false()


func _hit(damage: float) -> AttackData:
	var a: AttackData = AttackData.new()
	a.damage = damage
	a.posture_damage = 0.0
	return a


# --- monster #1's real part data ------------------------------------------------------------

func _real(id: String) -> MonsterPartConfig:
	return load("res://data/combat/monster01_part_%s.tres" % id) as MonsterPartConfig


func test_monster01_parts_load_with_matching_ids() -> void:
	for id: String in PARTS:
		var c: MonsterPartConfig = _real(id)
		assert_object(c).is_not_null()
		assert_str(String(c.part_id)).is_equal(id)


func test_monster01_limbs_head_and_tail_break_but_the_body_does_not() -> void:
	for id: String in ["head", "left_forelimb", "right_forelimb", "tail"]:
		assert_bool(_real(id).is_breakable()).override_failure_message("%s should break" % id).is_true()
		assert_float(_real(id).posture.max_posture).is_greater(0.0)
	assert_bool(_real("body").is_breakable()).is_false()


func test_monster01_head_is_a_weak_point() -> void:
	assert_float(_real("head").damage_multiplier).is_greater(_real("body").damage_multiplier)


func test_monster01_forelimb_breaks_disable_or_weaken_the_swipe() -> void:
	var swipe: StringName = &"monster01_front_swipe"
	assert_bool(_real("right_forelimb").disables_attacks.has(swipe)).is_true()
	assert_bool(_real("left_forelimb").weakens_attacks.has(swipe)).is_true()
	assert_float(_real("left_forelimb").weakened_scale).is_less(1.0)
	var right: MonsterPartState = MonsterPartState.new(_real("right_forelimb"))
	var left: MonsterPartState = MonsterPartState.new(_real("left_forelimb"))
	var parts: Array[MonsterPartState] = [left, right]
	left.add_hit(1000.0)
	assert_float(MonsterPartState.attack_scale(parts, swipe)).is_equal_approx(_real("left_forelimb").weakened_scale, 0.0001)
	right.add_hit(1000.0)
	assert_bool(MonsterPartState.is_attack_disabled(parts, swipe)).is_true()


func test_monster01_part_effects_name_real_attacks() -> void:
	var ids: Dictionary[StringName, bool] = {}
	for e: MonsterAttackEntry in (load(AI) as LargeMonsterConfig).attacks:
		ids[e.attack.id] = true
	for id: String in PARTS:
		var c: MonsterPartConfig = _real(id)
		for a: StringName in c.disables_attacks + c.weakens_attacks:
			assert_bool(ids.has(a)).override_failure_message("%s names unknown attack %s" % [id, a]).is_true()


## A greatsword hit (30 posture × 50% unguarded) breaks a forelimb in a handful of hits.
func test_monster01_forelimb_breaks_in_a_few_greatsword_hits() -> void:
	var gs: AttackData = load("res://data/attacks/greatsword_light_1.tres") as AttackData
	var cfg: MonsterPartConfig = _real("left_forelimb")
	var per_hit: float = gs.posture_damage * 0.5 * cfg.posture_multiplier
	var s: MonsterPartState = MonsterPartState.new(cfg)
	var hits: int = 0
	while not s.is_broken() and hits < 50:
		s.add_hit(per_hit)
		hits += 1
	assert_int(hits).is_between(3, 6)


## Deathblow reach geometry (LargeMonster): nearest ground-plane point of its round body.
func test_nearest_on_circle_outside_and_inside() -> void:
	var p: Vector3 = LargeMonster._nearest_on_circle(Vector3(5.0, 0.0, 0.0), Vector3(1.0, 3.0, 0.0), 2.0)
	assert_vector(p).is_equal_approx(Vector3(3.0, 0.0, 0.0), Vector3(0.001, 0.001, 0.001))
	var inside: Vector3 = Vector3(1.5, 0.0, 0.5)
	assert_vector(LargeMonster._nearest_on_circle(inside, Vector3(1.0, 0.0, 0.0), 2.0)).is_equal(inside)


## …and of a part's box hurtbox: clamped to the box on the ground plane, so the tip of a
## long head or tail is in reach even far from the monster's origin.
func test_nearest_on_box_shape_clamps_to_the_box() -> void:
	var cs: CollisionShape3D = auto_free(CollisionShape3D.new()) as CollisionShape3D
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.6, 1.8, 2.2)
	cs.shape = box
	cs.position = Vector3(0.0, 2.1, 4.4)
	add_child(cs)
	var p: Vector3 = LargeMonster._nearest_on_shape(Vector3(0.0, 0.0, 5.9), cs)
	assert_vector(p).is_equal_approx(Vector3(0.0, 0.0, 5.5), Vector3(0.001, 0.001, 0.001))
	var q: Vector3 = LargeMonster._nearest_on_shape(Vector3(3.0, 0.0, 4.0), cs)
	assert_vector(q).is_equal_approx(Vector3(0.8, 0.0, 4.0), Vector3(0.001, 0.001, 0.001))
