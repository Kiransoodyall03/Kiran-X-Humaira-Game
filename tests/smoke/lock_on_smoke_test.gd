extends SceneTree
## Headless lock-on smoke test in the sandbox, using the real input actions.
## lock_on locks the training dummy's LockOnPoint; the camera turns to it and the heroine
## turns to face it; sideways input strafes while she keeps facing it; a swing started
## facing away is aimed at it; the HUD shows the lock marker over it. Cycling (mouse wheel
## action, then right-stick flicks) goes dummy -> a test monster's best part -> the
## monster's other part -> back to the dummy, and the camera pulls back for the big
## monster; the Right arrow key (also bound to camera_right) does not switch. The camera
## pitch settles on the lock pitch. Disabling a locked part falls back to the other part,
## then breaks (POINT_GONE); sprinting faces the run direction; the marker hides when the
## point is behind the camera. The lock breaks when the target leaves range, when line of
## sight is blocked lost_sight_frames combat frames in a row (the count pauses in
## hit-stop), when she dies and when the target dies; lock_on again toggles it off.
## Defeated or staggered she can't pick up a lock and doesn't turn to one.
## Fails on any engine/script error, and on a frame-budget timeout instead of hanging.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/lock_on_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
const MAX_RUN_FRAMES: int = 6000
## Frames given to the camera / facing to settle on a target.
const SETTLE_FRAMES: int = 60

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _level: Node
var _player: PlayerController
var _combat: PlayerCombat
var _lock: LockOn
var _camera: ThirdPersonCamera
var _dummy: TrainingDummy
var _dummy_c: Combatant
var _dummy_point: LockOnPoint
var _hud: CombatHud
var _breaks: Array[LockOn.BreakReason] = []
var _swing_facing_error_degrees: float = -1.0
var _hud_refreshes: int = 0


func _initialize() -> void:
	OS.add_logger(_errors)
	physics_frame.connect(_watchdog)
	_run.call_deferred()


func _run() -> void:
	_level = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(_level)
	_player = _level.get_node("Heroine") as PlayerController
	_combat = _player.combat
	_lock = _player.get_node("LockOn") as LockOn
	_camera = _player.camera_rig
	_dummy = _level.get_node("TrainingDummy") as TrainingDummy
	_dummy_c = _dummy.get_combatant()
	_dummy_point = _dummy.get_node("LockOnPoint") as LockOnPoint
	_hud = _level.get_node("CombatHud") as CombatHud
	_dummy.attacking_enabled = false
	_lock.unlocked.connect(func(reason: LockOn.BreakReason) -> void: _breaks.append(reason))
	_combat.attack_started.connect(_on_attack_started)

	_expect(_player.lock_on == _lock, "the heroine's controller uses her LockOn")
	_expect(_dummy_point != null and _dummy_point.combatant == _dummy_c, "the dummy has a LockOnPoint owned by its Combatant")
	_expect(_lock.config != null and _lock.config.resource_path == "res://data/combat/lock_on.tres",
			"lock-on tuning comes from data/combat/lock_on.tres")
	await _physics_frames(10)

	await _test_lock_turns_camera_and_facing()
	await _test_strafe_and_attack_aim()
	await _test_toggle_off()
	await _test_cycling_and_framing()
	await _test_part_fallback()
	await _test_sprint_faces_run_direction()
	await _test_marker_hidden_behind_camera()
	await _test_break_out_of_range()
	await _test_break_line_of_sight()
	await _test_break_on_self_death()
	await _test_break_on_death()
	await _test_yaw_holds_overhead()
	await _test_hud_survives_freed_opponent() # last: frees the dummy
	_finish()


