class_name NavProfilesConfig
extends Resource
## Navmesh bake settings per agent size (docs/COMBAT_SPEC.md "Level navigation").
## Tuning file: data/world/nav_profiles.tres. A level bakes one NavigationMesh per profile
## from the same source geometry (a node group) and keeps them on separate navigation maps
## (scripts/levels/zone_navigation.gd), so a human-size enemy and a large monster each
## path only where they fit.
## After changing a value here, rebake every level's navmeshes (Zone 01:
## scripts/levels/rebuild_zone01_navmesh.gd); tests/unit/zone_navigation_test.gd fails while a
## baked navmesh doesn't match this file.

@export_group("Human-size agent")
## Heroine, duelist, guardians.
@export_range(0.05, 5.0, 0.05, "suffix:m") var human_agent_radius: float = 0.4
@export_range(0.5, 5.0, 0.05, "suffix:m") var human_agent_height: float = 1.8

@export_group("Large-monster agent")
## Monster class L (docs/ART_SPEC.md: 5-8 m). Monster #1's body capsule is 2.3 m.
@export_range(0.5, 10.0, 0.05, "suffix:m") var large_agent_radius: float = 2.4
@export_range(1.0, 20.0, 0.1, "suffix:m") var large_agent_height: float = 5.0

@export_group("Shared")
## Step-up height every agent walks over without animation (ART_SPEC step-up 0.35 m).
@export_range(0.0, 2.0, 0.05, "suffix:m") var agent_max_climb: float = 0.35
@export_range(0.0, 89.0, 1.0, "suffix:°") var agent_max_slope: float = 40.0
## Voxel size of the bake; also the navigation maps' cell size. Keep the agent radii
## multiples of cell_size and agent_max_climb / heights multiples of cell_height, or the
## bake rounds them (and warns).
@export_range(0.01, 2.0, 0.01, "suffix:m") var cell_size: float = 0.2
@export_range(0.01, 2.0, 0.01, "suffix:m") var cell_height: float = 0.05

@export_group("Agent matching")
## A NavigationAgent3D with at least this radius uses the large-monster map; smaller ones
## use the human-size map (the World3D's default map).
@export_range(0.1, 10.0, 0.05, "suffix:m") var large_agent_min_radius: float = 1.2


## True if an agent of `radius` should path on the large-monster navmesh.
func is_large_agent(radius: float) -> bool:
	return radius >= large_agent_min_radius


## Writes this profile's bake settings into `navmesh`: collision shapes of the nodes in
## `source_group` (and their children) only, so art meshes never change the navmesh.
func apply_to(navmesh: NavigationMesh, large: bool, source_group: StringName) -> void:
	navmesh.agent_radius = large_agent_radius if large else human_agent_radius
	navmesh.agent_height = large_agent_height if large else human_agent_height
	navmesh.agent_max_climb = agent_max_climb
	navmesh.agent_max_slope = agent_max_slope
	navmesh.cell_size = cell_size
	navmesh.cell_height = cell_height
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navmesh.geometry_source_group_name = source_group


## True if `navmesh` was baked with this profile's current settings.
func matches(navmesh: NavigationMesh, large: bool) -> bool:
	if navmesh == null:
		return false
	var radius: float = large_agent_radius if large else human_agent_radius
	var height: float = large_agent_height if large else human_agent_height
	return is_equal_approx(navmesh.agent_radius, radius) \
		and is_equal_approx(navmesh.agent_height, height) \
		and is_equal_approx(navmesh.agent_max_climb, agent_max_climb) \
		and is_equal_approx(navmesh.agent_max_slope, agent_max_slope) \
		and is_equal_approx(navmesh.cell_size, cell_size) \
		and is_equal_approx(navmesh.cell_height, cell_height) \
		and navmesh.geometry_parsed_geometry_type == NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS \
		and navmesh.geometry_source_geometry_mode == NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
