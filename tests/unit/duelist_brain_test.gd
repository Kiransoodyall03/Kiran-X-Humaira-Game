extends GdUnitTestSuite
## The duelist's decision rules (scripts/combat/duelist_brain.gd, duelist_attack_entry.gd):
## attack selection by distance, cooldown, repeat and weight; how close it walks in; guard
## rolls and parry timing; flinch build-up. Plus sanity checks on the real attack table in
## data/combat/duelist_ai.tres.

const AI: String = "res://data/combat/duelist_ai.tres"
const NEVER: int = DuelistAttackEntry.NEVER


func _attack(id: StringName) -> AttackData:
	var a: AttackData = AttackData.new()
	a.id = id
	return a


func _entry(id: StringName, min_range: float, max_range: float, cooldown: int, weight: float = 1.0) -> DuelistAttackEntry:
	var e: DuelistAttackEntry = DuelistAttackEntry.new()
	e.attack = _attack(id)
	e.min_range = min_range
	e.max_range = max_range
	e.cooldown_frames = cooldown
	e.weight = weight
	return e


## slash 0–2.5 (cd 60, w 3), overhead 1–3 (cd 120, w 2), thrust 2.5–4.5 (cd 300, w 1).
func _table() -> Array[DuelistAttackEntry]:
	var t: Array[DuelistAttackEntry] = [
		_entry(&"slash", 0.0, 2.5, 60, 3.0),
		_entry(&"overhead", 1.0, 3.0, 120, 2.0),
		_entry(&"thrust", 2.5, 4.5, 300, 1.0),
	]
	return t


func _select(distance: float, frame: int = 1000, used: Dictionary[int, int] = {}, last: int = -1,
		avoid_repeat: bool = false, roll: float = 0.0) -> int:
	return DuelistBrain.select_attack(_table(), distance, frame, used, last, avoid_repeat, roll)


func _config() -> DuelistConfig:
	var c: DuelistConfig = DuelistConfig.new()
	c.attacks = _table()
	c.rng_seed = 1234
	c.flinch_posture_threshold = 15.0
	c.flinch_memory_frames = 90
	return c


# --- distance ---------------------------------------------------------------------------

func test_only_attacks_in_range_are_chosen() -> void:
	assert_int(_select(0.5)).is_equal(0) # only the slash reaches this close
	assert_int(_select(3.5)).is_equal(2) # only the thrust reaches this far
	assert_int(_select(5.0)).is_equal(-1) # nothing reaches


func test_min_range_keeps_the_thrust_out_of_close_range() -> void:
	for roll: float in [0.0, 0.5, 0.99]:
		assert_int(_select(2.0, 1000, {}, -1, false, roll)).is_not_equal(2)
	assert_int(_select(0.9, 1000, {}, -1, false, 0.99)).is_equal(0) # overhead min is 1.0


func test_range_edges_are_inclusive() -> void:
	assert_int(_select(4.5)).is_equal(2)
	assert_int(_select(4.51)).is_equal(-1)
	assert_int(_select(2.5, 1000, {}, -1, false, 0.99)).is_equal(2) # slash, overhead, thrust all valid: last by weight


# --- cooldown ---------------------------------------------------------------------------

func test_an_attack_on_cooldown_is_skipped() -> void:
	var used: Dictionary[int, int] = {0: 1000}
	assert_int(_select(0.5, 1030, used)).is_equal(-1) # slash cooling down, nothing else reaches
	assert_int(_select(2.0, 1030, used)).is_equal(1) # the overhead is picked instead


func test_cooldown_ends_exactly_after_cooldown_frames() -> void:
	var used: Dictionary[int, int] = {0: 1000}
	assert_int(_select(0.5, 1059, used)).is_equal(-1)
	assert_int(_select(0.5, 1060, used)).is_equal(0)


func test_never_used_attacks_are_off_cooldown_from_frame_zero() -> void:
	assert_int(_select(0.5, 0)).is_equal(0)


# --- repeat and weight ------------------------------------------------------------------

