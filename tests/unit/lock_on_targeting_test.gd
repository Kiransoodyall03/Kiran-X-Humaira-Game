extends GdUnitTestSuite
## Lock-on target scoring and cycling order (scripts/combat/lock_on_targeting.gd) and the
## camera pull-back formula (LockOnConfig.pullback_for). Candidates are built by hand:
## screen = view-tangent offset from the screen centre (x right), distance in meters.


func _config() -> LockOnConfig:
	var c: LockOnConfig = LockOnConfig.new()
	c.acquire_range = 20.0
	c.break_range = 25.0
	c.acquire_max_angle_degrees = 55.0
	c.cycle_max_angle_degrees = 80.0
	c.screen_weight = 1.0
	c.distance_weight = 0.35
	c.priority_weight = 0.15
	return c


func _keys(cands: Array[LockOnCandidate]) -> Array[int]:
	var out: Array[int] = []
	for c: LockOnCandidate in cands:
		out.append(c.key)
	return out


## One cycle step the way LockOn does it: the visited set is reset on a new target.
func _cycle(cands: Array[LockOnCandidate], current_key: int, visited: Dictionary[int, bool], direction: int) -> int:
	var i: int = LockOnTargeting.next_index(cands, current_key, visited, direction, _config())
	if i == -1:
		return -1
	var cur: int = LockOnTargeting.index_of_key(cands, current_key)
	if cands[i].target_key != cands[cur].target_key:
		visited.clear()
	visited[cands[i].key] = true
	return cands[i].key


# --- picking ---------------------------------------------------------------------------

func test_pick_prefers_the_point_nearest_the_screen_centre() -> void:
	var cands: Array[LockOnCandidate] = [
		LockOnCandidate.make(1, 10, Vector2(0.5, 0.0), 6.0),
		LockOnCandidate.make(2, 20, Vector2(0.05, 0.02), 12.0),
		LockOnCandidate.make(3, 30, Vector2(-0.3, 0.1), 4.0),
	]
	assert_int(cands[LockOnTargeting.pick_best(cands, _config())].key).is_equal(2)


func test_pick_skips_points_behind_out_of_range_out_of_sight_dead_or_too_far_off_centre() -> void:
	var behind: LockOnCandidate = LockOnCandidate.make(1, 10, Vector2.ZERO, 5.0)
	behind.in_front = false
	var far: LockOnCandidate = LockOnCandidate.make(2, 20, Vector2.ZERO, 20.5)
	var hidden: LockOnCandidate = LockOnCandidate.make(3, 30, Vector2.ZERO, 5.0)
	hidden.has_los = false
	var dead: LockOnCandidate = LockOnCandidate.make(4, 40, Vector2.ZERO, 5.0)
	dead.alive = false
	var wide: LockOnCandidate = LockOnCandidate.make(5, 50, Vector2(tan(deg_to_rad(60.0)), 0.0), 5.0)
	var cands: Array[LockOnCandidate] = [behind, far, hidden, dead, wide]
	assert_int(LockOnTargeting.pick_best(cands, _config())).is_equal(-1)
	var ok: LockOnCandidate = LockOnCandidate.make(6, 60, Vector2(tan(deg_to_rad(50.0)), 0.0), 19.5)
	cands.append(ok)
	assert_int(cands[LockOnTargeting.pick_best(cands, _config())].key).is_equal(6)


func test_pick_returns_minus_one_with_no_points() -> void:
	var none: Array[LockOnCandidate] = []
	assert_int(LockOnTargeting.pick_best(none, _config())).is_equal(-1)


func test_distance_breaks_a_tie_on_screen() -> void:
	var cands: Array[LockOnCandidate] = [
		LockOnCandidate.make(1, 10, Vector2(0.2, 0.0), 15.0),
		LockOnCandidate.make(2, 20, Vector2(-0.2, 0.0), 5.0),
	]
	assert_int(cands[LockOnTargeting.pick_best(cands, _config())].key).is_equal(2)


