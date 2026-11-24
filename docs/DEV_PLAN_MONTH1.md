# Month-One Dev Plan: Soul Sword Game (Nov 24 – Dec 21, 2026)

## Context
The design foundation (`Downloads\Untitled Soul Sword Game — Design Foundation.md`) settles genre, story arc, combat and engine. It leaves naming, zones, bosses, the claw form, the opening and the slice scope as open questions. The project folder `C:\Users\humai\Bleach-Inspired Game` is empty.

This plan turns month one into **pre-production plus a playable greybox combat sandbox**. The main constraint is that the two devs must work in parallel without stepping on each other. The full vertical slice is the target for months 2–4. Month one proves the parts it depends on.

**Team:**
- **P (Kiran):** programmer, using Godot and Claude Code.
- **A (Humaira):** designer; models, rigs and animates in Blender.
- Both are part-time at about 15–20 h/week, so roughly 70 h each for the month.
- Both know git; both are new to Godot.

**End-of-month outcomes:**
1. A repo and pipeline both devs use daily with zero scene conflicts. A Blender asset can be re-exported without breaking P's work.
2. A playable greybox build: the heroine (proxy rig) duels one large proxy monster. It covers posture, parry, greatsword/katana switching, lock-on to body parts and corruption v0, with a shrine to rest at.
3. Living design docs v1: pillars, character bible, world/lore bible, naming sheet, combat spec with attack tables, Zone 1 bubble diagram.
4. Art bar set: heroine and cat silhouettes locked, heroine blockout mesh on its final rig, one painterly look-test scene.
5. Vertical-slice scope locked, plus a month-2 plan.

---

## 1. Parallel-work rules (the "no interference" contract)
These go into `docs/OWNERS.md` and `docs/WORKFLOW.md` in week 1.

### Tools and versions
- **Engine:** Godot **4.7.2** stable (4.8 is still in beta). Both devs pin exactly the same version; a different version rewrites `project.godot` and `.tscn` files. Upgrade together, only after 4.8.1.
- **Assets from Blender:** export to **.glb**. Don't import .blend directly: that needs Blender on both machines and makes exporting an implicit step. Blender sources live in `source_art/`, which gets a `.gdignore` so Godot skips it.
- **Version control:** Git + Git LFS, set up before the first commit.
  - `.gitattributes` starts with `* text=auto eol=lf`. These go to LFS: `.blend`, `.glb`, images, audio, fonts and `.res/.scn/.lmbake`. `.blend` and `.glb` are also marked `lockable`.
  - These stay plain text: `.tscn`, `.tres`, `.gd`, `.gdshader`, `.import`, `.uid`.
  - `.gitignore` contains `.godot/`, `*.translation`, `*.blend1`, `*.blend@` and `export/`.
  - **Commit** the `.import` and `.uid` files. If a file is moved outside the editor, move its `.uid` too (`git mv` both). This rule also goes in `CLAUDE.md`.
- **Hosting:** GitHub for code and issues. A gets **Anchorpoint** as a git GUI with locking. The GitHub free plan has 10 GiB/month of LFS bandwidth. If you hit it, move LFS to a cheap self-hosted Gitea or to Azure DevOps.

### Folder ownership
One owner per folder. The other dev requests changes rather than editing directly.

| Path | Owner | Contents |
|---|---|---|
| `source_art/` | A | .blend working files (locked while being edited) |
| `assets/characters/*/*.glb`, `assets/env/`, `assets/props/` | A | Exported meshes, rigs, animation libraries, textures, extracted `MAT_*.tres` |
| `scenes/actors/*.tscn` (wrapper scenes) | P | CharacterBody3D root that instances the glb, plus script, hit/hurt boxes, AnimationTree and BoneAttachment3D sockets |
| `scenes/levels/zone01/Zone01.tscn` (root) | P | Instances only the three sub-scenes below |
| `…/Zone01_Gameplay.tscn` | P | Greybox collision, spawns, triggers, navmesh, stealth volumes |
| `…/Zone01_Art.tscn` | A | Set dressing on top of the greybox |
| `…/Zone01_Lighting.tscn` | A | WorldEnvironment, lights, fog, LightmapGI |
| `scripts/`, `shaders/`, `project.godot` (input map, autoloads, layers) | P | A asks for changes |
| `docs/` | One owner per file | See §3 |

