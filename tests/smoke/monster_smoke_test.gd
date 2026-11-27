extends SceneTree
## Headless smoke test for the large monster (monster #1) in the sandbox's monster arena,
## using the real input actions. It waits at home while the heroine is far away; lock-on
## lands on one of its parts and cycles through all of them while the camera pulls back for
## its size; it picks its attack by where she stands round its body (front / side / rear,
## distance) with a tell colour and a long recovery; parrying its swipe builds its posture;
## her swings on a forelimb break that limb, which staggers the whole monster (no deathblow
## window) and weakens (left) or disables (right) its front swipe; locked on its body, her
## greatsword and katana swings from either flank land on the body part; two deathblows kill it
## (2 lives, requires deathblow: the second phase ends at 0 health) and SandboxRules revives
## it at home, whole; with a navmesh it chases along a NavigationAgent3D path; leaving its
## leash sends it home. Fails on any engine/script error, and on a frame-budget timeout.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/monster_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
const SWIPE: StringName = &"monster01_front_swipe"
const SWEEP: StringName = &"monster01_tail_sweep"
const STOMP: StringName = &"monster01_stomp"
const CHARGE: StringName = &"monster01_charge"
const PARTS: Array[StringName] = [&"head", &"left_forelimb", &"right_forelimb", &"tail", &"body"]
## Press guard this many frames before the hit lands (inside the 12-frame window).
const PARRY_LEAD_FRAMES: int = 6
const WAIT_FRAMES: int = 900
const SETTLE_FRAMES: int = 60
const MAX_RUN_FRAMES: int = 30000

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _level: Node
var _player: PlayerController
var _combat: PlayerCombat
var _player_c: Combatant
var _lock: LockOn
var _camera: ThirdPersonCamera
var _hud: CombatHud
var _rules: SandboxRules
var _monster: LargeMonster
var _mc: Combatant
var _config: LargeMonsterConfig
var _broken_parts: Array[StringName] = []
var _deathblows: Array[int] = []
var _breaks: Array[LockOn.BreakReason] = []
## Its facing at the start of the run (home facing).
var _start_forward: Vector3
## Outcomes of its attacks on her.
var _taken: Array[HitResult] = []
## Attack ids it started (STARTUP), in order.
var _started: Array[StringName] = []


func _initialize() -> void:
	OS.add_logger(_errors)
	physics_frame.connect(_watchdog)
	_run.call_deferred()


func _run() -> void:
	_level = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(_level)
	_player = _level.get_node("Heroine") as PlayerController
	_combat = _player.combat
	_player_c = _player.combatant
	_lock = _player.lock_on
	_camera = _player.camera_rig
	_hud = _level.get_node("CombatHud") as CombatHud
	_rules = _level.get_node("SandboxRules") as SandboxRules
	_monster = _level.get_node_or_null("Monster01") as LargeMonster
	_expect(_monster != null, "the sandbox has a Monster01 (LargeMonster)")
	if _monster == null:
		_finish()
		return
	_mc = _monster.get_combatant()
	_start_forward = _monster.get_forward()
	# A copy of the AI tuning with a fixed seed, so the run is repeatable.
	_config = _monster.config.duplicate() as LargeMonsterConfig
	_config.rng_seed = 11
	_monster.config = _config
	_monster.brain = MonsterBrain.new(_config)
	_monster.part_broken.connect(func(p: MonsterPart) -> void: _broken_parts.append(p.part_id()))
	_monster.attack_landed.connect(func(r: HitResult) -> void: _taken.append(r))
	_monster.state_changed.connect(func(s: LargeMonster.State, a: AttackData) -> void:
		if s == LargeMonster.State.STARTUP and a != null:
			_started.append(a.id))
	_mc.deathblow_landed.connect(func(left: int) -> void: _deathblows.append(left))
	_lock.unlocked.connect(func(r: LockOn.BreakReason) -> void: _breaks.append(r))

	await _physics_frames(5)
	_test_setup()
	await _test_waits_while_far()
	await _test_lock_on_cycles_parts()
	await _test_attack_choice_by_position()
	await _test_parry_builds_posture()
	await _test_left_forelimb_break_weakens_the_swipe()
	await _test_right_forelimb_break_disables_the_swipe()
	await _test_flank_swings_hit_the_body()
	await _test_two_deathblows_kill_it()
	await _test_revived_whole_at_home()
	await _test_second_break_restarts_the_stagger()
	_test_respawn_restores_facing()
	await _test_navmesh_chase()
	await _test_leash_returns_home()
	_finish()


