extends GdUnitTestSuite
## Guard timing rules (scripts/combat/guard.gd): parry window and mashing penalty.


func _config() -> GuardConfig:
	var c: GuardConfig = GuardConfig.new()
	c.parry_window_frames = 12
	c.mash_frames = 20
	c.mash_penalty_frames = 4
	c.min_parry_window_frames = 4
	return c


func test_never_pressed_is_not_parrying() -> void:
	var g: Guard = Guard.new(_config())
	assert_bool(g.is_parry_active(1000)).is_false()
	assert_int(g.frames_since_press(1000)).is_equal(-1)


func test_press_frame_counts_as_parry() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	assert_bool(g.is_parry_active(100)).is_true()


func test_window_is_exactly_n_frames() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	assert_bool(g.is_parry_active(111)).is_true() # 12th frame (age 11)
	assert_bool(g.is_parry_active(112)).is_false() # age 12: too late


func test_hit_before_press_is_not_a_parry() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	assert_bool(g.is_parry_active(99)).is_false()


func test_parry_does_not_need_guard_held() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	g.release()
	assert_bool(g.is_held).is_false()
	assert_bool(g.is_parry_active(105)).is_true()


func test_mashing_shrinks_the_window() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	g.press(110) # within 20 frames: mashed
	assert_int(g.current_window()).is_equal(8)
	g.press(120)
	assert_int(g.current_window()).is_equal(4)
	g.press(130)
	assert_int(g.current_window()).is_equal(4) # floor


func test_waiting_restores_the_full_window() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	g.press(110)
	g.press(200) # 90 frames later: not mashing
	assert_int(g.current_window()).is_equal(12)


func test_first_press_ever_gets_the_full_window() -> void:
	var g: Guard = Guard.new(_config())
	g.press(5) # early frame numbers must not look like mashing against "never"
	assert_int(g.current_window()).is_equal(12)


func test_cancel_closes_the_parry_window() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	g.cancel()
	assert_bool(g.is_held).is_false()
	assert_bool(g.is_parry_active(100)).is_false()
	assert_bool(g.is_parry_active(105)).is_false()


func test_cancel_after_a_tap_release_still_closes_the_window() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	g.release()
	assert_bool(g.is_parry_active(103)).is_true()
	g.cancel()
	assert_bool(g.is_parry_active(104)).is_false()


func test_press_after_cancel_reopens_the_window() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	g.cancel()
	g.press(200)
	assert_bool(g.is_held).is_true()
	assert_bool(g.is_parry_active(205)).is_true()


func test_cancel_keeps_mash_tracking() -> void:
	var g: Guard = Guard.new(_config())
	g.press(100)
	g.cancel()
	g.press(110) # still mashing: cancel must not reset the penalty
	assert_int(g.current_window()).is_equal(8)
	assert_int(g.frames_since_press(115)).is_equal(5)