func _test_lock_turns_camera_and_facing() -> void:
	await _setup_view(25.0)
	_expect(not _lock.is_locked(), "not locked at the start")
	await _hud_refresh()
	_expect(not _hud.lock_marker_visible(), "no lock marker before locking")
	_camera.add_look(0.0, 80.0) # pitch far off too (clamped to the camera's limit)
	var yaw_error_before: float = _camera_yaw_error()
	_expect(yaw_error_before > 15.0, "the camera starts off the dummy (%.1f°)" % yaw_error_before)
	var pitch_error_before: float = _camera_pitch_error()
	_expect(pitch_error_before > 15.0, "the camera pitch starts off the lock pitch (%.1f°)" % pitch_error_before)
	await _tap(&"lock_on")
	_expect(_lock.is_locked() and _lock.current_point() == _dummy_point, "lock_on locks the dummy's point")
	await _physics_frames(SETTLE_FRAMES)
	_expect(_camera.is_tracking(), "the camera tracks the locked point")
	_expect(_camera_yaw_error() < 3.0, "the camera turned to the dummy (yaw error %.1f°)" % _camera_yaw_error())
	_expect(_camera_pitch_error() < 2.0, "the camera pitched to the dummy (pitch %.1f°, error %.1f°)"
			% [rad_to_deg(_camera.get_view_pitch()), _camera_pitch_error()])
	_expect(_facing_error() < 5.0, "the heroine turned to face the dummy (error %.1f°)" % _facing_error())
	await _hud_refresh()
	_expect(_hud.lock_marker_visible(), "HUD shows the lock marker")
	var cam: Camera3D = _camera.get_camera()
	var projected: Vector2 = cam.unproject_position(_dummy_point.global_position)
	_expect(_hud.lock_marker_screen_position().distance_to(projected) < 2.0,
			"the marker sits on the projected point (%s vs %s)" % [_hud.lock_marker_screen_position(), projected])
	var width: float = cam.get_viewport().get_visible_rect().size.x
	_expect(absf(projected.x - width * 0.5) < width * 0.1, "…which is near the screen centre (x %.0f of %.0f)" % [projected.x, width])
	_expect(_hud.lock_marker_text() == "body", "the marker names the part (%s)" % _hud.lock_marker_text())


func _test_strafe_and_attack_aim() -> void:
	var start: Vector3 = _player.global_position
	var to_target: Vector3 = _flat(_dummy.global_position - start).normalized()
	Input.action_press(&"move_right")
	await _physics_frames(40)
	_expect(_facing_error() < 15.0, "strafing right she keeps facing the dummy (error %.1f°)" % _facing_error())
	Input.action_release(&"move_right")
	var moved: Vector3 = _flat(_player.global_position - start)
	var sideways: float = moved.cross(to_target).length()
	_expect(sideways > 1.0 and absf(moved.dot(to_target)) < sideways * 0.5,
			"camera-relative right input strafes sideways (sideways %.2f m, toward %.2f m)" % [sideways, moved.dot(to_target)])
	await _physics_frames(20)

	# A swing started while facing away is aimed at the locked target.
	_player.set_facing_direction(-_flat(_dummy.global_position - _player.global_position))
	_swing_facing_error_degrees = -1.0
	await _tap(&"attack")
	_expect(_swing_facing_error_degrees >= 0.0 and _swing_facing_error_degrees < 2.0,
			"the swing starts aimed at the target (error %.1f°)" % _swing_facing_error_degrees)
	await _wait_idle()


func _test_toggle_off() -> void:
	await _tap(&"lock_on")
	_expect(not _lock.is_locked(), "lock_on again unlocks")
	_expect(_breaks.size() == 1 and _breaks[0] == LockOn.BreakReason.MANUAL, "…as a manual unlock (%s)" % [_breaks])
	_expect(not _camera.is_tracking(), "the camera stops tracking")
	await _physics_frames(2)
	await _hud_refresh()
	_expect(not _hud.lock_marker_visible(), "the lock marker is gone")


