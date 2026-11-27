class_name LockOnCandidate
extends RefCounted
## One lock-on point as seen from the camera this frame: the data LockOnTargeting scores
## and cycles over. Built by LockOn from a LockOnPoint, or by hand in unit tests.

## The point, or null in unit tests.
var point: LockOnPoint
## Unique per point.
var key: int = 0
## Same for every part of one target (LockOnPoint.target_key()).
var target_key: int = 0
var part_id: StringName = &""
var priority: int = 0
## Distance from the heroine, in meters.
var distance: float = 0.0
## Offset from the screen centre in view-tangent units (x right, y up): x = tan of the
## horizontal angle off the view axis. Only meaningful when in_front.
var screen: Vector2 = Vector2.ZERO
## In front of the camera.
var in_front: bool = true
## Nothing on LockOnConfig.line_of_sight_mask between the heroine's eye and the point.
var has_los: bool = true
## Point enabled and its Combatant alive.
var alive: bool = true


static func make(p_key: int, p_target_key: int, p_screen: Vector2, p_distance: float,
		p_priority: int = 0, p_part_id: StringName = &"body") -> LockOnCandidate:
	var c: LockOnCandidate = LockOnCandidate.new()
	c.key = p_key
	c.target_key = p_target_key
	c.screen = p_screen
	c.distance = p_distance
	c.priority = p_priority
	c.part_id = p_part_id
	return c


## Angle between the camera's view axis and the point, in radians (PI if behind).
func view_angle() -> float:
	return atan(screen.length()) if in_front else PI
