# Brief — character models from 2D turnarounds

Owner: A (Humaira) · Date: 2026-11-27 · Source: `character_model_process_grill.md` (same folder)

## Output
In-game character models built from Humaira's own 2D turnarounds: the heroine first, then the cat spirit. Each one ships as `assets/characters/<name>/SK_<name>.glb` and follows `docs/ART_SPEC.md`.

## Who it's for
Kiran (P). His gameplay scenes wrap the glb, so each model replaces a grey placeholder without code changes. After that, it's for the players.

## Pipeline (per character)
1. **Thumbnails.** 30+ black-fill silhouettes for the heroine. For the cat: sealed, playful and menacing poses.
2. **Turnaround.** Drawn by Humaira in **T-pose**, front / ¾ / side / back. Views must line up on a **height/scale grid** (heroine 1.70 m). The weapons (greatsword and katana forms, grip, sheath) go on a **separate sheet** drawn to the same scale.
3. **Blockout on the final rig. This ships first.** A low-poly mesh from the turnaround on the **final skeleton**: humanoid bone names mapped to SkeletonProfileHumanoid, plus the sockets `weapon_R`, `weapon_back`, `cat_perch` and `fx_chest`. Export it as `SK_heroine.glb` so Kiran can replace the capsule.
4. **Sculpt.** A high-detail sculpt over the turnaround reference planes.
5. **Manual retopology.** Done fully by hand, 30–60k triangles. Shoulder, elbow, knee and face loops get extra care, because shoulders deform worst from a T-pose.
6. **UVs and textures.** Build a semi-real look with procedural textures in Blender, then **bake** it to image maps (`T_<name>_<map>`: albedo, roughness, normal from the sculpt) at 512–1024 px/m. Procedural nodes don't survive glTF export, so baking is required.
7. **Re-skin and re-export in place.** Bind the final mesh to the **same skeleton** and export over the same glb path. Keep the bone, node and socket names unchanged.
8. **Sign-off.** Kiran approves the **final model in-engine**. That is the only formal gate.

## Order
Heroine blockout → heroine final → cat. The cat follows the same steps on its own non-humanoid rig and starts once the heroine blockout has shipped.

## Not in scope
- AI image-to-3D or auto-retopology.
- Commissioned concept art.
- Rebuilding the look as Godot shaders.
- A face close-up sheet.
- Guardians, rival, orphans and monsters. They get their own pass later.

## Must never be guessed or changed silently
- Bone names, socket names and node names after the blockout ships. Tell Kiran **before** pushing any rename.
- Scale (1 unit = 1 m), facing +Z, origin at the feet, all transforms applied.

## How it's verified
- The blockout loads in the sandbox on the current animations, with the sword on `weapon_R` and the cat on `cat_perch`.
- The final model stays within 30–60k triangles and shows no deformation breaks at the shoulders or knees in the attack, dodge and guard clips.
- Kiran signs off the final model in the painterly look.

## Follow-ups (docs to update)
- ~~`ART_BIBLE.md` (A)~~: done 2026-11-27.
- `CHARACTER_BIBLE.md` (Kiran): same rule in the silhouette checklist.
- `ART_SPEC.md`: change the status from DRAFT to signed.
