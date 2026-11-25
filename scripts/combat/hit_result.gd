class_name HitResult
extends RefCounted
## What happened when an attack reached a defender, and what each side takes.

enum Outcome {
	HIT, ## Not defended: full health damage.
	BLOCKED, ## Guard held: posture damage, little or no health damage.
	PARRIED, ## Guard pressed just in time: posture damage goes back to the attacker.
	GUARD_BROKEN, ## A block that filled posture: the defender is staggered.
	MISSED, ## The attack could not connect (e.g. defender dead).
}

var attack: AttackData
var outcome: Outcome = Outcome.HIT
var health_damage: float = 0.0
var defender_posture_damage: float = 0.0
var attacker_posture_damage: float = 0.0
## True if the defender's posture broke from this hit.
var broke_defender_posture: bool = false


func _init(p_attack: AttackData, p_outcome: Outcome) -> void:
	attack = p_attack
	outcome = p_outcome


func outcome_name() -> String:
	return Outcome.keys()[outcome] as String