# --- tests -----------------------------------------------------------------------------------

func _test_setup() -> void:
	_expect(_mc != null and _mc.config.lives == 2 and _mc.config.can_be_deathblown and _mc.config.requires_deathblow,
			"2 lives, can be deathblown, requires a deathblow (boss rule)")
	_expect(_monster.is_in_group(CorruptionMeter.HOSTILE_GROUP) and _monster.is_in_group(PlayerRest.RESPAWN_GROUP),
			"it is hostile and respawns on a shrine rest")
	var ids: Array[StringName] = []
	for p: MonsterPart in _monster.parts:
		ids.append(p.part_id())
		_expect(p.hurtbox != null and p.hurtbox.combatant == _mc and p.lock_point != null and p.lock_point.combatant == _mc,
				"part %s has a hurtbox and a lock-on point owned by the monster's Combatant" % p.part_id())
		_expect(is_equal_approx(p.lock_point.target_size, _config.target_size),
				"part %s frames the camera by the monster's size (%.1f m)" % [p.part_id(), p.lock_point.target_size])
	for id: StringName in PARTS:
		_expect(ids.has(id), "it has a %s part" % id)
	for id: StringName in [&"head", &"left_forelimb", &"right_forelimb", &"tail"]:
		var part: MonsterPart = _monster.get_part(id)
		_expect(part != null and part.is_breakable() and part.posture_max() > 0.0, "%s has its own part posture bar" % id)
	_expect(not _monster.get_part(&"body").is_breakable(), "the body itself can't break")
	var box: AABB = _visual_bounds()
	_expect(box.size.y >= 5.0 and box.size.y <= 8.0, "size class L: 5–8 m tall (%.2f m)" % box.size.y)
	var dummy: Node3D = _level.get_node("TrainingDummy") as Node3D
	var duelist: Node3D = _level.get_node("Duelist") as Node3D
	_expect(_flat(_monster.global_position - dummy.global_position).length() > 40.0
			and _flat(_monster.global_position - duelist.global_position).length() > 40.0
			and _flat(_monster.global_position - _player.global_position).length() > 40.0,
			"its arena is far from the dummy, the duelist and the heroine's start")
	_expect(absf(_monster.global_position.y) < 0.2 and _monster.is_on_floor(), "it stands on the arena floor (y %.2f)" % _monster.global_position.y)
	_expect(not _monster.uses_navigation(), "no navmesh in the sandbox: direct steering")


func _test_waits_while_far() -> void:
	await _physics_frames(60)
	_expect(_monster.state == LargeMonster.State.IDLE, "with the heroine far away it stays idle (%s)" % _state_name())
	_expect(_flat(_monster.global_position - _monster.home).length() < 0.1, "…at its home point")


