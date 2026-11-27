class_name Hurtbox
extends Area3D
## A body part that can be hit. Sits on the "hurtbox" physics layer (layer 4); attack
## shape queries look for these. A hit resolves through the owner's Combatant, scaled by
## this part's multipliers, so guard, parry and dodge rules still apply (an enemy's Guard
## stays down unless its AI raises it). Large monsters get one per part (head, limbs…).
##
## Expected children: one or more CollisionShape3D.

## A hit landed on this part (after it was resolved). MonsterPart listens to fill its part
## posture bar.
signal hit_received(result: HitResult, attacker: Combatant)

## Physics layer number named "hurtbox" in project settings.
const LAYER: int = 4
const LAYER_MASK: int = 1 << (LAYER - 1)

## The Combatant this part belongs to. If unset, the parent's "Combatant" child is used.
@export var combatant: Combatant
## Which part this is, e.g. &"body", &"head", &"left_arm". Used by lock-on and logs.
@export var part_id: StringName = &"body"
## Health damage taken through this part = attack damage × this.
@export_range(0.0, 10.0, 0.05) var damage_multiplier: float = 1.0
## Posture damage taken through this part = attack posture damage × this.
@export_range(0.0, 10.0, 0.05) var posture_multiplier: float = 1.0


func _init() -> void:
	collision_layer = LAYER_MASK
	collision_mask = 0
	monitoring = false
	monitorable = true


func _ready() -> void:
	if combatant == null:
		combatant = Combatant.find_on(get_parent())
	assert(combatant != null, "Hurtbox %s has no Combatant" % get_path())


## Lands `attack` from `attacker` on this part. Returns the result (MISSED if the part
## has no combatant).
func receive_hit(attack: AttackData, attacker: Combatant = null, frame: int = -1) -> HitResult:
	if combatant == null:
		return HitResult.new(attack, HitResult.Outcome.MISSED)
	var result: HitResult = combatant.receive_attack(attack, attacker, frame, damage_multiplier, posture_multiplier)
	hit_received.emit(result, attacker)
	return result


## One hurtbox per Combatant out of `candidates`: the one with the highest damage
## multiplier (the first one wins a tie), in the order each Combatant was first seen.
## Hurtboxes without a combatant are skipped.
static func best_per_combatant(candidates: Array[Hurtbox]) -> Array[Hurtbox]:
	var best: Dictionary[int, Hurtbox] = {}
	for hurtbox: Hurtbox in candidates:
		if hurtbox == null or hurtbox.combatant == null:
			continue
		var key: int = hurtbox.combatant.get_instance_id()
		if not best.has(key) or hurtbox.damage_multiplier > best[key].damage_multiplier:
			best[key] = hurtbox
	var picked: Array[Hurtbox] = []
	picked.assign(best.values())
	return picked
