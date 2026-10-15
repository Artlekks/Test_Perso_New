# CODEX HIGH — DEEP TECHNICAL ART / RENDERING / ASSET AUDIT

Act as an independent senior technical artist and rendering/performance engineer for FishingGame (Godot 4.7.2; retro/pixel-art-inspired presentation with 3D fishing world and desktop/mobile UIs). Perform a **read-only, evidence-based** technical-art audit of the **same frozen baseline** used by the software auditor. Do not accept 'atlas everything' or 'add pooling everywhere' as universal solutions.

## Safety and scope rules

Do not modify source assets, imports, `.tscn`, `.tres`, `.gd`, shaders or export presets; only create findings and optional profiling logs under `audit_reports/tech_art/`. Existing approved wind, water currents, rain, small top-row RainImpact splashes, fishing camera and visual composition must remain untouched. If an improvement would change appearance, show quantified performance gain and visual regression risks before recommending it.

Label each statement **measured**, **confirmed by inspection**, or **hypothesis**, and cite paths, nodes, resource sizes and profiler captures. If GPU metrics are impossible in the execution environment, do not invent them. Imported GPU memory is not equal to PNG disk size. Desktop and mobile may have different platform budgets; assess both and clearly state device assumptions.

## Required audit workstreams

### 1. Complete asset and resource inventory
- Enumerate source images, imported textures, sprite sheets, SpriteFrames, AtlasTextures, fonts (inventory only—do not redistribute font files), audio, meshes, materials, shaders, scenes, particles, animation libraries, Resource files, backups, unused assets, duplicate content, path aliases, third-party packages and their licensing/usage boundaries.
- For raster textures record dimensions, format, alpha mode, disk bytes, import flags, filtering, mipmaps, compression, sampler/repeat, intended usage and referencing scenes/materials. For runtime memory, report estimates **with formula and assumptions** plus real measurements when available.
- Find genuinely duplicated images by hash and near-duplicates by visual/reference inspection; distinguish intentional aliases from removable duplicates.
- Check platform-specific import/export impact, pixel-art nearest-neighbor requirements and alpha/fringing artifacts.

### 2. Atlas / sprite sheet strategy — measure before recommending
- Analyze large independent UI backgrounds vs animated sprites vs NPCs vs particles vs frequently swapped environment textures. Identify candidates where shared texture pages could reduce actual material switches / batches or resource overhead. Record estimated draw-call impact, sampling constraints, gutter/bleed, 3D billboard and depth sorting issues, mipmaps/NPOT limitations, and whether the atlas becomes resident unnecessarily.
- Identify textures already packed as sheets. Never propose repacking an existing usable sheet simply because it has multiple frames.
- Recommend a selective strategy with explicit 'do not atlas' categories and practical production/authoring workflow.

### 3. Render pipeline and gameplay scenes
- Examine renderer choice, 3D/2D composition, viewports, camera stack, CanvasLayers, transparency sorting, ambient materials, ocean/sea shaders, lighting, shadow cost, surface overdraw and UI compositing.
- Inspect scene-instance counts, material duplication vs shared resources, batching, transparent draw calls, frustum/culling, draw order and expensive full-screen effects.
- Investigate whether current tint vs sea depth should be corrected in shader/material layering, not by arbitrarily forcing draw-over-water. Do not alter visuals during audit.
- Look for runtime instantiation, freeing, texture/material duplication, caches and leakage on location switches and desktop dock/floating state changes.

### 4. Weather VFX deep dive
- Inspect world-owned wind, underwater currents and rain; particle/emitter number, transparent overdraw, camera-follow layout, frame-time cost, pooling of rain impacts, splash bounds over actual sloped sea mesh, fall direction and irregularity controls, off-screen effects, transition blending and weather modes.
- Verify resource sharing vs repeated material/texture creation and lifecycle through Lake 2/River 2/world travel, fishing enter/exit and rapid Calm/Rain/Tempest switching.
- Document limits for drop count, splash rate/concurrency and potential visual/perf effects under target camera and resolution. Use real scene profiling when possible.
- Confirm texture frame slicing of `RainImpact.png` top row only; do not redraw or crop source assets just to reproduce a runtime region already supported.

