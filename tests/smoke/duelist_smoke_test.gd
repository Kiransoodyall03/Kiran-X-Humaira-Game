extends SceneTree
## Headless smoke test for the capsule duelist in the sandbox, using the real input actions.
## It waits at home while the heroine is far away; engages when she comes close, walks in
## and attacks with a tell (body colour ramps to the attack's tell colour during the
## wind-up); parrying its attacks gives it posture until it breaks; a deathblow kills it
## (1 life) and SandboxRules revives it at home. It parries / blocks her swings when its
## guard odds say so, can't guard in its recovery (punish window), flinches from an
## unguarded heavy hit (a flinch in its recovery doesn't end the punish window early), and the HUD opponent bars follow the nearest or locked enemy.
## Fails on any engine/script error, and on a frame-budget timeout instead of hanging.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/duelist_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
## Press guard this many frames before the hit lands (inside the 12-frame window).
const PARRY_LEAD_FRAMES: int = 6
const WAIT_FRAMES: int = 900
const MAX_RUN_FRAMES: int = 30000

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _level: Node
var _player: PlayerController
var _combat: PlayerCombat
var _player_c: Combatant
var _duelist: Duelist
var _duelist_c: Combatant
var _dummy: TrainingDummy
var _hud: CombatHud
var _rules: SandboxRules
var _lock: LockOn
var _config: DuelistConfig
var _broken: bool = false
var _deathblows: Array[int] = []
## Outcomes of the duelist's attacks on the heroine.
var _taken: Array[HitResult.Outcome] = []
## Attack ids it wound up, and whether each tell reached its colour.
var _attacks_seen: Dictionary[StringName, bool] = {}
var _defenses: Array[DuelistBrain.Defense] = []
## Every attack id it started, over the whole run.
var _started: Dictionary[StringName, int] = {}
## Its forward at the start of the run (home facing).
var _start_forward: Vector3


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
	_duelist = _level.get_node_or_null("Duelist") as Duelist
	_dummy = _level.get_node("TrainingDummy") as TrainingDummy
	_hud = _level.get_node("CombatHud") as CombatHud
	_rules = _level.get_node("SandboxRules") as SandboxRules
	_expect(_duelist != null, "the sandbox has a Duelist")
	if _duelist == null:
		_finish()
		return
	_duelist_c = _duelist.get_combatant()
	_start_forward = _duelist.get_forward()
	# Work on a copy of the AI tuning so the test can change odds without touching the data.
	_config = _duelist.config.duplicate() as DuelistConfig
	_config.rng_seed = 7
	_duelist.config = _config
	_duelist.brain = DuelistBrain.new(_config)
	_duelist_c.posture_broken.connect(func() -> void: _broken = true)
	_duelist_c.deathblow_landed.connect(func(left: int) -> void: _deathblows.append(left))
	_duelist.attack_landed.connect(func(r: HitResult) -> void: _taken.append(r.outcome))
	_duelist.defense_chosen.connect(func(d: DuelistBrain.Defense, _a: AttackData) -> void: _defenses.append(d))
	_duelist.state_changed.connect(func(s: Duelist.State, a: AttackData) -> void:
		if s == Duelist.State.STARTUP and a != null:
			_started[a.id] = _started.get(a.id, 0) as int + 1)

	_expect(_duelist_c.lives_left == 1 and _duelist_c.config.can_be_deathblown, "the duelist has 1 life and can be deathblown")
	_expect(_duelist.get_node_or_null("Hurtbox") is Hurtbox and _duelist.get_node_or_null("LockOnPoint") is LockOnPoint,
			"the duelist has a hurtbox and a lock-on point")
	_expect(_duelist.is_in_group(CorruptionMeter.HOSTILE_GROUP), "the duelist is hostile")
	_expect(_flat(_duelist.global_position - _dummy.global_position).length() > 20.0,
			"the duelist stands well away from the training dummy")
	_expect(_flat(_duelist.global_position).length() > 20.0, "…and from the heroine's start / the movement course")
	_expect(not _duelist.uses_navigation(), "no navmesh in the sandbox: direct steering")

	await _test_waits_while_far()
	await _test_hud_follows_nearest_and_locked()
	await _test_approaches_and_telegraphs()
	await _test_parry_breaks_posture_and_deathblow()
	await _test_revived_at_home()
	await _test_guards_her_swings()
	await _test_no_guard_in_recovery()
	await _test_flinch_keeps_punish_window()
	await _test_flinch()
	await _test_stays_on_floor_at_the_edge()
	await _test_fall_resets_home()
	await _test_navmesh_approach()
	await _test_leash_returns_home()
	await _test_too_close_switches_attack()
	await _test_perilous_super_armor()
	await _test_counter_after_guard()
	await _test_strafe_flips_at_wall()
	await _test_facing_restored()
	_finish()


