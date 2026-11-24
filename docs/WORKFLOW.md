# Team workflow

## One-time setup (week 1)
1. Both install **Godot 4.7.2 stable** (same exact version; upgrade only together, not before 4.8.1).
2. Install Git LFS: `git lfs install`.
3. P creates the GitHub repo, commits `.gitattributes` **before any binary file**, then pushes.
4. A installs **Anchorpoint** (git GUI with locking) and clones the repo.
5. P creates the Godot project in the repo root: Forward+ renderer, Project Settings → Debug → GDScript → `untyped_declaration` = Error. Install gdUnit4 from the Asset Library.

## Daily loop
1. **Pull before opening Godot or Blender.**
2. Lock any `.blend`/`.glb` you're about to edit (Anchorpoint lock, or `git lfs lock <file>`). Unlock after pushing.
3. Work only in paths you own (`OWNERS.md`).
4. Commit small and often. Open Godot once before committing art so `.import` files are generated, then commit them with the asset.
5. Push at least once per work session.

## Branching (trunk-based)
- `main` must always open and run.
- **P:** short feature branches (`feat/posture`, 1–3 days) → PR → Claude Code review → merge. Rebase on `main` daily.
- **A:** may commit directly to `main` when the commit touches only A-owned paths.
- Tag milestones: `m1-w1`, `m1-w2`, `m1-w3`, `m1-final`.

## Art handoff (how A ships an asset without breaking P)
1. Work in `source_art/<type>/<name>.blend`.
2. Follow `ART_SPEC.md` (scale, pivots, names, sockets, bone names).
3. Export glTF binary to `assets/<type>/<name>/SK_<name>.glb` (overwrite in place — same path, same node/bone names).
4. In Godot: Advanced Import Settings → set materials to external `MAT_*.tres` (first time only), set BoneMap to SkeletonProfileHumanoid for humanoids.
5. Commit glb + `.import` + materials. Post in chat: "dropped SK_heroine v3: changed X".
6. P's wrapper scene picks it up automatically. If a name had to change, A tells P **before** pushing.

## Never
- Edit someone else's file, even "just one node".
- Use Editable Children / inherited scenes on an imported glb.
- Hand-merge `.tscn`/`.tres` conflicts — take one side, redo the other change in the editor.
- Delete or ignore `.uid` / `.import` files.
- Change the Godot version alone.

## Weekly rhythm (~1 h shared)
| When | What |
|---|---|
| Mon, 20 min call | Review last week's exit check, pick this week's tasks from `DEV_PLAN_MONTH1.md`. |
| Wed, async | One chat message each: done / next / blocked. |
| Fri, 30 min | Play the latest `main` together. A shows art drops in-engine. 10-min retro: what was cut, what is at risk. |

## Playtests
- Internal every Friday. External (3–5 people) in week 4.
- Ask open questions ("What did you think of the fight?"), never leading ones.
- Record sessions; log every death with the attack ID that caused it.