func test_priority_prefers_the_main_part_when_parts_overlap() -> void:
	var cands: Array[LockOnCandidate] = [
		LockOnCandidate.make(1, 10, Vector2(0.02, 0.0), 8.0, 0, &"tail"),
		LockOnCandidate.make(2, 10, Vector2(0.06, 0.0), 8.0, 2, &"body"),
	]
	assert_int(cands[LockOnTargeting.pick_best(cands, _config())].key).is_equal(2)


func test_score_grows_with_angle_and_distance_and_shrinks_with_priority() -> void:
	var cfg: LockOnConfig = _config()
	var base: float = LockOnTargeting.score(LockOnCandidate.make(1, 1, Vector2(0.1, 0.0), 5.0), cfg)
	assert_float(LockOnTargeting.score(LockOnCandidate.make(1, 1, Vector2(0.4, 0.0), 5.0), cfg)).is_greater(base)
	assert_float(LockOnTargeting.score(LockOnCandidate.make(1, 1, Vector2(0.1, 0.0), 15.0), cfg)).is_greater(base)
	assert_float(LockOnTargeting.score(LockOnCandidate.make(1, 1, Vector2(0.1, 0.0), 5.0, 3), cfg)).is_less(base)


# --- cycling ---------------------------------------------------------------------------

## A monster (target 10) with three parts and two more targets (20 left, 30 right).
func _scene() -> Array[LockOnCandidate]:
	return [
		LockOnCandidate.make(11, 10, Vector2(0.0, 0.0), 8.0, 1, &"body"),
		LockOnCandidate.make(12, 10, Vector2(0.15, 0.3), 9.0, 0, &"head"),
		LockOnCandidate.make(13, 10, Vector2(-0.2, -0.1), 8.0, 0, &"tail"),
		LockOnCandidate.make(21, 20, Vector2(-0.6, 0.0), 10.0, 0, &"body"),
		LockOnCandidate.make(31, 30, Vector2(0.7, 0.0), 10.0, 0, &"body"),
		LockOnCandidate.make(32, 30, Vector2(0.75, 0.2), 10.0, -1, &"head"),
	]


func test_cycle_next_visits_the_other_parts_of_the_target_first_then_the_next_target() -> void:
	var cands: Array[LockOnCandidate] = _scene()
	var visited: Dictionary[int, bool] = {11: true}
	var order: Array[int] = []
	var key: int = 11
	for i: int in 6:
		key = _cycle(cands, key, visited, 1)
		order.append(key)
	# body(0) -> head(0.15, right) -> tail (wraps to the left) -> target 30 (the next target
	# right of the tail, landing on its best part, the body) -> its head -> target 20 (wraps)
	assert_array(order).is_equal([12, 13, 31, 32, 21, 11])


func test_cycle_prev_goes_left() -> void:
	var cands: Array[LockOnCandidate] = _scene()
	var visited: Dictionary[int, bool] = {11: true}
	var order: Array[int] = []
	var key: int = 11
	for i: int in 4:
		key = _cycle(cands, key, visited, -1)
		order.append(key)
	# body -> tail (left) -> head (wraps round to the right) -> target 20 (the nearest
	# other target left of the head) -> target 30 (nothing further left: wraps round to the
	# right-most target, landing on its body)
	assert_array(order).is_equal([13, 12, 21, 31])


func test_cycle_lands_on_the_best_part_of_a_new_target() -> void:
	var cands: Array[LockOnCandidate] = _scene()
	var visited: Dictionary[int, bool] = {21: true}
	# From target 20 going right, the nearest target is the monster: land on its body
	# (priority 1, nearest the centre), not the tail even though the tail is further left.
	assert_int(_cycle(cands, 21, visited, 1)).is_equal(11)


func test_cycle_with_a_single_target_goes_round_its_parts() -> void:
	var cands: Array[LockOnCandidate] = _scene().slice(0, 3)
	var visited: Dictionary[int, bool] = {11: true}
	var order: Array[int] = []
	var key: int = 11
	for i: int in 4:
		key = _cycle(cands, key, visited, 1)
		order.append(key)
	assert_array(order).is_equal([12, 13, 11, 12])


