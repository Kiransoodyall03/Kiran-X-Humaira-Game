class_name ShortcutGateConfig
extends Resource
## One-way shortcut gate tuning (docs/COMBAT_SPEC.md "Level navigation", docs/ZONE01.md).
## Tuning file: data/world/shortcut_gate.tres. Frames are at 60 fps.

## Frames the gate takes to open after interact. It still blocks until it is fully open.
@export_range(1, 600, 1, "suffix:frames") var open_frames: int = 45
## How far the gate panel's mesh rises while opening (visual only: its collision stays put
## and blocks until the gate is fully open).
@export_range(0.0, 10.0, 0.1, "suffix:m") var open_lift: float = 3.2
