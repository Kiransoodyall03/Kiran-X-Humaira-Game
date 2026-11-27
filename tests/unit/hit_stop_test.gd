extends GdUnitTestSuite
## Hit-stop service (scripts/systems/hit_stop_service.gd): time scale lowered and restored,
## overlapping requests extend instead of stacking, the combat clock pauses, and the
## time scale comes back if the service leaves the tree. Uses a private service node so
## the project's "HitStop" autoload is left alone.

var _service: HitStopService


func _make(time_scale: float = 0.1) -> HitStopService:
	var cfg: HitStopConfig = HitStopConfig.new()
	cfg.time_scale = time_scale
	cfg.parry_ms = 80
	cfg.hit_ms = 40
	cfg.posture_break_ms = 120
	cfg.deathblow_ms = 200
	var s: HitStopService = HitStopService.new()
	s.config = cfg
	add_child(s)
	return s


func before_test() -> void:
	_service = _make()


func after_test() -> void:
	if is_instance_valid(_service):
		_service.end_now()
		_service.queue_free()
	Engine.time_scale = 1.0


## Waits real seconds, unaffected by the time scale.
func _real_wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


## Waits (real time) until no freeze is active, at most `max_seconds`. Polling instead of a
## fixed wait keeps the restore checks from flaking when the machine is loaded; a freeze
## that never ends still fails them.
func _wait_until_restored(max_seconds: float = 1.0) -> void:
	var deadline: int = Time.get_ticks_usec() + int(max_seconds * 1_000_000.0)
	while HitStopService.is_active() and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame


## Waits (real time) until Time.get_ticks_usec() reaches `usec`.
func _wait_until_usec(usec: int) -> void:
	while Time.get_ticks_usec() < usec:
		await get_tree().process_frame


func test_config_maps_each_kind() -> void:
	var cfg: HitStopConfig = _service.config
	assert_int(cfg.duration_ms(HitStopService.Kind.PARRY)).is_equal(80)
	assert_int(cfg.duration_ms(HitStopService.Kind.HIT)).is_equal(40)
	assert_int(cfg.duration_ms(HitStopService.Kind.POSTURE_BREAK)).is_equal(120)
	assert_int(cfg.duration_ms(HitStopService.Kind.DEATHBLOW)).is_equal(200)


func test_project_tuning() -> void:
	var cfg: HitStopConfig = load("res://data/combat/hitstop.tres") as HitStopConfig
	assert_bool(cfg.enabled).is_true()
	assert_float(cfg.time_scale).is_equal(0.05)
	assert_int(cfg.parry_ms).is_equal(90)
	assert_int(cfg.hit_ms).is_equal(50)
	assert_int(cfg.posture_break_ms).is_equal(150)
	assert_int(cfg.deathblow_ms).is_equal(250)
	# Escalation: a deathblow freezes longest, a plain hit shortest.
	assert_int(cfg.deathblow_ms).is_greater(cfg.posture_break_ms)
	assert_int(cfg.posture_break_ms).is_greater(cfg.parry_ms)
	assert_int(cfg.parry_ms).is_greater(cfg.hit_ms)


func test_autoload_is_registered() -> void:
	assert_object(HitStopService.instance()).is_not_null()
	assert_str(ProjectSettings.get_setting("autoload/HitStop", "") as String).contains("hit_stop_service.gd")


func test_request_lowers_time_scale_and_restores_it() -> void:
	_service.request(HitStopService.Kind.HIT)
	assert_bool(HitStopService.is_active()).is_true()
	assert_float(Engine.time_scale).is_equal_approx(0.1, 0.0001)
	await _real_wait(0.05) # past its 40 ms
	await _wait_until_restored()
	assert_bool(HitStopService.is_active()).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)


func test_disabled_config_does_nothing() -> void:
	_service.config.enabled = false
	_service.request(HitStopService.Kind.DEATHBLOW)
	assert_bool(HitStopService.is_active()).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)


func test_zero_duration_does_nothing() -> void:
	assert_bool(_service.freeze_ms(0)).is_false()
	assert_bool(HitStopService.is_active()).is_false()


func test_overlapping_requests_extend_not_stack() -> void:
	_service.freeze_ms(100, 0.1)
	var first_end: int = HitStopService.end_usec()
	_service.freeze_ms(30, 0.1) # ends earlier: no change
	assert_int(HitStopService.end_usec()).is_equal(first_end)
	var before: int = Time.get_ticks_usec()
	_service.freeze_ms(300, 0.1)
	var second_end: int = HitStopService.end_usec()
	assert_int(second_end).is_greater_equal(before + 300_000)
	# Stacking would end 300 ms after the first end; extending ends 300 ms after now.
	assert_int(second_end).is_less(first_end + 300_000)
	assert_float(Engine.time_scale).is_equal_approx(0.1, 0.0001)


func test_lower_time_scale_wins_while_overlapping() -> void:
	_service.freeze_ms(100, 0.2)
	_service.freeze_ms(50, 0.05)
	assert_float(Engine.time_scale).is_equal_approx(0.05, 0.0001)
	_service.end_now()
	assert_float(Engine.time_scale).is_equal(1.0)


func test_extended_freeze_still_restores() -> void:
	_service.freeze_ms(60, 0.1)
	var first_end: int = HitStopService.end_usec()
	await _real_wait(0.03)
	_service.freeze_ms(120, 0.1)
	var second_end: int = HitStopService.end_usec()
	assert_int(second_end).is_greater(first_end)
	# Past the first end (its timer has fired by now), inside the extension. On a machine
	# too loaded to wake before the extension also ends, only the restore is checked.
	await _wait_until_usec(first_end + 10_000)
	if Time.get_ticks_usec() < second_end - 5_000:
		assert_bool(HitStopService.is_active()).is_true()
	await _real_wait(0.05)
	await _wait_until_restored()
	assert_bool(HitStopService.is_active()).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)


func test_leaving_the_tree_restores_time_scale() -> void:
	_service.freeze_ms(5000, 0.1)
	assert_float(Engine.time_scale).is_equal_approx(0.1, 0.0001)
	remove_child(_service)
	assert_bool(HitStopService.is_active()).is_false()
	assert_float(Engine.time_scale).is_equal(1.0)
	_service.free()


func test_combat_clock_pauses_during_the_freeze() -> void:
	await get_tree().physics_frame
	var start: int = HitStopService.combat_frame()
	_service.freeze_ms(5000, 0.1)
	assert_bool(HitStopService.is_frozen()).is_false() # the requesting tick runs normally
	for i: int in 4:
		await get_tree().physics_frame
	assert_bool(HitStopService.is_frozen()).is_true()
	assert_int(HitStopService.combat_frame()).is_equal(start)
	_service.end_now()
	assert_int(HitStopService.combat_frame()).is_equal(start)
	await get_tree().physics_frame
	assert_int(HitStopService.combat_frame()).is_equal(start + 1)
	assert_bool(HitStopService.is_frozen()).is_false()