## Held at the edge of its leash toward the nearest floor edge (north, z = -30), it fights
## her there without leaving the floor, and over the fight it uses all of its attacks
## (the short-range slash too: it walks in to the planned attack's range).
func _test_stays_on_floor_at_the_edge() -> void:
	await _wait_idle()
	_config.parry_chance = 0.0
	_config.block_chance = 0.0
	_config.flinch_posture_threshold = 1000.0
	_player_c.revive()
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	var spot: Vector3 = Vector3(_duelist.home.x, 0.0, -27.5) # 2.5 m from the north floor edge
	_expect(_flat(spot - _duelist.home).length() < _config.leash_radius, "the edge spot is inside its leash")
	# Start it between her and the edge, so backing off / circling pushes it toward the edge.
	_duelist.global_position = Vector3(spot.x + 0.5, _duelist.global_position.y, -29.2)
	_duelist.velocity = Vector3.ZERO
	_duelist.reset_physics_interpolation()
	var before: Dictionary[StringName, int] = _started.duplicate()
	var lowest: float = INF
	var furthest_z: float = INF
	var engaged_frames: int = 0
	for i: int in 2400:
		_player.global_position = Vector3(spot.x, _player.global_position.y, spot.z)
		_player.velocity = Vector3.ZERO
		await physics_frame
		lowest = minf(lowest, _duelist.global_position.y)
		furthest_z = minf(furthest_z, _duelist.global_position.z)
		if _duelist.is_engaged():
			engaged_frames += 1
	_player_c.clear_invulnerability()
	_expect(engaged_frames > 2000, "it fought her at the floor edge (%d engaged frames)" % engaged_frames)
	_expect(lowest > -0.5 and furthest_z > -30.0,
			"it stayed on the floor at the edge (lowest y %.2f, furthest z %.2f)" % [lowest, furthest_z])
	var used: Dictionary[StringName, int] = {}
	var missing: Array[StringName] = []
	for e: DuelistAttackEntry in _config.attacks:
		used[e.attack.id] = (_started.get(e.attack.id, 0) as int) - (before.get(e.attack.id, 0) as int)
		if used[e.attack.id] <= 0:
			missing.append(e.attack.id)
	_expect(missing.is_empty(), "fighting her there it used all 3 attacks of its table (%s; missing %s)" % [used, missing])
	_place(_duelist.home + Vector3(0.0, 0.0, 30.0), Vector3.FORWARD)
	await _wait_state(Duelist.State.IDLE)


## If it ever falls out of the level it is put back at home.
func _test_fall_resets_home() -> void:
	_duelist.global_position = _duelist.home + Vector3(0.0, _config.fall_reset_height - 5.0, -12.0)
	_duelist.velocity = Vector3.ZERO
	await _physics_frames(3)
	_expect(_flat(_duelist.global_position - _duelist.home).length() < 0.2 and _duelist.global_position.y > -0.5,
			"fallen below fall_reset_height, it is put back at home (%s)" % _duelist.global_position)
	_expect(_duelist.state == Duelist.State.IDLE, "…idle (%s)" % _state_name())


