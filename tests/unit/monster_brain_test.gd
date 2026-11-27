extends GdUnitTestSuite
## A large monster's decision rules (scripts/combat/monster_brain.gd,
## monster_attack_entry.gd): which zone round its body the target is in (front / side /
## rear), and attack selection by zone, distance, cooldown, disabled attacks, repeat and
## weight. Plus checks on monster #1's real attack table in data/combat/monster01_ai.tres.

const AI: String = "res://data/combat/monster01_ai.tres"
const NEVER: int = MonsterAttackEntry.NEVER
const FRONT: MonsterBrain.Zone = MonsterBrain.Zone.FRONT
const SIDE: MonsterBrain.Zone = MonsterBrain.Zone.SIDE
const REAR: MonsterBrain.Zone = MonsterBrain.Zone.REAR


func _entry(id: StringName, front: bool, side: bool, rear: bool, min_range: float, max_range: float,
		cooldown: int = 100, weight: float = 1.0) -> MonsterAttackEntry:
	var a: AttackData = AttackData.new()
	a.id = id
	var e: MonsterAttackEntry = MonsterAttackEntry.new()
	e.attack = a
	e.from_front = front
	e.from_side = side
	e.from_rear = rear
	e.min_range = min_range
	e.max_range = max_range
	e.cooldown_frames = cooldown
	e.weight = weight
	return e


## swipe: front 0–8 · tail: side+rear 0–8 · stomp: all 0–6.5 · charge: front 8–13.
func _table() -> Array[MonsterAttackEntry]:
	var t: Array[MonsterAttackEntry] = [
		_entry(&"swipe", true, false, false, 0.0, 8.0, 150, 3.0),
		_entry(&"tail", false, true, true, 0.0, 8.0, 180, 2.0),
		_entry(&"stomp", true, true, true, 0.0, 6.5, 300, 1.5),
		_entry(&"charge", true, false, false, 8.0, 13.0, 360, 2.0),
	]
	return t


func _select(zone: MonsterBrain.Zone, distance: float, roll: float = 0.0, used: Dictionary[int, int] = {},
		blocked: Dictionary[StringName, bool] = {}, last: int = -1, avoid_repeat: bool = false,
		frame: int = 10000) -> int:
	return MonsterBrain.select_attack(_table(), zone, distance, frame, used, blocked, last, avoid_repeat, roll)


## Every row index select_attack can return for some roll (the test table if `entries` is
## empty).
func _possible(zone: MonsterBrain.Zone, distance: float, blocked: Dictionary[StringName, bool] = {},
		entries: Array[MonsterAttackEntry] = []) -> Dictionary[int, bool]:
	if entries.is_empty():
		entries = _table()
	var out: Dictionary[int, bool] = {}
	for i: int in 100:
		var pick: int = MonsterBrain.select_attack(entries, zone, distance, 10000, {}, blocked, -1, false, float(i) / 100.0)
		if pick >= 0:
			out[pick] = true
	return out


## The rows _possible returns, sorted.
func _rows(zone: MonsterBrain.Zone, distance: float, blocked: Dictionary[StringName, bool] = {},
		entries: Array[MonsterAttackEntry] = []) -> Array[int]:
	var keys: Array[int] = []
	keys.assign(_possible(zone, distance, blocked, entries).keys())
	keys.sort()
	return keys


# --- zones ------------------------------------------------------------------------------

func test_zone_in_front_beside_and_behind() -> void:
	var fwd: Vector3 = Vector3(0.0, 0.0, 1.0)
	assert_int(MonsterBrain.zone_of(fwd, Vector3(0.0, 0.0, 5.0), 40.0, 60.0)).is_equal(FRONT)
	assert_int(MonsterBrain.zone_of(fwd, Vector3(5.0, 0.0, 0.0), 40.0, 60.0)).is_equal(SIDE)
	assert_int(MonsterBrain.zone_of(fwd, Vector3(-5.0, 0.0, 0.0), 40.0, 60.0)).is_equal(SIDE)
	assert_int(MonsterBrain.zone_of(fwd, Vector3(0.0, 0.0, -5.0), 40.0, 60.0)).is_equal(REAR)


