class_name Combatant
extends Node
## Health, posture and guard for anything that fights. Add as a child named "Combatant"
## to the heroine, enemies and bosses. Attacks go through receive_attack(); the rules
## live in DefenseResolver. Runs on combat frames (HitStopService.combat_frame()): one per
## physics tick at 60 fps, paused during hit-stop.
##
## Deathblows (config.can_be_deathblown): while staggered by a posture break the window is
## open and receive_deathblow() takes a life. With config.requires_deathblow, 0 health
## doesn't kill: it staggers with no time limit until a deathblow lands.
##
## stagger(frames) staggers without a posture break (a large monster's part break): it
## can't act for that long, but no deathblow window opens.

signal attack_resolved(result: HitResult, attacker: Combatant)
signal health_changed(value: float, max_value: float)
signal posture_changed(value: float, max_value: float)
## Posture filled up: the owner is staggered (and, for enemies, open to a deathblow).
signal posture_broken
## Staggered by stagger() (no posture break, no deathblow window) for `frames` combat frames.
signal staggered(frames: int)
## A stagger ended (posture-break stagger, stagger(), or a deathblow that left a life).
signal stagger_ended
signal died
signal revived
## A deathblow can land now (posture broken, or 0 health waiting for one).
signal deathblow_available
## The deathblow window closed: the stagger ended, a deathblow landed, or it died.
signal deathblow_unavailable
## A deathblow landed. `lives_left` 0 means it also died.
signal deathblow_landed(lives_left: int)
## Lives left changed (deathblow, death or revive).
signal lives_changed(lives_left: int, max_lives: int)

@export var config: CombatantConfig

var health: float = 0.0
var posture: Posture
var guard: Guard
var is_dead: bool = false
## Lives left; see CombatantConfig.lives.
var lives_left: int = 1
var _stagger_frames_left: int = 0
## Frames left of a stagger() stagger (no deathblow window).
var _hit_stagger_frames_left: int = 0
## 0 health with requires_deathblow: staggered until a deathblow lands.
var _awaiting_deathblow: bool = false
## deathblow_available was emitted and deathblow_unavailable not yet.
var _deathblow_open: bool = false
## Physics frame on which posture damage last landed. That frame's own step is skipped,
## so stagger and recovery delays last exactly as long as the data says, whether this
## node steps before or after the attacker in the tree.
var _skip_step_frame: int = -1
## Invulnerability window (dodge i-frames): hits landing on frames
## [_invulnerable_from, _invulnerable_from + _invulnerable_frames) are DODGED.
var _invulnerable_from: int = 0
var _invulnerable_frames: int = 0


func _ready() -> void:
	if posture == null:
		setup(config)


## Builds the meters from a config. Called from _ready; tests call it directly.
func setup(p_config: CombatantConfig) -> void:
	assert(p_config != null and p_config.posture != null and p_config.guard != null,
			"Combatant needs a CombatantConfig with posture and guard configs")
	config = p_config
	health = config.max_health
	lives_left = maxi(config.lives, 1)
	posture = Posture.new(config.posture)
	guard = Guard.new(config.guard)
	posture.changed.connect(func(v: float, m: float) -> void: posture_changed.emit(v, m))
	posture.broken.connect(_on_posture_broken)


func _physics_process(_delta: float) -> void:
	if HitStopService.is_frozen() or current_frame() == _skip_step_frame:
		return
	step(1)


## Advances stagger and posture recovery by `frames`. Nothing advances while dead or
## while waiting for a deathblow.
func step(frames: int) -> void:
	if is_dead or _awaiting_deathblow:
		return
	if _stagger_frames_left > 0:
		_stagger_frames_left -= frames
		if _stagger_frames_left <= 0:
			_end_stagger()
		return
	if _hit_stagger_frames_left > 0:
		_hit_stagger_frames_left -= frames
		if _hit_stagger_frames_left <= 0:
			_hit_stagger_frames_left = 0
			stagger_ended.emit()
		return
	posture.tick(frames, guard.is_held, health_ratio())


## The frame number all combat timing uses (paused during hit-stop).
static func current_frame() -> int:
	return HitStopService.combat_frame()


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


## The player let go of guard: block ends, the parry window of the press stays open.
func guard_release() -> void:
	guard.release()