## With a navmesh on the map it walks in along a NavigationAgent3D path.
func _test_navmesh_approach() -> void:
	_config.parry_chance = 0.0
	_config.block_chance = 0.0
	_place(_duelist.home + Vector3(0.0, 0.0, 30.0), Vector3.FORWARD)
	await _wait_state(Duelist.State.IDLE)
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-29, 0, -29), Vector3(29, 0, -29), Vector3(29, 0, 29), Vector3(-29, 0, 29)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.navigation_mesh = mesh
	_level.add_child(region)
	await _physics_frames(3)
	_expect(_duelist.uses_navigation(), "with a navmesh in the level the duelist uses NavigationAgent3D")
	_place(_duelist.home + Vector3(6.0, 0.0, 5.0), Vector3.FORWARD)
	var start_distance: float = _duelist.distance_to_target()
	var a: AttackData = await _next_attack()
	_expect(a != null and _duelist.distance_to_target() < start_distance - 2.0,
			"…and still walks in to attack (%.2f -> %.2f m)" % [start_distance, _duelist.distance_to_target()])
	region.queue_free()
	await _physics_frames(3)


## Leaving its leash sends it back home.
func _test_leash_returns_home() -> void:
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	_place(_duelist.home + Vector3(0.0, 0.0, _config.leash_radius + 4.0), Vector3.FORWARD)
	await _wait_state(Duelist.State.IDLE)
	_expect(_duelist.state == Duelist.State.IDLE and _flat(_duelist.global_position - _duelist.home).length() <= _config.home_tolerance + 0.1,
			"with the heroine outside its leash it walks home and waits")
	_player_c.clear_invulnerability()


## Planning the delayed overhead (min range 1 m) with her closer than that, it swings an
## attack valid at that distance instead of backing off forever.
func _test_too_close_switches_attack() -> void:
	_config.parry_chance = 0.0
	_config.block_chance = 0.0
	_duelist.respawn() # fresh cooldowns
	_player_c.revive()
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	var overhead: int = _row_index(&"duelist_delayed_overhead")
	_expect(overhead >= 0 and _config.attacks[overhead].min_range > 0.8, "the delayed overhead has a min range over 0.8 m")
	_place(_duelist.global_position + _duelist.get_forward() * 0.7, -_duelist.get_forward())
	_duelist._start_circling()
	_duelist.planned_index = overhead
	_duelist._enter(Duelist.State.APPROACH)
	var started: AttackData = null
	for i: int in 120:
		_place(_duelist.global_position + _duelist.get_forward() * 0.7, -_duelist.get_forward())
		await physics_frame
		if _duelist.state == Duelist.State.STARTUP:
			started = _duelist.current_attack
			break
	_expect(started != null and started != _config.attacks[overhead].attack,
			"too close for the planned overhead, it swings another attack within 120 frames (%s, now %s)" % [started.id if started != null else &"none", _state_name()])
	await _send_home()
	_player_c.clear_invulnerability()


## Hits over the flinch threshold don't flinch it in a perilous attack's wind-up or swing
## (super armour), but do in a normal attack's wind-up.
func _test_perilous_super_armor() -> void:
	var old_threshold: float = _config.flinch_posture_threshold
	_config.flinch_posture_threshold = 1.0
	var hurtbox: Hurtbox = _duelist.get_node("Hurtbox") as Hurtbox
	var swing: AttackData = _combat.current_form().light_combo[0]
	var thrust: int = _row_index(&"duelist_perilous_thrust")
	_expect(thrust >= 0 and _config.attacks[thrust].attack.perilous != AttackData.Perilous.NONE, "the thrust is perilous")
	for s: Duelist.State in [Duelist.State.STARTUP, Duelist.State.ACTIVE]:
		_duelist.respawn()
		_force_attack(thrust, s)
		var r: HitResult = hurtbox.receive_hit(swing, _player_c)
		_expect(r.outcome == HitResult.Outcome.HIT and _duelist.state == s,
				"a hit over the flinch threshold in the perilous thrust's %s doesn't flinch it (%s, now %s)" % [Duelist.State.keys()[s], HitResult.Outcome.keys()[r.outcome], _state_name()])
	_duelist.respawn()
	_force_attack(_row_index(&"duelist_quick_slash"), Duelist.State.STARTUP)
	var hit: HitResult = hurtbox.receive_hit(swing, _player_c)
	_expect(hit.outcome == HitResult.Outcome.HIT and _duelist.state == Duelist.State.FLINCH,
			"the same hit in the quick slash's STARTUP flinches it (%s, now %s)" % [HitResult.Outcome.keys()[hit.outcome], _state_name()])
	_duelist.respawn()
	_config.flinch_posture_threshold = old_threshold