### Never edit an imported .glb scene
- Don't use Editable Children or inherited scenes from a glb.
- A re-exports in place and P's wrapper keeps working, **as long as node and bone names stay stable**. Those names are the contract in `docs/ART_SPEC.md`.

### Branching (trunk-based)
- `main` must always open and run.
- P uses feature branches of 1–3 days, merged through PRs with a Claude review.
- A may commit directly to `main` when a commit touches only A-owned paths.
- **Pull before opening the editor.** Tag milestones (`m1-w2`, `m1-final`).

### Scene conflicts
If two people conflict on a scene, don't hand-merge it. Take one side and redo the other side's change in the editor. Save big animations and materials as separate `.tres` files, not embedded in scenes.

### Weekly rhythm (about 1 h of shared time per week)
- **Mon, 20 min:** sync and pick the week's tasks.
- **Wed:** async check-in in chat.
- **Fri, 30 min:** play the build together, swap art drops, 10-minute retro.
- **Week 4 only:** external playtest.

---

## 2. Asset contract (`docs/ART_SPEC.md`, agreed by end of week 1)

**Scale and orientation**
- 1 Blender unit = 1 m. Apply scale and rotation before export.
- Characters face +Z, matching Godot's humanoid profile.

**Pivots**
- Characters pivot at the feet, centered.
- Props pivot at the bottom center.
- Modular environment pieces sit on a 1 m grid.

**Metrics**
These fix greybox dimensions so final art drops in. Tune them in week 2.
- Heroine height: 1.7 m.
- Door height: 2.4 m.
- Climb heights: 1.0 m and 2.2 m.
- Monster classes: S (2–3 m), L (5–8 m), XL (12 m+).

**Naming**
- Prefixes: `SM_` static mesh, `SK_` skinned mesh, `A_<char>_<action>` animation, `MAT_`, `T_<name>_<map>`.
- Socket names stay stable: `weapon_R`, `weapon_back`, `cat_perch`.
- Import suffixes: `-col`, `-convcol`, `-colonly`, `-navmesh`, `-loop`.

**Rigs**
- The heroine uses a humanoid rig mapped to **SkeletonProfileHumanoid**.
- Mixamo animations are placeholders only. Add a root bone with the Mixamo-Root add-on, and check the license before shipping any of it.
- Monsters use **2–3 shared rig families** for the whole game: large biped/oni, quadruped/beast, serpentine. Each family gets a custom SkeletonProfile.

**Budgets**
These are starting values to revise after the look test.
| Asset | Triangles |
|---|---|
| Heroine | 30–60k |
| Large monster | 60–120k |
| Modular piece | 1–10k |

Texel density: about 512–1024 px/m. The painterly style allows the lower end.

**Animation handoff**
- Animations ship as AnimationLibrary .glb files.
- Root motion goes on the root bone.
- P owns the clip list and frame-timing notes: startup, active and recovery frames for each attack.

---

## 3. Design-doc stack (living, one page each, one owner each)
Store these in `docs/` as Markdown so Claude Code can read them. Every new idea must pass the pillars.

