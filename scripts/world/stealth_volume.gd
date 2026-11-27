class_name StealthVolume
extends Area3D
## A marked stealth-pocket volume (docs/ZONE01.md "Stealth pocket: see -> plan -> execute").
## Placeholder only: it marks where the overlook, the high and low routes, hide spots,
## lantern-pool sightlines and patrol loops go, so the layout can be walked and reviewed
## before guardians and stealth rules exist. It reports whether the heroine is inside.
## Collision: no layer, mask = player layer.

enum Kind { OVERLOOK, HIGH_ROUTE, LOW_ROUTE, HIDE_SPOT, LANTERN_POOL, PATROL_LOOP }

const GROUP: StringName = &"stealth_volume"

@export var kind: Kind = Kind.LOW_ROUTE
## What the volume stands for, for whoever builds the stealth pass.
@export_multiline var note: String = ""


func _ready() -> void:
	add_to_group(GROUP)


## True while the heroine stands in the volume.
func player_inside() -> bool:
	if not monitoring:
		return false
	for b: Node3D in get_overlapping_bodies():
		if b is PlayerController:
			return true
	return false


func kind_name() -> String:
	return str(Kind.keys()[kind])