## Guard forced down (form without guard, attacking, dodging, healing, stagger, death):
## block ends AND the open parry window closes.
func cancel_guard() -> void:
	guard.cancel()


func is_guarding() -> bool:
	return guard.is_held and can_act()


## Staggered: by a posture break, out of health and waiting for a deathblow, or by stagger().
func is_staggered() -> bool:
	return _stagger_frames_left > 0 or _awaiting_deathblow or _hit_stagger_frames_left > 0


## Staggered by a posture break or waiting for a deathblow (the deathblow window can open).
func is_break_staggered() -> bool:
	return _stagger_frames_left > 0 or _awaiting_deathblow


## Staggers for `frames` combat frames without a posture break: no acting, guard dropped,
## no deathblow window, posture doesn't recover meanwhile. Used when a large monster's part
## breaks. Does nothing while dead or already staggered by a posture break; a longer
## stagger() extends a running one. Returns true if it staggered.
func stagger(frames: int) -> bool:
	if is_dead or frames <= 0 or is_break_staggered():
		return false
	_hit_stagger_frames_left = maxi(_hit_stagger_frames_left, frames)
	_skip_step_frame = current_frame()
	guard.cancel()
	staggered.emit(frames)
	return true


## Combat frames left of a stagger() stagger (0 if none).
func hit_stagger_frames_left() -> int:
	return _hit_stagger_frames_left


## Out of health and waiting for a deathblow (requires_deathblow).
func is_awaiting_deathblow() -> bool:
	return _awaiting_deathblow


## True while a deathblow would land: can be deathblown, alive and staggered by a posture
## break (or waiting for a deathblow). A stagger() stagger doesn't count.
func is_deathblow_available() -> bool:
	return config.can_be_deathblown and not is_dead and is_break_staggered()


## Lands a deathblow from `attacker`. Takes one life: at 0 lives it dies; otherwise it
## gets up for the next phase with full health, empty posture and no stagger.
## Returns false (and changes nothing) if no deathblow is available.
func receive_deathblow(_attacker: Combatant = null) -> bool:
	if not is_deathblow_available():
		return false
	lives_left = maxi(lives_left - 1, 0)
	_awaiting_deathblow = false
	_stagger_frames_left = 0
	_hit_stagger_frames_left = 0
	_close_deathblow_window()
	_hit_stop(HitStopService.Kind.DEATHBLOW)
	lives_changed.emit(lives_left, config.lives)
	deathblow_landed.emit(lives_left)
	if lives_left <= 0:
		health = 0.0
		health_changed.emit(health, config.max_health)
		_die()
	else:
		health = config.max_health
		health_changed.emit(health, config.max_health)
		posture.reset()
		stagger_ended.emit()
	return true


## False while staggered or dead: no moving, guarding or attacking.
func can_act() -> bool:
	return not is_dead and not is_staggered()


## Makes hits landing on frames [first_frame, first_frame + frame_count) come back DODGED
## (no damage, no posture, works against perilous attacks too). Replaces any earlier window.
func set_invulnerable(first_frame: int, frame_count: int) -> void:
	_invulnerable_from = first_frame
	_invulnerable_frames = maxi(frame_count, 0)


func clear_invulnerability() -> void:
	_invulnerable_frames = 0


## True if a hit landing on `frame` (default: now) would be dodged.
func is_invulnerable(frame: int = -1) -> bool:
	var f: int = frame if frame >= 0 else current_frame()
	return _invulnerable_frames > 0 and f >= _invulnerable_from and f < _invulnerable_from + _invulnerable_frames


func health_ratio() -> float:
	return health / config.max_health