## A big test monster with two parts to the right of the dummy.
func _test_cycling_and_framing() -> void:
	var monster: Node3D = Node3D.new()
	monster.name = "TestMonster"
	_level.add_child(monster)
	monster.global_position = _dummy.global_position + Vector3(4.0, 0.0, 0.0)
	var body_point: LockOnPoint = _add_point(monster, &"body", Vector3(0.0, 2.0, 0.0), 1, 8.0)
	var head_point: LockOnPoint = _add_point(monster, &"head", Vector3(0.6, 4.0, 0.0), 0, 8.0)
	await _setup_view(0.0)
	await _tap(&"lock_on")
	_expect(_lock.current_point() == _dummy_point, "lock_on picks the dummy at the screen centre")
	await _physics_frames(SETTLE_FRAMES)
	var base_distance: float = _camera.get_goal_distance()

	await _tap(&"lock_cycle_next")
	_expect(_lock.current_point() == body_point, "cycle next: the monster to the right, on its best part (%s)" % _point_name())
	await _physics_frames(SETTLE_FRAMES * 2)
	var pullback: float = _lock.config.pullback_for(8.0)
	_expect(pullback > 1.0 and _camera.get_goal_distance() > base_distance + pullback * 0.8,
			"the camera pulls back for the big monster (%.2f -> %.2f m)" % [base_distance, _camera.get_goal_distance()])
	_expect(_camera_yaw_error() < 3.0, "the camera turned to the monster (yaw error %.1f°)" % _camera_yaw_error())

	# Right-stick flicks: one switch per flick, a held stick doesn't repeat.
	_stick(1.0)
	await _physics_frames(20)
	_expect(_lock.current_point() == head_point, "a right-stick flick switches to the monster's other part first (%s)" % _point_name())
	_stick(0.0)
	await _physics_frames(3)
	_stick(1.0)
	await _physics_frames(3)
	_stick(0.0)
	_expect(_lock.current_point() == _dummy_point, "another flick moves on to the next target, the dummy (%s)" % _point_name())
	# The Right arrow key is bound to camera_right too, but only the stick flicks.
	await _physics_frames(3)
	_key(KEY_RIGHT, true)
	await _physics_frames(10)
	_key(KEY_RIGHT, false)
	await _physics_frames(2)
	_expect(_lock.current_point() == _dummy_point, "the Right arrow key doesn't switch target (%s)" % _point_name())
	await _physics_frames(SETTLE_FRAMES * 2)
	_expect(_camera.get_goal_distance() < base_distance + 0.2, "the camera comes back in for the small dummy (%.2f m)" % _camera.get_goal_distance())

	await _tap(&"lock_cycle_prev")
	_expect(_lock.current_point() == body_point, "cycle prev wraps round to the monster (%s)" % _point_name())
	_lock.unlock()
	monster.queue_free()
	await _physics_frames(2)
	_breaks.clear()


## Disabling a locked part hands the lock to the target's other part; disabling the last
## part breaks it (POINT_GONE).
func _test_part_fallback() -> void:
	var monster: Node3D = Node3D.new()
	monster.name = "FallbackMonster"
	_level.add_child(monster)
	monster.global_position = _dummy.global_position + Vector3(3.0, 0.0, 0.0)
	var body_point: LockOnPoint = _add_point(monster, &"body", Vector3(0.0, 2.0, 0.0), 1, 6.0)
	var head_point: LockOnPoint = _add_point(monster, &"head", Vector3(0.5, 3.5, 0.0), 0, 6.0)
	await _setup_view(0.0)
	_lock.lock_onto(body_point)
	await _physics_frames(3)
	_expect(_lock.current_point() == body_point, "locked the fallback monster's body")
	body_point.enabled = false
	await _physics_frames(3)
	_expect(_lock.is_locked() and _lock.current_point() == head_point,
			"disabling the locked part moves the lock to the other part (%s)" % _point_name())
	_expect(_breaks.is_empty(), "…without an unlock (%s)" % [_breaks])
	head_point.enabled = false
	await _physics_frames(3)
	_expect(not _lock.is_locked(), "disabling the last part breaks the lock")
	_expect(_breaks.size() == 1 and _breaks[0] == LockOn.BreakReason.POINT_GONE, "…for POINT_GONE (%s)" % [_breaks])
	monster.queue_free()
	await _physics_frames(2)
	_breaks.clear()


## Sprinting while locked faces the run direction; letting go turns her back to the target.
func _test_sprint_faces_run_direction() -> void:
	await _setup_view(0.0)
	await _tap(&"lock_on")
	await _physics_frames(SETTLE_FRAMES)
	_expect(_lock.is_locked() and _facing_error() < 5.0, "locked and facing the dummy before sprinting")
	Input.action_press(&"move_back")
	Input.action_press(&"sprint")
	await _physics_frames(30)
	var sprint_error: float = _facing_error()
	Input.action_release(&"sprint")
	Input.action_release(&"move_back")
	_expect(_lock.is_locked(), "still locked while sprinting away")
	_expect(sprint_error > 150.0, "sprinting away she faces the run direction (%.1f° off the target)" % sprint_error)
	await _physics_frames(SETTLE_FRAMES)
	_expect(_facing_error() < 5.0, "after the sprint she turns back to the target (error %.1f°)" % _facing_error())
	_lock.unlock()
	await _physics_frames(2)
	_breaks.clear()


