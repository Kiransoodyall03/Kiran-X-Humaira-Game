class_name HealCharges
extends RefCounted
## The heroine's healing charges (docs/COMBAT_SPEC.md "Healing charges"): a limited count,
## a heal that takes HealConfig.use_frames and lands on apply_frame, interruption and
## refill. Pure logic driven by frame counts (60 fps), so it can be unit-tested without a
## scene. PlayerHealing (scripts/actors/player_healing.gd) runs it on the heroine.
##
## The charge is spent when the heal lands (apply_frame), not on the press: a heal
## cancelled before it lands costs nothing.

signal charges_changed(charges: int, max_charges: int)
signal started
## The heal landed: `amount` health should be restored now and one charge was spent.
signal applied(amount: float)
## The heal ran its full use_frames.
signal finished
## The heal was cancelled. `charge_spent` is true if it had already landed.
signal interrupted(charge_spent: bool)

const IDLE: int = -1

var config: HealConfig
var charges: int = 0
## Frames since the heal started, or IDLE.
var _elapsed: int = IDLE
var _applied: bool = false


func _init(p_config: HealConfig) -> void:
	assert(p_config != null, "HealCharges needs a HealConfig")
	assert(p_config.apply_frame <= p_config.use_frames, "HealConfig.apply_frame must be <= use_frames")
	config = p_config
	charges = config.max_charges


func max_charges() -> int:
	return config.max_charges


## A heal is in progress (from the press until use_frames or an interrupt).
func is_active() -> bool:
	return _elapsed != IDLE


## The heal in progress has already landed (it is in its recovery frames).
func has_applied() -> bool:
	return is_active() and _applied


## Frames since the heal in progress started (IDLE when none).
func elapsed_frames() -> int:
	return _elapsed


## A heal could start now for someone at `health_ratio` (0–1) health.
func can_start(health_ratio: float) -> bool:
	if is_active() or charges <= 0:
		return false
	return config.allow_at_full_health or health_ratio < 1.0


## Starts a heal. Returns false (and changes nothing) if can_start() is false.
func start(health_ratio: float) -> bool:
	if not can_start(health_ratio):
		return false
	_elapsed = 0
	_applied = false
	started.emit()
	return true


## Advances the heal in progress by `frames`. Returns the health to restore now:
## heal_amount on the step that reaches apply_frame (spending one charge), else 0.
func step(frames: int) -> float:
	if not is_active() or frames <= 0:
		return 0.0
	_elapsed += frames
	var amount: float = 0.0
	if not _applied and _elapsed >= config.apply_frame:
		_applied = true
		charges = maxi(charges - 1, 0)
		charges_changed.emit(charges, config.max_charges)
		amount = config.heal_amount
		applied.emit(amount)
	if _elapsed >= config.use_frames:
		_elapsed = IDLE
		_applied = false
		finished.emit()
	return amount


## Cancels the heal in progress. Returns false if none was running.
func interrupt() -> bool:
	if not is_active():
		return false
	var spent: bool = _applied
	_elapsed = IDLE
	_applied = false
	interrupted.emit(spent)
	return true


## Shrine rest: all charges back. Doesn't touch a heal in progress.
func refill() -> void:
	set_charges(config.max_charges)


## Sets the charge count (clamped to 0..max_charges).
func set_charges(count: int) -> void:
	var clamped: int = clampi(count, 0, config.max_charges)
	if clamped == charges:
		return
	charges = clamped
	charges_changed.emit(charges, config.max_charges)