## Blocking or parrying her swing while circling cuts its circling to counter_frames.
func _test_counter_after_guard() -> void:
	var hurtbox: Hurtbox = _duelist.get_node("Hurtbox") as Hurtbox
	var swing: AttackData = _combat.current_form().light_combo[0]
	for parry: bool in [false, true]:
		_duelist.respawn()
		_duelist._start_circling()
		_duelist._circle_frames_left = _config.counter_frames + 200
		if parry:
			_duelist_c.guard_press()
		else:
			_duelist_c.guard_hold()
		var r: HitResult = hurtbox.receive_hit(swing, _player_c)
		var want: HitResult.Outcome = HitResult.Outcome.PARRIED if parry else HitResult.Outcome.BLOCKED
		_expect(r.outcome == want and _duelist._circle_frames_left <= _config.counter_frames,
				"after it %s her swing while circling it counters within %d frames (%s, %d frames left)" % ["parried" if parry else "blocked", _config.counter_frames, HitResult.Outcome.keys()[r.outcome], _duelist._circle_frames_left])
		_duelist._drop_guard()
	_duelist.respawn()
	await _wait_hit_stop_over()
	_player_c.revive()


## Circling into a wall flips its strafe direction.
func _test_strafe_flips_at_wall() -> void:
	_config.parry_chance = 0.0
	_config.block_chance = 0.0
	_duelist.respawn()
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	var pos: Vector3 = _duelist.global_position
	var her: Vector3 = Vector3(pos.x, _player.global_position.y, pos.z + 3.5) # inside its circling band
	# With her to +Z and _strafe_sign +1 it strafes toward -X: put a wall there.
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.3, 2.0, 6.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	var wall: StaticBody3D = StaticBody3D.new()
	wall.add_child(shape)
	wall.position = Vector3(pos.x - 1.2, 1.0, pos.z + 1.75)
	_level.add_child(wall)
	_place(her, Vector3.FORWARD)
	await physics_frame
	_duelist._start_circling()
	_duelist._strafe_sign = 1.0
	_duelist._circle_frames_left = 100000
	var flipped_at: int = -1
	for i: int in 180:
		_place(her, Vector3.FORWARD)
		await physics_frame
		if _duelist._strafe_sign < 0.0:
			flipped_at = i
			break
	_expect(flipped_at >= 0 and _duelist.state == Duelist.State.CIRCLE,
			"circling into a wall flips its strafe direction (frame %d, x %.2f, %s)" % [flipped_at, _duelist.global_position.x - pos.x, _state_name()])
	wall.queue_free()
	await _send_home()
	_player_c.clear_invulnerability()


## Respawning, or falling below fall_reset_height, puts its facing back to its start.
func _test_facing_restored() -> void:
	var visual: Node3D = _duelist.get_node("Visual") as Node3D
	visual.global_rotation.y += 2.0
	_expect(_duelist.get_forward().dot(_start_forward) < 0.9, "turned away from its start facing")
	_duelist.respawn()
	_expect(_duelist.get_forward().dot(_start_forward) > 0.999,
			"respawned, it faces its start direction again (%s vs %s)" % [_duelist.get_forward(), _start_forward])
	visual.global_rotation.y += 2.0
	_duelist.global_position = _duelist.home + Vector3(0.0, _config.fall_reset_height - 5.0, 0.0)
	_duelist.velocity = Vector3.ZERO
	await _physics_frames(3)
	_expect(_duelist.get_forward().dot(_start_forward) > 0.999 and _duelist.global_position.y > -0.5,
			"fallen below fall_reset_height, it faces its start direction again (%s vs %s)" % [_duelist.get_forward(), _start_forward])


func _test_waits_while_far() -> void:
	await _physics_frames(90)
	_expect(_duelist.state == Duelist.State.IDLE, "with the heroine far away the duelist stays idle (%s)" % _state_name())
	_expect(_flat(_duelist.global_position - _duelist.home).length() < 0.1, "…at its home point")
	await _hud_refresh()
	_expect(_hud.current_opponent() == _dummy.get_combatant(), "the HUD shows the nearest enemy (the dummy) at the start")