## The marker is only drawn when the point is in front of the camera.
func _test_marker_hidden_behind_camera() -> void:
	await _setup_view(0.0)
	await _tap(&"lock_on")
	await _physics_frames(5)
	await _hud_refresh()
	_expect(_hud.lock_marker_visible(), "marker visible with the point in view")
	_camera.release_lock() # stop tracking so the view can be turned away
	_camera.set_view_yaw(_camera.get_view_yaw() + PI)
	await _physics_frames(3)
	# The rig turns in its _process; the HUD's runs after it, so this also waits for the turn.
	await _hud_refresh()
	_expect(_lock.is_locked() and _camera.get_camera().is_position_behind(_dummy_point.global_position),
			"still locked with the point behind the camera")
	_expect(not _hud.lock_marker_visible(), "no marker for a point behind the camera")
	_lock.unlock()
	await _physics_frames(2)
	_breaks.clear()


func _test_break_out_of_range() -> void:
	await _setup_view(0.0)
	await _tap(&"lock_on")
	_expect(_lock.is_locked(), "locked for the range test")
	_place(_dummy.global_position + Vector3(0.0, 0.0, _lock.config.break_range - 2.0))
	await _physics_frames(5)
	_expect(_lock.is_locked(), "still locked just inside break range")
	_place(_dummy.global_position + Vector3(0.0, 0.0, _lock.config.break_range + 3.0))
	await _physics_frames(3)
	_expect(not _lock.is_locked(), "the lock breaks out of range")
	_expect(_breaks.size() == 1 and _breaks[0] == LockOn.BreakReason.OUT_OF_RANGE, "…for OUT_OF_RANGE (%s)" % [_breaks])
	_breaks.clear()


func _test_break_line_of_sight() -> void:
	await _setup_view(0.0)
	await _tap(&"lock_on")
	_expect(_lock.is_locked(), "locked for the line-of-sight test")
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = 1
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(4.0, 5.0, 0.5)
	shape.shape = box
	wall.add_child(shape)
	_level.add_child(wall)
	wall.global_position = (_dummy.global_position + _player.global_position) * 0.5 + Vector3.UP * 2.5
	var limit: int = _lock.config.lost_sight_frames
	for i: int in 30:
		if _lock.blocked_frames() > 0:
			break
		await physics_frame
	await _physics_frames(5)
	_expect(_lock.is_locked() and _lock.blocked_frames() > 0, "briefly out of sight the lock holds (%d frames blocked)" % _lock.blocked_frames())

	# Hit-stop pauses the sight timer with the combat clock.
	var service: HitStopService = HitStopService.instance()
	_expect(service != null, "the HitStop autoload is running")
	if service != null:
		service.freeze_ms(10000)
		await _physics_frames(2)
		var frozen_at: int = _lock.blocked_frames()
		await _physics_frames(20)
		_expect(_lock.is_locked() and _lock.blocked_frames() == frozen_at,
				"during hit-stop the blocked count doesn't rise (%d -> %d)" % [frozen_at, _lock.blocked_frames()])
		service.end_now()

	# Watch every blocked frame up to the break: it holds through limit - 1, breaks on limit.
	var last_blocked: int = -1
	var steady: bool = true
	var previous: int = _lock.blocked_frames()
	for i: int in limit * 2 + 60:
		if not _lock.is_locked():
			break
		var b: int = _lock.blocked_frames()
		if b < previous or b > previous + 1:
			steady = false
		previous = b
		last_blocked = b
		await physics_frame
	_expect(steady, "the blocked count rises one combat frame at a time")
	_expect(not _lock.is_locked(), "the lock breaks out of sight")
	_expect(last_blocked == limit - 1, "it holds through %d blocked frames and breaks on frame %d (last held: %d)"
			% [limit - 1, limit, last_blocked])
	_expect(_breaks.size() == 1 and _breaks[0] == LockOn.BreakReason.LOST_SIGHT, "…for LOST_SIGHT (%s)" % [_breaks])
	wall.queue_free()
	await _physics_frames(2)
	_breaks.clear()


