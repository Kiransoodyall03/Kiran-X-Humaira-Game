class_name DuelistBrain
extends RefCounted
## The duelist's decisions, as pure logic (no scene): which attack to use at a given
## distance, how close to get, whether to guard a swing, when a hit makes it flinch.
## Rules are static functions taking explicit rolls so tests/unit/duelist_brain_test.gd
## can check them exactly; the instance keeps the state (cooldowns, last attack, flinch
## build-up) and rolls its own RandomNumberGenerator.

enum Defense { NONE, BLOCK, PARRY }

const NEVER: int = DuelistAttackEntry.NEVER

var config: DuelistConfig
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Combat frame each attack-table row was last started on, by index.
var last_used: Dictionary[int, int] = {}
## Index of the last attack started, or -1.
var last_index: int = -1
var _flinch_build_up: float = 0.0
var _last_hit_frame: int = NEVER


func _init(p_config: DuelistConfig) -> void:
	assert(p_config != null, "DuelistBrain needs a DuelistConfig")
	config = p_config
	if config.rng_seed != 0:
		rng.seed = config.rng_seed
	else:
		rng.randomize()


# --- rules (static, pure) ---------------------------------------------------------------

## The row to use at `distance` on `frame`, or -1 if none is valid. Valid rows are in
## range and off cooldown (DuelistAttackEntry.is_available). With `avoid_repeat` and more
## than one valid row, `last` is dropped. Then `roll` (0 ≤ roll < 1) picks by weight, in
## table order.
static func select_attack(entries: Array[DuelistAttackEntry], distance: float, frame: int,
		used: Dictionary[int, int], last: int, avoid_repeat: bool, roll: float) -> int:
	var valid: Array[int] = []
	for i: int in entries.size():
		if entries[i] != null and entries[i].is_available(distance, frame, used.get(i, NEVER) as int):
			valid.append(i)
	if avoid_repeat and valid.size() > 1 and valid.has(last):
		valid.erase(last)
	if valid.is_empty():
		return -1
	var total: float = 0.0
	for i: int in valid:
		total += entries[i].weight
	var pick: float = clampf(roll, 0.0, 1.0) * total
	for i: int in valid:
		pick -= entries[i].weight
		if pick < 0.0:
			return i
	return valid[valid.size() - 1]


## The row it decides to go for when it stops circling, or -1 if every row is cooling
## down. Like select_attack but ignoring distance (rows off cooldown with an attack and a
## weight > 0), so a short-range row gets picked by weight even from the circling band,
## and it then walks in to that row's range (APPROACH). `avoid_repeat` drops `last` when
## another row is ready; `roll` (0 ≤ roll < 1) picks by weight, in table order.
static func plan_attack(entries: Array[DuelistAttackEntry], frame: int, used: Dictionary[int, int],
		last: int, avoid_repeat: bool, roll: float) -> int:
	var ready: Array[int] = []
	for i: int in entries.size():
		var e: DuelistAttackEntry = entries[i]
		if e != null and e.attack != null and e.weight > 0.0 and e.is_off_cooldown(frame, used.get(i, NEVER) as int):
			ready.append(i)
	if avoid_repeat and ready.size() > 1 and ready.has(last):
		ready.erase(last)
	if ready.is_empty():
		return -1
	var total: float = 0.0
	for i: int in ready:
		total += entries[i].weight
	var pick: float = clampf(roll, 0.0, 1.0) * total
	for i: int in ready:
		pick -= entries[i].weight
		if pick < 0.0:
			return i
	return ready[ready.size() - 1]


## How close it wants to get to attack: the largest max_range among rows off cooldown
## (-1 if all are cooling down). Further than this it walks in.
static func approach_range(entries: Array[DuelistAttackEntry], frame: int, used: Dictionary[int, int]) -> float:
	var best: float = -1.0
	for i: int in entries.size():
		var e: DuelistAttackEntry = entries[i]
		if e != null and e.attack != null and e.weight > 0.0 and e.is_off_cooldown(frame, used.get(i, NEVER) as int):
			best = maxf(best, e.max_range)
	return best


## How it answers a swing, from one roll (0 ≤ roll < 1): PARRY below parry_chance, BLOCK
## below parry_chance + block_chance, otherwise NONE.
static func choose_defense(roll: float, parry_chance: float, block_chance: float) -> Defense:
	if roll < parry_chance:
		return Defense.PARRY
	if roll < parry_chance + block_chance:
		return Defense.BLOCK
	return Defense.NONE


## Combat frame on which to press guard to parry a swing that started on `swing_frame`
## (her press frame = swing frame 1, so the first active frame is swing_frame + startup).
## Never earlier than `swing_frame`.
static func parry_press_frame(swing_frame: int, startup_frames: int, lead_frames: int) -> int:
	return maxi(swing_frame, swing_frame + startup_frames - lead_frames)


# --- stateful helpers ---------------------------------------------------------------------

## Picks the attack to use now (rolling the RNG), or -1.
func pick_attack(distance: float, frame: int) -> int:
	return select_attack(config.attacks, distance, frame, last_used, last_index, config.avoid_repeat, rng.randf())


## Rolls the row to go for next (plan_attack), or -1.
func plan_next_attack(frame: int) -> int:
	return plan_attack(config.attacks, frame, last_used, last_index, config.avoid_repeat, rng.randf())


func distance_to_attack(frame: int) -> float:
	return approach_range(config.attacks, frame, last_used)


## Records that row `index` started on `frame` (starts its cooldown).
func note_attack(index: int, frame: int) -> void:
	last_used[index] = frame
	last_index = index


func roll_defense() -> Defense:
	return choose_defense(rng.randf(), config.parry_chance, config.block_chance)


## Frames to circle before the next attack try.
func roll_circle_frames() -> int:
	return rng.randi_range(mini(config.circle_frames_min, config.circle_frames_max),
			maxi(config.circle_frames_min, config.circle_frames_max))


## -1 or +1: which way to strafe.
func roll_strafe_sign() -> float:
	return -1.0 if rng.randf() < 0.5 else 1.0


## An unguarded hit dealt `posture_damage` on `frame`. Returns true when the build-up
## reaches flinch_posture_threshold (it then starts again from 0). Build-up older than
## flinch_memory_frames is forgotten first.
func add_hit(posture_damage: float, frame: int) -> bool:
	if frame - _last_hit_frame > config.flinch_memory_frames:
		_flinch_build_up = 0.0
	_last_hit_frame = frame
	_flinch_build_up += maxf(posture_damage, 0.0)
	if _flinch_build_up >= config.flinch_posture_threshold and config.flinch_posture_threshold > 0.0:
		_flinch_build_up = 0.0
		return true
	return false


func flinch_build_up() -> float:
	return _flinch_build_up


## Forgets cooldowns, the last attack and flinch build-up (on revive).
func reset() -> void:
	last_used.clear()
	last_index = -1
	_flinch_build_up = 0.0
	_last_hit_frame = NEVER
