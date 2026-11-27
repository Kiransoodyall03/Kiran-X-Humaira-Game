extends GdUnitTestSuite
## Level navigation and the shortcut gate (docs/COMBAT_SPEC.md "Level navigation"):
## NavProfilesConfig agent matching and bake settings, the shipped data/world/nav_profiles.tres
## against the actors that use it, the baked Zone 01 navmeshes matching the profiles (fails
## after a profile change until they are rebaked), ZoneNavigation putting agents on the map
## that fits them (also after the level re-enters the tree), no walkable islands on top of or
## inside Zone 01's walls, pillars and landmark, and the shortcut gate's far-side rule and
## blocking until it is fully open.

const NAV_PROFILES: String = "res://data/world/nav_profiles.tres"
const NAV_HUMAN: String = "res://data/navigation/zone01_nav_human.tres"
const NAV_LARGE: String = "res://data/navigation/zone01_nav_large.tres"
const GATE_CFG: String = "res://data/world/shortcut_gate.tres"
const GATE_SCENE: String = "res://scenes/world/shortcut_gate.tscn"
const DUELIST: String = "res://scenes/actors/duelist.tscn"
const MONSTER: String = "res://scenes/actors/monster01.tscn"
const MONSTER_AI: String = "res://data/combat/monster01_ai.tres"
const ZONE01_GAMEPLAY: String = "res://scenes/levels/zone01/Zone01_Gameplay.tscn"
## Zone 01's solid blockers (walls, pillars, the arena landmark), wherever they sit in the scene.
const BLOCKER_PREFIXES: Array[String] = ["Wall_", "Combat_Pillar_", "Arena_Landmark"]


func _profiles() -> NavProfilesConfig:
	return load(NAV_PROFILES) as NavProfilesConfig


func _agent_radius(scene_path: String) -> float:
	var actor: Node = auto_free((load(scene_path) as PackedScene).instantiate()) as Node
	var agent: NavigationAgent3D = actor.get_node("NavigationAgent3D") as NavigationAgent3D
	return agent.radius


func test_is_large_agent_threshold() -> void:
	var c: NavProfilesConfig = NavProfilesConfig.new()
	c.large_agent_min_radius = 1.2
	assert_bool(c.is_large_agent(0.4)).is_false()
	assert_bool(c.is_large_agent(1.19)).is_false()
	assert_bool(c.is_large_agent(1.2)).is_true()
	assert_bool(c.is_large_agent(2.5)).is_true()


func test_apply_to_and_matches() -> void:
	var c: NavProfilesConfig = NavProfilesConfig.new()
	var human: NavigationMesh = NavigationMesh.new()
	var large: NavigationMesh = NavigationMesh.new()
	c.apply_to(human, false, &"some_group")
	c.apply_to(large, true, &"some_group")
	assert_float(human.agent_radius).is_equal_approx(c.human_agent_radius, 0.0001)
	assert_float(large.agent_radius).is_equal_approx(c.large_agent_radius, 0.0001)
	assert_float(large.agent_height).is_equal_approx(c.large_agent_height, 0.0001)
	assert_str(String(human.geometry_source_group_name)).is_equal("some_group")
	assert_int(human.geometry_source_geometry_mode).is_equal(NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN)
	assert_int(large.geometry_parsed_geometry_type).is_equal(NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS)
	assert_bool(c.matches(human, false)).is_true()
	assert_bool(c.matches(large, true)).is_true()
	assert_bool(c.matches(human, true)).is_false()
	c.human_agent_radius += 0.2
	assert_bool(c.matches(human, false)).is_false()
	assert_bool(c.matches(null, false)).is_false()