func _test_break_on_self_death() -> void:
	await _setup_view(0.0)
	await _tap(&"lock_on")
	_expect(_lock.is_locked(), "locked for the self-defeat test")
	var me: Combatant = _player.combatant
	var big: AttackData = AttackData.new()
	big.id = &"test_big_hit_on_heroine"
	big.damage = 10000.0
	for i: int in 10:
		if me.is_dead:
			break
		me.receive_attack(big, _dummy_c)
		me.receive_deathblow(_dummy_c)
	_expect(me.is_dead, "the heroine is defeated")
	await _physics_frames(2)
	_expect(not _lock.is_locked(), "the lock breaks when she dies")
	_expect(_breaks.size() == 1 and _breaks[0] == LockOn.BreakReason.SELF_DEFEATED, "…for SELF_DEFEATED (%s)" % [_breaks])

	# Defeated, she can't lock again, and a lock held anyway doesn't turn her.
	_player.set_facing_direction(Vector3.BACK)
	await _tap(&"lock_on")
	await _physics_frames(2)
	_expect(me.is_dead, "still defeated for the dead lock_on press")
	_expect(not _lock.is_locked(), "a defeated heroine can't lock on")
	_expect(not _camera.is_tracking(), "…and the camera doesn't track anything")
	_lock.lock_onto(_dummy_point) # scripted lock: she still must not turn
	await _physics_frames(SETTLE_FRAMES)
	_expect(me.is_dead, "still defeated while locked by script")
	_expect(not _player.is_facing_lock_target(), "a defeated heroine doesn't face the lock target")
	_expect(_facing_error() > 150.0, "…and her body doesn't turn to it (%.1f° off)" % _facing_error())
	_lock.unlock()
	me.revive()
	await _wait_hit_stop_over()
	await _physics_frames(5)
	_breaks.clear()

	# Staggered (unable to act), the same holds.
	await _setup_view(0.0)
	_expect(me.stagger(SETTLE_FRAMES * 2), "the heroine is staggered")
	await _tap(&"lock_on")
	_expect(me.is_staggered() and not _lock.is_locked(), "a staggered heroine can't lock on")
	_lock.lock_onto(_dummy_point)
	await _physics_frames(20)
	_expect(me.is_staggered(), "still staggered while locked by script")
	_expect(_facing_error() > 150.0, "a staggered heroine doesn't turn to the lock target (%.1f° off)" % _facing_error())
	await _combat_frames(SETTLE_FRAMES * 2)
	_expect(me.can_act(), "the stagger ends")
	await _physics_frames(SETTLE_FRAMES)
	_expect(_facing_error() < 5.0, "once she can act she turns to the lock target again (error %.1f°)" % _facing_error())
	_lock.unlock()
	await _physics_frames(2)
	_breaks.clear()


func _test_break_on_death() -> void:
	await _setup_view(0.0)
	await _tap(&"lock_on")
	_expect(_lock.is_locked(), "locked for the death test")
	var big: AttackData = AttackData.new()
	big.id = &"test_big_hit"
	big.damage = 10000.0
	_dummy_c.receive_attack(big, _player.combatant)
	_dummy_c.receive_deathblow(_player.combatant)
	await _physics_frames(3)
	_expect(not _dummy_c.is_dead and _lock.is_locked(), "a deathblow with a life left keeps the lock")
	_dummy_c.receive_attack(big, _player.combatant)
	_dummy_c.receive_deathblow(_player.combatant)
	_expect(_dummy_c.is_dead, "the second deathblow kills the dummy")
	await _physics_frames(3)
	_expect(not _lock.is_locked(), "the lock breaks when the target dies")
	_expect(_breaks.size() == 1 and _breaks[0] == LockOn.BreakReason.TARGET_DIED, "…for TARGET_DIED (%s)" % [_breaks])
	_expect(not _camera.is_tracking(), "the camera stops tracking")
	await _tap(&"lock_on")
	_expect(not _lock.is_locked(), "a dead target can't be locked")
	await _wait_hit_stop_over()