func test_cycle_skips_dead_and_hidden_points() -> void:
	var cands: Array[LockOnCandidate] = _scene()
	cands[1].alive = false # head broken off
	cands[4].has_los = false # target 30's body behind a wall
	var visited: Dictionary[int, bool] = {11: true}
	assert_int(_cycle(cands, 11, visited, 1)).is_equal(13) # tail, not the dead head
	assert_int(_cycle(cands, 13, visited, 1)).is_equal(32) # target 30 via its visible head


func test_off_screen_parts_of_the_current_target_can_still_be_cycled_to() -> void:
	var cands: Array[LockOnCandidate] = _scene().slice(0, 3)
	cands[2].in_front = false # the tail is behind the camera
	cands[2].screen = Vector2(-1000.0, 0.0)
	var visited: Dictionary[int, bool] = {11: true, 12: true}
	assert_int(_cycle(cands, 12, visited, 1)).is_equal(13)


func test_cycle_with_nothing_else_returns_minus_one() -> void:
	var cands: Array[LockOnCandidate] = [LockOnCandidate.make(1, 1, Vector2.ZERO, 5.0)]
	var visited: Dictionary[int, bool] = {1: true}
	assert_int(LockOnTargeting.next_index(cands, 1, visited, 1, _config())).is_equal(-1)


func test_cycle_from_a_point_that_is_gone_picks_the_best() -> void:
	var cands: Array[LockOnCandidate] = _scene()
	var visited: Dictionary[int, bool] = {}
	assert_int(cands[LockOnTargeting.next_index(cands, 999, visited, 1, _config())].key).is_equal(11)


func test_other_targets_off_screen_are_not_cycled_to() -> void:
	var cands: Array[LockOnCandidate] = [
		LockOnCandidate.make(1, 1, Vector2.ZERO, 5.0),
		LockOnCandidate.make(2, 2, Vector2(tan(deg_to_rad(85.0)), 0.0), 5.0),
	]
	var visited: Dictionary[int, bool] = {1: true}
	assert_int(LockOnTargeting.next_index(cands, 1, visited, 1, _config())).is_equal(-1)


func test_cycling_reaches_other_targets_wider_than_the_first_pick() -> void:
	# 65° off centre: outside the 55° pick cone, inside the 80° cycle cone.
	var wide: LockOnCandidate = LockOnCandidate.make(2, 2, Vector2(tan(deg_to_rad(65.0)), 0.0), 5.0)
	var cands: Array[LockOnCandidate] = [LockOnCandidate.make(1, 1, Vector2.ZERO, 5.0), wide]
	var only_wide: Array[LockOnCandidate] = [wide]
	assert_int(LockOnTargeting.pick_best(only_wide, _config())).is_equal(-1)
	var visited: Dictionary[int, bool] = {1: true}
	assert_int(_cycle(cands, 1, visited, 1)).is_equal(2)


func test_cycle_skips_a_hidden_part_of_the_current_target() -> void:
	var cands: Array[LockOnCandidate] = _scene()
	cands[1].has_los = false # the head is behind a pillar
	var visited: Dictionary[int, bool] = {11: true}
	assert_int(_cycle(cands, 11, visited, 1)).is_equal(13) # tail, not the hidden head
	assert_int(_cycle(cands, 13, visited, 1)).is_equal(31) # then the next target


# --- camera framing --------------------------------------------------------------------

func test_pullback_grows_with_target_size_and_is_clamped() -> void:
	var c: LockOnConfig = _config()
	c.framing_base_size = 2.5
	c.pullback_per_meter = 0.8
	c.max_pullback = 6.0
	assert_float(c.pullback_for(2.2)).is_equal(0.0)
	assert_float(c.pullback_for(5.0)).is_equal_approx(2.0, 0.0001)
	assert_float(c.pullback_for(40.0)).is_equal(6.0)


func test_shipped_lock_on_tuning_is_consistent() -> void:
	var c: LockOnConfig = load("res://data/combat/lock_on.tres") as LockOnConfig
	assert_object(c).is_not_null()
	assert_float(c.break_range).is_greater(c.acquire_range)
	assert_float(c.flick_reset).is_less(c.flick_threshold)
	assert_float(c.cycle_max_angle_degrees).is_greater_equal(c.acquire_max_angle_degrees)
	assert_int(c.lost_sight_frames).is_greater(0)
