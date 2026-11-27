class_name MonsterBrain
extends RefCounted
## A large monster's decisions, as pure logic (no scene): which zone round its body the
## target is in, and which attack to use for that zone and distance. Rules are static
## functions taking explicit rolls so tests/unit/monster_brain_test.gd can check them
## exactly; the instance keeps the state (cooldowns, last attack) and rolls its own
## RandomNumberGenerator.

enum Zone { FRONT, SIDE, REAR }

const NEVER: int = MonsterAttackEntry.NEVER

var config: LargeMonsterConfig
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Combat frame each attack-table row was last started on, by index.
var last_used: Dictionary[int, int] = {}
## Index of the last attack started, or -1.
var last_index: int = -1


func _init(p_config: LargeMonsterConfig) -> void:
	assert(p_config != null, "MonsterBrain needs a LargeMonsterConfig")
	config = p_config
	if config.rng_seed != 0:
		rng.seed = config.rng_seed
	else:
		rng.randomize()


# --- rules (static, pure) ---------------------------------------------------------------

## Where `offset` (target minus monster) lies round a body facing `forward`, on the ground
## plane: FRONT within front_half_angle of the facing (inclusive), REAR within
## rear_half_angle of straight behind (inclusive), SIDE otherwise. A target right on top of
## it counts as FRONT.
static func zone_of(forward: Vector3, offset: Vector3, front_half_angle_degrees: float,
		rear_half_angle_degrees: float) -> Zone:
	var f: Vector2 = Vector2(forward.x, forward.z)
	var o: Vector2 = Vector2(offset.x, offset.z)
	if f.length_squared() < 0.000001 or o.length_squared() < 0.000001:
		return Zone.FRONT
	var angle: float = rad_to_deg(absf(f.angle_to(o)))
	if angle <= front_half_angle_degrees + 0.0001:
		return Zone.FRONT
	if angle >= 180.0 - rear_half_angle_degrees - 0.0001:
		return Zone.REAR
	return Zone.SIDE


## The row to use with the target in `zone` at `distance` on `frame`, or -1 if none is
## valid. Valid rows cover the zone, are in range (inclusive) and off cooldown
## (MonsterAttackEntry.is_available), and their attack id is not in `blocked` (disabled by
## a broken part). With `avoid_repeat` and more than one valid row, `last` is dropped. Then
## `roll` (0 ≤ roll < 1) picks by weight, in table order.
static func select_attack(entries: Array[MonsterAttackEntry], zone: Zone, distance: float, frame: int,
		used: Dictionary[int, int], blocked: Dictionary[StringName, bool], last: int,
		avoid_repeat: bool, roll: float) -> int:
	var valid: Array[int] = []
	for i: int in entries.size():
		var e: MonsterAttackEntry = entries[i]
		if e == null or not e.is_available(zone, distance, frame, used.get(i, NEVER) as int):
			continue
		if blocked.has(e.attack.id):
			continue
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


# --- stateful helpers ---------------------------------------------------------------------

func zone_for(forward: Vector3, offset: Vector3) -> Zone:
	return zone_of(forward, offset, config.front_half_angle_degrees, config.rear_half_angle_degrees)


## Picks the attack to use now (rolling the RNG), or -1.
func pick_attack(zone: Zone, distance: float, frame: int, blocked: Dictionary[StringName, bool]) -> int:
	return select_attack(config.attacks, zone, distance, frame, last_used, blocked, last_index,
			config.avoid_repeat, rng.randf())


## Records that row `index` started on `frame` (starts its cooldown).
func note_attack(index: int, frame: int) -> void:
	last_used[index] = frame
	last_index = index


## Frames to wait before the next attack try.
func roll_think_frames() -> int:
	return rng.randi_range(mini(config.think_frames_min, config.think_frames_max),
			maxi(config.think_frames_min, config.think_frames_max))


## Forgets cooldowns and the last attack (on revive).
func reset() -> void:
	last_used.clear()
	last_index = -1
