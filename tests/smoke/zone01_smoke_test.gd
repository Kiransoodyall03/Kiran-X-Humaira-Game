extends SceneTree
## Headless smoke test for the Zone 01 greybox slice (docs/ZONE01.md). Loads
## scenes/levels/zone01/Zone01.tscn and checks that: it loads with the Gameplay sub-scene
## and the temporary lighting (no Art/Lighting scenes yet); both navmeshes (human-size and
## large-monster, baked from the same source group) have polygons and sit on separate
## navigation maps, with the duelist on the human map and monster #1 on the large one; Shrine
## A is the start respawn point; a human path runs from Shrine A to the boss arena and up to
## the vista; the vista has a clear line of sight to the arena; the large agent can path
## inside the arena but its navmesh never leaves it; the stealth pocket has its marked
## volumes; the shortcut gate refuses to open from the near side (prompt and interact), opens
## from the far side, blocks until it is fully open, then stops blocking (physics and navigation: she walks through and the
## path through it gets short); and resting at Shrine B makes it the respawn point, so a
## death respawns her there.
## Fails on any engine/script error, and on a frame-budget timeout instead of hanging.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/zone01_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const ZONE: String = "res://scenes/levels/zone01/Zone01.tscn"
const MAX_RUN_FRAMES: int = 3000

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _gp: Node3D
var _player: PlayerController
var _player_c: Combatant
var _rest: PlayerRest
var _shrine_a: Shrine
var _shrine_b: Shrine
var _gate: ShortcutGate
var _nav: ZoneNavigation
var _duelist: Duelist
var _monster: LargeMonster


func _initialize() -> void:
	OS.add_logger(_errors)
	physics_frame.connect(_watchdog)
	_run.call_deferred()


