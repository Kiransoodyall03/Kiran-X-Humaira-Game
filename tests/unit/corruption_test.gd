extends GdUnitTestSuite
## Corruption meter v0 (scripts/combat/corruption.gd): rise in katana, drain in
## greatsword, faster drain out of combat, in-combat rules, thresholds, rampage enter/exit,
## shrine reset and the input-hijack stub. Also checks data/combat/corruption.tres and the
## form rates against docs/COMBAT_SPEC.md. Frames are passed in explicitly (60 fps).

const CONFIG: String = "res://data/combat/corruption.tres"
const GREATSWORD: String = "res://data/forms/greatsword.tres"
const KATANA: String = "res://data/forms/katana.tres"
const HEROINE: String = "res://scenes/actors/heroine.tscn"


func _config() -> CorruptionConfig:
	var c: CorruptionConfig = CorruptionConfig.new()
	c.max_corruption = 100.0
	c.combat_linger_frames = 300
	c.thresholds = [50.0, 75.0, 100.0]
	c.hijack_start = 50.0
	c.hijack_chance_at_max = 0.25
	c.hijack_curve_exponent = 2.0
	c.rampage_exit_corruption = 50.0
	c.rampage_exit_health_ratio = 0.25
	c.rampage_locks_dodge = true
	return c


func _katana() -> FormConfig:
	var f: FormConfig = FormConfig.new()
	f.corruption_per_second = 4.0
	f.corruption_out_of_combat_multiplier = 1.0
	return f


func _greatsword() -> FormConfig:
	var f: FormConfig = FormConfig.new()
	f.corruption_per_second = -2.0
	f.corruption_out_of_combat_multiplier = 2.0
	return f


func _meter(start: float = 0.0) -> Corruption:
	var m: Corruption = Corruption.new(_config())
	m.value = start
	return m


func test_katana_rises_per_second() -> void:
	var m: Corruption = _meter()
	m.step(60, _katana(), true)
	assert_float(m.value).is_equal_approx(4.0, 0.0001)
	m.step(150, _katana(), false) # katana multiplier 1: same rate out of combat
	assert_float(m.value).is_equal_approx(14.0, 0.0001)


func test_greatsword_drains_slowly_in_combat() -> void:
	var m: Corruption = _meter(50.0)
	m.step(60, _greatsword(), true)
	assert_float(m.value).is_equal_approx(48.0, 0.0001)


func test_greatsword_drains_faster_out_of_combat() -> void:
	var m: Corruption = _meter(50.0)
	m.step(60, _greatsword(), false)
	assert_float(m.value).is_equal_approx(46.0, 0.0001)
	assert_float(Corruption.rate_per_second(_greatsword(), false)).is_equal(-4.0)
	assert_float(Corruption.rate_per_second(_greatsword(), true)).is_equal(-2.0)


func test_meter_clamps_to_zero_and_max() -> void:
	var m: Corruption = _meter(1.0)
	m.step(600, _greatsword(), false)
	assert_float(m.value).is_equal(0.0)
	m.step(60 * 60, _katana(), true)
	assert_float(m.value).is_equal(100.0)
	assert_float(m.ratio()).is_equal(1.0)


func test_no_form_no_change() -> void:
	var m: Corruption = _meter(30.0)
	m.step(600, null, true)
	assert_float(m.value).is_equal(30.0)


func test_in_combat_when_a_hostile_is_in_range() -> void:
	var m: Corruption = _meter()
	assert_bool(m.is_in_combat(1000, true)).is_true()
	assert_bool(m.is_in_combat(1000, false)).is_false()


func test_in_combat_lingers_after_an_attack() -> void:
	var m: Corruption = _meter()
	m.note_combat(1000)
	assert_bool(m.is_in_combat(1000, false)).is_true()
	assert_bool(m.is_in_combat(1299, false)).is_true()
	assert_bool(m.is_in_combat(1300, false)).is_false()


func test_thresholds_fire_once_each_way() -> void:
	var m: Corruption = _meter(40.0)
	var reached: Array[float] = []
	var dropped: Array[float] = []
	m.threshold_reached.connect(func(t: float) -> void: reached.append(t))
	m.threshold_dropped.connect(func(t: float) -> void: dropped.append(t))
	m.set_value(80.0)
	assert_array(reached).is_equal([50.0, 75.0])
	m.set_value(90.0)
	assert_array(reached).is_equal([50.0, 75.0])
	m.set_value(100.0)
	assert_array(reached).is_equal([50.0, 75.0, 100.0])
	m.set_value(60.0)
	assert_array(dropped).is_equal([75.0, 100.0])
	m.set_value(10.0)
	assert_array(dropped).is_equal([75.0, 100.0, 50.0])


func test_rampage_starts_at_max_and_locks_dodge() -> void:
	var m: Corruption = _meter(99.0)
	var started: Array[int] = [0]
	m.rampage_started.connect(func() -> void: started[0] += 1)
	m.step(14, _katana(), true) # +0.93
	assert_bool(m.is_rampaging).is_false()
	assert_bool(m.locks_dodge()).is_false()
	m.step(2, _katana(), true)
	assert_bool(m.is_rampaging).is_true()
	assert_bool(m.locks_dodge()).is_true()
	m.step(600, _katana(), true) # staying at max doesn't restart it
	assert_int(started[0]).is_equal(1)


