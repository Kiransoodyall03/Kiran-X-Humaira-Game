# Character model design process — grill notes

Date: 2026-11-27 · With: Humaira (A) · Goal: agree how A goes from 2D turnarounds to in-engine 3D character models.

## What the docs already say (not asked)
- ART_BIBLE: heroine 30+ thumbnails → locked silhouette → turnaround front / ¾ / side / back. Cat: sealed / playful / menacing poses + expression sheet. Turnarounds only after silhouette approval.
- Look: painterly realistic; painterliness comes from lighting/env + Kuwahara post filter, not ultra-detailed characters. Hand-painted albedo, low texture noise.
- ART_SPEC: 1 unit = 1 m, +Y up, face +Z, origin at feet. Heroine 1.70 m, 30–60k tris, 512–1024 px/m. Humanoid rig → SkeletonProfileHumanoid. Sockets weapon_R, weapon_back, cat_perch, fx_chest. Export `assets/characters/<name>/SK_<name>.glb`, source in `source_art/characters/`.
- Month-1 target: heroine + cat silhouettes locked, heroine blockout on its final rig.
- source_art/ and assets/ are currently empty.
- Blender MCP is connected (can run Blender scripts, and has an image-to-3D generator).

## Summary / key decisions
Humaira draws everything herself in T-pose with a 1.70 m scale grid and a separate sword sheet → blockout on the final rig ships first → sculpt → fully manual retopo → UV → procedural texturing baked to image maps → re-skin to the same skeleton, re-export in place. Kiran signs off only the final model in-engine. Cat follows the same pipeline after the heroine blockout. Docs to be updated to match.
Tally: 11 questions · 6 took the recommendation · 4 chose another option · 1 partly Other (Q4).

## Q&A log
- **Q1 (design status)** — not answered. Paused: Humaira hasn't read the docs yet; gave her a project rundown first. Resume at Q1.
- **ART_SPEC sign-off** — Humaira: "art spec is fine". Captured: A accepts ART_SPEC.md as drafted. (Formal sign-off line in the doc not yet updated.)
- **Q1 (design status)** — Nothing drawn yet. Plan the whole chain thumbnails → silhouette → turnaround → model. Rec-vs-chosen: took recommendation.
- **Q2 (who draws)** — Humaira draws thumbnails + turnaround herself. Took recommendation.
- **Q3 (pose)** — T-pose. Chose another option (rec was A-pose). Flag: shoulders need extra care in skinning; matches Mixamo placeholders directly.
- **Q4 (sheet contents)** — Height/scale grid + separate sword sheet. No face close-up. Colour/material: "we will use blender generated textures and procedural texturing to get the semi realism feel, and not the overly realistic visual that normal blender textures give." Took rec (grid) + chose others / Other.
  - Flag: procedural Blender node textures do not export through glTF — they must be baked to image maps to reach Godot. Art bible says "hand-painted albedo"; procedural is a change to log there.
- **Q5 (getting textures to Godot)** — Bake procedural look to image maps (albedo/roughness/normal, T_ naming). Took recommendation.
- **Q6 (modeling method)** — Humaira: "could we sculpt and then ai retopolgies?" → sculpt first. Chose another option (rec was poly-model over planes).
- **Q6b (retopo tool)** — After hearing auto-retopo needs hand fixes at joints/face anyway: fully manual retopo. Chose another option (rec was Quad Remesher + fixes). Normals baked from the sculpt.
- **Q7 (staging)** — Blockout on final rig first (final bone names + sockets, exported as SK_heroine.glb), then sculpt → manual retopo → bake, re-skinned to the same skeleton and re-exported over the same file. Took recommendation.
- **Q8 (sign-offs)** — Only the final model in-engine needs Kiran's sign-off. Chose another option (rec was silhouette + turnaround + blockout). Flag: contradicts ART_BIBLE / CHARACTER_BIBLE "turnarounds only after silhouette approval" — those docs need updating (A owns ART_BIBLE; CHARACTER_BIBLE is P-owned).
- **Q9 (cat)** — Same pipeline, after the heroine blockout ships. Own (non-humanoid) rig. Took recommendation.
- **Q10 (doc conflicts)** — Update docs to match the decisions. Took recommendation.

## Open flags
- ART_BIBLE (A): replace "hand-painted albedo" with baked procedural textures; drop "turnarounds only after silhouette approval".
- CHARACTER_BIBLE (P/Kiran): silhouette checklist line "Turnarounds only after silhouette approval" — Kiran to edit.
- ART_SPEC sign-off line still reads DRAFT — mark signed.