## Resolves an attack landing on this combatant on `frame` (default: now), applies the
## result to both sides and returns it. The multipliers scale the health and posture
## damage this side takes (hurtbox body-part multipliers); they don't change parry
## damage dealt back to the attacker.
func receive_attack(attack: AttackData, attacker: Combatant = null, frame: int = -1,
		damage_multiplier: float = 1.0, posture_multiplier: float = 1.0) -> HitResult:
	if is_dead:
		var missed: HitResult = HitResult.new(attack, HitResult.Outcome.MISSED)
		attack_resolved.emit(missed, attacker)
		return missed
	var hit_frame: int = frame if frame >= 0 else current_frame()
	if is_invulnerable(hit_frame):
		var dodged: HitResult = HitResult.new(attack, HitResult.Outcome.DODGED)
		attack_resolved.emit(dodged, attacker)
		return dodged
	var result: HitResult = DefenseResolver.resolve(attack, guard, hit_frame, config.guard, not is_staggered())
	result.health_damage *= damage_multiplier
	result.defender_posture_damage *= posture_multiplier
	if result.outcome == HitResult.Outcome.PARRIED:
		_hit_stop(HitStopService.Kind.PARRY)

	var can_break: bool = result.outcome != HitResult.Outcome.PARRIED or config.guard.parry_can_break_posture
	if result.defender_posture_damage > 0.0 and not is_staggered():
		_skip_step_frame = current_frame() # not while staggered: hits must not stretch a stagger
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
	if not is_staggered():
		_skip_step_frame = current_frame()
	return posture.add(amount)


## Restores up to `amount` health (not past max, not while dead). Returns what it restored.
func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var old: float = health
	health = minf(health + amount, config.max_health)
	if health != old:
		health_changed.emit(health, config.max_health)
	return health - old


## Shrine rest: full health, empty posture, no stagger. Revives if dead.
## Unlike revive() it doesn't emit `revived` for a living combatant.
func restore() -> void:
	if is_dead:
		revive()
		return
	var was_staggered: bool = is_staggered()
	_stagger_frames_left = 0
	_hit_stagger_frames_left = 0
	_awaiting_deathblow = false
	_close_deathblow_window()
	health = config.max_health
	posture.reset()
	health_changed.emit(health, config.max_health)
	if was_staggered:
		stagger_ended.emit()


## Restores full health, all lives, empty posture, no stagger.
func revive() -> void:
	is_dead = false
	_stagger_frames_left = 0
	_hit_stagger_frames_left = 0
	_awaiting_deathblow = false
	_close_deathblow_window()
	_invulnerable_frames = 0
	health = config.max_health
	lives_left = maxi(config.lives, 1)
	posture.reset()
	health_changed.emit(health, config.max_health)
	lives_changed.emit(lives_left, config.lives)
	revived.emit()


func _take_health_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, config.max_health)
	if health > 0.0 or is_dead or _awaiting_deathblow:
		return
	if config.can_be_deathblown and config.requires_deathblow:
		_await_deathblow()
	else:
		lives_left = 0
		lives_changed.emit(lives_left, config.lives)
		_die()


func _die() -> void:
	is_dead = true
	_awaiting_deathblow = false
	_stagger_frames_left = 0
	_hit_stagger_frames_left = 0
	_close_deathblow_window()
	guard.cancel()
	died.emit()


## Out of health but needs a deathblow: staggered with no time limit. If posture wasn't
## broken yet this fills it and counts as a posture break (signal, hit-stop).
func _await_deathblow() -> void:
	_awaiting_deathblow = true
	if posture.is_broken:
		_open_deathblow_window()
	else:
		posture.add(config.posture.max_posture) # breaks → _on_posture_broken


func _on_posture_broken() -> void:
	_stagger_frames_left = maxi(config.posture.break_stagger_frames, 1)
	_hit_stagger_frames_left = 0 # the posture break takes over
	_skip_step_frame = current_frame() # the break frame itself doesn't count
	guard.cancel()
	_hit_stop(HitStopService.Kind.POSTURE_BREAK)
	posture_broken.emit()
	_open_deathblow_window()


func _open_deathblow_window() -> void:
	if _deathblow_open or not is_deathblow_available():
		return
	_deathblow_open = true
	deathblow_available.emit()


func _close_deathblow_window() -> void:
	if not _deathblow_open:
		return
	_deathblow_open = false
	deathblow_unavailable.emit()


## Hit-stop only for combatants in a scene, not for bare unit-test instances.
func _hit_stop(kind: HitStopService.Kind) -> void:
	if is_inside_tree():
		HitStopService.trigger(kind)


func _end_stagger() -> void:
	_stagger_frames_left = 0
	_close_deathblow_window()
	if config.posture.reset_after_break:
		posture.reset()
	else:
		posture.end_break()
	stagger_ended.emit()