## A locked point passing over her (0.4 m in front of the rig to 0.4 m behind, 1 m up)
## must not swing the camera round: inside hold_yaw_within the yaw is held.
func _test_yaw_holds_overhead() -> void:
	await _wait_hit_stop_over()
	await _setup_view(0.0)
	var holder: Node3D = Node3D.new()
	holder.name = "OverheadTarget"
	_level.add_child(holder)
	var point: LockOnPoint = _add_point(holder, &"body", Vector3.ZERO, 0, 1.0)
	var yaw0: float = _camera.get_view_yaw()
	var forward: Vector3 = Vector3(-sin(yaw0), 0.0, -cos(yaw0))
	holder.global_position = _camera.global_position + forward * 0.4 + Vector3.UP
	_lock.lock_onto(point)
	var worst: float = 0.0
	for i: int in 31:
		var along: float = lerpf(0.4, -0.4, minf(i / 18.0, 1.0))
		holder.global_position = _camera.global_position + forward * along + Vector3.UP
		await process_frame
		worst = maxf(worst, rad_to_deg(absf(angle_difference(_camera.get_view_yaw(), yaw0))))
	_expect(_lock.is_locked() and _lock.current_point() == point, "locked on the point passing overhead")
	_expect(worst < 5.0, "the camera holds its yaw while the point passes overhead (swung %.1f°)" % worst)
	_lock.unlock()
	holder.queue_free()
	await _physics_frames(2)
	_breaks.clear()


## The HUD never hands back a freed opponent: free the enemy it shows, locked and then
## unlocked, with no other enemy around; no script error and it keeps refreshing.
func _test_hud_survives_freed_opponent() -> void:
	var rules: SandboxRules = _level.get_node("SandboxRules") as SandboxRules
	for i: int in 600: # let SandboxRules revive the dummy first, so it never touches it freed
		if rules.frames_until_revive(_dummy_c) < 0:
			break
		await physics_frame
	_expect(not _dummy_c.is_dead, "the dummy is back up for the freed-opponent test")
	for node: Node in get_nodes_in_group(CorruptionMeter.HOSTILE_GROUP):
		if node != _dummy:
			node.remove_from_group(CorruptionMeter.HOSTILE_GROUP)
	_hud.refreshed.connect(func() -> void: _hud_refreshes += 1)
	var errors_before: int = _errors.errors

	# Locked on it.
	await _setup_view(0.0)
	await _tap(&"lock_on")
	await _hud_refresh()
	_expect(_lock.is_locked() and _hud.current_opponent() == _dummy_c, "the HUD shows the locked dummy")
	var dummy_scene: String = _dummy.scene_file_path
	_dummy.queue_free()
	_hud_refreshes = 0
	await _physics_frames(20)
	_expect(not _lock.is_locked(), "freeing the locked dummy ends the lock")
	_expect(_hud_refreshes >= 10, "the HUD keeps refreshing after its locked opponent is freed (%d)" % _hud_refreshes)
	_expect(_hud.current_opponent() == null, "…and shows no opponent")

	# Unlocked: a second dummy, the only enemy, then freed.
	var spare: TrainingDummy = (load(dummy_scene) as PackedScene).instantiate() as TrainingDummy
	spare.name = "SpareDummy"
	spare.attacking_enabled = false
	_level.add_child(spare)
	spare.global_position = _player.global_position + Vector3(0.0, 0.0, -6.0)
	await _physics_frames(2)
	await _hud_refresh()
	_expect(_hud.current_opponent() == spare.get_combatant(), "unlocked, the HUD shows the nearest enemy")
	spare.queue_free()
	_hud_refreshes = 0
	await _physics_frames(20)
	_expect(_hud_refreshes >= 10, "the HUD keeps refreshing after its unlocked opponent is freed (%d)" % _hud_refreshes)
	_expect(_hud.current_opponent() == null, "…and shows no opponent")
	_expect(_errors.errors == errors_before, "no script errors from freed opponents (%d; first: %s)"
			% [_errors.errors - errors_before, _errors.first_error])


func _on_attack_started(_attack: AttackData, _step: int) -> void:
	if _lock.is_locked():
		_swing_facing_error_degrees = rad_to_deg(_player.get_facing_direction().angle_to(_lock.direction_to_target()))


func _add_point(parent: Node3D, part: StringName, offset: Vector3, priority: int, size: float) -> LockOnPoint:
	var p: LockOnPoint = LockOnPoint.new()
	p.name = String(part)
	p.part_id = part
	p.priority = priority
	p.target_size = size
	parent.add_child(p)
	p.position = offset
	return p


