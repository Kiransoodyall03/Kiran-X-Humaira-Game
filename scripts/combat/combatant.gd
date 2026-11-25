class_name Combatant
extends Node
## Health, posture and guard for anything that fights. Add as a child named "Combatant"
## to the heroine, enemies and bosses. Attacks go through receive_attack(); the rules
## live in DefenseResolver. Runs on physics frames, so 1 tick = 1 frame at 60 fps.

signal attack_resolved(result: HitResult, attacker: Combatant)
signal health_changed(value: float, max_value: float)
signal posture_changed(value: float, max_value: float)
## Posture filled up: the owner is staggered (and, for enemies, open to a deathblow).
signal posture_broken
signal stagger_ended
signal died
signal revived

@export var config: CombatantConfig

var health: float = 0.0
var posture: Posture
var guard: Guard
var is_dead: bool = false
var _stagger_frames_left: int = 0
## Physics frame on which posture damage last landed. That frame's own step is skipped,
## so stagger and recovery delays last exactly as long as the data says, whether this
## node steps before or after the attacker in the tree.
var _skip_step_frame: int = -1


func _ready() -> void:
	if posture == null:
		setup(config)


## Builds the meters from a config. Called from _ready; tests call it directly.
func setup(p_config: CombatantConfig) -> void:
	assert(p_config != null and p_config.posture != null and p_config.guard != null,
			"Combatant needs a CombatantConfig with posture and guard configs")
	config = p_config
	health = config.max_health
	posture = Posture.new(config.posture)
	guard = Guard.new(config.guard)
	posture.changed.connect(func(v: float, m: float) -> void: posture_changed.emit(v, m))
	posture.broken.connect(_on_posture_broken)


func _physics_process(_delta: float) -> void:
	if current_frame() == _skip_step_frame:
		return
	step(1)


## Advances stagger and posture recovery by `frames`. Nothing advances while dead.
func step(frames: int) -> void:
	if is_dead:
		return
	if _stagger_frames_left > 0:
		_stagger_frames_left -= frames
		if _stagger_frames_left <= 0:
			_end_stagger()
		return
	posture.tick(frames, guard.is_held, health_ratio())


## The frame number all combat timing uses.
static func current_frame() -> int:
	return Engine.get_physics_frames()


## Finds the Combatant child of a node, or null.
static func find_on(node: Node) -> Combatant:
	if node == null:
		return null
	return node.get_node_or_null(^"Combatant") as Combatant


func guard_press(frame: int = -1) -> void:
	if not can_act():
		return
	guard.press(frame if frame >= 0 else current_frame())


## Raises guard without opening a parry window — for a block button that was already
## held (e.g. through a stagger) rather than freshly pressed.
func guard_hold() -> void:
	if can_act():
		guard.is_held = true


func guard_release() -> void:
	guard.release()


func is_guarding() -> bool:
	return guard.is_held and can_act()


func is_staggered() -> bool:
	return _stagger_frames_left > 0


## False while staggered or dead: no moving, guarding or attacking.
func can_act() -> bool:
	return not is_dead and not is_staggered()


func health_ratio() -> float:
	return health / config.max_health


## Resolves an attack landing on this combatant on `frame` (default: now), applies the
## result to both sides and returns it.
func receive_attack(attack: AttackData, attacker: Combatant = null, frame: int = -1) -> HitResult:
	if is_dead:
		var missed: HitResult = HitResult.new(attack, HitResult.Outcome.MISSED)
		attack_resolved.emit(missed, attacker)
		return missed
	var hit_frame: int = frame if frame >= 0 else current_frame()
	var result: HitResult = DefenseResolver.resolve(attack, guard, hit_frame, config.guard, not is_staggered())

	var can_break: bool = result.outcome != HitResult.Outcome.PARRIED or config.guard.parry_can_break_posture
	if result.defender_posture_damage > 0.0:
		_skip_step_frame = current_frame()
	result.broke_defender_posture = posture.add(result.defender_posture_damage, can_break)
	if result.broke_defender_posture and result.outcome == HitResult.Outcome.BLOCKED:
		result.outcome = HitResult.Outcome.GUARD_BROKEN
	_take_health_damage(result.health_damage)

	if attacker != null and result.attacker_posture_damage > 0.0:
		attacker.take_posture_damage(result.attacker_posture_damage)
	attack_resolved.emit(result, attacker)
	return result


## Posture damage from outside an attack (e.g. being parried). Returns true if it broke.
func take_posture_damage(amount: float) -> bool:
	if is_dead or amount <= 0.0:
		return false
	_skip_step_frame = current_frame()
	return posture.add(amount)


## Restores full health, empty posture, no stagger.
func revive() -> void:
	is_dead = false
	_stagger_frames_left = 0
	health = config.max_health
	posture.reset()
	health_changed.emit(health, config.max_health)
	revived.emit()


func _take_health_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, config.max_health)
	if health <= 0.0 and not is_dead:
		is_dead = true
		guard.release()
		died.emit()


func _on_posture_broken() -> void:
	_stagger_frames_left = maxi(config.posture.break_stagger_frames, 1)
	guard.release()
	posture_broken.emit()


func _end_stagger() -> void:
	_stagger_frames_left = 0
	if config.posture.reset_after_break:
		posture.reset()
	else:
		posture.end_break()
	stagger_ended.emit()
