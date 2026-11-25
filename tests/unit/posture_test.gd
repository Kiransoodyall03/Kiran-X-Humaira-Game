extends GdUnitTestSuite
## Posture meter rules (scripts/combat/posture.gd). Uses its own config so tuning
## changes in data/ don't break these tests.


func _config() -> PostureConfig:
	var c: PostureConfig = PostureConfig.new()
	c.max_posture = 100.0
	c.regen_per_second = 60.0 # 1 point per frame: easy maths
	c.regen_delay_frames = 30
	c.guard_regen_multiplier = 2.0
	c.low_health_regen_multiplier = 0.5
	return c


func test_starts_empty() -> void:
	var p: Posture = Posture.new(_config())
	assert_float(p.value).is_equal(0.0)
	assert_bool(p.is_broken).is_false()


func test_add_accumulates_without_breaking() -> void:
	var p: Posture = Posture.new(_config())
	assert_bool(p.add(40.0)).is_false()
	assert_bool(p.add(40.0)).is_false()
	assert_float(p.value).is_equal_approx(80.0, 0.001)


func test_filling_to_max_breaks_once() -> void:
	var p: Posture = Posture.new(_config())
	p.add(90.0)
	assert_bool(p.add(20.0)).is_true()
	assert_bool(p.is_broken).is_true()
	assert_float(p.value).is_equal(100.0)
	# Further damage while broken does nothing.
	assert_bool(p.add(50.0)).is_false()


func test_broken_signal_fires() -> void:
	var p: Posture = Posture.new(_config())
	var fired: Array[int] = [0]
	p.broken.connect(func() -> void: fired[0] += 1)
	p.add(150.0)
	assert_int(fired[0]).is_equal(1)


func test_non_breaking_add_stops_just_below_max() -> void:
	var p: Posture = Posture.new(_config())
	p.add(95.0)
	assert_bool(p.add(50.0, false)).is_false()
	assert_bool(p.is_broken).is_false()
	assert_float(p.value).is_less(100.0)
	assert_float(p.value).is_greater(99.9)


func test_no_recovery_before_delay() -> void:
	var p: Posture = Posture.new(_config())
	p.add(50.0)
	p.tick(29, false, 1.0)
	assert_float(p.value).is_equal_approx(50.0, 0.001)


func test_recovers_after_delay() -> void:
	var p: Posture = Posture.new(_config())
	p.add(50.0)
	p.tick(30, false, 1.0) # reaches the delay: this tick recovers 30 frames' worth
	assert_float(p.value).is_equal_approx(20.0, 0.001)
	p.tick(30, false, 1.0)
	assert_float(p.value).is_equal(0.0) # never below zero


func test_new_damage_restarts_the_delay() -> void:
	var p: Posture = Posture.new(_config())
	p.add(50.0)
	p.tick(25, false, 1.0)
	p.add(10.0)
	p.tick(25, false, 1.0)
	assert_float(p.value).is_equal_approx(60.0, 0.001)


func test_guarding_recovers_faster() -> void:
	var p: Posture = Posture.new(_config())
	p.add(80.0)
	p.tick(30, false, 1.0)
	p.tick(10, true, 1.0) # 10 frames × 1/frame × 2.0
	assert_float(p.value).is_equal_approx(80.0 - 30.0 - 20.0, 0.001)


func test_low_health_recovers_slower() -> void:
	var p: Posture = Posture.new(_config())
	p.add(80.0)
	p.tick(30, false, 0.0) # 30 frames × 1/frame × 0.5 at zero health
	assert_float(p.value).is_equal_approx(65.0, 0.001)


func test_no_recovery_while_broken() -> void:
	var p: Posture = Posture.new(_config())
	p.add(200.0)
	p.tick(600, true, 1.0)
	assert_float(p.value).is_equal(100.0)


func test_reset_clears_broken() -> void:
	var p: Posture = Posture.new(_config())
	p.add(200.0)
	p.reset()
	assert_bool(p.is_broken).is_false()
	assert_float(p.value).is_equal(0.0)