func _run() -> void:
	var level: Node3D = (load(ZONE) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	_gp = level.get_node_or_null("Zone01_Gameplay") as Node3D
	_expect(_gp != null, "Zone01 instances Zone01_Gameplay")
	_expect(level.get_node_or_null("TEMP_PlaceholderLighting/WorldEnvironment") is WorldEnvironment, "temporary placeholder lighting is present")
	_expect(level.get_node_or_null("Zone01_Art") == null and level.get_node_or_null("Zone01_Lighting") == null, "no Art/Lighting scenes are faked in (they are A's)")
	if _gp == null:
		_finish()
		return
	_player = _gp.get_node("Actors/Heroine") as PlayerController
	_player_c = _player.combatant
	_rest = _player.get_node_or_null("Rest") as PlayerRest
	_shrine_a = _gp.get_node_or_null("NavSource/ShrineA") as Shrine
	_shrine_b = _gp.get_node_or_null("NavSource/ShrineB") as Shrine
	_gate = _gp.get_node_or_null("NavSource/ShortcutGate") as ShortcutGate
	_nav = _gp.get_node_or_null("Navigation") as ZoneNavigation
	_duelist = _gp.get_node_or_null("Actors/Duelist") as Duelist
	_monster = _gp.get_node_or_null("Actors/Monster01") as LargeMonster
	_expect(_rest != null and _shrine_a != null and _shrine_b != null and _gate != null and _nav != null and _duelist != null and _monster != null,
		"the zone has the heroine (with Rest), two shrines, the shortcut gate, navigation, the duelist and monster #1")
	if _rest == null or _shrine_a == null or _shrine_b == null or _gate == null or _nav == null or _duelist == null or _monster == null:
		_finish()
		return
	await _wait_maps_synced()

	_test_navigation_setup()
	_test_start_shrine()
	_test_human_paths()
	_test_vista_sees_arena()
	_test_large_agent_in_arena()
	_test_stealth_volumes()
	await _test_shortcut_gate()
	await _test_rest_at_shrine_b()
	_finish()


func _test_navigation_setup() -> void:
	var human: NavigationRegion3D = _nav.human_region
	var large: NavigationRegion3D = _nav.large_region
	var hm: NavigationMesh = human.navigation_mesh
	var lm: NavigationMesh = large.navigation_mesh
	_expect(hm != null and hm.get_polygon_count() > 0, "human navmesh has polygons (%d)" % (hm.get_polygon_count() if hm != null else 0))
	_expect(lm != null and lm.get_polygon_count() > 0, "large navmesh has polygons (%d)" % (lm.get_polygon_count() if lm != null else 0))
	if hm == null or lm == null:
		return
	_expect(_nav.config.matches(hm, false), "human navmesh baked with the human profile (radius %.2f)" % hm.agent_radius)
	_expect(_nav.config.matches(lm, true), "large navmesh baked with the large profile (radius %.2f)" % lm.agent_radius)
	_expect(hm.geometry_source_group_name == lm.geometry_source_group_name, "both navmeshes bake from the same source group")
	var sources: Array[Node] = get_nodes_in_group(hm.geometry_source_group_name)
	_expect(sources.size() == 1 and sources[0] == _gp.get_node("NavSource"), "the source group is the zone's NavSource node")
	var world_map: RID = _player.get_world_3d().navigation_map
	_expect(_nav.human_map() == world_map, "the human region is on the world's default map")
	_expect(_nav.large_map().is_valid() and large.get_navigation_map() == _nav.large_map(), "the large region is on its own map")
	_expect(_nav.large_map() != world_map, "the two navmeshes are on separate maps")
	var duelist_agent: NavigationAgent3D = _duelist.get_node("NavigationAgent3D") as NavigationAgent3D
	var monster_agent: NavigationAgent3D = _monster.get_node("NavigationAgent3D") as NavigationAgent3D
	_expect(duelist_agent.get_navigation_map() == world_map, "the duelist paths on the human map")
	_expect(monster_agent.get_navigation_map() == _nav.large_map(), "monster #1 paths on the large map")
	_expect(_duelist.uses_navigation() and _monster.uses_navigation(), "both enemies see a navmesh on their map")


func _test_start_shrine() -> void:
	_expect(_rest.will_respawn() and _rest.respawn_shrine == _shrine_a, "Shrine A is the start respawn point")
	_expect(_flat(_player.global_position - _shrine_a.spawn_transform().origin).length() < 0.5, "she starts at Shrine A")


func _test_human_paths() -> void:
	var map: RID = _nav.human_map()
	var start: Vector3 = _shrine_a.spawn_transform().origin
	var arena: Vector3 = _marker("ArenaCenter")
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, arena, true)
	_expect(path.size() >= 2, "a human path from Shrine A to the arena exists (%d points)" % path.size())
	if path.size() >= 2:
		_expect(_flat(path[0] - start).length() < 1.0, "the path starts at Shrine A")
		_expect(_flat(path[path.size() - 1] - arena).length() < 1.0, "the path reaches the arena centre (ends %s)" % path[path.size() - 1])
		_expect(_length(path) > 120.0, "it takes the long way, not through the closed shortcut (%.0f m)" % _length(path))
	var vista: Vector3 = _marker("VistaPoint")
	var to_vista: PackedVector3Array = NavigationServer3D.map_get_path(map, start, vista, true)
	_expect(to_vista.size() >= 2 and (to_vista[to_vista.size() - 1] - vista).length() < 1.0, "the vista platform is reachable on foot (up the ramp)")


func _test_vista_sees_arena() -> void:
	var eye: Vector3 = _marker("VistaPoint") + Vector3(0.0, 1.6, 0.0)
	var target: Vector3 = _marker("ArenaCenter") + Vector3(0.0, 3.0, 0.0)
	var hit: Dictionary = _ray(eye, target)
	_expect(hit.is_empty(), "the vista sees the arena centre (blocked by %s)" % (str(hit.get("collider")) if not hit.is_empty() else "nothing"))