func test_zone_edges_are_inclusive() -> void:
	var fwd: Vector3 = Vector3(0.0, 0.0, 1.0)
	var at_40: Vector3 = Vector3(sin(deg_to_rad(40.0)), 0.0, cos(deg_to_rad(40.0))) * 6.0
	var at_41: Vector3 = Vector3(sin(deg_to_rad(41.0)), 0.0, cos(deg_to_rad(41.0))) * 6.0
	var at_120: Vector3 = Vector3(sin(deg_to_rad(120.0)), 0.0, cos(deg_to_rad(120.0))) * 6.0
	var at_119: Vector3 = Vector3(sin(deg_to_rad(119.0)), 0.0, cos(deg_to_rad(119.0))) * 6.0
	assert_int(MonsterBrain.zone_of(fwd, at_40, 40.0, 60.0)).is_equal(FRONT)
	assert_int(MonsterBrain.zone_of(fwd, at_41, 40.0, 60.0)).is_equal(SIDE)
	assert_int(MonsterBrain.zone_of(fwd, at_120, 40.0, 60.0)).is_equal(REAR)
	assert_int(MonsterBrain.zone_of(fwd, at_119, 40.0, 60.0)).is_equal(SIDE)


func test_zone_follows_the_facing_and_ignores_height() -> void:
	var fwd: Vector3 = Vector3(-1.0, 0.0, 0.0) # facing -X
	assert_int(MonsterBrain.zone_of(fwd, Vector3(-6.0, 5.0, 1.0), 40.0, 60.0)).is_equal(FRONT)
	assert_int(MonsterBrain.zone_of(fwd, Vector3(6.0, -2.0, 0.5), 40.0, 60.0)).is_equal(REAR)
	assert_int(MonsterBrain.zone_of(fwd, Vector3(0.5, 0.0, 6.0), 40.0, 60.0)).is_equal(SIDE)


func test_a_target_on_top_counts_as_front() -> void:
	assert_int(MonsterBrain.zone_of(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 3.0, 0.0), 40.0, 60.0)).is_equal(FRONT)


# --- selection by position -------------------------------------------------------------------

func test_close_in_front_swipe_or_stomp() -> void:
	assert_array(_rows(FRONT, 5.0)).is_equal([0, 2])


func test_far_in_front_only_the_charge() -> void:
	assert_array(_rows(FRONT, 10.0)).is_equal([3])
	assert_int(_select(FRONT, 14.0)).is_equal(-1) # too far for anything: it walks in


func test_beside_or_behind_tail_sweep_or_stomp() -> void:
	assert_array(_rows(SIDE, 5.0)).is_equal([1, 2])
	assert_array(_rows(REAR, 5.0)).is_equal([1, 2])
	assert_array(_rows(REAR, 7.5)).is_equal([1]) # out of stomp range
	assert_int(_select(REAR, 9.0)).is_equal(-1) # behind and far: nothing, it turns
	assert_int(_select(SIDE, 10.0)).is_equal(-1) # the charge is front only


func test_the_swipe_is_never_chosen_from_behind() -> void:
	for d: float in [0.5, 3.0, 6.0, 7.9]:
		assert_bool(_possible(REAR, d).has(0)).is_false()
		assert_bool(_possible(SIDE, d).has(0)).is_false()


func test_range_edges_are_inclusive() -> void:
	assert_bool(_possible(FRONT, 8.0).has(0)).is_true()
	assert_bool(_possible(FRONT, 8.0).has(3)).is_true()
	assert_bool(_possible(FRONT, 6.5).has(2)).is_true()
	assert_bool(_possible(FRONT, 6.51).has(2)).is_false()
	assert_bool(_possible(FRONT, 13.01).has(3)).is_false()


# --- cooldown, disabled, repeat, weight ------------------------------------------------------

func test_an_attack_on_cooldown_is_skipped() -> void:
	var used: Dictionary[int, int] = {0: 10000}
	assert_int(_select(FRONT, 5.0, 0.0, used, {}, -1, false, 10100)).is_equal(2) # swipe cooling: stomp
	assert_int(_select(FRONT, 5.0, 0.0, used, {}, -1, false, 10150)).is_equal(0) # exactly cooldown_frames later


