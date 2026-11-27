class_name LockOnPoint
extends Marker3D
## A point the heroine's lock-on can target. Place one per lockable target (on the
## training dummy's chest), or one per body part on a large monster (head, limbs, weak
## points). Points that share a Combatant count as parts of the same target: lock-on
## cycling visits the other parts of the current target before moving to another target.
## The camera frames the target by `target_size` (bigger = camera pulls back further).

const GROUP: StringName = &"lock_on_points"

## The Combatant this point belongs to (its "owner" for lock-on). If unset, the nearest
## ancestor with a "Combatant" child is used. Lock breaks when it dies.
@export var combatant: Combatant
## Which part this is, e.g. &"body", &"head", &"left_arm".
@export var part_id: StringName = &"body"
## Higher = preferred when picking a target and when choosing which part of a newly
## selected target to land on (e.g. a monster's body over its tail).
@export_range(-10, 10, 1) var priority: int = 0
## Rough size of the whole target in meters (largest dimension). The camera pulls back for
## big targets; see LockOnConfig framing values.
@export_range(0.1, 50.0, 0.1, "suffix:m") var target_size: float = 2.0
## Switch off to make the part unlockable (e.g. a broken or hidden part).
@export var enabled: bool = true


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if combatant == null:
		combatant = _find_combatant()


## True while it can be (or stay) locked: enabled, in the tree and its Combatant alive.
func is_lockable() -> bool:
	if not enabled or not is_inside_tree():
		return false
	return combatant == null or not combatant.is_dead


## Points with the same key are parts of one target.
func target_key() -> int:
	if combatant != null:
		return combatant.get_instance_id()
	var parent: Node = get_parent()
	return parent.get_instance_id() if parent != null else get_instance_id()


func _find_combatant() -> Combatant:
	var node: Node = get_parent()
	while node != null:
		var found: Combatant = Combatant.find_on(node)
		if found != null:
			return found
		node = node.get_parent()
	return null