func _test_large_agent_in_arena() -> void:
	var map: RID = _nav.large_map()
	var centre: Vector3 = _marker("ArenaCenter")
	var corner: Vector3 = Vector3(16.0, 0.0, -121.0)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, centre, corner, true)
	_expect(path.size() >= 2 and _flat(path[path.size() - 1] - corner).length() < 1.0, "the large agent can path across the arena (%d points)" % path.size())
	var monster_home: Vector3 = NavigationServer3D.map_get_closest_point(map, _monster.global_position)
	_expect(_flat(monster_home - _monster.global_position).length() < 0.5, "monster #1 stands on the large navmesh")
	# The 4 m arena gate is too narrow for the large agent: it can't path out to Shrine B.
	var hall: Vector3 = _shrine_b.spawn_transform().origin
	var out: PackedVector3Array = NavigationServer3D.map_get_path(map, centre, hall, true)
	var reached: float = _flat(out[out.size() - 1] - hall).length() if out.size() > 0 else INF
	_expect(reached > 5.0, "the large agent can't path out of the arena (stops %.1f m short of Shrine B)" % reached)
	var arena_gate: Vector3 = _marker("ArenaEntrance")
	var gate_nearest: Vector3 = NavigationServer3D.map_get_closest_point(map, arena_gate)
	_expect(_flat(gate_nearest - arena_gate).length() > 1.5, "the large navmesh doesn't enter the 4 m arena gate")
	var human_nearest: Vector3 = NavigationServer3D.map_get_closest_point(_nav.human_map(), hall)
	_expect(_flat(human_nearest - hall).length() < 0.5, "the human navmesh covers Shrine B's hall")


func _test_stealth_volumes() -> void:
	var kinds: Dictionary[int, int] = {}
	for node: Node in get_nodes_in_group(StealthVolume.GROUP):
		var v: StealthVolume = node as StealthVolume
		if v != null:
			kinds[v.kind] = kinds.get(v.kind, 0) + 1
	for k: StealthVolume.Kind in [StealthVolume.Kind.OVERLOOK, StealthVolume.Kind.HIGH_ROUTE, StealthVolume.Kind.LOW_ROUTE,
			StealthVolume.Kind.HIDE_SPOT, StealthVolume.Kind.LANTERN_POOL, StealthVolume.Kind.PATROL_LOOP]:
		_expect(kinds.get(k, 0) > 0, "the stealth pocket marks a %s volume" % StealthVolume.Kind.keys()[k])


