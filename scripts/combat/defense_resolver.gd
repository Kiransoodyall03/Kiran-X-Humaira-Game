class_name DefenseResolver
extends RefCounted
## The rules for what happens when an attack reaches a defender. Pure functions only:
## no scene, no state, so every rule is unit-tested in tests/unit/defense_resolver_test.gd.
##
## Order of checks: parry beats block beats hit.
##   PARRIED  — attack is deflectable and guard was pressed within the parry window.
##   BLOCKED  — attack is blockable and guard is held.
##   HIT      — anything else, including perilous attacks the defender didn't answer.
## GUARD_BROKEN is decided later by the Combatant, when a block fills posture.


static func resolve(attack: AttackData, guard: Guard, frame: int, config: GuardConfig, can_defend: bool = true) -> HitResult:
	if can_defend and attack.deflectable and guard.is_parry_active(frame):
		var parried: HitResult = HitResult.new(attack, HitResult.Outcome.PARRIED)
		parried.defender_posture_damage = attack.posture_damage * config.parry_self_posture_multiplier
		parried.attacker_posture_damage = attack.posture_damage * config.parry_attacker_posture_multiplier
		return parried
	if can_defend and attack.blockable and guard.is_held:
		var blocked: HitResult = HitResult.new(attack, HitResult.Outcome.BLOCKED)
		blocked.defender_posture_damage = attack.posture_damage * config.block_posture_multiplier
		blocked.health_damage = attack.damage * config.block_health_multiplier
		return blocked
	var hit: HitResult = HitResult.new(attack, HitResult.Outcome.HIT)
	hit.health_damage = attack.damage
	hit.defender_posture_damage = attack.posture_damage * config.hit_posture_multiplier
	return hit
