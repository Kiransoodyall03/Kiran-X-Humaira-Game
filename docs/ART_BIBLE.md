# Art bible

Owner: A · Reviewer: P · Status: TEMPLATE — mood boards week 1, look test week 4

## Target look
Painterly realistic, mythic ancient Japan: shrines, wild forests, spirit-filled mountains. Painterly realism comes mostly from **lighting and environment art**, not ultra-detailed characters.

## Mood boards (week 1)
Links/images for: overall world · shrines & architecture · forests & mountains · the spirit world's "otherness" · monsters · guardians · the heroine · the cat · painterly rendering references.

## Shape language per faction (week 2)
| Faction | Primary shapes | Feel |
|---|---|---|
| Heroine & hideout | | |
| Guardian order | | |
| Monsters | | |
| Cat spirit | | |

## Color script
Plan the color/light mood beat by beat across the story (theft → struggle → taming → twist → ending), then per zone.

## Silhouettes and turnarounds
- Heroine: 30+ thumbnails (week 1) → chosen silhouette → turnaround in **T-pose**, front / ¾ / side / back, on a 1.70 m height grid, plus a separate to-scale sword sheet (week 2).
- Cat: sealed / playful / menacing poses + expression sheet (week 2); same model pipeline as the heroine, started after her blockout ships.
- Monster #1: 20 thumbnails (week 3).
- Model pipeline (see `requests/character_model_BRIEF.md`): blockout on the final rig ships first → sculpt → manual retopo → bake → re-skin to the same skeleton and re-export in place. P signs off the final model in-engine.

## Painterly rendering recipe (week-4 look test)
- Semi-real procedural textures built in Blender, baked to image maps (albedo / roughness / normal); reduced texture noise.
- LightmapGI for static areas + ReflectionProbes (SDFGI only if lighting must be dynamic).
- Stylized fog volumes, color grading LUT.
- Post-process: Kuwahara-style painterly filter (P builds it as a CompositorEffect; A tunes exported parameters).
- Optional custom toon/ramp lighting in spatial shaders (P).

## Originality
The claw form and all characters must be original designs. Note any reference used and how ours differs.
