class_name LockOnTargeting
extends RefCounted
## Pure lock-on rules (unit tested in tests/unit/lock_on_targeting_test.gd): which point
## the lock_on button picks, and which point cycling switches to.
##
## Pick: among points in front of the camera, within acquire range and angle, with line of
## sight, the lowest score wins. Score = screen_weight × (angle / max angle)
## + distance_weight × (distance / range) − priority_weight × priority. So "nearest to the
## screen centre" dominates, distance and part priority break near-ties.
##
## Cycle (direction +1 = next / right, −1 = previous / left): first the other parts of the
## current target not yet visited since landing on it, nearest on screen in that direction
## (wrapping round). When every part has been visited, the next other target in that
## direction (landing on its best-scoring part). With no other target, round its own parts
## again.

const _WRAP: float = 1.0e6
const _EPS: float = 0.0001


## Can be picked by the lock_on button.
static func is_acquirable(c: LockOnCandidate, config: LockOnConfig) -> bool:
	return c.alive and c.has_los and c.in_front and c.distance <= config.acquire_range \
			and c.view_angle() <= deg_to_rad(config.acquire_max_angle_degrees)


## Another target can be cycled to (a wider angle than the first pick).
static func is_cyclable_target(c: LockOnCandidate, config: LockOnConfig) -> bool:
	return c.alive and c.has_los and c.in_front and c.distance <= config.acquire_range \
			and c.view_angle() <= deg_to_rad(config.cycle_max_angle_degrees)


## Another part of the current target can be cycled to: it only needs to be in break range
## and in sight (a big monster's tail may be off screen).
static func is_cyclable_part(c: LockOnCandidate, config: LockOnConfig) -> bool:
	return c.alive and c.has_los and c.distance <= config.break_range


## Lower is better.
static func score(c: LockOnCandidate, config: LockOnConfig) -> float:
	var max_angle: float = maxf(deg_to_rad(config.acquire_max_angle_degrees), _EPS)
	var angle_term: float = c.view_angle() / max_angle
	var distance_term: float = c.distance / maxf(config.acquire_range, _EPS)
	return config.screen_weight * angle_term + config.distance_weight * distance_term \
			- config.priority_weight * float(c.priority)


## Index of the point the lock_on button picks, or -1 if none is acquirable.
static func pick_best(candidates: Array[LockOnCandidate], config: LockOnConfig) -> int:
	var best: int = -1
	var best_score: float = INF
	for i: int in candidates.size():
		var c: LockOnCandidate = candidates[i]
		if not is_acquirable(c, config):
			continue
		var s: float = score(c, config)
		if best == -1 or s < best_score - _EPS or (absf(s - best_score) <= _EPS and c.key < candidates[best].key):
			best = i
			best_score = s
	return best


## Index of the point to switch to from the point with key `current_key`, or -1 if there
## is nothing else. `visited` holds the keys of the current target's parts already locked
## since landing on it (the caller keeps it; it should contain current_key). If the current
## point is not among the candidates, this is pick_best.
static func next_index(candidates: Array[LockOnCandidate], current_key: int,
		visited: Dictionary[int, bool], direction: int, config: LockOnConfig) -> int:
	var current: int = index_of_key(candidates, current_key)
	if current == -1:
		return pick_best(candidates, config)
	var cur: LockOnCandidate = candidates[current]
	var dir: int = 1 if direction >= 0 else -1

	# 1. Unvisited parts of the same target.
	var parts: Array[int] = []
	var all_parts: Array[int] = []
	for i: int in candidates.size():
		var c: LockOnCandidate = candidates[i]
		if i == current or c.target_key != cur.target_key or not is_cyclable_part(c, config):
			continue
		all_parts.append(i)
		if not visited.has(c.key):
			parts.append(i)
	if not parts.is_empty():
		return _pick_in_direction(candidates, parts, cur, dir)

	# 2. Other targets: each represented by its best-scoring part.
	var reps: Dictionary[int, int] = {}
	for i: int in candidates.size():
		var c: LockOnCandidate = candidates[i]
		if c.target_key == cur.target_key or not is_cyclable_target(c, config):
			continue
		if not reps.has(c.target_key) or _better_part(c, candidates[reps[c.target_key]], config):
			reps[c.target_key] = i
	if not reps.is_empty():
		var targets: Array[int] = []
		targets.assign(reps.values())
		return _pick_in_direction(candidates, targets, cur, dir)

	# 3. Only this target: go round its parts again.
	if not all_parts.is_empty():
		return _pick_in_direction(candidates, all_parts, cur, dir)
	return -1


static func index_of_key(candidates: Array[LockOnCandidate], key: int) -> int:
	for i: int in candidates.size():
		if candidates[i].key == key:
			return i
	return -1


## `a` is a better landing part than `b` on the same target.
static func _better_part(a: LockOnCandidate, b: LockOnCandidate, config: LockOnConfig) -> bool:
	var sa: float = score(a, config)
	var sb: float = score(b, config)
	if absf(sa - sb) > _EPS:
		return sa < sb
	return a.key < b.key


## The pool entry nearest to `from` on screen in direction `dir` (+1 right, −1 left),
## wrapping round to the far side when nothing is that way.
static func _pick_in_direction(candidates: Array[LockOnCandidate], pool: Array[int],
		from: LockOnCandidate, dir: int) -> int:
	var best: int = -1
	var best_rank: float = INF
	for i: int in pool:
		var c: LockOnCandidate = candidates[i]
		var d: float = (c.screen.x - from.screen.x) * float(dir)
		var rank: float = d if d > _EPS else d + _WRAP
		if best == -1 or rank < best_rank - _EPS or (absf(rank - best_rank) <= _EPS and c.key < candidates[best].key):
			best = i
			best_rank = rank
	return best