func test_shipped_profiles_fit_the_actors() -> void:
	var c: NavProfilesConfig = _profiles()
	assert_object(c).is_not_null()
	assert_float(c.human_agent_radius).is_equal_approx(0.4, 0.001)
	assert_float(c.human_agent_height).is_equal_approx(1.8, 0.001)
	assert_float(c.agent_max_climb).is_equal_approx(0.35, 0.001) # ART_SPEC step-up
	var monster_cfg: LargeMonsterConfig = load(MONSTER_AI) as LargeMonsterConfig
	assert_float(c.large_agent_radius).is_greater_equal(monster_cfg.body_radius)
	assert_bool(c.is_large_agent(_agent_radius(DUELIST))).is_false()
	assert_bool(c.is_large_agent(_agent_radius(MONSTER))).is_true()
	# No rounding in the bake: radii are whole cells, climb and heights whole cell heights.
	for v: float in [c.human_agent_radius, c.large_agent_radius]:
		assert_float(fposmod(v + 0.0001, c.cell_size)).is_less(0.001)
	for v: float in [c.agent_max_climb, c.human_agent_height, c.large_agent_height]:
		assert_float(fposmod(v + 0.0001, c.cell_height)).is_less(0.001)
	# The navigation maps use the same cell size (project default map).
	assert_float(float(ProjectSettings.get_setting("navigation/3d/default_cell_size"))).is_equal_approx(c.cell_size, 0.0001)
	assert_float(float(ProjectSettings.get_setting("navigation/3d/default_cell_height"))).is_equal_approx(c.cell_height, 0.0001)


func test_zone01_navmeshes_are_baked_with_current_profiles() -> void:
	var c: NavProfilesConfig = _profiles()
	var human: NavigationMesh = load(NAV_HUMAN) as NavigationMesh
	var large: NavigationMesh = load(NAV_LARGE) as NavigationMesh
	assert_bool(c.matches(human, false)).override_failure_message("zone01 human navmesh is stale: run scripts/levels/rebuild_zone01_navmesh.gd").is_true()
	assert_bool(c.matches(large, true)).override_failure_message("zone01 large navmesh is stale: run scripts/levels/rebuild_zone01_navmesh.gd").is_true()
	assert_int(human.get_polygon_count()).is_greater(0)
	assert_int(large.get_polygon_count()).is_greater(0)
	assert_str(String(human.geometry_source_group_name)).is_equal(String(large.geometry_source_group_name))
	# The large agent fits in fewer places than the human one.
	assert_int(large.get_polygon_count()).is_less(human.get_polygon_count())


func test_zone01_navmeshes_have_no_polygons_on_blockers() -> void:
	# Walls, pillars and the landmark must carve the navmeshes, not add walkable (and
	# unreachable) islands on their tops or inside them. Rebuild with
	# scripts/levels/rebuild_zone01_navmesh.gd if this fails.
	var gp: Node = auto_free((load(ZONE01_GAMEPLAY) as PackedScene).instantiate()) as Node
	var rects: Array[Rect2] = []
	var names: Array[String] = []
	_collect_blocker_footprints(gp, gp, rects, names)
	assert_int(rects.size()).override_failure_message("no Zone 01 blockers found").is_greater(50)
	assert_bool(names.has("Arena_Landmark_16m")).is_true()
	for path: String in [NAV_HUMAN, NAV_LARGE]:
		var mesh: NavigationMesh = load(path) as NavigationMesh
		var verts: PackedVector3Array = mesh.get_vertices()
		var bad: Array[String] = []
		for p: int in mesh.get_polygon_count():
			var poly: PackedInt32Array = mesh.get_polygon(p)
			var c: Vector3 = Vector3.ZERO
			for vi: int in poly:
				c += verts[vi]
			c /= float(poly.size())
			for r: int in rects.size():
				if rects[r].has_point(Vector2(c.x, c.z)):
					bad.append("%s at %s" % [names[r], c])
		assert_array(bad).override_failure_message("%s has %d polygons on/inside blockers: %s" % [path, bad.size(), bad.slice(0, 5)]) 			.is_empty()


## XZ footprints (shrunk 5 cm) of every StaticBody3D named like a blocker below `node`.
func _collect_blocker_footprints(root: Node, node: Node, rects: Array[Rect2], names: Array[String]) -> void:
	var body: StaticBody3D = node as StaticBody3D
	if body != null and BLOCKER_PREFIXES.any(func(pre: String) -> bool: return String(body.name).begins_with(pre)):
		for child: Node in body.get_children():
			var shape_node: CollisionShape3D = child as CollisionShape3D
			var box: BoxShape3D = (shape_node.shape as BoxShape3D) if shape_node != null else null
			if box == null:
				continue
			var xf: Transform3D = _to_root(root, shape_node)
			var h: Vector3 = box.size * 0.5
			var rect: Rect2 = Rect2()
			for i: int in 8:
				var corner: Vector3 = xf * Vector3(h.x if (i & 1) != 0 else -h.x, h.y if (i & 2) != 0 else -h.y, h.z if (i & 4) != 0 else -h.z)
				var pt: Vector2 = Vector2(corner.x, corner.z)
				rect = Rect2(pt, Vector2.ZERO) if i == 0 else rect.expand(pt)
			rects.append(rect.grow(-0.05))
			names.append(String(body.name))
	for child: Node in node.get_children():
		_collect_blocker_footprints(root, child, rects, names)