func test_a_disabled_attack_is_never_chosen() -> void:
	var blocked: Dictionary[StringName, bool] = {&"swipe": true}
	assert_array(_rows(FRONT, 5.0, blocked)).is_equal([2])
	assert_int(_select(FRONT, 7.5, 0.0, {}, blocked)).is_equal(-1) # nothing else reaches


func test_avoid_repeat_drops_the_last_attack_when_another_is_valid() -> void:
	for roll: float in [0.0, 0.5, 0.99]:
		assert_int(_select(FRONT, 5.0, roll, {}, {}, 0, true)).is_equal(2)
	assert_int(_select(FRONT, 7.5, 0.0, {}, {}, 0, true)).is_equal(0) # the only valid one: repeat allowed


func test_roll_picks_by_weight_in_table_order() -> void:
	# swipe weight 3, stomp 1.5: swipe for rolls below 3 / 4.5.
	assert_int(_select(FRONT, 5.0, 0.0)).is_equal(0)
	assert_int(_select(FRONT, 5.0, 0.66)).is_equal(0)
	assert_int(_select(FRONT, 5.0, 0.67)).is_equal(2)
	assert_int(_select(FRONT, 5.0, 1.0)).is_equal(2)


func test_brain_cooldowns_and_reset() -> void:
	var c: LargeMonsterConfig = LargeMonsterConfig.new()
	c.attacks = _table()
	c.rng_seed = 99
	c.avoid_repeat = false
	var brain: MonsterBrain = MonsterBrain.new(c)
	var first: int = brain.pick_attack(FRONT, 7.5, 10000, {})
	assert_int(first).is_equal(0)
	brain.note_attack(first, 10000)
	assert_int(brain.pick_attack(FRONT, 7.5, 10010, {})).is_equal(-1)
	brain.reset()
	assert_int(brain.pick_attack(FRONT, 7.5, 10010, {})).is_equal(0)
	assert_int(brain.roll_think_frames()).is_between(c.think_frames_min, c.think_frames_max)


# --- monster #1's real table ------------------------------------------------------------------

func _real() -> LargeMonsterConfig:
	return load(AI) as LargeMonsterConfig


func _index_of(cfg: LargeMonsterConfig, id: StringName) -> int:
	for i: int in cfg.attacks.size():
		if cfg.attacks[i].attack.id == id:
			return i
	return -1


func test_monster01_has_its_four_attacks() -> void:
	var cfg: LargeMonsterConfig = _real()
	assert_int(cfg.attacks.size()).is_equal(4)
	for id: StringName in [&"monster01_front_swipe", &"monster01_tail_sweep", &"monster01_stomp", &"monster01_charge"]:
		assert_int(_index_of(cfg, id)).override_failure_message("missing %s" % id).is_greater_equal(0)


func test_monster01_attack_types() -> void:
	var cfg: LargeMonsterConfig = _real()
	var sweep: AttackData = cfg.attacks[_index_of(cfg, &"monster01_tail_sweep")].attack
	var stomp: AttackData = cfg.attacks[_index_of(cfg, &"monster01_stomp")].attack
	var charge: AttackData = cfg.attacks[_index_of(cfg, &"monster01_charge")].attack
	var swipe: AttackData = cfg.attacks[_index_of(cfg, &"monster01_front_swipe")].attack
	assert_int(sweep.perilous).is_equal(AttackData.Perilous.SWEEP)
	assert_bool(sweep.misses_airborne).is_true()
	assert_bool(stomp.blockable or stomp.deflectable).is_false() # unblockable area attack
	assert_int(charge.perilous).is_equal(AttackData.Perilous.THRUST)
	assert_bool(charge.blockable).is_false()
	assert_bool(charge.deflectable).is_true()
	assert_float(charge.lunge_distance).is_greater(3.0)
	assert_bool(swipe.blockable and swipe.deflectable).is_true()