func _test_shortcut_gate() -> void:
	var near: Vector3 = _marker("ShortcutNearSide")
	var far: Vector3 = _marker("ShortcutFarSide")
	var map: RID = _nav.human_map()
	_expect(not _gate.is_far_side(near) and _gate.is_far_side(far), "the far side is the Shrine B hall side")
	var closed_path: PackedVector3Array = NavigationServer3D.map_get_path(map, near, far, true)
	_expect(closed_path.size() < 2 or _length(closed_path) > 60.0, "closed: no short path through the gate (%.0f m)" % _length(closed_path))
	_expect(not _ray(near + Vector3.UP, far + Vector3.UP).is_empty(), "closed: the gate blocks the way")

	# Near side: locked prompt, interact does nothing, and she can't walk through.
	_place(near, Vector3.RIGHT)
	await _physics_frames(4)
	_expect(_gate.player_in_range(), "near side counts as in range")
	_expect(_gate.prompt_visible() and _gate.prompt_text() == ShortcutGate.PROMPT_LOCKED, "near side prompt says it opens from the other side (%s)" % _gate.prompt_text())
	_expect(not _gate.can_open(), "can't open from the near side")
	await _tap(&"interact")
	await _physics_frames(2)
	_expect(not _gate.is_opening() and not _gate.is_open(), "interact on the near side leaves it closed")
	Input.action_press(&"move_forward")
	await _physics_frames(90)
	Input.action_release(&"move_forward")
	_expect(_player.global_position.x < -45.2, "she can't walk through the closed gate (x %.2f)" % _player.global_position.x)

	# Far side: opens.
	var opened: Array[int] = [0]
	_gate.opened.connect(func() -> void: opened[0] += 1)
	_place(far, Vector3.LEFT)
	await _physics_frames(4)
	_expect(_gate.prompt_visible() and _gate.prompt_text() == ShortcutGate.PROMPT_OPEN, "far side prompt offers Open (%s)" % _gate.prompt_text())
	await _tap(&"interact")
	_expect(_gate.is_opening(), "interact on the far side starts opening it")
	_expect(_gate.blocks(), "it still blocks while opening")
	# Nearly open (the panel mesh is high enough to walk under): its collision still blocks.
	await _physics_frames(_gate.config.open_frames - 4)
	_expect(_gate.is_opening(), "still opening a few frames before its open frames")
	_expect(not _ray(near + Vector3.UP, far + Vector3.UP).is_empty(), "nearly open: the gate still blocks the way at waist height")
	await _physics_frames(7)
	_expect(_gate.is_open() and opened[0] == 1, "the gate is open after its open frames")
	_expect(not _gate.blocks() and _gate.link_enabled(), "open: collision off, nav link on")
	_expect(not _gate.prompt_visible(), "no prompt once open")
	_expect(_ray(near + Vector3.UP, far + Vector3.UP).is_empty(), "open: nothing blocks the way")
	await _physics_frames(3)
	var open_path: PackedVector3Array = NavigationServer3D.map_get_path(map, near, far, true)
	_expect(open_path.size() >= 2 and _length(open_path) < 12.0, "open: the path goes through the gate (%.1f m)" % _length(open_path))
	# She walks back through to the near side.
	_place(far, Vector3.LEFT)
	await _physics_frames(2)
	Input.action_press(&"move_forward")
	await _physics_frames(90)
	Input.action_release(&"move_forward")
	_expect(_player.global_position.x < -46.0, "she walks through the open gate (x %.2f)" % _player.global_position.x)


func _test_rest_at_shrine_b() -> void:
	_place(_shrine_b.spawn_transform().origin, Vector3.BACK)
	await _physics_frames(4)
	_expect(_shrine_b.player_in_range() and _shrine_b.prompt_text() == Shrine.PROMPT_REST, "Shrine B offers Rest (%s)" % _shrine_b.prompt_text())
	await _tap(&"interact")
	_expect(_rest.respawn_shrine == _shrine_b, "resting at Shrine B makes it the respawn point")
	_expect(_rest.respawn_transform.origin.is_equal_approx(_shrine_b.spawn_transform().origin), "respawn point = Shrine B's SpawnPoint")
	# Die somewhere else: she comes back at Shrine B.
	_place(_marker("ArenaEntrance"), Vector3.FORWARD)
	await _physics_frames(3)
	var hit: AttackData = AttackData.new()
	hit.id = &"smoke_zone_kill"
	hit.damage = 10000.0
	hit.posture_damage = 0.0
	_player_c.receive_attack(hit)
	_expect(_player_c.is_dead, "she died at the arena entrance")
	await _combat_frames(_rest.config.respawn_delay_frames + 15)
	_expect(not _player_c.is_dead, "she respawned")
	_expect(_flat(_player.global_position - _shrine_b.spawn_transform().origin).length() < 0.5, "she respawned at Shrine B")


# --- helpers

func _marker(n: String) -> Vector3:
	return (_gp.get_node("Markers/" + n) as Node3D).global_position


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
	return _player.get_world_3d().direct_space_state.intersect_ray(q)


## Puts her at `pos` facing `facing`, with the camera behind her (move_forward = facing).
func _place(pos: Vector3, facing: Vector3) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(facing)
	_player.camera_rig.set_view_yaw(atan2(-facing.x, -facing.z))
	_player.reset_physics_interpolation()


func _wait_maps_synced() -> void:
	for i: int in 120:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(_nav.human_map()) > 0 \
				and NavigationServer3D.map_get_iteration_id(_nav.large_map()) > 0 and i > 4:
			return
	_expect(false, "both navigation maps synced within 120 frames")


static func _length(path: PackedVector3Array) -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


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
	print("ZONE01 SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
