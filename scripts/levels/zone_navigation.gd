class_name ZoneNavigation
extends Node3D
## A level's navigation (docs/COMBAT_SPEC.md "Level navigation"): two NavigationRegion3D
## children baked from the same source geometry group with NavProfilesConfig, one for
## human-size agents and one for large monsters. The human region stays on the World3D's
## default map; on ready the large region is moved to its own navigation map so the two
## navmeshes never merge. Every NavigationAgent3D below agents_root (and any added later)
## is put on the map that fits its radius (NavProfilesConfig.is_large_agent), so the
## duelist paths on the human navmesh and monster #1 on the large one.
## Leaving the tree frees the large map and puts everything back on the default map; it
## also requests _ready again, so re-adding the level (or this node) sets both maps up anew.
## Rebake Zone 01 with scripts/levels/rebuild_zone01_navmesh.gd (both regions use the source
## group, so set dressing never changes them; solid blockers only carve via their footprints).

@export var config: NavProfilesConfig
@export var human_region: NavigationRegion3D
@export var large_region: NavigationRegion3D
## Agents below this node are matched to a map. Default: this node's parent.
@export var agents_root: Node

var _large_map: RID
var _agents: Array[NavigationAgent3D] = []


func _ready() -> void:
	assert(config != null, "ZoneNavigation needs a NavProfilesConfig")
	assert(human_region != null and large_region != null, "ZoneNavigation needs both regions")
	# The maps' cell size must match the baked navmeshes' (the project default is 0.25 m).
	_match_cell_size(human_map(), human_region.navigation_mesh)
	_large_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(_large_map, Vector3.UP)
	_match_cell_size(_large_map, large_region.navigation_mesh)
	NavigationServer3D.map_set_active(_large_map, true)
	large_region.set_navigation_map(_large_map)
	if agents_root == null:
		agents_root = get_parent()
	if agents_root != null:
		for agent: NavigationAgent3D in find_agents(agents_root):
			assign_agent(agent)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for agent: NavigationAgent3D in _agents:
		if is_instance_valid(agent):
			agent.set_navigation_map(RID())
	_agents.clear()
	if large_region != null:
		large_region.set_navigation_map(RID())
	if _large_map.is_valid():
		NavigationServer3D.free_rid(_large_map)
		_large_map = RID()
	# _ready runs only once per node unless requested: without this a re-added level would
	# keep every agent and the large region on the default map (the navmeshes would merge).
	request_ready()


## The human-size agents' map (the World3D default map).
func human_map() -> RID:
	return human_region.get_navigation_map()


## The large monsters' map.
func large_map() -> RID:
	return _large_map


## The map an agent of `radius` uses.
func map_for_radius(radius: float) -> RID:
	return _large_map if config.is_large_agent(radius) else human_map()


## Puts `agent` on the map that fits its radius.
func assign_agent(agent: NavigationAgent3D) -> void:
	if not is_instance_valid(agent):
		return
	agent.set_navigation_map(map_for_radius(agent.radius))
	if not _agents.has(agent):
		_agents.append(agent)


## Every NavigationAgent3D at or below `node`.
static func find_agents(node: Node) -> Array[NavigationAgent3D]:
	var found: Array[NavigationAgent3D] = []
	var agent: NavigationAgent3D = node as NavigationAgent3D
	if agent != null:
		found.append(agent)
	for child: Node in node.get_children():
		found.append_array(find_agents(child))
	return found


func _match_cell_size(map: RID, mesh: NavigationMesh) -> void:
	if not map.is_valid():
		return
	NavigationServer3D.map_set_cell_size(map, mesh.cell_size if mesh != null else config.cell_size)
	NavigationServer3D.map_set_cell_height(map, mesh.cell_height if mesh != null else config.cell_height)


func _on_node_added(node: Node) -> void:
	var agent: NavigationAgent3D = node as NavigationAgent3D
	if agent != null and agents_root != null and agents_root.is_ancestor_of(agent):
		assign_agent.call_deferred(agent)