| Doc | Owner | Method |
|---|---|---|
| `VISION.md` | Both, wk 1 | One-page vision: an experience statement ("makes the player feel X by letting them be Y who Z") and 3–4 pillars written as experiences, not features. Draft pillars: *Every duel is a conversation* / *Mercy is harder than murder* / *The sword talks back* / *A world that folds in on itself*. |
| `CHARACTER_BIBLE.md` | P drafts, A reviews | Template per character: Ghost→Wound→Lie→Flaw, Want vs Need, voice (3 sample lines plus words never used), silhouette key (1 shape, 1 prop, 1 color), how the arc shows in mechanics, 5 arc beats. The cat's arc mirrors the heroine's. The cat should work like Dishonored's Outsider (commentary) combined with Atreus's directive and autonomous modes (a companion that is also a mechanic). |
| `WORLD_BIBLE.md` | P drafts | Iceberg structure: about 10% is shown in game, 90% stays in the bible. Contents: timeline, cosmology, a three-way faction sheet (goal, method, fear, what they misunderstand about the other two, how they show up in gameplay, shape and color; each pair has one shared interest and one hard conflict), and a "never reveal" list. |
| `NAMING.md` | Both | "Conlang-lite" rules: build names from real Japanese morphemes with glosses. Never use real enshrined kami, real shrines or real clans. Avoid all Bleach terms (zanpakutō, shinigami, Hollow, bankai, shikai, Soul Society). Have a Japanese speaker review every name. Use yokai.com plus scholarly sources for folklore. |
| `COMBAT_SPEC.md` | P | Rules for posture, parry, forms and corruption. Attack-table template: Startup / Active / Recovery (frames at 60 fps), damage, posture damage, deflectable?, perilous type, tell (animation, sound, VFX), punish window, phase. Monsters get **per-part posture bars**; breaking a part staggers the whole monster. This fixes Sekiro's weakness against non-humanoid enemies. |
| `BOSS_TEMPLATE.md` | P | Sections: fantasy and the lesson it teaches, arena metrics, phases, moveset table, unblockables (each with its own color flash), counters, a stealth opener, the cat's lines, and a death-feedback goal (the player knows why they died). |
| `ZONE01.md` | P (layout), A (visual) | Bubble/molecule diagram showing one critical path, 2–3 loops, a one-way shortcut at about 70% through, an early vista of the boss arena, and one stealth pocket. The stealth pocket follows **see → plan → execute**: an overlook, high and low routes, readable patrols, lantern-pool sightlines, and recovery hide spots. |
| `ART_BIBLE.md` | A | Mood boards, shape language per faction, color script, silhouette sheets, turnarounds, and painterly references. |
| `ITEM_TEXT.md` | P | Four-line template: what it is / mechanical hint / lore fragment / an unanswered question. Under 60 words each. |

---

## 4. Week-by-week schedule
Hours per dev per week are about 15–20. Each row is one week; P and A work at the same time without sharing files.

### Week 1 (Nov 24–30): Foundations and contracts
**Shared:**
- 2 h vision and pillars session.
- 1 h naming brainstorm, producing a shortlist, not final names.
- Sign off `ART_SPEC.md` and `OWNERS.md`.

**P:**
- Repo, LFS and .gitattributes/.gitignore; Godot 4.7.2 project with typed GDScript (`untyped_declaration` set to error).
- Folder skeleton, `CLAUDE.md` with the ownership and .uid rules, and gdUnit4 installed.
- Godot basics (official 3D tutorial, plus the AnimationTree and CharacterBody3D docs).
- Capsule player: movement, third-person camera, input map.

**A:**
- Set up Anchorpoint and LFS locking. Blender scene template at 1 m scale with a 1.7 m reference figure.
- **Pipeline smoke test:** export a cube-man with a 3-bone rig, two clips and a `-col` mesh, then P re-imports it after a change. This proves re-export doesn't break the wrapper.
- Mood boards, and 30+ heroine silhouette thumbnails.

**Exit check:** a round-trip re-export with no diff in P's scenes; pillars written.

### Week 2 (Dec 1–7): Combat feel prototype ("find the fun")
**P:**
- Posture system (posture only, no stamina), block, and a parry window (start generous at 10–12 frames).
- Hit-stop, plus deathblow on posture break.
- One capsule duelist with 3 telegraphed attacks, driven by data tables (Resources) so it can be tuned live.
- Lock-on.
- gdUnit4 tests for the posture and parry math.

**A:**
- Shape-language sheet.
- Cat-spirit silhouettes and an expression sheet (sealed, playful, menacing).
- Heroine silhouette locked, then a turnaround.
- Greatsword and katana proxy props with the `weapon_R` socket.

**Docs:** P drafts `COMBAT_SPEC.md` and the character bibles for the heroine and the cat.