## Stands her 6 m in front (+Z) of the dummy facing away, camera `offset_degrees` off it.
func _setup_view(offset_degrees: float) -> void:
	if _lock.is_locked():
		_lock.unlock()
	_place(_dummy.global_position + Vector3(0.0, 0.0, 6.0))
	_player.set_facing_direction(Vector3.BACK)
	var to: Vector3 = _dummy_point.global_position - _player.global_position
	_camera.set_view_yaw(atan2(-to.x, -to.z) + deg_to_rad(offset_degrees))
	await _physics_frames(30)
	_breaks.clear()


## Sends a right-stick x value as a real joypad event.
func _stick(x: float) -> void:
	var e: InputEventJoypadMotion = InputEventJoypadMotion.new()
	e.device = 0
	e.axis = JOY_AXIS_RIGHT_X
	e.axis_value = x
	Input.parse_input_event(e)


func _key(keycode: Key, pressed: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	Input.parse_input_event(e)


func _place(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _camera_yaw_error() -> float:
	var to: Vector3 = _lock.target_position() if _lock.is_locked() else _dummy_point.global_position
	to -= _camera.global_position
	var desired: float = atan2(-to.x, -to.z)
	return rad_to_deg(absf(angle_difference(_camera.get_view_yaw(), desired)))


## Degrees between the camera pitch and the lock pitch it should settle on.
func _camera_pitch_error() -> float:
	var cfg: LockOnConfig = _lock.config
	var to: Vector3 = _dummy_point.global_position - _camera.global_position
	var flat: float = Vector2(to.x, to.z).length()
	var desired: float = rad_to_deg(atan2(to.y, maxf(flat, 0.1))) + cfg.pitch_offset_degrees
	desired = clampf(desired, maxf(cfg.min_pitch_degrees, _camera.config.min_pitch_degrees),
			minf(cfg.max_pitch_degrees, _camera.config.max_pitch_degrees))
	return absf(rad_to_deg(_camera.get_view_pitch()) - desired)


func _facing_error() -> float:
	var to: Vector3 = _flat(_lock.target_position() - _player.global_position).normalized()
	return rad_to_deg(_player.get_facing_direction().angle_to(to))


func _point_name() -> String:
	var p: LockOnPoint = _lock.current_point()
	return "none" if p == null else "%s/%s" % [p.get_parent().name, p.part_id]


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _wait_idle() -> void:
	for i: int in 600:
		if not _combat.is_busy():
			return
		await physics_frame
	_expect(false, "the heroine was idle again within 600 frames")


func _wait_hit_stop_over() -> void:
	for i: int in 600:
		if not HitStopService.is_active():
			return
		await physics_frame
	_expect(false, "hit-stop ended within 600 frames")


func _tap(action: StringName, hold_frames: int = 2) -> void:
	Input.action_press(action)
	await _physics_frames(hold_frames)
	Input.action_release(action)


func _physics_frames(count: int) -> void:
	for i: int in count:
		await physics_frame


## Waits `count` combat frames (physics ticks frozen by hit-stop don't count).
func _combat_frames(count: int) -> void:
	var target: int = Combatant.current_frame() + count
	for i: int in count + 600:
		if Combatant.current_frame() >= target:
			return
		await physics_frame


func _watchdog() -> void:
	_frames_run += 1
	if _frames_run > MAX_RUN_FRAMES and not _finished:
		_expect(false, "finished within %d frames (watchdog)" % MAX_RUN_FRAMES)
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	Input.action_release(&"move_right")
	Input.action_release(&"move_back")
	Input.action_release(&"sprint")
	_stick(0.0)
	_expect(_errors.errors == 0, "no engine/script errors (%d; first: %s)" % [_errors.errors, _errors.first_error])
	print("LOCK-ON SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)


## CombatHud refreshes its widgets in _process, and physics_frame waits don't promise a
## process frame ran after them (several physics ticks can run in one frame). Its
## `refreshed` signal fires at the end of that _process, so a read right after it sees the
## latest physics tick, with no tick (and no camera/body move) in between.
func _hud_refresh() -> void:
	await _hud.refreshed
