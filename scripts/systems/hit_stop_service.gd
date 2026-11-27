class_name HitStopService
extends Node
## Hit-stop: a short freeze on parries, landed hits, posture breaks and deathblows.
## Registered as the autoload "HitStop" (project.godot). Gameplay code calls
## HitStopService.trigger(kind); without the autoload (e.g. a bare unit test) it does nothing.
##
## A freeze lowers Engine.time_scale and restores it from a SceneTreeTimer that ignores
## time scale and runs while paused, so it lasts real milliseconds. Overlapping requests
## extend the freeze to whichever ends last; they never stack. The previous time_scale
## is put back when the freeze ends, when the scene changes and when this node leaves
## the tree, so a freeze can never be left stuck on.
##
## Godot keeps ticking physics at 60 Hz whatever Engine.time_scale is (only the delta is
## scaled), so frame-counted combat timing needs its own clock: combat_frame() is the
## physics frame count minus every frame spent frozen. Combatant.current_frame() uses it,
## and per-tick frame counters (stagger, combos, enemy phases) skip ticks while
## is_frozen() is true, so all combat timing pauses for exactly the freeze.

enum Kind { PARRY, HIT, POSTURE_BREAK, DEATHBLOW }

const AUTOLOAD_PATH: NodePath = ^"/root/HitStop"
const DEFAULT_CONFIG: String = "res://data/combat/hitstop.tres"

signal started(kind: Kind, duration_ms: int)
signal ended

@export var config: HitStopConfig

## The freeze state is global, like Engine.time_scale itself.
static var _frozen: bool = false
## Physics frame on which the freeze started; ticks after it are frozen.
static var _freeze_start_frame: int = 0
## Physics frames spent frozen by all earlier freezes.
static var _frozen_frames_total: int = 0
## Real time (Time.get_ticks_usec) at which the current freeze ends.
static var _end_usec: int = 0
static var _saved_time_scale: float = 1.0
## Bumped on every freeze start/end so stale timers are ignored.
static var _generation: int = 0
## Instance id of the service whose timer will end the current freeze.
static var _owner_id: int = 0


## The frame number all combat timing uses: physics frames, minus the frozen ones.
## Stays on the freeze's starting frame for as long as a freeze lasts.
static func combat_frame() -> int:
	var physics: int = Engine.get_physics_frames()
	if _frozen:
		physics = mini(physics, _freeze_start_frame)
	return physics - _frozen_frames_total


## True on physics ticks inside a freeze (from the tick after the request on). Per-tick
## combat counters skip these ticks. The requesting tick itself runs normally, so every
## node sees the same frame.
static func is_frozen() -> bool:
	return _frozen and Engine.get_physics_frames() > _freeze_start_frame


## True from the request until the freeze ends (also on the requesting tick).
static func is_active() -> bool:
	return _frozen


## Real time (Time.get_ticks_usec) the current freeze ends at, or 0 when not frozen.
static func end_usec() -> int:
	return _end_usec if _frozen else 0


## Asks the "HitStop" autoload for a freeze of the given kind. No-op without it.
static func trigger(kind: Kind) -> void:
	var service: HitStopService = instance()
	if service != null:
		service.request(kind)


## The autoload, or null.
static func instance() -> HitStopService:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(AUTOLOAD_PATH) as HitStopService


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config == null:
		config = load(DEFAULT_CONFIG) as HitStopConfig
	get_tree().scene_changed.connect(end_now)


func _exit_tree() -> void:
	if _frozen and _owner_id == get_instance_id():
		end_now() # its timer dies with it: never leave the game slowed down


## Freezes for the duration configured for `kind`.
func request(kind: Kind) -> void:
	if config == null or not config.enabled:
		return
	if freeze_ms(config.duration_ms(kind), config.time_scale):
		started.emit(kind, config.duration_ms(kind))


## Freezes for `ms` real milliseconds at `time_scale`. If a freeze is already running it
## is extended to end at the later of the two end times (never added on top), and the
## lower time scale wins. Returns true if a freeze is now running.
func freeze_ms(ms: int, time_scale: float = 0.05) -> bool:
	if ms <= 0 or not is_inside_tree():
		return false
	var end: int = Time.get_ticks_usec() + ms * 1000
	if _frozen:
		if end > _end_usec:
			_end_usec = end
		Engine.time_scale = minf(Engine.time_scale, time_scale)
		return true
	_frozen = true
	_generation += 1
	_freeze_start_frame = Engine.get_physics_frames()
	_end_usec = end
	_saved_time_scale = Engine.time_scale
	_owner_id = get_instance_id()
	Engine.time_scale = time_scale
	_schedule(_generation)
	return true


## Ends any freeze at once and restores the time scale.
func end_now() -> void:
	if not _frozen:
		return
	_frozen = false
	_generation += 1
	_frozen_frames_total += maxi(Engine.get_physics_frames() - _freeze_start_frame, 0)
	_end_usec = 0
	Engine.time_scale = _saved_time_scale if _saved_time_scale > 0.0 else 1.0
	ended.emit()


func _schedule(generation: int) -> void:
	var left_sec: float = maxf(float(_end_usec - Time.get_ticks_usec()) / 1_000_000.0, 0.001)
	# process_always, not in physics, ignore_time_scale: real time even while frozen/paused.
	get_tree().create_timer(left_sec, true, false, true).timeout.connect(_on_timer.bind(generation))


func _on_timer(generation: int) -> void:
	if generation != _generation or not _frozen:
		return # a stale timer from an earlier freeze
	if Time.get_ticks_usec() < _end_usec:
		_schedule(generation) # extended meanwhile
	else:
		end_now()