### 5. Other VFX, art assets, animations, and UI
- Examine NPC AnimatedSprite3D/frame sheets, fish shadow/rope/bait effects, line effects, card-game visuals, crafting and desktop UI backgrounds; identify avoidable duplicate materials and texture memory churn.
- Audit the 640x480 gameplay composition, desktop embedded viewport, full-screen and floating shell scaling, 16:9/4:3 and mobile portrait safe areas. Investigate wrong filtering and scaled pixel edges without assuming resampling is always undesirable.
- Do not change the approved palette or move UI elements. UI layout redesign is separate: assess technical constraints and opportunities only.

### 6. Performance measurement plan and stress cases
- Test realistic baseline states: clear beach exploration; lake fishing; river fishing; full Rain with sea splashes/wind/current; Tempest during fight; scene swaps; Triple Triad; expanded equipment/data menus; desktop dock left/right/float; mobile portrait and relevant landscape configuration.
- If engine/editor and hardware permit, measure CPU frame time, GPU frame time, draws, objects, active particles, texture and render memory, scene-load spikes, GC/allocations and peaks over several runs; include hardware/Godot build/resolution and sample duration. If not, supply a fully reproducible measurement protocol and mark estimates clearly.
- Use controlled A/B experiments conceptually, e.g. rain on/off, splash count 25/50/100, one shared material vs current, atlased vs separate candidate textures. Recommend implementation only after demonstrated benefit; preserve quality.
- Propose provisional target budgets only with explicit assumptions for low/midrange target platforms; don't claim they have been achieved.

### 7. Modularity, future art workflow, value authoring
- Evaluate whether artists can add weather VFX, fish sprites, NPC animations, environmental assets and UI art without editing core gameplay scripts. Identify asset/profile schemas and ownership boundaries.
- Explore native Inspector saves, scene overrides, shared `.tres` tuning resources and optional editor 'save tuned values' workflow. Ensure visual defaults and per-location overrides can coexist, with undo/revert and version control.
- Distinguish asset-pipeline improvements from gameplay architectural changes; flag cross-team decisions for reconciliation.

## Deliverables

**EXECUTIVE_SUMMARY.md** — objective visual/performance health assessment, top 10 issues and what should stay unchanged.

**ASSET_MANIFEST.csv** — path, asset type, width, height, pixels, original bytes, import configuration (when known), known references, duplicate group, confidence, notes. Mark unknowns rather than filling fabricated values.

**RENDERING_AND_MEMORY.md** — scene/renderer graph, measured performance tables where possible, transparent overdraw, GPU texture memory assumptions, lifetimes, draw-call observations and reproducible benchmarks.

**VFX_AND_MATERIALS.md** — weather/sea/current/wind and other effects audit, material/texture sharing map, presentation risks, approval-sensitive changes.

**OPTIMIZATION_EXPERIMENTS.md** — prioritized experiments with expected outcome, profiling method, risk, required approval, time estimate and success/stop criteria. Explicitly include reasons NOT to pursue certain atlases.

**FINDINGS.md** — TA-001... entries with severity, evidence path/node/asset, status measured/confirmed/suspected, resource/perf impact, trade-offs, dependency on software changes, risk and confidence.

**OPEN_QUESTIONS.md** — target GPUs/resolutions/FPS, missing runtime capture, ambiguous authoring workflows, missing licenses/import metadata, etc.

## Method

Inventory first, trace actual referencing/scene lifecycles second, profile (if possible) third, then challenge your findings. Prefer a small number of high-confidence optimizations over speculative breadth. Do not modify production data or silently add new FX. End with report locations, prioritized short list and known evidence gaps.

## FRESH6-specific input note

FRESH6 is the frozen source snapshot. The ZIP omits the generated `.godot/` cache; native source PNGs and `.png.import` settings are still present. Do not claim measured VRAM, draw calls, upload sizes or GPU times without an actual engine/profile run. The `export/index.wasm` and `export/index.pck` files are generated artifacts (~70.5 MiB uncompressed combined) and should be excluded from raw asset inventory totals or reported in a separate output-artifact section. Current approved saved rain overrides (including width, opacity, wind-follow) are visible in `actors/FishingRainVFX.tscn`.
