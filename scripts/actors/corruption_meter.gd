class_name CorruptionMeter
extends Node
## Runs the heroine's Corruption meter (scripts/combat/corruption.gd). A child of the
## heroine named "CorruptionMeter", next to her Combatant and PlayerCombat.
## Each combat frame (paused during hit-stop and while she is dead) it reads her sword
## form and whether she is in combat, and steps the meter. In combat = a living Combatant
## whose body is in the "hostile" group within CorruptionConfig.combat_radius, or an attack
## dealt or taken (or a deathblow) within combat_linger_frames.
## A rampage locks the katana dodge (PlayerCombat.set_dodge_locked). Input hijack is a
## stub: should_hijack_input() is exposed but nothing changes her input yet.
## Shrines call reset_at_shrine().

signal corruption_changed(value: float, max_value: float)
signal threshold_reached(threshold: float)
signal threshold_dropped(threshold: float)
signal rampage_started
signal rampage_ended(reason: Corruption.RampageEnd)
signal shrine_reset

## Bodies in this group (with a Combatant child) count as hostile for "in combat".
const HOSTILE_GROUP: StringName = &"hostile"

@export var config: CorruptionConfig
## Her forms and dodge. If unset, the sibling named "PlayerCombat".
@export var combat: PlayerCombat
## Her health. If unset, the sibling named "Combatant".
@export var combatant: Combatant

var corruption: Corruption
## Whether she counted as in combat on the last step.
var in_combat: bool = false
var _body: Node3D


func _ready() -> void:
	assert(config != null, "CorruptionMeter needs a CorruptionConfig")
	_body = get_parent() as Node3D
	if combat == null:
		combat = get_parent().get_node_or_null(^"PlayerCombat") as PlayerCombat
	if combatant == null:
		combatant = Combatant.find_on(get_parent())
	corruption = Corruption.new(config)
	corruption.changed.connect(func(v: float, m: float) -> void: corruption_changed.emit(v, m))
	corruption.threshold_reached.connect(func(t: float) -> void: threshold_reached.emit(t))
	corruption.threshold_dropped.connect(func(t: float) -> void: threshold_dropped.emit(t))
	corruption.rampage_started.connect(_on_rampage_started)
	corruption.rampage_ended.connect(_on_rampage_ended)
	corruption.shrine_reset.connect(func() -> void: shrine_reset.emit())
	if combatant != null:
		combatant.attack_resolved.connect(_on_attack_taken)
		combatant.health_changed.connect(func(_v: float, _m: float) -> void:
			corruption.check_health(combatant.health_ratio()))
	if combat != null:
		combat.attack_landed.connect(_on_attack_dealt)
		combat.deathblow_performed.connect(func(_t: Combatant, _l: int) -> void: _note_combat())


func _physics_process(_delta: float) -> void:
	if HitStopService.is_frozen():
		return
	if combatant != null and combatant.is_dead:
		return
	in_combat = corruption.is_in_combat(Combatant.current_frame(), hostile_in_range())
	var form: FormConfig = combat.current_form() if combat != null else null
	corruption.step(1, form, in_combat, combatant.health_ratio() if combatant != null else 1.0)


func value() -> float:
	return corruption.value


func max_value() -> float:
	return corruption.max_value()


func ratio() -> float:
	return corruption.ratio()


func is_rampaging() -> bool:
	return corruption.is_rampaging


## Change per second right now (form and in-combat state from the last step).
func current_rate() -> float:
	return Corruption.rate_per_second(combat.current_form() if combat != null else null, in_combat)


## Shrine rest: empties the meter and ends any rampage.
func reset_at_shrine() -> void:
	corruption.reset_at_shrine()


## STUB: 0–1 chance the cat hijacks her input on one check. See Corruption.hijack_chance.
func hijack_chance() -> float:
	return corruption.hijack_chance()


## STUB: rolls `rng` against hijack_chance(). Player input is not changed yet.
func should_hijack_input(rng: RandomNumberGenerator) -> bool:
	return corruption.should_hijack_input(rng)


## A living hostile Combatant's body is within combat_radius of hers (ground plane).
func hostile_in_range() -> bool:
	if _body == null or not _body.is_inside_tree():
		return false
	var radius_sq: float = config.combat_radius * config.combat_radius
	for node: Node in get_tree().get_nodes_in_group(HOSTILE_GROUP):
		var hostile: Node3D = node as Node3D
		var c: Combatant = Combatant.find_on(node)
		if hostile == null or c == null or c.is_dead or c == combatant:
			continue
		var offset: Vector3 = hostile.global_position - _body.global_position
		offset.y = 0.0
		if offset.length_squared() <= radius_sq:
			return true
	return false


func _note_combat() -> void:
	corruption.note_combat(Combatant.current_frame())


func _on_attack_taken(result: HitResult, _attacker: Combatant) -> void:
	if result.outcome != HitResult.Outcome.MISSED:
		_note_combat()


func _on_attack_dealt(result: HitResult, _target: Combatant, _hurtbox: Hurtbox) -> void:
	if result.outcome != HitResult.Outcome.MISSED:
		_note_combat()


func _on_rampage_started() -> void:
	if combat != null and config.rampage_locks_dodge:
		combat.set_dodge_locked(true)
	rampage_started.emit()


func _on_rampage_ended(reason: Corruption.RampageEnd) -> void:
	if combat != null:
		combat.set_dodge_locked(false)
	rampage_ended.emit(reason)