func _test_lock_on_cycles_parts() -> void:
	_monster.ai_enabled = false
	_hold_local(Vector3(0.0, 0.0, 12.0))
	var body_point: LockOnPoint = _monster.get_part(&"body").lock_point
	var to: Vector3 = body_point.global_position - _player.global_position
	_camera.set_view_yaw(atan2(-to.x, -to.z))
	await _physics_frames(SETTLE_FRAMES)
	var base_distance: float = _camera.get_goal_distance()
	await _tap(&"lock_on")
	_expect(_lock.is_locked() and _lock.current_target() == _mc, "lock_on locks the monster")
	_expect(_lock.current_point() != null and _lock.current_point().get_parent() is MonsterPart,
			"…landing on one of its parts (%s)" % _point_name())
	await _physics_frames(SETTLE_FRAMES * 2)
	var pullback: float = _lock.config.pullback_for(_config.target_size)
	_expect(pullback > 2.0 and _camera.get_goal_distance() > base_distance + pullback * 0.8,
			"the camera pulls back for the big monster (%.2f -> %.2f m)" % [base_distance, _camera.get_goal_distance()])
	await _hud_refresh()
	_expect(_hud.current_opponent() == _mc, "the HUD shows the locked monster")
	_expect(_hud.opponent_life_pips() == Vector2i(2, 2), "…with 2 life pips (%s)" % _hud.opponent_life_pips())
	var visited: Dictionary[StringName, bool] = {_lock.current_point().part_id: true}
	for i: int in PARTS.size() - 1:
		await _tap(&"lock_cycle_next")
		var p: LockOnPoint = _lock.current_point()
		_expect(p != null and p.combatant == _mc, "cycling stays on the monster's parts (%s)" % _point_name())
		if p != null:
			visited[p.part_id] = true
		await _physics_frames(2)
		await _hud_refresh()
		_expect(_hud.lock_marker_text() == String(p.part_id) if p != null else false,
				"the lock marker names the part (%s)" % _hud.lock_marker_text())
		if p != null and p.part_id == &"left_forelimb":
			_expect(_hud.part_bar_visible() and _hud.part_bar_text() == "LEFT FORELIMB",
					"locked on a breakable part, the HUD shows its part posture bar (%s)" % _hud.part_bar_text())
		if p != null and p.part_id == &"body":
			_expect(not _hud.part_bar_visible(), "the body has no part bar on the HUD")
	_expect(visited.size() == PARTS.size(), "cycling visits every part: %s" % [visited.keys()])
	await _tap(&"lock_cycle_next")
	_expect(_lock.is_locked() and _lock.current_target() == _mc, "with no other target near, it goes round its parts again")
	_lock.unlock()
	_monster.ai_enabled = true


## Held at fixed spots round its body (re-placed each frame in its own frame, so the zone
## doesn't change as it turns), it picks attacks for that zone and distance.
func _test_attack_choice_by_position() -> void:
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	var cases: Array[Array] = [
		[Vector3(0.0, 0.0, 6.5), MonsterBrain.Zone.FRONT, [SWIPE, STOMP], "close in front"],
		[Vector3(0.0, 0.0, 11.0), MonsterBrain.Zone.FRONT, [CHARGE], "far in front"],
		[Vector3(5.5, 0.0, -0.5), MonsterBrain.Zone.SIDE, [SWEEP, STOMP], "beside it"],
		[Vector3(1.5, 0.0, -7.2), MonsterBrain.Zone.REAR, [SWEEP], "behind it, past stomp range"],
	]
	var first: bool = true
	for c: Array in cases:
		await _wait_ready()
		_monster.brain.reset()
		var offset: Vector3 = c[0] as Vector3
		var a: AttackData = await _next_attack(offset)
		var allowed: Array = c[2] as Array
		_expect(a != null and allowed.has(a.id), "%s it uses %s (%s)" % [c[3], allowed, a.id if a != null else &"nothing"])
		_expect(_monster.target_zone() == (c[1] as MonsterBrain.Zone), "…and reads her as %s (%s)"
				% [MonsterBrain.Zone.keys()[c[1]], MonsterBrain.Zone.keys()[_monster.target_zone()]])
		if a == null:
			continue
		if first:
			first = false
			var early: Color = _monster.body_color()
			await _hold_frames(offset, a.startup_frames - 3)
			_expect(_monster.state == LargeMonster.State.STARTUP, "still winding up near the end of startup")
			_expect(_color_distance(_monster.body_color(), a.tell_color) < _color_distance(early, a.tell_color) * 0.5,
					"the tell: its colour ramps toward %s's tell colour" % a.id)
		await _hold_until_state(offset, LargeMonster.State.RECOVERY)
		var frames: int = 0
		while _monster.state == LargeMonster.State.RECOVERY and frames < WAIT_FRAMES:
			_place_local(offset)
			var before: int = Combatant.current_frame()
			await physics_frame
			frames += Combatant.current_frame() - before
		_expect(frames >= a.recovery_frames - 1 and a.recovery_frames >= 60,
				"…then a long recovery (%d frames, data %d)" % [frames, a.recovery_frames])
	_player_c.clear_invulnerability()


