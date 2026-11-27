class_name Guard
extends RefCounted
## Tracks the guard button: whether it is held (block) and when it was last pressed
## (parry window). Mashing guard shrinks the window so parries can't be spammed.
## Pure logic: callers pass physics frame numbers.

const NEVER: int = -1_000_000

var config: GuardConfig
var is_held: bool = false
var _press_frame: int = NEVER
var _window: int = 0
## True after cancel(): the last press's parry window is closed early. A new press reopens.
var _parry_cancelled: bool = false


func _init(p_config: GuardConfig) -> void:
	assert(p_config != null, "Guard needs a GuardConfig")
	config = p_config
	_window = config.parry_window_frames


## Guard button pressed on `frame`.
func press(frame: int) -> void:
	var mashed: bool = _press_frame != NEVER and frame - _press_frame <= config.mash_frames
	if mashed:
		_window = maxi(config.min_parry_window_frames, _window - config.mash_penalty_frames)
	else:
		_window = config.parry_window_frames
	_press_frame = frame
	_parry_cancelled = false
	is_held = true


## Guard button released by the player. The parry window stays open (tap to parry).
func release() -> void:
	is_held = false


## Guard forced down (form without guard, attack, dodge, heal, stagger, death): drops the
## block AND closes the parry window of the last press. Mash tracking is kept.
func cancel() -> void:
	is_held = false
	_parry_cancelled = true


## True if a hit landing on `frame` would be a parry: guard pressed within the window
## before it (the press frame itself counts as frame 0) and not cancelled since.
## Holding is not required.
func is_parry_active(frame: int) -> bool:
	if _parry_cancelled:
		return false
	var age: int = frame - _press_frame
	return age >= 0 and age < _window


## The parry window the current press got, in frames (shrinks when mashing).
func current_window() -> int:
	return _window


## Frames since guard was last pressed, or -1 if it never was.
func frames_since_press(frame: int) -> int:
	return -1 if _press_frame == NEVER else frame - _press_frame