func test_rampage_ends_when_drained_to_exit_value() -> void:
	var m: Corruption = _meter(99.9)
	m.step(60, _katana(), true)
	assert_bool(m.is_rampaging).is_true()
	var reasons: Array[Corruption.RampageEnd] = []
	m.rampage_ended.connect(func(r: Corruption.RampageEnd) -> void: reasons.append(r))
	m.set_value(51.0)
	assert_bool(m.is_rampaging).is_true() # still above 50
	m.step(29, _greatsword(), true) # -0.97 → 50.03
	assert_bool(m.is_rampaging).is_true()
	m.step(2, _greatsword(), true) # → 49.97
	assert_bool(m.is_rampaging).is_false()
	assert_bool(m.locks_dodge()).is_false()
	assert_array(reasons).is_equal([Corruption.RampageEnd.DRAINED])


func test_rampage_ends_at_critical_health() -> void:
	var m: Corruption = _meter(99.9)
	m.step(60, _katana(), true, 1.0)
	assert_bool(m.is_rampaging).is_true()
	var reasons: Array[Corruption.RampageEnd] = []
	m.rampage_ended.connect(func(r: Corruption.RampageEnd) -> void: reasons.append(r))
	m.step(1, _katana(), true, 0.26)
	assert_bool(m.is_rampaging).is_true()
	m.check_health(0.25)
	assert_bool(m.is_rampaging).is_false()
	assert_array(reasons).is_equal([Corruption.RampageEnd.CRITICAL_HEALTH])
	# Still at max with health back up: no restart until it drops below max and returns.
	m.step(60, _katana(), true, 1.0)
	assert_bool(m.is_rampaging).is_false()
	m.step(30, _greatsword(), true, 1.0)
	m.step(60, _katana(), true, 1.0)
	assert_bool(m.is_rampaging).is_true()


func test_no_rampage_while_health_is_critical() -> void:
	var m: Corruption = _meter(99.9)
	m.step(60, _katana(), true, 0.1)
	assert_float(m.value).is_equal(100.0)
	assert_bool(m.is_rampaging).is_false()


func test_shrine_reset_empties_and_ends_rampage() -> void:
	var m: Corruption = _meter(99.9)
	m.step(60, _katana(), true)
	m.note_combat(500)
	var reasons: Array[Corruption.RampageEnd] = []
	var resets: Array[int] = [0]
	m.rampage_ended.connect(func(r: Corruption.RampageEnd) -> void: reasons.append(r))
	m.shrine_reset.connect(func() -> void: resets[0] += 1)
	m.reset_at_shrine()
	assert_float(m.value).is_equal(0.0)
	assert_bool(m.is_rampaging).is_false()
	assert_array(reasons).is_equal([Corruption.RampageEnd.SHRINE])
	assert_int(resets[0]).is_equal(1)
	assert_bool(m.is_in_combat(501, false)).is_false()


func test_hijack_chance_rises_with_corruption() -> void:
	var m: Corruption = _meter(50.0)
	assert_float(m.hijack_chance()).is_equal(0.0)
	m.value = 75.0
	assert_float(m.hijack_chance()).is_equal_approx(0.25 * 0.25, 0.0001) # ((75-50)/50)^2 × 0.25
	m.value = 100.0
	assert_float(m.hijack_chance()).is_equal_approx(0.25, 0.0001)


func test_should_hijack_input_follows_the_chance() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var m: Corruption = _meter(20.0)
	for i: int in 200:
		assert_bool(m.should_hijack_input(rng)).is_false()
	m.value = 100.0
	var hits: int = 0
	for i: int in 2000:
		if m.should_hijack_input(rng):
			hits += 1
	assert_int(hits).is_between(400, 600) # 25% of 2000 = 500


func test_tuning_file_matches_the_spec() -> void:
	var c: CorruptionConfig = load(CONFIG) as CorruptionConfig
	assert_object(c).is_not_null()
	assert_float(c.max_corruption).is_equal(100.0)
	assert_array(c.thresholds).is_equal([50.0, 75.0, 100.0])
	assert_float(c.rampage_exit_corruption).is_less(c.max_corruption)
	assert_float(c.hijack_start).is_less(c.max_corruption)
	assert_float(c.combat_radius).is_greater(0.0)
	assert_int(c.combat_linger_frames).is_greater(0)
	assert_bool(c.rampage_locks_dodge).is_true()
	var gs: FormConfig = load(GREATSWORD) as FormConfig
	var kt: FormConfig = load(KATANA) as FormConfig
	assert_float(Corruption.rate_per_second(kt, true)).is_greater(0.0)
	assert_float(Corruption.rate_per_second(gs, true)).is_less(0.0)
	assert_float(Corruption.rate_per_second(gs, false)).is_less(Corruption.rate_per_second(gs, true))


func test_heroine_scene_has_a_corruption_meter() -> void:
	var heroine: Node = auto_free((load(HEROINE) as PackedScene).instantiate()) as Node
	var meter: CorruptionMeter = heroine.get_node_or_null(^"CorruptionMeter") as CorruptionMeter
	assert_object(meter).is_not_null()
	assert_object(meter.config).is_not_null()
	assert_str(meter.config.resource_path).is_equal(CONFIG)
