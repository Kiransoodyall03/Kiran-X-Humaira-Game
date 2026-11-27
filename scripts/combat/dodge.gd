class_name Dodge
extends RefCounted
## Dodge timing: when it runs, which frames are invulnerable and when the next one is
## allowed. Pure logic: callers pass physics frame numbers. The press frame is dodge
## frame 0. The owner applies the i-frames with Combatant.set_invulnerable().

const NEVER: int = -1_000_000

## World direction of the dodge in progress (unit length, on the ground plane).
var direction: Vector3 = Vector3.ZERO
var config: FormConfig
var _start_frame: int = NEVER
var _end_frame: int = NEVER
var _ready_frame: int = NEVER


## Starts a dodge on `frame` using `p_config`'s dodge settings. Returns false (and does
## nothing) if that form can't dodge or the dodge isn't ready yet.
func start(frame: int, p_config: FormConfig, p_direction: Vector3) -> bool:
	if p_config == null or not p_config.can_dodge or not is_ready(frame):
		return false
	config = p_config
	direction = p_direction.normalized()
	_start_frame = frame
	_end_frame = frame + config.dodge_duration_frames
	_ready_frame = _end_frame + config.dodge_cooldown_frames
	return true


## Ends the dodge in progress early (stagger, death). The cooldown still runs from now.
func cancel(frame: int) -> void:
	if not is_dodging(frame):
		return
	_end_frame = frame
	_ready_frame = frame + config.dodge_cooldown_frames


func is_dodging(frame: int) -> bool:
	return frame >= _start_frame and frame < _end_frame


func is_ready(frame: int) -> bool:
	return not is_dodging(frame) and frame >= _ready_frame


## Frames until the next dodge is allowed (0 = ready).
func frames_until_ready(frame: int) -> int:
	return maxi(_ready_frame - frame, 0)


## First invulnerable frame of the dodge that started on `start_frame`.
static func iframe_first(start_frame: int, p_config: FormConfig) -> int:
	return start_frame + p_config.dodge_iframe_start_frames


## The i-frame window of the current dodge as (first frame, frame count).
func iframe_window() -> Vector2i:
	if config == null:
		return Vector2i(NEVER, 0)
	return Vector2i(iframe_first(_start_frame, config), config.dodge_iframe_frames)