func _test_parry_builds_posture() -> void:
	await _wait_ready()
	_player_c.revive()
	_monster.brain.reset()
	_mc.restore()
	_cool_down(STOMP)
	var offset: Vector3 = Vector3(0.0, 0.0, 6.5)
	var a: AttackData = await _next_attack(offset)
	_expect(a != null and a.id == SWIPE, "with the stomp cooling down, close in front it swipes (%s)" % [a.id if a != null else &"nothing"])
	if a == null:
		return
	var before_posture: float = _mc.posture.value
	var hits: int = _taken.size()
	await _hold_frames(offset, a.startup_frames - PARRY_LEAD_FRAMES - 1)
	Input.action_press(&"block")
	await _hold_frames(offset, 2)
	Input.action_release(&"block")
	await _hold_frames(offset, PARRY_LEAD_FRAMES + a.active_frames)
	var outcome: HitResult.Outcome = _taken[hits].outcome if _taken.size() > hits else HitResult.Outcome.MISSED
	_expect(outcome == HitResult.Outcome.PARRIED, "she parries its front swipe (%s)" % HitResult.Outcome.keys()[outcome])
	_expect(_mc.posture.value >= before_posture + a.posture_damage * 0.5,
			"a parried swipe fills its whole-body posture (%.1f -> %.1f)" % [before_posture, _mc.posture.value])
	await _hold_until_state(offset, LargeMonster.State.CHASE)


func _test_left_forelimb_break_weakens_the_swipe() -> void:
	await _break_part(&"left_forelimb")
	var scale: float = _monster.attack_scale(SWIPE)
	_expect(scale > 0.0 and scale < 1.0, "a broken left forelimb weakens its swipe (×%.2f)" % scale)
	await _wait_ready()
	_player_c.revive()
	_monster.brain.reset()
	_cool_down(STOMP)
	var offset: Vector3 = Vector3(0.0, 0.0, 6.5)
	var hits: int = _taken.size()
	var a: AttackData = await _next_attack(offset)
	var base: AttackData = load("res://data/attacks/monster01_front_swipe.tres") as AttackData
	_expect(a != null and a.id == SWIPE and is_equal_approx(a.damage, base.damage * scale),
			"its next swipe is weaker (%.1f dmg, full %.1f)" % [a.damage if a != null else -1.0, base.damage])
	_expect(a != null and base.posture_damage > 0.0 and is_equal_approx(a.posture_damage, base.posture_damage * scale),
			"…and does less posture damage (%.1f, full %.1f)" % [a.posture_damage if a != null else -1.0, base.posture_damage])
	if a == null:
		return
	await _hold_until_state(offset, LargeMonster.State.RECOVERY)
	var landed: HitResult = _taken[hits] if _taken.size() > hits else null
	_expect(landed != null and landed.outcome == HitResult.Outcome.HIT and is_equal_approx(landed.health_damage, base.damage * scale),
			"…and hits her for less (%s)" % ("%.1f" % landed.health_damage if landed != null else "no hit"))
	_expect(is_equal_approx(base.damage, 25.0), "…while the data file keeps its full damage (%.1f)" % base.damage)
	_player_c.revive()
	await _hold_until_state(offset, LargeMonster.State.CHASE)


func _test_right_forelimb_break_disables_the_swipe() -> void:
	await _break_part(&"right_forelimb")
	_expect(_monster.disabled_attacks().has(SWIPE), "a broken right forelimb disables its swipe")
	await _wait_ready()
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	_monster.brain.reset()
	_cool_down(STOMP)
	var offset: Vector3 = Vector3(0.0, 0.0, 6.5)
	var count: int = _started.size()
	await _hold_frames(offset, 200)
	_expect(_started.size() == count, "close in front with the stomp cooling down, it no longer has an attack (%s)" % [_started.slice(count)])
	_monster.brain.reset()
	var a: AttackData = await _next_attack(offset)
	_expect(a != null and a.id == STOMP, "…and its next attack there is the stomp, never the swipe (%s)" % [a.id if a != null else &"nothing"])
	await _hold_until_state(offset, LargeMonster.State.CHASE)
	_player_c.clear_invulnerability()