func test_avoid_repeat_drops_the_last_attack_when_another_is_valid() -> void:
	for roll: float in [0.0, 0.5, 0.99]:
		assert_int(_select(2.0, 1000, {}, 0, true, roll)).is_equal(1)


func test_avoid_repeat_still_repeats_when_it_is_the_only_option() -> void:
	assert_int(_select(0.5, 1000, {}, 0, true, 0.5)).is_equal(0)


func test_without_avoid_repeat_the_last_attack_can_come_again() -> void:
	assert_int(_select(2.0, 1000, {}, 0, false, 0.0)).is_equal(0)


func test_roll_picks_by_weight_in_table_order() -> void:
	# At 2.0 m: slash (w 3) and overhead (w 2) → slash for roll < 0.6, overhead above.
	assert_int(_select(2.0, 1000, {}, -1, false, 0.0)).is_equal(0)
	assert_int(_select(2.0, 1000, {}, -1, false, 0.59)).is_equal(0)
	assert_int(_select(2.0, 1000, {}, -1, false, 0.61)).is_equal(1)
	assert_int(_select(2.0, 1000, {}, -1, false, 1.0)).is_equal(1)


func test_zero_weight_or_missing_attack_is_never_chosen() -> void:
	var t: Array[DuelistAttackEntry] = _table()
	t[0].weight = 0.0
	assert_int(DuelistBrain.select_attack(t, 0.5, 1000, {}, -1, false, 0.0)).is_equal(-1)
	t[0].weight = 1.0
	t[0].attack = null
	assert_int(DuelistBrain.select_attack(t, 0.5, 1000, {}, -1, false, 0.0)).is_equal(-1)


func test_weighted_rolls_spread_roughly_by_weight() -> void:
	var brain: DuelistBrain = DuelistBrain.new(_config())
	var counts: Array[int] = [0, 0, 0]
	for i: int in 2000:
		counts[brain.pick_attack(2.0, 1000)] += 1 # never noted, so no cooldown or repeat
	assert_int(counts[2]).is_equal(0)
	assert_float(float(counts[0]) / 2000.0).is_between(0.53, 0.67) # 3 / (3 + 2) = 0.6


# --- approach distance -----------------------------------------------------------------

func test_approach_range_is_the_longest_reach_off_cooldown() -> void:
	assert_float(DuelistBrain.approach_range(_table(), 1000, {})).is_equal(4.5)
	var used: Dictionary[int, int] = {2: 900}
	assert_float(DuelistBrain.approach_range(_table(), 1000, used)).is_equal(3.0)
	used = {0: 990, 1: 990, 2: 990}
	assert_float(DuelistBrain.approach_range(_table(), 1000, used)).is_equal(-1.0)


# --- planning (what it walks in for when it stops circling) ---------------------------

func test_plan_ignores_distance_and_picks_by_weight() -> void:
	# Weights 3 / 2 / 1 of 6: slash below 0.5, overhead below 0.833, thrust above.
	assert_int(DuelistBrain.plan_attack(_table(), 1000, {}, -1, false, 0.0)).is_equal(0)
	assert_int(DuelistBrain.plan_attack(_table(), 1000, {}, -1, false, 0.49)).is_equal(0)
	assert_int(DuelistBrain.plan_attack(_table(), 1000, {}, -1, false, 0.6)).is_equal(1)
	assert_int(DuelistBrain.plan_attack(_table(), 1000, {}, -1, false, 0.9)).is_equal(2)


func test_plan_skips_rows_cooling_down_and_repeats() -> void:
	var used: Dictionary[int, int] = {0: 990}
	assert_int(DuelistBrain.plan_attack(_table(), 1000, used, -1, false, 0.0)).is_equal(1)
	assert_int(DuelistBrain.plan_attack(_table(), 1000, {}, 0, true, 0.0)).is_equal(1)
	assert_int(DuelistBrain.plan_attack(_table(), 1000, {}, 0, false, 0.0)).is_equal(0)
	used = {0: 990, 1: 990, 2: 990}
	assert_int(DuelistBrain.plan_attack(_table(), 1000, used, -1, false, 0.5)).is_equal(-1)
	used = {0: 990, 1: 990}
	assert_int(DuelistBrain.plan_attack(_table(), 1000, used, 2, true, 0.0)).is_equal(2) # only one ready: repeat allowed


