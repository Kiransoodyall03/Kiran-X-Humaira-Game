class_name ShortcutGate
extends Node3D
## A one-way shortcut gate (docs/ZONE01.md: "one-way shortcut ... opened from the far
## side"). Greybox scene: scenes/world/shortcut_gate.tscn. The far side is the gate's local
## +Z. Standing in the InteractArea on the far side shows "Open" and interact opens it; on
## the near side (local -Z) the prompt says it opens from the other side and interact does
## nothing. Opening takes ShortcutGateConfig.open_frames: the panel's mesh rises while its
## collision stays where it is (it blocks until fully open), then the collision turns off and NavLink (a NavigationLink3D across the gap, which is baked
## closed into the navmesh) turns on, so agents can path through. Once open it stays open.
## She can't open it while dead, staggered, attacking, dodging or healing.
##
## Expected children: Panel (StaticBody3D with a CollisionShape3D "Shape" and a MeshInstance3D
## "Mesh"), InteractArea
## (Area3D, mask = player layer), NavLink (NavigationLink3D), Prompt/Label (on-screen).

signal opened

enum State { CLOSED, OPENING, OPEN }

const PROMPT_OPEN: String = "Open  ·  E / X"
const PROMPT_LOCKED: String = "Opens from the other side"

@export var config: ShortcutGateConfig
## Starts open (a later save system can restore an opened shortcut).
@export var start_open: bool = false

@onready var _panel: StaticBody3D = $Panel
@onready var _panel_shape: CollisionShape3D = $Panel/Shape
@onready var _panel_mesh: Node3D = $Panel/Mesh
@onready var _area: Area3D = $InteractArea
@onready var _link: NavigationLink3D = $NavLink
@onready var _prompt: Label = $Prompt/Label

var state: State = State.CLOSED
var _opening_frames: int = 0
## The panel mesh's resting local height (only the mesh rises; the body never moves).
var _mesh_base_y: float = 0.0
## The heroine while she stands in the interact area, else null.
var _player: PlayerController


func _ready() -> void:
	assert(config != null, "ShortcutGate needs a ShortcutGateConfig")
	_mesh_base_y = _panel_mesh.position.y
	_prompt.visible = false
	_link.enabled = false
	if start_open:
		_finish_open(false)


func _physics_process(_delta: float) -> void:
	if state == State.OPENING:
		_opening_frames += 1
		var t: float = clampf(float(_opening_frames) / float(maxi(config.open_frames, 1)), 0.0, 1.0)
		_panel_mesh.position.y = _mesh_base_y + config.open_lift * t
		if _opening_frames >= config.open_frames:
			_finish_open(true)
	_player = _find_player()
	_refresh_prompt()
	if state == State.CLOSED and _player != null and Input.is_action_just_pressed(&"interact"):
		try_open()


## Starts opening if can_open(). Returns true if it started.
func try_open() -> bool:
	if not can_open():
		return false
	state = State.OPENING
	_opening_frames = 0
	_refresh_prompt()
	return true


## Closed, and the heroine is in the interact area on the far side and free to act.
func can_open() -> bool:
	return state == State.CLOSED and _player_free() and is_far_side(_player.global_position)


func is_open() -> bool:
	return state == State.OPEN


func is_opening() -> bool:
	return state == State.OPENING


## True if `point` is on the gate's far side (local +Z), the side it opens from.
func is_far_side(point: Vector3) -> bool:
	return to_local(point).z > 0.0


## True while the panel still blocks the way (closed or still opening).
func blocks() -> bool:
	return not _panel_shape.disabled


## True while the navigation link through the gate is on.
func link_enabled() -> bool:
	return _link.enabled


func player_in_range() -> bool:
	return _player != null


func prompt_visible() -> bool:
	return _prompt.visible


func prompt_text() -> String:
	return _prompt.text


func _finish_open(emit: bool) -> void:
	state = State.OPEN
	_panel_mesh.position.y = _mesh_base_y + config.open_lift
	_panel_shape.set_deferred(&"disabled", true)
	_panel.visible = false
	_link.enabled = true
	_refresh_prompt()
	if emit:
		opened.emit()


func _player_free() -> bool:
	if _player == null or _player.is_dead():
		return false
	if _player.combatant != null and not _player.combatant.can_act():
		return false
	return not _player.is_busy() and not _player.is_healing()


func _refresh_prompt() -> void:
	var shown: bool = state == State.CLOSED and _player_free()
	_prompt.visible = shown
	if shown:
		_prompt.text = PROMPT_OPEN if is_far_side(_player.global_position) else PROMPT_LOCKED


func _find_player() -> PlayerController:
	if not _area.monitoring:
		return null
	for b: Node3D in _area.get_overlapping_bodies():
		var player: PlayerController = b as PlayerController
		if player != null:
			return player
	return null
