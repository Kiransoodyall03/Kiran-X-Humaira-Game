class_name MonsterPartState
extends RefCounted
## The rules of one large-monster part, as pure logic (unit tested in
## tests/unit/monster_part_test.gd): its part posture bar, when it breaks, its damage
## multiplier, and what a broken part does to the monster's attacks. MonsterPart (the node)
## wraps one of these.

## The part broke (its posture bar filled).
signal broken
signal posture_changed(value: float, max_value: float)

var config: MonsterPartConfig
## The part posture bar, or null for a part that can't break.
var posture: Posture


func _init(p_config: MonsterPartConfig) -> void:
	assert(p_config != null, "MonsterPartState needs a MonsterPartConfig")
	config = p_config
	if config.is_breakable():
		posture = Posture.new(config.posture)
		# Bound methods, not lambdas: a lambda would capture self and make a reference
		# cycle (state -> posture -> lambda -> state) that never frees.
		posture.changed.connect(_on_posture_changed)
		posture.broken.connect(_on_posture_broken)


func is_breakable() -> bool:
	return posture != null


func is_broken() -> bool:
	return posture != null and posture.is_broken


## A hit through this part dealt `body_posture_damage` whole-body posture damage. Fills the
## part bar by that × part_posture_multiplier. Returns true if this hit broke the part.
## Does nothing for an unbreakable or already broken part.
func add_hit(body_posture_damage: float) -> bool:
	if posture == null or posture.is_broken:
		return false
	return posture.add(body_posture_damage * config.part_posture_multiplier)


## Part posture value (0 for an unbreakable part).
func value() -> float:
	return posture.value if posture != null else 0.0


## Part posture 0–1 (0 for an unbreakable part).
func ratio() -> float:
	return posture.ratio() if posture != null else 0.0


## Health damage multiplier of its hurtbox now: higher once broken.
func damage_multiplier() -> float:
	return config.damage_multiplier * (config.broken_damage_multiplier if is_broken() else 1.0)


## Advances part posture recovery (PostureConfig regen) by `frames`. A broken part stays
## broken until reset().
func tick(frames: int) -> void:
	if posture != null:
		posture.tick(frames, false, 1.0)


## Empty bar, not broken (the monster respawned).
func reset() -> void:
	if posture != null:
		posture.reset()


## True if a broken part in `parts` disables `attack_id`.
static func is_attack_disabled(parts: Array[MonsterPartState], attack_id: StringName) -> bool:
	for p: MonsterPartState in parts:
		if p != null and p.is_broken() and p.config.disables_attacks.has(attack_id):
			return true
	return false


## Damage / posture damage scale of `attack_id`: the product of weakened_scale over broken
## parts that weaken it; 0 if a broken part disables it; 1 if nothing is broken.
static func attack_scale(parts: Array[MonsterPartState], attack_id: StringName) -> float:
	if is_attack_disabled(parts, attack_id):
		return 0.0
	var scale: float = 1.0
	for p: MonsterPartState in parts:
		if p != null and p.is_broken() and p.config.weakens_attacks.has(attack_id):
			scale *= p.config.weakened_scale
	return scale


func _on_posture_changed(v: float, m: float) -> void:
	posture_changed.emit(v, m)


func _on_posture_broken() -> void:
	broken.emit()
