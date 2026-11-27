extends SceneTree
## Rebuilds Zone 01's navigation (docs/COMBAT_SPEC.md "Level navigation"):
##  1. NavSource/BlockerFootprints in scenes/levels/zone01/Zone01_Gameplay.tscn: one
##     NavigationObstacle3D per solid blocker below the Blockers node (walls, pillars, the
##     arena landmark), the footprint of its box collision. Blockers are not in the nav source
##     group, so their tops never become walkable islands; their footprints carve the
##     navmeshes instead (grown by each profile's agent radius).
##  2. data/navigation/zone01_nav_human.tres and zone01_nav_large.tres, baked from the source
##     group with the profiles in data/world/nav_profiles.tres, with the shortcut gate closed.
## Existing UIDs are kept. Run after moving greybox pieces or changing nav_profiles.tres:
##   godot --headless --path . --script res://scripts/levels/rebuild_zone01_navmesh.gd

const GAMEPLAY: String = "res://scenes/levels/zone01/Zone01_Gameplay.tscn"
const HUMAN: String = "res://data/navigation/zone01_nav_human.tres"
const LARGE: String = "res://data/navigation/zone01_nav_large.tres"
const BLOCKERS: NodePath = ^"Blockers"
const FOOTPRINTS: NodePath = ^"NavSource/BlockerFootprints"
## The footprint reaches this far below a blocker's bottom, so the floor it stands on is
## inside the carved height range.
const FOOTPRINT_MARGIN: float = 0.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = rebuild_footprints()
	var ok: bool = scene != null and await bake(scene, root)
	quit(0 if ok else 1)


## Regenerates the footprint obstacles from the blockers and saves the scene. Returns the
## saved scene, or null on failure.
static func rebuild_footprints() -> PackedScene:
	var gp: Node3D = (load(GAMEPLAY) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node3D
	var blockers: Node3D = gp.get_node_or_null(BLOCKERS) as Node3D
	var footprints: Node3D = gp.get_node_or_null(FOOTPRINTS) as Node3D
	if blockers == null or footprints == null:
		printerr("Zone01_Gameplay needs %s and %s" % [BLOCKERS, FOOTPRINTS])
		gp.free()
		return null
	for child: Node in footprints.get_children():
		footprints.remove_child(child)
		child.free()
	var parent_inv: Transform3D = to_root(gp, footprints).affine_inverse()
	var count: int = 0
	for body: StaticBody3D in find_blocker_bodies(blockers):
		var fp: Dictionary = footprint(gp, body)
		if fp.is_empty():
			printerr("blocker %s has no box collision" % gp.get_path_to(body))
			continue
		var obstacle: NavigationObstacle3D = NavigationObstacle3D.new()
		obstacle.name = body.name
		var origin: Vector3 = Vector3((fp.center as Vector2).x, float(fp.bottom) - FOOTPRINT_MARGIN, (fp.center as Vector2).y)
		obstacle.transform = parent_inv * Transform3D(Basis.IDENTITY, origin)
		var verts: PackedVector3Array = PackedVector3Array()
		for p: Vector2 in fp.outline as PackedVector2Array:
			verts.append(Vector3(p.x - (fp.center as Vector2).x, 0.0, p.y - (fp.center as Vector2).y))
		obstacle.vertices = verts
		obstacle.height = float(fp.top) - float(fp.bottom) + FOOTPRINT_MARGIN
		obstacle.radius = 0.0
		obstacle.avoidance_enabled = false
		obstacle.affect_navigation_mesh = true
		obstacle.carve_navigation_mesh = false # grown by the agent radius
		footprints.add_child(obstacle)
		obstacle.owner = gp
		count += 1
	var scene: PackedScene = PackedScene.new()
	var err: Error = scene.pack(gp)
	gp.free()
	if err != OK or not _save(scene, GAMEPLAY):
		return null
	print("%d blocker footprints" % count)
	return scene


## Bakes both navmeshes from `scene` (added under `tree_root`, gate closed) and saves them.
static func bake(scene: PackedScene, tree_root: Node) -> bool:
	var gp: Node3D = scene.instantiate() as Node3D
	tree_root.add_child(gp)
	await tree_root.get_tree().process_frame
	var gate: ShortcutGate = gp.get_node_or_null(^"NavSource/ShortcutGate") as ShortcutGate
	var nav: ZoneNavigation = gp.get_node(^"Navigation") as ZoneNavigation
	var ok: bool = gate == null or gate.blocks()
	if not ok:
		printerr("the shortcut gate must be closed for the bake")
	else:
		var group: StringName = nav.human_region.navigation_mesh.geometry_source_group_name
		ok = _bake_region(nav.human_region, nav.config, false, group, HUMAN) \
			and _bake_region(nav.large_region, nav.config, true, group, LARGE)
	tree_root.remove_child(gp)
	gp.queue_free()
	return ok


static func _bake_region(region: NavigationRegion3D, config: NavProfilesConfig, large: bool,
		group: StringName, path: String) -> bool:
	var mesh: NavigationMesh = NavigationMesh.new()
	config.apply_to(mesh, large, group)
	var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, region)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	print("%s: %d polygons" % [path, mesh.get_polygon_count()])
	return mesh.get_polygon_count() > 0 and _save(mesh, path)