static func _to_root(root: Node, node: Node) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		var n3: Node3D = n as Node3D
		if n3 != null:
			xf = n3.transform * xf
		n = n.get_parent()
	return xf


## A level with a ZoneNavigation (fresh human/large regions) and two agents below `actors`.
func _make_nav_level() -> Dictionary:
	var level: Node3D = auto_free(Node3D.new()) as Node3D
	var nav: ZoneNavigation = ZoneNavigation.new()
	nav.config = _profiles()
	var human: NavigationRegion3D = NavigationRegion3D.new()
	var large: NavigationRegion3D = NavigationRegion3D.new()
	human.navigation_mesh = NavigationMesh.new()
	large.navigation_mesh = NavigationMesh.new()
	nav.config.apply_to(human.navigation_mesh, false, &"unit_test_nav")
	nav.config.apply_to(large.navigation_mesh, true, &"unit_test_nav")
	nav.add_child(human)
	nav.add_child(large)
	nav.human_region = human
	nav.large_region = large
	level.add_child(nav)
	var actors: Node3D = Node3D.new()
	level.add_child(actors)
	var small_agent: NavigationAgent3D = NavigationAgent3D.new()
	small_agent.radius = 0.4
	var big_agent: NavigationAgent3D = NavigationAgent3D.new()
	big_agent.radius = 2.5
	actors.add_child(small_agent)
	actors.add_child(big_agent)
	nav.agents_root = actors
	return {"level": level, "nav": nav, "large": large, "actors": actors, "small": small_agent, "big": big_agent}


func test_zone_navigation_assigns_agents_by_radius() -> void:
	var d: Dictionary = _make_nav_level()
	var level: Node3D = d.level as Node3D
	var nav: ZoneNavigation = d.nav as ZoneNavigation
	var large: NavigationRegion3D = d.large as NavigationRegion3D
	var actors: Node3D = d.actors as Node3D
	var small_agent: NavigationAgent3D = d.small as NavigationAgent3D
	var big_agent: NavigationAgent3D = d.big as NavigationAgent3D
	add_child(level)
	var world_map: RID = level.get_world_3d().navigation_map
	assert_bool(nav.large_map().is_valid()).is_true()
	assert_bool(nav.large_map() != world_map).is_true()
	assert_bool(nav.human_map() == world_map).is_true()
	assert_bool(large.get_navigation_map() == nav.large_map()).is_true()
	assert_bool(small_agent.get_navigation_map() == world_map).is_true()
	assert_bool(big_agent.get_navigation_map() == nav.large_map()).is_true()
	assert_int(ZoneNavigation.find_agents(actors).size()).is_equal(2)
	# An agent added later is matched too (deferred).
	var late: NavigationAgent3D = NavigationAgent3D.new()
	late.radius = 3.0
	actors.add_child(late)
	await await_idle_frame()
	assert_bool(late.get_navigation_map() == nav.large_map()).is_true()
	remove_child(level)


