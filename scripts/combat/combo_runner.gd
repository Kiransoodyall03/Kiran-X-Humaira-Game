class_name ComboRunner
extends RefCounted
## Frame-stepped light-combo state machine for the heroine. Pure logic (no scene), so
## timing and buffering are unit-tested in tests/unit/combo_runner_test.gd.
##
## Per physics tick the owner calls step_frame() first, then press() if attack was just
## pressed, then checks is_active() to run the hit query.
##
## Swing timing: the press tick is swing frame 1. Frames 1..startup are STARTUP, the next
## `active` frames are ACTIVE, the next `recovery` frames are RECOVERY. A buffered press
## starts the next step on the tick after the last recovery frame (exactly
## AttackData.total_frames() after the previous swing started).
##
## Form switching: the form can change at any time. A switch during RECOVERY cancels the
## rest of it. A switch during STARTUP/ACTIVE lets the swing land with its old data, then
## cancels its recovery the moment it starts. Either way the next combo step comes from
## the new form's combo.

enum Phase { IDLE, STARTUP, ACTIVE, RECOVERY }

signal swing_started(attack: AttackData, step: int)
## `cancelled` is true for cancel() (stagger, guard), false when the swing ran out or a
## form switch cut its recovery.
signal swing_ended(attack: AttackData, cancelled: bool)

## Current form; set through switch_form().
var form: FormConfig
## The swing in progress, or null when idle.
var attack: AttackData
## Combo index of the swing in progress (or the last one).
var step: int = -1
## 1-based frame of the swing in progress, 0 when idle.
var swing_frame: int = 0
## An attack press is waiting to start the next step.
var buffered: bool = false
## The form the swing in progress came from.
var _swing_form: FormConfig
var _next_step: int = 0
var _window_left: int = 0


func _init(p_form: FormConfig) -> void:
	assert(p_form != null, "ComboRunner needs a FormConfig")
	form = p_form


func phase() -> Phase:
	if attack == null:
		return Phase.IDLE
	if swing_frame <= attack.startup_frames:
		return Phase.STARTUP
	if swing_frame <= attack.startup_frames + attack.active_frames:
		return Phase.ACTIVE
	return Phase.RECOVERY


func is_busy() -> bool:
	return attack != null


func is_active() -> bool:
	return phase() == Phase.ACTIVE


## The combo index the next started swing will use.
func next_step() -> int:
	return _next_step


## Frames left in which an attack still continues the combo after a swing ended.
func combo_window_left() -> int:
	return _window_left


## Attack pressed this tick. Idle: starts the next step now. ACTIVE/RECOVERY: buffers it.
## STARTUP: ignored. Returns true if a swing started or the press was buffered.
func press() -> bool:
	match phase():
		Phase.IDLE:
			return _start(_next_step)
		Phase.STARTUP:
			return false
		_:
			buffered = true
			return true


## Advances one physics frame.
func step_frame() -> void:
	if attack == null:
		if _window_left > 0:
			_window_left -= 1
			if _window_left == 0:
				_next_step = 0
		return
	var was: Phase = phase()
	swing_frame += 1
	if swing_frame > attack.total_frames():
		_finish()
	elif _swing_form != form and was != Phase.RECOVERY and phase() == Phase.RECOVERY:
		_finish() # switched forms mid-swing: the hit landed, now cancel its recovery


## Changes form. See the class notes for what happens to a swing in progress.
func switch_form(new_form: FormConfig) -> void:
	assert(new_form != null)
	if new_form == form:
		return
	form = new_form
	_next_step = _wrap(_next_step)
	if attack != null and phase() == Phase.RECOVERY:
		_finish()


## Stops the swing at once and resets the combo (stagger, death, guard cancel).
func cancel() -> void:
	var stopped: AttackData = attack
	attack = null
	swing_frame = 0
	buffered = false
	_next_step = 0
	_window_left = 0
	if stopped != null:
		swing_ended.emit(stopped, true)


func _start(index: int) -> bool:
	if form.light_combo.is_empty():
		return false
	step = _wrap(index)
	attack = form.light_combo[step]
	_swing_form = form
	swing_frame = 1
	buffered = false
	_window_left = 0
	swing_started.emit(attack, step)
	return true


func _finish() -> void:
	var done: AttackData = attack
	attack = null
	swing_frame = 0
	_next_step = _wrap(step + 1)
	swing_ended.emit(done, false)
	if buffered:
		_start(_next_step)
	else:
		_window_left = form.combo_window_frames
		if _window_left <= 0:
			_next_step = 0


func _wrap(index: int) -> int:
	var size: int = form.light_combo.size()
	return 0 if size == 0 else posmod(index, size)