func _test_hud_follows_nearest_and_locked() -> void:
	# Between the two, nearer the dummy, and outside the duelist's leash.
	_place(Vector3(0.0, 0.0, -17.0), Vector3.LEFT)
	await _physics_frames(3)
	await _hud_refresh()
	_expect(_hud.current_opponent() == _dummy.get_combatant(), "nearer the dummy, the HUD shows the dummy")
	_lock.lock_onto(_duelist.get_node("LockOnPoint") as LockOnPoint)
	await _physics_frames(2)
	await _hud_refresh()
	_expect(_lock.is_locked() and _hud.current_opponent() == _duelist_c, "locked on the duelist, the HUD shows the duelist")
	_expect(_hud.opponent_name_text() == "DUELIST", "the opponent name reads DUELIST (%s)" % _hud.opponent_name_text())
	_expect(_hud.opponent_life_pips() == Vector2i(1, 1), "HUD shows the duelist's 1 life pip (%s)" % _hud.opponent_life_pips())
	_lock.unlock()
	await _physics_frames(2)
	await _hud_refresh()
	_expect(_hud.current_opponent() == _dummy.get_combatant(), "unlocked, the HUD goes back to the nearest (dummy)")
	_expect(_duelist.state == Duelist.State.IDLE, "outside its leash the duelist doesn't engage")


func _test_approaches_and_telegraphs() -> void:
	_config.parry_chance = 0.0
	_config.block_chance = 0.0
	_place(_duelist.home + Vector3(0.0, 0.0, 8.0), Vector3.FORWARD)
	var start_distance: float = _duelist.distance_to_target()
	var attack: AttackData = await _next_attack()
	var attack_frame: int = Combatant.current_frame()
	_expect(attack != null, "the duelist engaged and started an attack")
	if attack == null:
		return
	var early: Color = _duelist.body_color()
	_expect(_duelist.distance_to_target() < start_distance - 2.0,
			"it walked in before attacking (%.2f -> %.2f m)" % [start_distance, _duelist.distance_to_target()])
	await _hud_refresh()
	_expect(_hud.current_opponent() == _duelist_c, "the HUD switched to the duelist (nearest)")
	# Counted from the attack's start: the HUD wait can take a few ticks under load.
	await _combat_frames(attack_frame + attack.startup_frames - 2 - Combatant.current_frame())
	_expect(_duelist.state == Duelist.State.STARTUP, "still winding up near the end of startup")
	var late: Color = _duelist.body_color()
	_expect(_color_distance(late, attack.tell_color) < _color_distance(early, attack.tell_color) * 0.5,
			"the tell: its colour ramps toward %s's tell colour" % attack.id)
	await _wait_state_not(Duelist.State.STARTUP)
	_expect(_duelist.state == Duelist.State.ACTIVE or _duelist.state == Duelist.State.RECOVERY, "the wind-up leads into the swing")
	await _wait_state(Duelist.State.RECOVERY)
	_expect(_duelist.state == Duelist.State.RECOVERY and not _duelist_c.guard.is_held, "after the swing it stands in recovery, guard down")
	await _wait_state_not(Duelist.State.RECOVERY)


