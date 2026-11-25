class_name Posture
extends RefCounted
## A posture meter: fills from damage, breaks when full, recovers after a delay.
## Pure logic, driven by frame counts so it can be unit-tested without a scene.

signal changed(value: float, max_value: float)
signal broken

## How close below max a non-breaking hit (a parry) may fill posture.
const NON_BREAKING_GAP: float = 0.01

var config: PostureConfig
var value: float = 0.0
var is_broken: bool = false
var _frames_since_damage: int = 0


func _init(p_config: PostureConfig) -> void:
	assert(p_config != null, "Posture needs a PostureConfig")
	config = p_config


func max_value() -> float:
	return config.max_posture


func ratio() -> float:
	return value / config.max_posture


## Adds posture damage. Returns true if this call broke posture.
## With can_break off, posture stops just below max instead of breaking.
func add(amount: float, can_break: bool = true) -> bool:
	if amount <= 0.0 or is_broken:
		return false
	_frames_since_damage = 0
	var cap: float = config.max_posture if can_break else config.max_posture - NON_BREAKING_GAP
	value = minf(maxf(value, minf(value + amount, cap)), config.max_posture)
	changed.emit(value, config.max_posture)
	if can_break and value >= config.max_posture:
		is_broken = true
		broken.emit()
		return true
	return false


## Advances recovery by `frames` (60 fps). Recovery is faster while guarding and slower
## at low health (health_ratio 0–1). Nothing recovers while broken.
func tick(frames: int, guarding: bool, health_ratio: float) -> void:
	_frames_since_damage += frames
	if is_broken or value <= 0.0 or _frames_since_damage < config.regen_delay_frames:
		return
	var rate: float = config.regen_per_second
	if guarding:
		rate *= config.guard_regen_multiplier
	rate *= lerpf(config.low_health_regen_multiplier, 1.0, clampf(health_ratio, 0.0, 1.0))
	value = maxf(value - rate * float(frames) / 60.0, 0.0)
	changed.emit(value, config.max_posture)


## Ends the broken state but keeps the value (just below max, so the next hit doesn't
## re-break it at once). Recovery starts again after the usual delay.
func end_break() -> void:
	is_broken = false
	_frames_since_damage = 0
	value = minf(value, config.max_posture - NON_BREAKING_GAP)
	changed.emit(value, config.max_posture)


## Empties posture and clears the broken state.
func reset() -> void:
	value = 0.0
	is_broken = false
	_frames_since_damage = 0
	changed.emit(value, config.max_posture)
