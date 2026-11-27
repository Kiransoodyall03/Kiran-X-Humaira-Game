class_name Corruption
extends RefCounted
## The corruption meter (docs/COMBAT_SPEC.md "Corruption v0"): one value 0..max that rises
## in the katana form and drains in the greatsword form (faster out of combat), with
## threshold signals, a rampage state and a stubbed input-hijack roll.
## Pure logic driven by frame counts (60 fps), so it can be unit-tested without a scene.
## CorruptionMeter (scripts/actors/corruption_meter.gd) runs it on the heroine.
##
## Rampage: starts when the meter *reaches* max (rising from below) unless her health is
## already critical. It ends when the meter drains to rampage_exit_corruption, when her
## health turns critical, or on a shrine reset. After a critical-health exit, staying at
## max doesn't restart it: the meter has to drop below max and reach it again.

enum RampageEnd { DRAINED, CRITICAL_HEALTH, SHRINE }

signal changed(value: float, max_value: float)
## The meter rose to (or past) `threshold` from below it.
signal threshold_reached(threshold: float)
## The meter fell below `threshold` from at or above it.
signal threshold_dropped(threshold: float)
signal rampage_started
signal rampage_ended(reason: RampageEnd)
## reset_at_shrine() emptied the meter.
signal shrine_reset

const NEVER: int = -1_000_000

var config: CorruptionConfig
var value: float = 0.0
var is_rampaging: bool = false
## Combat frame of the last attack dealt or taken, or NEVER.
var _last_combat_frame: int = NEVER
## Last health ratio passed to step()/check_health().
var _health_ratio: float = 1.0


func _init(p_config: CorruptionConfig) -> void:
	assert(p_config != null, "Corruption needs a CorruptionConfig")
	config = p_config


func max_value() -> float:
	return config.max_corruption


func ratio() -> float:
	return value / config.max_corruption


## Change per second in `form`: FormConfig.corruption_per_second, times the form's
## out-of-combat multiplier when not in combat. 0 without a form.
static func rate_per_second(form: FormConfig, in_combat: bool) -> float:
	if form == null:
		return 0.0
	var rate: float = form.corruption_per_second
	if not in_combat:
		rate *= form.corruption_out_of_combat_multiplier
	return rate


## Advances the meter by `frames` (60 fps) in `form`, then applies the critical-health
## rampage exit for `health_ratio` (0–1).
func step(frames: int, form: FormConfig, in_combat: bool, health_ratio: float = 1.0) -> void:
	_health_ratio = health_ratio
	var rate: float = rate_per_second(form, in_combat)
	if frames > 0 and rate != 0.0:
		set_value(value + rate * float(frames) / 60.0)
	check_health(health_ratio)


## Sets the meter (clamped to 0..max), firing changed, threshold and rampage signals.
func set_value(new_value: float) -> void:
	var old: float = value
	value = clampf(new_value, 0.0, config.max_corruption)
	if old == value:
		return
	changed.emit(value, config.max_corruption)
	for t: float in config.thresholds:
		if old < t and value >= t:
			threshold_reached.emit(t)
		elif old >= t and value < t:
			threshold_dropped.emit(t)
	if is_rampaging:
		if value <= config.rampage_exit_corruption:
			_end_rampage(RampageEnd.DRAINED)
	elif old < config.max_corruption and value >= config.max_corruption and not _is_health_critical(_health_ratio):
		is_rampaging = true
		rampage_started.emit()


## Ends a rampage if `health_ratio` (0–1) is at or below the critical ratio.
func check_health(health_ratio: float) -> void:
	_health_ratio = health_ratio
	if is_rampaging and _is_health_critical(health_ratio):
		_end_rampage(RampageEnd.CRITICAL_HEALTH)


## Records that she dealt or took an attack on `frame`.
func note_combat(frame: int) -> void:
	_last_combat_frame = frame


## In combat on `frame`: a living hostile is in range, or an attack was dealt or taken
## within the last combat_linger_frames.
func is_in_combat(frame: int, hostile_in_range: bool) -> bool:
	if hostile_in_range:
		return true
	if _last_combat_frame == NEVER:
		return false
	var since: int = frame - _last_combat_frame
	return since >= 0 and since < config.combat_linger_frames


## Shrine rest: empties the meter and ends any rampage.
func reset_at_shrine() -> void:
	if is_rampaging:
		_end_rampage(RampageEnd.SHRINE)
	set_value(0.0)
	_last_combat_frame = NEVER
	shrine_reset.emit()


## No katana dodge while rampaging (if the config says so).
func locks_dodge() -> bool:
	return is_rampaging and config.rampage_locks_dodge


## STUB: chance (0–1) that the cat takes over her input on one check. 0 at or below
## hijack_start, rising along hijack_curve_exponent to hijack_chance_at_max at max.
## Nothing reads it to change input yet.
func hijack_chance() -> float:
	var span: float = config.max_corruption - config.hijack_start
	if value <= config.hijack_start or span <= 0.0:
		return 0.0
	var t: float = clampf((value - config.hijack_start) / span, 0.0, 1.0)
	return config.hijack_chance_at_max * pow(t, config.hijack_curve_exponent)


## STUB: rolls `rng` against hijack_chance(). True = the input should be hijacked this
## check. The caller decides how often to check; player input is not changed yet.
func should_hijack_input(rng: RandomNumberGenerator) -> bool:
	var chance: float = hijack_chance()
	if chance <= 0.0:
		return false
	return rng.randf() < chance


func _is_health_critical(health_ratio: float) -> bool:
	return health_ratio <= config.rampage_exit_health_ratio


func _end_rampage(reason: RampageEnd) -> void:
	is_rampaging = false
	rampage_ended.emit(reason)