## Locked on the body part, her real greatsword and katana swings from either flank (midway
## between its forelimbs and hind legs, as close as its collision lets her stand) land on the
## body part. Her swing box only reaches 1.8 m up, so the body's hurtbox has to reach down
## its flank to the ground.
func _test_flank_swings_hit_the_body() -> void:
	await _wait_ready()
	_monster.ai_enabled = false
	_player_c.revive()
	_mc.restore()
	await _physics_frames(5)
	var body_part: MonsterPart = _monster.get_part(&"body")
	var landed: Array[Hurtbox] = []
	var on_landed: Callable = func(r: HitResult, target: Combatant, hurtbox: Hurtbox) -> void:
		if target == _mc and r.outcome == HitResult.Outcome.HIT:
			landed.append(hurtbox)
	_combat.attack_landed.connect(on_landed)
	_lock.lock_onto(body_part.lock_point) # her swings aim at the locked part
	# Its collision cylinder (2.3 m) plus her capsule (0.4 m): the closest she can stand.
	var stand: float = 2.3 + 0.45
	for form_id: StringName in [&"greatsword", &"katana"]:
		if _combat.current_form().id != form_id:
			_combat.switch_form()
		for side: float in [1.0, -1.0]:
			await _wait_ready()
			var offset: Vector3 = Vector3(side * stand, 0.0, -0.5)
			_place_local(offset)
			await _physics_frames(1)
			landed.clear()
			var health_before: float = _mc.health
			await _tap(&"attack")
			for i: int in 60:
				if not landed.is_empty():
					break
				_place_local(offset)
				await physics_frame
			var where: String = "left" if side > 0.0 else "right"
			var part: StringName = landed[0].part_id if not landed.is_empty() else &"nothing"
			_expect(part == &"body", "locked on its body, a %s swing from its %s flank hits the body (%s)" % [form_id, where, part])
			_expect(_mc.health < health_before, "…and damages it (%.1f -> %.1f)" % [health_before, _mc.health])
			await _wait_idle()
	_combat.attack_landed.disconnect(on_landed)
	if _combat.current_form().id != &"greatsword":
		_combat.switch_form()
	_lock.unlock()
	await _wait_ready()
	_mc.restore()
	_player_c.revive()
	_monster.ai_enabled = true


func _test_two_deathblows_kill_it() -> void:
	await _wait_ready()
	_monster.ai_enabled = false
	_player_c.revive()
	await _physics_frames(5)
	_lock.lock_onto(_monster.get_part(&"head").lock_point)
	_breaks.clear()
	# Phase 1: posture break.
	_mc.take_posture_damage(_mc.config.posture.max_posture)
	await _physics_frames(2)
	_expect(_mc.is_deathblow_available() and _monster.state == LargeMonster.State.STAGGERED,
			"a whole-body posture break staggers it with a deathblow window (%s)" % _state_name())
	await _hud_refresh()
	_expect(_hud.deathblow_prompt_visible(), "the HUD shows the DEATHBLOW prompt")
	var side: Vector3 = Vector3(4.6, 0.0, 0.0) # beside it, at its body's edge
	_place_local(side)
	await _physics_frames(1)
	_expect(_flat(_player.global_position - _monster.global_position).length() > _combat.deathblow.reach,
			"her spot beside it is beyond reach of its origin…")
	_expect(_combat.deathblow_target() == _mc, "…but in reach of its body: the monster is the deathblow target")
	_place_local(Vector3(0.0, 0.0, 9.0)) # 3.5 m beyond its head's tip
	await _physics_frames(1)
	_expect(_combat.deathblow_target() == null, "well clear of its head, it is out of deathblow reach")
	var front: Vector3 = Vector3(0.0, 0.0, 5.9) # just in front of its head, where she parries the swipe
	_place_local(front)
	await _physics_frames(1)
	_expect(_combat.deathblow_target() == _mc, "in front of its head (5.9 m from its origin) it is the deathblow target")
	await _tap(&"attack")
	_expect(_deathblows.size() == 1 and _deathblows[0] == 1, "the first deathblow lands, 1 life left (%s)" % [_deathblows])
	_expect(not _mc.is_dead and is_equal_approx(_mc.health, _mc.config.max_health) and not _mc.is_staggered(),
			"it gets up for its second phase with full health")
	_expect(_lock.is_locked(), "the lock holds through the first deathblow")
	await _combat_frames(_combat.deathblow.recovery_frames + 5)
	# Phase 2: 0 health doesn't kill (requires deathblow): it waits, staggered.
	var big: AttackData = AttackData.new()
	big.id = &"test_big_hit"
	big.damage = _mc.config.max_health * 2.0
	big.posture_damage = 0.0
	_mc.receive_attack(big)
	await _physics_frames(2)
	_expect(not _mc.is_dead and _mc.is_awaiting_deathblow() and _monster.state == LargeMonster.State.STAGGERED,
			"at 0 health it doesn't die: it waits, staggered, for a deathblow")
	var rear: Vector3 = Vector3(0.0, 0.0, -7.7) # just behind its tail tip
	_place_local(rear)
	await _physics_frames(1)
	_expect(_combat.deathblow_target() == _mc, "behind its tail tip (7.7 m from its origin) it is the deathblow target")
	await _tap(&"attack")
	_expect(_deathblows.size() == 2 and _deathblows[1] == 0, "the second deathblow lands (%s)" % [_deathblows])
	_expect(_mc.is_dead and _monster.state == LargeMonster.State.DEAD, "two deathblows kill it (%s)" % _state_name())
	await _physics_frames(3)
	_expect(not _lock.is_locked() and _breaks.has(LockOn.BreakReason.TARGET_DIED), "the lock breaks when it dies")
	await _hud_refresh()
	_expect(_hud.opponent_life_pips() == Vector2i(0, 2) or _hud.current_opponent() != _mc,
			"HUD shows 0 of 2 life pips (%s)" % _hud.opponent_life_pips())
	_monster.ai_enabled = true