## Parries every attack until its posture breaks, then lands the deathblow.
func _test_parry_breaks_posture_and_deathblow() -> void:
	var parried: int = 0
	var posture_after_first: float = -1.0
	for i: int in 16:
		if _broken:
			break
		_player.set_facing_direction(_flat(_duelist.global_position - _player.global_position).normalized())
		var a: AttackData = await _next_attack()
		if a == null:
			break
		_attacks_seen[a.id] = true
		var before: int = _taken.size()
		await _combat_frames(a.startup_frames - PARRY_LEAD_FRAMES)
		await _tap(&"block" if a.deflectable else &"jump", 2 if a.deflectable else 10)
		await _combat_frames(a.active_frames + 2)
		if _taken.size() > before and _taken[before] == HitResult.Outcome.PARRIED:
			parried += 1
			if posture_after_first < 0.0:
				posture_after_first = _duelist_c.posture.value
	_expect(parried >= 1, "the heroine parried the duelist (%d parries)" % parried)
	_expect(posture_after_first > 0.0, "a parried duelist takes posture (%.1f)" % posture_after_first)
	_expect(_attacks_seen.size() >= 2, "it used more than one attack from its table (%s)" % [_attacks_seen.keys()])
	_expect(_broken, "parrying broke the duelist's posture")
	_expect(_duelist.state == Duelist.State.STAGGERED, "the duelist is staggered (%s)" % _state_name())
	_expect(_duelist_c.is_deathblow_available(), "a deathblow is available")
	await _physics_frames(2)
	await _hud_refresh()
	_expect(_hud.deathblow_prompt_visible(), "the HUD shows the DEATHBLOW prompt")
	_place(_duelist.global_position + _duelist.get_forward() * 2.0, -_duelist.get_forward())
	await _physics_frames(1)
	_expect(_combat.deathblow_target() == _duelist_c, "the duelist is the deathblow target in reach")
	await _tap(&"attack")
	_expect(_deathblows.size() == 1 and _deathblows[0] == 0, "the deathblow landed (%s)" % [_deathblows])
	_expect(_duelist_c.is_dead and _duelist.state == Duelist.State.DEAD, "with 1 life the duelist dies")
	await _hud_refresh()
	_expect(_hud.opponent_life_pips() == Vector2i(0, 1), "HUD shows 0 of 1 life pips (%s)" % _hud.opponent_life_pips())
	await _physics_frames(30)
	_expect(_duelist.state == Duelist.State.DEAD and _duelist.velocity.length() < 0.01, "dead, it stays down")


func _test_revived_at_home() -> void:
	_place(_duelist.home + Vector3(0.0, 0.0, 30.0), Vector3.FORWARD) # out of its way
	await _combat_frames(_rules.duelist_revive_delay_frames + 3)
	_expect(not _duelist_c.is_dead and _duelist_c.lives_left == 1, "SandboxRules revived the duelist")
	_expect(_flat(_duelist.global_position - _duelist.home).length() < 0.2, "…back at its home point")
	_expect(_duelist.state == Duelist.State.IDLE, "…idle (%s)" % _state_name())


## With parry (then block) odds at 100%, her swing is parried (then blocked).
func _test_guards_her_swings() -> void:
	await _wait_idle()
	_player_c.revive() # fresh posture, so the parry's cost shows
	_config.parry_chance = 1.0
	_config.block_chance = 0.0
	var outcome: HitResult.Outcome = await _swing_at_circling_duelist()
	_expect(_defenses.has(DuelistBrain.Defense.PARRY), "the duelist chose to parry her swing")
	_expect(outcome == HitResult.Outcome.PARRIED, "her swing was PARRIED (%s)" % HitResult.Outcome.keys()[outcome])
	_expect(_player_c.posture.value > 0.0, "being parried cost her posture (%.1f)" % _player_c.posture.value)
	await _wait_idle()
	_config.parry_chance = 0.0
	_config.block_chance = 1.0
	_defenses.clear()
	outcome = await _swing_at_circling_duelist()
	_expect(_defenses.has(DuelistBrain.Defense.BLOCK), "the duelist chose to block her swing")
	_expect(outcome == HitResult.Outcome.BLOCKED, "her swing was BLOCKED (%s)" % HitResult.Outcome.keys()[outcome])
	await _wait_idle()