## Readable tells and long recoveries: every wind-up ≥ 40 frames, every recovery ≥ 60, and
## every perilous / unblockable attack has its own tell colour.
func test_monster01_tells_and_recoveries() -> void:
	var colors: Dictionary[String, StringName] = {}
	for e: MonsterAttackEntry in _real().attacks:
		assert_int(e.attack.startup_frames).is_greater_equal(40)
		assert_int(e.attack.recovery_frames).is_greater_equal(60)
		var key: String = e.attack.tell_color.to_html(false)
		assert_bool(colors.has(key)).override_failure_message("%s shares a tell colour with %s" % [e.attack.id, colors.get(key, &"")]).is_false()
		colors[key] = e.attack.id


func test_monster01_choice_by_position() -> void:
	var cfg: LargeMonsterConfig = _real()
	var swipe: int = _index_of(cfg, &"monster01_front_swipe")
	var sweep: int = _index_of(cfg, &"monster01_tail_sweep")
	var stomp: int = _index_of(cfg, &"monster01_stomp")
	var charge: int = _index_of(cfg, &"monster01_charge")
	var close_front: Dictionary[int, bool] = _possible(FRONT, 6.0, {}, cfg.attacks)
	assert_bool(close_front.has(swipe) and not close_front.has(sweep) and not close_front.has(charge)).is_true()
	var close_rear: Dictionary[int, bool] = _possible(REAR, 6.0, {}, cfg.attacks)
	assert_bool(close_rear.has(sweep) and not close_rear.has(swipe) and not close_rear.has(charge)).is_true()
	assert_bool(_possible(SIDE, 4.0, {}, cfg.attacks).has(stomp)).is_true()
	assert_array(_rows(FRONT, 11.0, {}, cfg.attacks)).is_equal([charge])


## Close in (up to 8 m) it always has an answer wherever she stands, and in front it can
## reach her out to the charge's range — so it never just stares at her.
func test_monster01_always_has_an_attack_close_in() -> void:
	var cfg: LargeMonsterConfig = _real()
	for zone: MonsterBrain.Zone in [FRONT, SIDE, REAR]:
		var d: float = 0.5
		while d <= 8.0:
			assert_bool(_possible(zone, d, {}, cfg.attacks).is_empty()) \
					.override_failure_message("no attack at %.1f m in zone %d" % [d, zone]).is_false()
			d += 0.5
	var far: float = 8.0
	while far <= 13.0:
		assert_bool(_possible(FRONT, far, {}, cfg.attacks).is_empty()).is_false()
		far += 0.5


## The hit box of each attack covers the far edge of its range in each zone it is chosen
## from (in its own frame: +Z forward), so it never picks an attack that can't reach her.
func test_monster01_hit_boxes_reach_their_range() -> void:
	var cfg: LargeMonsterConfig = _real()
	for e: MonsterAttackEntry in cfg.attacks:
		var directions: Array[float] = []
		if e.from_front:
			directions.append_array([0.0, cfg.front_half_angle_degrees, -cfg.front_half_angle_degrees])
		if e.from_side:
			directions.append_array([90.0, -90.0])
		if e.from_rear:
			directions.append(180.0)
		var reach: float = e.max_range - 0.4 # her hurtbox has ~0.45 m of thickness
		var travel: float = e.attack.lunge_distance
		# Front attacks turn toward her during the wind-up.
		var turned: float = cfg.startup_turn_speed_degrees * float(e.attack.startup_frames) / 60.0 if e.tracks_target else 0.0
		for raw: float in directions:
			var deg: float = signf(raw) * maxf(absf(raw) - turned, 0.0) if absf(raw) < 179.0 else raw
			var p: Vector3 = Vector3(sin(deg_to_rad(deg)), 0.0, cos(deg_to_rad(deg))) * reach
			var half: Vector3 = e.hit_size * 0.5
			var lo: Vector3 = e.hit_center - half
			var hi: Vector3 = e.hit_center + half + Vector3(0.0, 0.0, travel)
			var inside: bool = p.x >= lo.x and p.x <= hi.x and p.z >= lo.z and p.z <= hi.z and lo.y <= 1.0 and hi.y >= 0.2
			assert_bool(inside).override_failure_message("%s doesn't reach %.1f m at %.0f°" % [e.attack.id, reach, deg]).is_true()
