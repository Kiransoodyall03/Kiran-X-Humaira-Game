# Soul Sword Game — Claude Code rules

3D action RPG (Sekiro-style parry/posture duels, stealth zones) in **Godot 4.7.2** (pinned — never change `config/features` in project.godot). Team: P = Kiran, programmer (owns code); A = Humaira, designer (owns art: modeling, rigging, animation). Design docs live in `docs/` — read `docs/VISION.md` pillars and the relevant spec before designing a feature.

## Ownership (see docs/OWNERS.md)
- You work on P's behalf. Only edit P-owned paths: `scripts/`, `shaders/`, `tests/`, `scenes/actors/`, `scenes/ui/`, `scenes/levels/*/ZoneXX.tscn` and `*_Gameplay.tscn`, `project.godot`, P-owned docs.
- **Never edit** A-owned paths: `source_art/`, `assets/**` (glb, textures, `MAT_*.tres`), `*_Art.tscn`, `*_Lighting.tscn`. If a change is needed there, write it up as a request instead.
- Never edit an imported `.glb` scene, use "Editable Children", or create inherited scenes from a glb. Wrap the glb as a child of a P-owned scene; attach things with `BoneAttachment3D` using the socket names in `docs/ART_SPEC.md`.

## Godot file rules
- Commit `.import` and `.uid` files. When moving/renaming a `.gd` or `.gdshader` outside the editor, move its `.uid` sidecar too (`git mv a.gd b.gd && git mv a.gd.uid b.gd.uid`). Never hand-edit or regenerate UIDs.
- Do not hand-merge `.tscn` conflicts: take one side and redo the other change.
- Save large Animations/Materials/Resources as separate `.tres`, not embedded in scenes.

## Code style
- GDScript, **statically typed everywhere** (`untyped_declaration` warning is an error).
- Combat tuning values (parry windows, posture damage, attack frame data) live in `Resource` data files, not hard-coded, so they can be tuned live.
- Gameplay logic (posture, parry timing, corruption) lives in code; AnimationTree only drives visuals. Timing comes from method tracks or timers expressed in frames at 60 fps.
- Unit-test combat math with gdUnit4 in `tests/`.

## Naming
- Never use Bleach terms (zanpakutō, shinigami, Soul Reaper, Hollow, bankai, shikai, Soul Society) in code, assets or text. Use names from `docs/NAMING.md`; use placeholder names (`heroine`, `cat`, `guardian`, `monster`) until names are final.