## In its recovery the duelist can't guard: her swing lands even at 100% parry odds.
func _test_no_guard_in_recovery() -> void:
	_config.parry_chance = 1.0
	_config.block_chance = 0.0
	_player_c.revive()
	# Its swing comes back DODGED: no stagger or hit-stop on her while she waits.
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	_place(_duelist.global_position + Vector3(0.0, 0.0, 3.0), Vector3.FORWARD)
	await _wait_state(Duelist.State.RECOVERY)
	_expect(_duelist.state == Duelist.State.RECOVERY, "the duelist reached its recovery")
	await _wait_hit_stop_over()
	_place(_duelist.global_position + _duelist.get_forward() * 2.0, -_duelist.get_forward())
	await _physics_frames(1)
	var landed: Array[HitResult.Outcome] = []
	var on_landed: Callable = func(r: HitResult, t: Combatant, _h: Hurtbox) -> void:
		if t == _duelist_c:
			landed.append(r.outcome)
	_combat.attack_landed.connect(on_landed)
	_defenses.clear()
	await _tap(&"attack")
	await _wait_idle()
	_combat.attack_landed.disconnect(on_landed)
	_player_c.clear_invulnerability()
	_expect(_defenses.is_empty(), "no guard decision during its recovery")
	_expect(landed.size() == 1 and landed[0] == HitResult.Outcome.HIT,
			"her swing in its recovery (the punish window) is a clean HIT (%s)" % [landed])


## A flinch from a hit in its recovery doesn't cut the punish window short: it can't
## guard again before its recovery would have ended. (A short flinch_frames makes any
## early end show.)
func _test_flinch_keeps_punish_window() -> void:
	await _wait_idle()
	var old_threshold: float = _config.flinch_posture_threshold
	var old_flinch_frames: int = _config.flinch_frames
	_config.parry_chance = 1.0 # if it could guard again, it would
	_config.block_chance = 0.0
	_config.flinch_posture_threshold = 1.0
	_config.flinch_frames = 2
	_duelist.brain.reset()
	_player_c.revive()
	_player_c.set_invulnerable(Combatant.current_frame(), 100000)
	_place(_duelist.global_position + Vector3(0.0, 0.0, 3.0), Vector3.FORWARD)
	var attack: AttackData = await _next_attack()
	if attack == null:
		return
	# Combat frames its recovery (the punish window) starts and ends on.
	var recovery_start: int = Combatant.current_frame() - _duelist._frames_in_state + attack.startup_frames + attack.active_frames
	var recovery_end: int = recovery_start + attack.recovery_frames
	# Swing so her blade lands in the first frames of its recovery (startup + 1 frames after
	# the press), leaving most of the punish window after the flinch.
	var her_startup: int = _combat.current_form().light_combo[0].startup_frames
	await _combat_frames(recovery_start + 2 - (her_startup + 1) - Combatant.current_frame())
	_place(_duelist.global_position + _duelist.get_forward() * 2.0, -_duelist.get_forward())
	# [state, combat frame] for each state it enters (lambdas capture locals by value).
	var entered: Array[Vector2i] = []
	var watch: Callable = func(s: Duelist.State, _a: AttackData) -> void:
		entered.append(Vector2i(s, Combatant.current_frame()))
	_duelist.state_changed.connect(watch)
	_defenses.clear()
	await _tap(&"attack")
	var guard_frame: int = -1
	for i: int in WAIT_FRAMES:
		await physics_frame
		if _duelist._can_guard_in(_duelist.state):
			guard_frame = Combatant.current_frame()
			break
	_duelist.state_changed.disconnect(watch)
	await _wait_idle()
	_player_c.clear_invulnerability()
	var flinch_frame: int = -1
	for e: Vector2i in entered:
		if e.x == Duelist.State.FLINCH:
			flinch_frame = e.y
			break
	_expect(flinch_frame >= 0 and flinch_frame < recovery_end,
			"her hit in its recovery made it flinch (flinch at %d, recovery ends %d, states %s)" % [flinch_frame, recovery_end, entered])
	_expect(flinch_frame + _config.flinch_frames + 2 < recovery_end,
			"…early enough that a %d-frame flinch would end before the recovery (flinch at %d, recovery ends %d)" % [_config.flinch_frames, flinch_frame, recovery_end])
	_expect(guard_frame >= recovery_end - 1,
			"the flinch doesn't end the punish window early: no guarding before its recovery would have ended (guard-able at %d, recovery ends %d)" % [guard_frame, recovery_end])
	_expect(_defenses.is_empty(), "no guard decision during the flinch inside its punish window")
	_config.flinch_posture_threshold = old_threshold
	_config.flinch_frames = old_flinch_frames