func _test_revived_whole_at_home() -> void:
	_place(_monster.home + Vector3(-40.0, 0.0, 0.0)) # in the corridor, outside its leash
	await _combat_frames(_rules.monster_revive_delay_frames + 5)
	_expect(not _mc.is_dead and _mc.lives_left == 2, "SandboxRules revived it with both lives")
	_expect(_flat(_monster.global_position - _monster.home).length() < 0.2 and _monster.state == LargeMonster.State.IDLE,
			"…idle at home (%s)" % _state_name())
	var whole: bool = true
	for p: MonsterPart in _monster.parts:
		whole = whole and not p.is_broken()
	_expect(whole and _monster.disabled_attacks().is_empty() and is_equal_approx(_monster.attack_scale(SWIPE), 1.0),
			"…with every part whole and every attack back")
	for p: MonsterPart in _monster.parts:
		_expect(is_equal_approx(p.hurtbox.damage_multiplier, p.config.damage_multiplier),
				"…and %s takes normal damage again (×%.2f, config ×%.2f)" % [p.part_id(), p.hurtbox.damage_multiplier, p.config.damage_multiplier])


## A second part breaking while the first part-break stagger runs restarts it in full.
func _test_second_break_restarts_the_stagger() -> void:
	_monster.ai_enabled = false
	var left: MonsterPart = _monster.get_part(&"left_forelimb")
	var right: MonsterPart = _monster.get_part(&"right_forelimb")
	left.state.add_hit(1000000.0) # -> broken -> whole-body stagger
	_expect(left.is_broken() and _mc.hit_stagger_frames_left() == left.config.break_stagger_frames,
			"breaking the left forelimb staggers it (%d frames)" % _mc.hit_stagger_frames_left())
	await _combat_frames(100)
	right.state.add_hit(1000000.0)
	_expect(right.is_broken() and _mc.hit_stagger_frames_left() == right.config.break_stagger_frames,
			"breaking the right forelimb %d frames into that stagger restarts it in full (%d left, want %d)"
			% [100, _mc.hit_stagger_frames_left(), right.config.break_stagger_frames])


## A shrine-rest respawn puts it back facing its start direction.
func _test_respawn_restores_facing() -> void:
	_monster.global_rotation.y += 2.0
	_expect(_monster.get_forward().dot(_start_forward) < 0.9, "turned away from its start facing")
	_monster.respawn()
	_expect(_monster.get_forward().dot(_start_forward) > 0.999,
			"respawn() restores its start facing (%s, want %s)" % [_monster.get_forward(), _start_forward])
	_monster.ai_enabled = true


