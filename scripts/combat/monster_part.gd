class_name MonsterPart
extends Node3D
## One body part of a large monster (head, a forelimb, the tail, the body): a component
## node that sits under the monster (later under a BoneAttachment3D on the rig's socket).
## Its rules live in MonsterPartState (pure, unit tested); its tuning in MonsterPartConfig.
##
## Hits through its Hurtbox fill its own part posture bar; when that fills the part breaks:
## `broken` fires (LargeMonster staggers the whole body and adds whole-body posture), its
## hurtbox takes more damage, and attacks listed in the config get weaker or are disabled.
## It stays broken until reset() (the monster respawns). Part posture recovers on combat
## frames (paused during hit-stop).
##
## Expected children: Hurtbox (with its CollisionShape3D; set its `combatant` to the
## monster's Combatant), LockOnPoint; any meshes (tinted when broken).

signal broken(part: MonsterPart)
signal part_posture_changed(part: MonsterPart, value: float, max_value: float)

@export var config: MonsterPartConfig

var state: MonsterPartState
var hurtbox: Hurtbox
var lock_point: LockOnPoint


func _ready() -> void:
	assert(config != null, "MonsterPart %s needs a MonsterPartConfig" % name)
	state = MonsterPartState.new(config)
	for child: Node in get_children():
		if child is Hurtbox and hurtbox == null:
			hurtbox = child as Hurtbox
		elif child is LockOnPoint and lock_point == null:
			lock_point = child as LockOnPoint
	assert(hurtbox != null, "MonsterPart %s needs a Hurtbox child" % name)
	hurtbox.part_id = config.part_id
	hurtbox.posture_multiplier = config.posture_multiplier
	hurtbox.hit_received.connect(_on_hit_received)
	if lock_point != null:
		lock_point.part_id = config.part_id
		lock_point.priority = config.lock_priority
	state.broken.connect(_on_state_broken)
	state.posture_changed.connect(func(v: float, m: float) -> void: part_posture_changed.emit(self, v, m))
	_apply_multipliers()


func _physics_process(_delta: float) -> void:
	if state != null and not HitStopService.is_frozen():
		state.tick(1)


func part_id() -> StringName:
	return config.part_id


func is_breakable() -> bool:
	return state.is_breakable()


func is_broken() -> bool:
	return state.is_broken()


## Part posture value / max (0 / 1 for a part that can't break).
func posture_value() -> float:
	return state.value()


func posture_max() -> float:
	return config.posture.max_posture if config.is_breakable() else 1.0


## Lands `attack` on this part's hurtbox, as a hit from `attacker` (tests, scripted hits).
func receive_hit(attack: AttackData, attacker: Combatant = null) -> HitResult:
	return hurtbox.receive_hit(attack, attacker)


## Empty part posture, not broken, normal multipliers (the monster respawned).
func reset() -> void:
	state.reset()
	_apply_multipliers()


## The meshes that belong to this part (tinted while broken).
func meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		out.append(node as MeshInstance3D)
	return out


func _on_hit_received(result: HitResult, _attacker: Combatant) -> void:
	match result.outcome:
		HitResult.Outcome.HIT, HitResult.Outcome.BLOCKED, HitResult.Outcome.GUARD_BROKEN:
			state.add_hit(result.defender_posture_damage) # -> _on_state_broken when it fills
		_:
			pass


func _on_state_broken() -> void:
	_apply_multipliers()
	broken.emit(self)


func _apply_multipliers() -> void:
	hurtbox.damage_multiplier = state.damage_multiplier()