## An unguarded greatsword hit over the flinch threshold makes it flinch; under it, no.
func _test_flinch() -> void:
	_config.parry_chance = 0.0
	_config.block_chance = 0.0
	_config.flinch_posture_threshold = 1.0
	await _wait_state(Duelist.State.CIRCLE)
	var states: Array[Duelist.State] = [] # lambdas capture locals by value: collect in an array
	var watch: Callable = func(s: Duelist.State, _a: AttackData) -> void: states.append(s)
	_duelist.state_changed.connect(watch)
	var outcome: HitResult.Outcome = await _swing_at_circling_duelist()
	_duelist.state_changed.disconnect(watch)
	_expect(states.has(Duelist.State.FLINCH), "an unguarded hit over the flinch threshold makes it flinch (hit: %s, now %s)" % [HitResult.Outcome.keys()[outcome], _state_name()])
	# Below the threshold, a hit doesn't flinch it.
	await _wait_idle()
	_config.flinch_posture_threshold = 1000.0
	_duelist.brain.reset()
	states.clear()
	_duelist.state_changed.connect(watch)
	outcome = await _swing_at_circling_duelist()
	_duelist.state_changed.disconnect(watch)
	_expect(outcome == HitResult.Outcome.HIT and not states.has(Duelist.State.FLINCH),
			"a hit below the flinch threshold doesn't flinch it (hit: %s, states %s)" % [HitResult.Outcome.keys()[outcome], states])


## Places her 2 m in front of the duelist (while it circles), swings, returns the outcome
## of the swing on it (MISSED if it never connected).
func _swing_at_circling_duelist() -> HitResult.Outcome:
	_place(_duelist.global_position + Vector3(0.0, 0.0, 3.0), Vector3.FORWARD)
	await _wait_state(Duelist.State.CIRCLE)
	await _wait_hit_stop_over()
	var result: Array[HitResult.Outcome] = []
	var on_landed: Callable = func(r: HitResult, t: Combatant, _h: Hurtbox) -> void:
		if t == _duelist_c:
			result.append(r.outcome)
	_combat.attack_landed.connect(on_landed)
	_place(_duelist.global_position + _duelist.get_forward() * 2.0, -_duelist.get_forward())
	await _physics_frames(1)
	await _tap(&"attack")
	await _wait_idle()
	_combat.attack_landed.disconnect(on_landed)
	return result[0] if not result.is_empty() else HitResult.Outcome.MISSED


## Starts row `index` of its attack table in state `s` (STARTUP or ACTIVE) right now.
func _force_attack(index: int, s: Duelist.State) -> void:
	_duelist.current_index = index
	_duelist.current_attack = _config.attacks[index].attack
	_duelist._enter(s)


func _row_index(id: StringName) -> int:
	for i: int in _config.attacks.size():
		if _config.attacks[i].attack.id == id:
			return i
	return -1


## Moves her out of its leash and waits until it is idle at home.
func _send_home() -> void:
	_place(_duelist.home + Vector3(0.0, 0.0, _config.leash_radius + 4.0), Vector3.FORWARD)
	await _wait_state(Duelist.State.IDLE)


func _place(position: Vector3, facing: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	if facing.length_squared() > 0.0001:
		_player.set_facing_direction(facing)
	_player.reset_physics_interpolation()


## Waits for the duelist to start its next wind-up; returns the attack.
func _next_attack() -> AttackData:
	for i: int in WAIT_FRAMES:
		await physics_frame
		if _duelist.state == Duelist.State.STARTUP and _duelist._frames_in_state <= 1:
			return _duelist.current_attack
	_expect(false, "the duelist started an attack within %d frames (%s)" % [WAIT_FRAMES, _state_name()])
	return null


func _wait_state(s: Duelist.State) -> void:
	for i: int in WAIT_FRAMES:
		if _duelist.state == s:
			return
		await physics_frame
	_expect(false, "the duelist reached %s within %d frames (%s)" % [Duelist.State.keys()[s], WAIT_FRAMES, _state_name()])


func _wait_state_not(s: Duelist.State) -> void:
	for i: int in WAIT_FRAMES:
		if _duelist.state != s:
			return
		await physics_frame


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


func _state_name() -> String:
	return Duelist.State.keys()[_duelist.state] as String


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
	print("DUELIST SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
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