**Exit check:** the deflect-and-posture-break loop is fun with capsules. If it isn't, iterate here before adding anything.

### Week 3 (Dec 8–14): Forms, corruption and the first monster
**P:**
- Greatsword/katana toggle mid-combo, katana dodge with i-frames.
- Corruption meter v0 (rises in katana form, drains in greatsword form). Input hijack is stubbed.
- Shrine: rest, refill heals, reset.
- AnimationTree state machine running on A's heroine rig with Mixamo placeholders.
- Large-monster controller: per-part hurtboxes and posture, a part-cycling lock-on, and a camera that pulls back based on the monster's bounding box.

**A:**
- Heroine blockout mesh on the final humanoid rig (re-export replaces the cube-man).
- First animation set: idle, run, 3-hit combo, block, parry, dodge, hit-react.
- Monster #1: a one-paragraph brief (folklore inspiration, the lesson it teaches, its parts), 20 thumbnails, then a **capsule proxy on the shared rig** with 4 placeholder attack poses. No sculpting yet.

**Docs:** P drafts the `WORLD_BIBLE.md` faction sheet and the `ZONE01.md` bubble diagram.

### Week 4 (Dec 15–21): Integration, look test and scope lock
**P:**
- Zone 01 greybox arena slice: a shrine, a path, one shortcut, and the boss arena with a navmesh baked per agent size.
- Monster #1 AI with 4 attacks from the attack table, and limb breaks.
- A Windows export build.

**A:**
- **Painterly look test** in `Zone01_Lighting.tscn` plus a small kit (shrine, rock, tree): hand-painted albedo, LightmapGI, fog, and a LUT.
- P supplies the Kuwahara/CompositorEffect post-process shader. A tunes its parameters through exported variables.

**Shared:**
- External playtest with 3–5 people. Ask open questions; record sessions; log deaths by attack ID.
- Retro.
- **Lock the vertical-slice scope:** zone, bosses, opening, which forms are included.
- Pick final names for the heroine, the cat and the guardian order.
- Write the month-2 plan.

---

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Part-time hours slip | Each week has one "must" (the exit check). Everything else can be cut. |
| Animation is A's bottleneck (modeling, rigging and animating) | Mixamo placeholders are retargeted through the humanoid profile. Monsters reuse rig families. A animates only clips that are locked in an attack table. |
| Both devs are new to Godot | Week 1 includes learning time. Claude Code works from `CLAUDE.md` and the docs. Code is typed GDScript with tests. |
| LFS bandwidth runs out | Monitor GitHub usage. Fallback: Gitea or Azure. |
| Bleach resemblance | Follow `NAMING.md` rules and design an original claw form (that design starts in month 2). |

## Key sources
- Godot version-control docs and UID changes in 4.4: https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html and https://godotengine.org/article/uid-changes-coming-to-godot-4-4/
- Godot import suffixes and retargeting: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html and https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html
- Blender Studio, Project Dogwalk Godot workflow: https://studio.blender.org/blog/our-workflow-with-blender-and-godot/
- Librande, "One-Page Designs"; Level Design Book on blockout; Totten on molecule diagrams.
- Valve, TF2 silhouette design; GDC "Raising Atreus for Battle"; Ghost of Tsushima on cultural authenticity.
- Sekiro posture mechanics; Game Developer articles on telegraphing and boss design; Monster Hunter part-breaking.
- Donovan (Volition), "The Vertical Slice Challenge," GDC 2015.

---

## Where things live
- Workflow: `docs/WORKFLOW.md`, ownership: `docs/OWNERS.md`, asset contract: `docs/ART_SPEC.md`.
- Design docs: `docs/VISION.md`, `CHARACTER_BIBLE.md`, `WORLD_BIBLE.md`, `NAMING.md`, `COMBAT_SPEC.md`, `BOSS_TEMPLATE.md`, `ZONE01.md`, `ART_BIBLE.md`, `ITEM_TEXT.md`.
- Repo rules for Claude Code: `CLAUDE.md`.
- The Godot project is created in week 1 by P after installing Godot 4.7.2 (see `WORKFLOW.md`).
