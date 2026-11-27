class_name PlayerHealing
extends Node
## Runs the heroine's HealCharges (scripts/combat/heal_charges.gd). A child of the heroine
## named "Healing", next to her Combatant. PlayerController calls physics_update() once per
## physics tick (after guard input, before attacks), which advances the heal on combat
## frames (paused during hit-stop) and reads the "heal" action.
## While a heal runs she can only walk slowly (HealConfig.move_speed_multiplier): no
## attacks, dodges, guard, form switches or jumps. Hits cancel it (HealConfig rules); a
## posture break or death always does.
## Shrines refill the charges (refill()).

signal charges_changed(charges: int, max_charges: int)
signal heal_started
signal heal_applied(amount: float)
signal heal_finished
signal heal_interrupted(charge_spent: bool)

@export var config: HealConfig
## Her health. If unset, the sibling named "Combatant".
@export var combatant: Combatant

var charges: HealCharges


func _ready() -> void:
	assert(config != null, "PlayerHealing needs a HealConfig")
	if combatant == null:
		combatant = Combatant.find_on(get_parent())
	charges = HealCharges.new(config)
	charges.charges_changed.connect(func(c: int, m: int) -> void: charges_changed.emit(c, m))
	charges.started.connect(func() -> void: heal_started.emit())
	charges.applied.connect(func(a: float) -> void: heal_applied.emit(a))
	charges.finished.connect(func() -> void: heal_finished.emit())
	charges.interrupted.connect(func(spent: bool) -> void: heal_interrupted.emit(spent))
	if combatant != null:
		combatant.attack_resolved.connect(_on_attack_resolved)
		combatant.posture_broken.connect(interrupt)
		combatant.died.connect(interrupt)


## Advances the heal one combat frame (not during hit-stop), then starts one if "heal" was
## just pressed and `can_start` (she can act, isn't attacking or dodging, is on the floor).
func physics_update(can_start: bool) -> void:
	if not HitStopService.is_frozen():
		var amount: float = charges.step(1)
		if amount > 0.0 and combatant != null:
			combatant.heal(amount)
	if can_start and Input.is_action_just_pressed(&"heal"):
		try_heal()


## Starts a heal if she has a charge, can act and (unless allowed) isn't at full health.
## Lowers her guard. Returns true if it started.
func try_heal() -> bool:
	if combatant != null and not combatant.can_act():
		return false
	var ratio: float = combatant.health_ratio() if combatant != null else 0.0
	if not charges.start(ratio):
		return false
	if combatant != null:
		combatant.cancel_guard()
	return true


func is_healing() -> bool:
	return charges != null and charges.is_active()


## Cancels a heal in progress (a charge is only spent if it had already landed).
func interrupt() -> void:
	if charges != null:
		charges.interrupt()


func charges_left() -> int:
	return charges.charges


func max_charges() -> int:
	return charges.max_charges()


## Walk speed factor right now: HealConfig.move_speed_multiplier while healing, else 1.
func move_speed_multiplier() -> float:
	return config.move_speed_multiplier if is_healing() else 1.0


## Shrine rest: all charges back.
func refill() -> void:
	charges.refill()


func _on_attack_resolved(result: HitResult, _attacker: Combatant) -> void:
	if not config.interrupted_by_hits or not is_healing():
		return
	if result.outcome == HitResult.Outcome.HIT or result.outcome == HitResult.Outcome.GUARD_BROKEN:
		interrupt()