func test_real_table_every_row_is_planned_and_reachable_from_circling() -> void:
	# Circle -> plan -> attack, over and over with cooldowns: every row of the real table
	# gets used, and each row's range can be reached by walking in from the circling band.
	var c: DuelistConfig = (_real().duplicate() as DuelistConfig)
	c.rng_seed = 99
	var brain: DuelistBrain = DuelistBrain.new(c)
	var counts: Array[int] = [0, 0, 0]
	var frame: int = 0
	for i: int in 300:
		frame += c.circle_frames_min + 60 # circling + wind-up + recovery
		var index: int = brain.plan_next_attack(frame)
		if index >= 0:
			brain.note_attack(index, frame)
			counts[index] += 1
	for i: int in c.attacks.size():
		assert_int(counts[i]).override_failure_message("row %d never planned (%s)" % [i, counts]).is_greater(10)
		assert_float(c.attacks[i].min_range).is_less(c.circle_max_distance)


func test_note_attack_starts_the_cooldown_and_sets_last() -> void:
	var brain: DuelistBrain = DuelistBrain.new(_config())
	brain.note_attack(2, 500)
	assert_int(brain.last_index).is_equal(2)
	assert_float(brain.distance_to_attack(600)).is_equal(3.0) # thrust cooling down
	assert_int(brain.pick_attack(3.5, 600)).is_equal(-1)
	assert_int(brain.pick_attack(3.5, 800)).is_equal(2)
	brain.reset()
	assert_int(brain.last_index).is_equal(-1)
	assert_int(brain.pick_attack(3.5, 501)).is_equal(2)


# --- guard ------------------------------------------------------------------------------

func test_defense_roll_parry_first_then_block_then_none() -> void:
	assert_int(DuelistBrain.choose_defense(0.0, 0.25, 0.35)).is_equal(DuelistBrain.Defense.PARRY)
	assert_int(DuelistBrain.choose_defense(0.249, 0.25, 0.35)).is_equal(DuelistBrain.Defense.PARRY)
	assert_int(DuelistBrain.choose_defense(0.25, 0.25, 0.35)).is_equal(DuelistBrain.Defense.BLOCK)
	assert_int(DuelistBrain.choose_defense(0.599, 0.25, 0.35)).is_equal(DuelistBrain.Defense.BLOCK)
	assert_int(DuelistBrain.choose_defense(0.6, 0.25, 0.35)).is_equal(DuelistBrain.Defense.NONE)


func test_zero_chances_never_defend_and_full_parry_always_parries() -> void:
	for roll: float in [0.0, 0.5, 0.999]:
		assert_int(DuelistBrain.choose_defense(roll, 0.0, 0.0)).is_equal(DuelistBrain.Defense.NONE)
		assert_int(DuelistBrain.choose_defense(roll, 1.0, 0.0)).is_equal(DuelistBrain.Defense.PARRY)
		assert_int(DuelistBrain.choose_defense(roll, 0.0, 1.0)).is_equal(DuelistBrain.Defense.BLOCK)


func test_parry_press_lands_inside_the_parry_window() -> void:
	# Swing starts on frame 100 with 18 startup frames: first active frame 118.
	var press: int = DuelistBrain.parry_press_frame(100, 18, 5)
	assert_int(press).is_equal(113)
	var guard_config: GuardConfig = GuardConfig.new()
	guard_config.parry_window_frames = 12
	var guard: Guard = Guard.new(guard_config)
	guard.press(press)
	assert_bool(guard.is_parry_active(118)).is_true()
	# A wind-up shorter than the lead presses at once, never before the swing.
	assert_int(DuelistBrain.parry_press_frame(100, 3, 5)).is_equal(100)


# --- flinch -----------------------------------------------------------------------------

func test_flinch_when_hit_posture_reaches_the_threshold() -> void:
	var brain: DuelistBrain = DuelistBrain.new(_config())
	assert_bool(brain.add_hit(5.0, 100)).is_false()
	assert_bool(brain.add_hit(5.0, 110)).is_false()
	assert_bool(brain.add_hit(5.0, 120)).is_true()
	assert_float(brain.flinch_build_up()).is_equal(0.0) # starts over after a flinch
	assert_bool(brain.add_hit(15.0, 130)).is_true() # one heavy hit is enough