func _test_navmesh_chase() -> void:
	var mesh: NavigationMesh = NavigationMesh.new()
	var h: Vector3 = _monster.home
	mesh.vertices = PackedVector3Array([h + Vector3(-24, 0, -24), h + Vector3(24, 0, -24), h + Vector3(24, 0, 24), h + Vector3(-24, 0, 24)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.navigation_mesh = mesh
	_level.add_child(region)
	await _physics_frames(3)
	_expect(_monster.uses_navigation(), "with a navmesh in the level it chases with NavigationAgent3D")
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	_monster.brain.reset()
	_cool_down(CHARGE) # nothing reaches from far away: it has to walk in
	var spot: Vector3 = _monster.global_position + _monster.get_forward() * 16.0
	var start: float = 16.0
	var closest: float = start
	for i: int in 240:
		_place(spot)
		await physics_frame
		closest = minf(closest, _monster.distance_to_target())
	_expect(_monster.is_engaged() and closest < start - 4.0, "…and walks in toward her (%.1f -> %.1f m)" % [start, closest])
	region.queue_free()
	await _physics_frames(3)
	_player_c.clear_invulnerability()


func _test_leash_returns_home() -> void:
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	_place(_monster.home + Vector3(-(_config.leash_radius + 6.0), 0.0, 0.0))
	await _wait_state(LargeMonster.State.IDLE, 1800)
	_expect(_monster.state == LargeMonster.State.IDLE and _flat(_monster.global_position - _monster.home).length() <= _config.home_tolerance + 0.2,
			"with the heroine outside its leash it walks home and waits (%s, %.2f m from home)"
			% [_state_name(), _flat(_monster.global_position - _monster.home).length()])
	_player_c.clear_invulnerability()


# --- helpers -----------------------------------------------------------------------------------

## Breaks `part_id` with her real greatsword swings from beside it (AI off), and checks the
## whole-body stagger.
func _break_part(part_id: StringName) -> void:
	await _wait_ready()
	_monster.ai_enabled = false
	_player_c.revive()
	await _physics_frames(5)
	var part: MonsterPart = _monster.get_part(part_id)
	var multiplier: float = part.hurtbox.damage_multiplier
	var posture_before: float = _mc.posture.value
	var limb: Vector3 = _monster.to_local(part.global_position)
	var side: float = signf(limb.x)
	var offset: Vector3 = Vector3(limb.x + side * 2.1, 0.0, limb.z)
	var stagger_frames: Array[int] = [-1]
	var on_stagger: Callable = func(frames: int) -> void: stagger_frames[0] = frames
	_mc.staggered.connect(on_stagger)
	_lock.lock_onto(part.lock_point) # her swings aim at the locked part
	var swings: int = 0
	while not part.is_broken() and swings < 10:
		_place_local(offset)
		_player.set_facing_direction(_monster.global_basis * Vector3(-side, 0.0, 0.0))
		await _physics_frames(1)
		await _tap(&"attack")
		await _wait_idle()
		swings += 1
	_mc.staggered.disconnect(on_stagger)
	_expect(part.is_broken() and _broken_parts.has(part_id), "%d greatsword swings broke its %s" % [swings, part_id])
	_expect(swings >= 3, "…it took several hits (%d), not one" % swings)
	_expect(stagger_frames[0] == part.config.break_stagger_frames and _mc.is_staggered() and _monster.state == LargeMonster.State.STAGGERED,
			"…which staggers the whole monster (%d frames, %s)" % [stagger_frames[0], _state_name()])
	_expect(not _mc.is_deathblow_available() and _combat.deathblow_target() == null,
			"…without a deathblow window")
	_expect(_mc.posture.value >= posture_before + part.config.body_posture_on_break,
			"…and adds whole-body posture (%.1f -> %.1f)" % [posture_before, _mc.posture.value])
	_expect(part.hurtbox.damage_multiplier > multiplier, "…and the broken %s takes more damage (×%.2f -> ×%.2f)"
			% [part_id, multiplier, part.hurtbox.damage_multiplier])
	var mesh: MeshInstance3D = part.meshes()[0]
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	_expect(mat != null and mat.albedo_color.is_equal_approx(_config.broken_part_color), "…and looks broken")
	await _physics_frames(1)
	await _hud_refresh()
	_expect(_hud.part_bar_visible() and _hud.part_bar_text().ends_with("BROKEN") and _hud.part_bar_ratio() > 0.99,
			"…and the HUD part bar reads full and BROKEN (%s, %.2f)" % [_hud.part_bar_text(), _hud.part_bar_ratio()])
	_lock.unlock()
	await _combat_frames(part.config.break_stagger_frames + 2)
	_expect(not _mc.is_staggered(), "the part-break stagger ends after %d frames" % part.config.break_stagger_frames)
	_mc.restore() # empty whole-body posture again, so later checks start clean
	_monster.ai_enabled = true


## Puts row `id` on cooldown (as if just used).
func _cool_down(id: StringName) -> void:
	for i: int in _config.attacks.size():
		if _config.attacks[i].attack.id == id:
			_monster.brain.last_used[i] = Combatant.current_frame()
	_monster.brain.last_index = -1


## Visual bounds of every mesh of the monster, in world space.
func _visual_bounds() -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for node: Node in _monster.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = node as MeshInstance3D
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Waits until the monster is not in an attack or a stagger, she is idle and hit-stop is over.
func _wait_ready() -> void:
	for i: int in WAIT_FRAMES:
		var busy: bool = _monster.state == LargeMonster.State.STARTUP or _monster.state == LargeMonster.State.ACTIVE \
				or _monster.state == LargeMonster.State.RECOVERY or _monster.state == LargeMonster.State.STAGGERED
		if not busy and not _combat.is_busy() and not HitStopService.is_active():
			return
		await physics_frame
	_expect(false, "the monster and the heroine were ready again within %d frames (%s)" % [WAIT_FRAMES, _state_name()])


## Holds her at `offset` in the monster's frame until it starts a wind-up; returns the attack.
func _next_attack(offset: Vector3) -> AttackData:
	for i: int in WAIT_FRAMES:
		_place_local(offset)
		await physics_frame
		if _monster.state == LargeMonster.State.STARTUP and _monster._frames_in_state <= 1:
			return _monster.current_attack
	_expect(false, "it started an attack within %d frames (%s)" % [WAIT_FRAMES, _state_name()])
	return null


func _hold_frames(offset: Vector3, count: int) -> void:
	var target: int = Combatant.current_frame() + count
	for i: int in count + 600:
		if Combatant.current_frame() >= target:
			return
		_place_local(offset)
		await physics_frame


func _hold_until_state(offset: Vector3, s: LargeMonster.State) -> void:
	for i: int in WAIT_FRAMES:
		if _monster.state == s:
			return
		_place_local(offset)
		await physics_frame
	_expect(false, "it reached %s within %d frames (%s)" % [LargeMonster.State.keys()[s], WAIT_FRAMES, _state_name()])


## Places her at `offset` in the monster's own frame (+Z = its forward), facing it.
func _place_local(offset: Vector3) -> void:
	var p: Vector3 = _monster.global_transform * offset
	p.y = _player.global_position.y
	_place(p)
	var to: Vector3 = _flat(_monster.global_position - p)
	if to.length_squared() > 0.0001:
		_player.set_facing_direction(to.normalized())


func _hold_local(offset: Vector3) -> void:
	_place_local(offset)


func _place(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _wait_state(s: LargeMonster.State, frames: int = WAIT_FRAMES) -> void:
	for i: int in frames:
		if _monster.state == s:
			return
		await physics_frame
	_expect(false, "it reached %s within %d frames (%s)" % [LargeMonster.State.keys()[s], frames, _state_name()])


func _wait_idle() -> void:
	for i: int in 600:
		if not _combat.is_busy():
			return
		await physics_frame
	_expect(false, "the heroine was idle again within 600 frames")


func _state_name() -> String:
	return LargeMonster.State.keys()[_monster.state] as String


func _point_name() -> String:
	var p: LockOnPoint = _lock.current_point()
	return "none" if p == null else String(p.part_id)


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


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _watchdog() -> void:
	_frames_run += 1
	if _frames_run > MAX_RUN_FRAMES and not _finished:
		_expect(false, "finished within %d frames (watchdog)" % MAX_RUN_FRAMES)
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_expect(_errors.errors == 0, "no engine/script errors (%d; first: %s)" % [_errors.errors, _errors.first_error])
	print("MONSTER SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
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