func test_zone_navigation_keeps_maps_separate_after_reentry() -> void:
	var d: Dictionary = _make_nav_level()
	var level: Node3D = d.level as Node3D
	var nav: ZoneNavigation = d.nav as ZoneNavigation
	var large: NavigationRegion3D = d.large as NavigationRegion3D
	var actors: Node3D = d.actors as Node3D
	var small_agent: NavigationAgent3D = d.small as NavigationAgent3D
	var big_agent: NavigationAgent3D = d.big as NavigationAgent3D
	add_child(level)
	var first_map: RID = nav.large_map()
	assert_bool(first_map.is_valid()).is_true()
	# Leave the tree: the large map is freed and everything falls back to the default map.
	remove_child(level)
	assert_bool(nav.large_map().is_valid()).is_false()
	# Come back (e.g. the zone is unloaded and loaded again): two separate maps again.
	add_child(level)
	await await_idle_frame()
	var world_map: RID = level.get_world_3d().navigation_map
	assert_bool(nav.large_map().is_valid()) 		.override_failure_message("re-added ZoneNavigation has no large map").is_true()
	assert_bool(nav.large_map() != world_map).is_true()
	assert_bool(large.get_navigation_map() == nav.large_map()) 		.override_failure_message("re-added large region is not on the large map").is_true()
	assert_bool(big_agent.get_navigation_map() == nav.large_map()) 		.override_failure_message("re-added large agent is not on the large map").is_true()
	assert_bool(small_agent.get_navigation_map() == world_map).is_true()
	# Agents added after re-entry are still matched.
	var late: NavigationAgent3D = NavigationAgent3D.new()
	late.radius = 3.0
	actors.add_child(late)
	await await_idle_frame()
	assert_bool(late.get_navigation_map() == nav.large_map()).is_true()
	remove_child(level)


func test_gate_opens_only_from_far_side() -> void:
	var cfg: ShortcutGateConfig = load(GATE_CFG) as ShortcutGateConfig
	assert_int(cfg.open_frames).is_greater(0)
	var gate: ShortcutGate = auto_free((load(GATE_SCENE) as PackedScene).instantiate()) as ShortcutGate
	gate.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(10.0, 0.0, 0.0))
	add_child(gate)
	# Local +Z is world +X after the turn.
	assert_bool(gate.is_far_side(Vector3(12.0, 0.0, 0.0))).is_true()
	assert_bool(gate.is_far_side(Vector3(8.0, 0.0, 0.0))).is_false()
	assert_bool(gate.is_open()).is_false()
	assert_bool(gate.blocks()).is_true()
	assert_bool(gate.link_enabled()).is_false()
	# No heroine in range: it can't be opened at all.
	assert_bool(gate.can_open()).is_false()
	assert_bool(gate.try_open()).is_false()
	remove_child(gate)


func test_gate_blocks_until_fully_open() -> void:
	var gate: ShortcutGate = auto_free((load(GATE_SCENE) as PackedScene).instantiate()) as ShortcutGate
	add_child(gate)
	await get_tree().physics_frame
	var shape: CollisionShape3D = gate.get_node("Panel/Shape") as CollisionShape3D
	var mesh: Node3D = gate.get_node("Panel/Mesh") as Node3D
	var shape_pos: Vector3 = shape.global_position
	var mesh_y: float = mesh.global_position.y
	# Waist height straight through the gate (local -Z to +Z).
	var from: Vector3 = gate.to_global(Vector3(0.0, 1.0, -2.0))
	var to: Vector3 = gate.to_global(Vector3(0.0, 1.0, 2.0))
	assert_bool(_ray_hits(gate, from, to)).is_true()
	# Open it (no heroine needed for this check) and wait until the panel is 80 % up, well
	# past the height where she would fit under it if its collision rose with it.
	gate.state = ShortcutGate.State.OPENING
	for i: int in gate.config.open_frames + 10:
		if mesh.global_position.y >= mesh_y + gate.config.open_lift * 0.8 or not gate.is_opening():
			break
		await get_tree().physics_frame
	assert_bool(gate.is_opening()).is_true()
	assert_float(mesh.global_position.y).is_greater_equal(mesh_y + gate.config.open_lift * 0.8)
	assert_bool(gate.blocks()).is_true()
	assert_vector(shape.global_position).override_failure_message("the gate's collision moved while opening") 		.is_equal_approx(shape_pos, Vector3(0.001, 0.001, 0.001))
	assert_bool(_ray_hits(gate, from, to)).override_failure_message("she can pass under the gate before it is fully open") 		.is_true()
	for i: int in gate.config.open_frames + 4:
		if gate.is_open():
			break
		await get_tree().physics_frame
	for i: int in 3:
		await get_tree().physics_frame
	assert_bool(gate.is_open()).is_true()
	assert_bool(gate.blocks()).is_false()
	assert_bool(_ray_hits(gate, from, to)).is_false()
	remove_child(gate)


func _ray_hits(node: Node3D, from: Vector3, to: Vector3) -> bool:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	return not node.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