func test_flinch_build_up_is_forgotten_after_the_memory_window() -> void:
	var brain: DuelistBrain = DuelistBrain.new(_config())
	assert_bool(brain.add_hit(10.0, 100)).is_false()
	assert_bool(brain.add_hit(10.0, 191)).is_false() # 91 frames later: the first hit is forgotten
	assert_float(brain.flinch_build_up()).is_equal(10.0)
	assert_bool(brain.add_hit(5.0, 281)).is_true() # exactly 90 frames later: still remembered (10 + 5)


func test_zero_threshold_never_flinches() -> void:
	var c: DuelistConfig = _config()
	c.flinch_posture_threshold = 0.0
	var brain: DuelistBrain = DuelistBrain.new(c)
	assert_bool(brain.add_hit(50.0, 100)).is_false()


# --- the real attack table --------------------------------------------------------------

func _real() -> DuelistConfig:
	return load(AI) as DuelistConfig


func test_real_table_has_three_telegraphed_attacks() -> void:
	var c: DuelistConfig = _real()
	assert_object(c).is_not_null()
	assert_int(c.attacks.size()).is_equal(3)
	var ids: Dictionary[StringName, bool] = {}
	var perilous: int = 0
	for e: DuelistAttackEntry in c.attacks:
		assert_object(e.attack).is_not_null()
		assert_str(String(e.attack.id)).starts_with("duelist_")
		assert_str(e.attack.resource_path).starts_with("res://data/attacks/duelist_")
		ids[e.attack.id] = true
		assert_int(e.attack.startup_frames).is_greater_equal(15) # readable wind-up
		assert_int(e.attack.recovery_frames).is_greater_equal(20) # a punish window
		assert_float(e.max_range).is_greater_equal(e.min_range)
		assert_float(e.max_range).is_less_equal(e.attack.reach + e.attack.lunge_distance)
		assert_float(e.weight).is_greater(0.0)
		if e.attack.perilous != AttackData.Perilous.NONE:
			perilous += 1
			assert_bool(e.attack.tell_color.is_equal_approx(Color(1.0, 0.75, 0.3))).is_false()
	assert_int(ids.size()).is_equal(3)
	assert_int(perilous).is_greater_equal(1)


func test_real_table_tells_are_distinct_colours() -> void:
	var c: DuelistConfig = _real()
	for i: int in c.attacks.size():
		for j: int in range(i + 1, c.attacks.size()):
			assert_bool(c.attacks[i].attack.tell_color.is_equal_approx(c.attacks[j].attack.tell_color)).is_false()


func test_real_table_covers_every_distance_it_circles_at() -> void:
	# Fresh (no cooldowns), from point blank out to the far edge of circling, some attack
	# is always valid — no dead zone where it would stand and stare.
	var c: DuelistConfig = _real()
	var d: float = 0.0
	while d <= c.circle_max_distance:
		assert_int(DuelistBrain.select_attack(c.attacks, d, 0, {}, -1, c.avoid_repeat, 0.5)).override_failure_message(
				"no attack valid at %.2f m" % d).is_not_equal(-1)
		d += 0.1


func test_real_spacing_and_guard_odds_are_sane() -> void:
	var c: DuelistConfig = _real()
	assert_float(c.circle_min_distance).is_less(c.circle_max_distance)
	assert_float(c.aggro_radius).is_less_equal(c.leash_radius)
	assert_float(c.parry_chance + c.block_chance).is_less_equal(1.0)
	var guard: GuardConfig = (load("res://data/combat/duelist_combatant.tres") as CombatantConfig).guard
	assert_int(c.parry_lead_frames).is_less(guard.parry_window_frames)
	var cc: CombatantConfig = load("res://data/combat/duelist_combatant.tres") as CombatantConfig
	assert_int(cc.lives).is_equal(1)
	assert_bool(cc.can_be_deathblown).is_true()