## Every StaticBody3D at or below `node`.
static func find_blocker_bodies(node: Node) -> Array[StaticBody3D]:
	var found: Array[StaticBody3D] = []
	var body: StaticBody3D = node as StaticBody3D
	if body != null:
		found.append(body)
	for child: Node in node.get_children():
		found.append_array(find_blocker_bodies(child))
	return found


## `node`'s transform relative to `root` (works outside the tree).
static func to_root(root: Node, node: Node) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		var n3: Node3D = n as Node3D
		if n3 != null:
			xf = n3.transform * xf
		n = n.get_parent()
	return xf


## A blocker's footprint relative to `root`, from its BoxShape3D collision shapes:
## {outline: PackedVector2Array (XZ convex hull), center: Vector2, bottom: float, top: float}.
## Empty if it has no box collision.
static func footprint(root: Node, body: StaticBody3D) -> Dictionary:
	var points: PackedVector2Array = PackedVector2Array()
	var bottom: float = INF
	var top: float = -INF
	for child: Node in body.get_children():
		var shape_node: CollisionShape3D = child as CollisionShape3D
		if shape_node == null or shape_node.disabled:
			continue
		var box: BoxShape3D = shape_node.shape as BoxShape3D
		if box == null:
			continue
		var xf: Transform3D = to_root(root, shape_node)
		var h: Vector3 = box.size * 0.5
		for i: int in 8:
			var corner: Vector3 = xf * Vector3(h.x if (i & 1) != 0 else -h.x, h.y if (i & 2) != 0 else -h.y, h.z if (i & 4) != 0 else -h.z)
			points.append(Vector2(corner.x, corner.z))
			bottom = minf(bottom, corner.y)
			top = maxf(top, corner.y)
	if points.is_empty():
		return {}
	var hull: PackedVector2Array = Geometry2D.convex_hull(points)
	hull.resize(hull.size() - 1) # convex_hull repeats the first point at the end
	var center: Vector2 = Vector2.ZERO
	for p: Vector2 in hull:
		center += p
	center /= float(hull.size())
	return {"outline": hull, "center": center, "bottom": bottom, "top": top}


## Saves with the path's existing UID: --script mode drops the uid header.
static func _save(resource: Resource, path: String) -> bool:
	var uid: int = _uid_in_file(path)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var err: Error = ResourceSaver.save(resource, path)
	if err != OK:
		printerr("could not save %s (%s)" % [path, error_string(err)])
		return false
	ResourceSaver.set_uid(path, uid)
	print("saved ", path)
	return true


## The uid in a saved resource/scene header.
static func _uid_in_file(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	var header: String = FileAccess.open(path, FileAccess.READ).get_line()
	var at: int = header.find("uid=\"uid://")
	if at < 0:
		return ResourceUID.INVALID_ID
	var end: int = header.find("\"", at + 5)
	return ResourceUID.text_to_id(header.substr(at + 5, end - at - 5))
