extends GdUnitTestSuite
## ComboRunner (scripts/combat/combo_runner.gd): swing phase timing, buffering the next
## step, the combo window, and switching forms mid-combo. Each step_frame() is one frame.


func _attack(id: StringName, startup: int, active: int, recovery: int) -> AttackData:
	var a: AttackData = AttackData.new()
	a.id = id
	a.startup_frames = startup
	a.active_frames = active
	a.recovery_frames = recovery
	return a


## Three steps of 10/3/5 frames (18 total), combo window 6 frames.
func _form(prefix: String, window: int = 6) -> FormConfig:
	var f: FormConfig = FormConfig.new()
	f.id = StringName(prefix)
	var combo: Array[AttackData] = []
	for i: int in 3:
		combo.append(_attack(StringName("%s_%d" % [prefix, i + 1]), 10, 3, 5))
	f.light_combo = combo
	f.combo_window_frames = window
	return f


func _steps(runner: ComboRunner, frames: int) -> void:
	for i: int in frames:
		runner.step_frame()


func test_swing_phases_follow_the_frame_data() -> void:
	var r: ComboRunner = ComboRunner.new(_form("a"))
	assert_bool(r.press()).is_true()
	assert_int(r.swing_frame).is_equal(1)
	assert_int(r.phase()).is_equal(ComboRunner.Phase.STARTUP)
	_steps(r, 9) # frame 10: last startup frame
	assert_int(r.phase()).is_equal(ComboRunner.Phase.STARTUP)
	r.step_frame() # frame 11: first active frame
	assert_int(r.phase()).is_equal(ComboRunner.Phase.ACTIVE)
	_steps(r, 2) # frame 13: last active frame
	assert_bool(r.is_active()).is_true()
	r.step_frame() # frame 14: recovery
	assert_int(r.phase()).is_equal(ComboRunner.Phase.RECOVERY)
	_steps(r, 4) # frame 18: last recovery frame
	assert_bool(r.is_busy()).is_true()
	r.step_frame()
	assert_int(r.phase()).is_equal(ComboRunner.Phase.IDLE)


func test_press_during_startup_is_ignored() -> void:
	var r: ComboRunner = ComboRunner.new(_form("a"))
	r.press()
	_steps(r, 3)
	assert_bool(r.press()).is_false()
	assert_bool(r.buffered).is_false()


func test_buffered_press_in_recovery_chains_on_the_next_frame() -> void:
	var r: ComboRunner = ComboRunner.new(_form("a"))
	var started: Array[int] = []
	r.swing_started.connect(func(_a: AttackData, s: int) -> void: started.append(s))
	r.press()
	_steps(r, 14) # frame 15: recovery
	assert_bool(r.press()).is_true()
	assert_bool(r.buffered).is_true()
	_steps(r, 2) # frame 17
	assert_int(r.step).is_equal(0)
	_steps(r, 1) # frame 18: still the first swing's last recovery frame
	assert_int(r.step).is_equal(0)
	r.step_frame() # 18 frames after the first press: step 2 starts
	assert_int(r.step).is_equal(1)
	assert_int(r.swing_frame).is_equal(1)
	assert_array(started).is_equal([0, 1])


func test_press_during_active_frames_is_buffered_too() -> void:
	var r: ComboRunner = ComboRunner.new(_form("a"))
	r.press()
	_steps(r, 10) # frame 11: active
	assert_bool(r.press()).is_true()
	_steps(r, 8)
	assert_int(r.step).is_equal(1)


func test_combo_wraps_after_the_last_step() -> void:
	var r: ComboRunner = ComboRunner.new(_form("a"))
	var started: Array[int] = []
	r.swing_started.connect(func(_a: AttackData, s: int) -> void: started.append(s))
	r.press()
	for i: int in 3:
		_steps(r, 15)
		r.press()
		_steps(r, 3)
	assert_array(started).is_equal([0, 1, 2, 0])


func test_press_inside_the_combo_window_continues_the_combo() -> void:
	var r: ComboRunner = ComboRunner.new(_form("a", 6))
	r.press()
	_steps(r, 18) # swing over
	assert_bool(r.is_busy()).is_false()
	assert_int(r.combo_window_left()).is_equal(6)
	_steps(r, 5)
	r.press()
	assert_int(r.step).is_equal(1)


func test_press_after_the_combo_window_restarts_the_combo() -> void:
	var r: ComboRunner = ComboRunner.new(_form("a", 6))
	r.press()
	_steps(r, 18 + 6)
	r.press()
	assert_int(r.step).is_equal(0)


func test_switch_in_recovery_cancels_it_and_continues_in_the_new_form() -> void:
	var a: FormConfig = _form("a")
	var b: FormConfig = _form("b")
	var r: ComboRunner = ComboRunner.new(a)
	var ended: Array[bool] = []
	r.swing_ended.connect(func(_x: AttackData, cancelled: bool) -> void: ended.append(cancelled))
	r.press()
	_steps(r, 13) # frame 14: first recovery frame
	r.switch_form(b)
	assert_bool(r.is_busy()).is_false()
	assert_array(ended).is_equal([false])
	r.press()
	assert_int(r.step).is_equal(1)
	assert_object(r.attack).is_same(b.light_combo[1])


func test_switch_with_a_buffered_press_chains_straight_into_the_new_form() -> void:
	var a: FormConfig = _form("a")
	var b: FormConfig = _form("b")
	var r: ComboRunner = ComboRunner.new(a)
	r.press()
	_steps(r, 14)
	r.press()
	r.switch_form(b)
	assert_object(r.attack).is_same(b.light_combo[1])
	assert_int(r.swing_frame).is_equal(1)


func test_switch_during_startup_lets_the_hit_land_then_cuts_recovery() -> void:
	var a: FormConfig = _form("a")
	var b: FormConfig = _form("b")
	var r: ComboRunner = ComboRunner.new(a)
	r.press()
	_steps(r, 4) # startup
	r.switch_form(b)
	assert_object(r.form).is_same(b)
	assert_object(r.attack).is_same(a.light_combo[0]) # the swing keeps its data
	_steps(r, 6) # frame 11: active, the old form's hit
	assert_bool(r.is_active()).is_true()
	_steps(r, 2) # frame 13: last active frame
	assert_bool(r.is_busy()).is_true()
	r.step_frame() # would be recovery: cut
	assert_bool(r.is_busy()).is_false()
	r.press()
	assert_object(r.attack).is_same(b.light_combo[1])


func test_switching_while_idle_keeps_the_combo_position() -> void:
	var a: FormConfig = _form("a")
	var b: FormConfig = _form("b")
	var r: ComboRunner = ComboRunner.new(a)
	r.press()
	_steps(r, 18)
	r.switch_form(b)
	r.press()
	assert_object(r.attack).is_same(b.light_combo[1])


func test_cancel_resets_the_combo() -> void:
	var r: ComboRunner = ComboRunner.new(_form("a"))
	var ended: Array[bool] = []
	r.swing_ended.connect(func(_x: AttackData, cancelled: bool) -> void: ended.append(cancelled))
	r.press()
	_steps(r, 14)
	r.press()
	r.cancel()
	assert_bool(r.is_busy()).is_false()
	assert_bool(r.buffered).is_false()
	assert_array(ended).is_equal([true])
	r.press()
	assert_int(r.step).is_equal(0)


func test_empty_combo_never_starts() -> void:
	var f: FormConfig = FormConfig.new()
	var r: ComboRunner = ComboRunner.new(f)
	assert_bool(r.press()).is_false()
	assert_bool(r.is_busy()).is_false()
