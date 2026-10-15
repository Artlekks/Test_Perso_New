# CODEX ASSIGNMENT 2 — Godot 4.7.2 Rendering / Memory / Runtime Verification

Perform an actual reproducible benchmark investigation on FRESH6, independently assessing TA-002 through TA-007 and TA-010. This is **not** another source-only art inventory. Begin with `RENDERING_AND_MEMORY.md`, `OPTIMIZATION_EXPERIMENTS.md`, `VFX_AND_MATERIALS.md` and the architectural dependency map; recheck the specific claims against current source.

## Safety and baseline
- Do not edit FRESH6 frozen source. Create a full disposable working clone outside the audit folder for Godot import/profiling/instrumentation; reports only at `audit_reports/verification_runtime/`.
- Prove sandbox `user://` isolation for ALL autoload and session stores before launching. If not provable, do not run Godot; document a user-side protocol instead.
- First measure **unmodified** clone (including authored `weather_mode=2`) to distinguish actual launch behavior. Only then run explicit Auto-mode A/B in a separate disposable variant. Keep approved rain, current, wind, camera and pixel art unchanged in original.
- Record OS, CPU/GPU, RAM, graphics driver, Godot exact version, renderer, VSync/FPS cap, display resolution, game render target and import mode. Distinguish GUI profiler from headless timings; headless does not measure GPU output.
- No invented FPS, draw calls, texture residency, release suitability or memory estimates labeled 'measured'. If graphical capture unavailable, report exactly that and collect only supported metrics or a reproducible capture plan.

## Experiments, in descending value
1. **Production weather correctness**: untouched Calm/Rain/Tempest startup and travel. Does Rain Preview visibly persist in Calm? Preserve scene-mode evidence, screenshot/log.
2. **Rain impact surface-search CPU**: instrument attempted impacts, screen retries, tests per triangle, sea/beach triangle counts, misses, spawn budget, per-frame and per-impact CPU time on beach/Lake 2/River 2. First baseline. If significant, evaluate but do not production-implement exact-contact-preserving broad phase.
3. **Rain transparent passes**: clear versus settled rain versus tempest at matched camera; CPU/GPU time, effective particle count, transparent passes, overdraw/draw evidence; distinguish quad count from draw call count.
4. **Underwater current/sea blending**: on/off render-pass cost, sea opacity/render_priority impact, depth/tint and sorting screenshots. Do not put current above water just to increase visibility.
5. **Desktop and mobile viewports**: menu closed/open, Active/Passive, dock/float, mobile portrait/landscape if executable and correctly rendered. Count active 3D/2D viewports, render targets and GPU time. Test updating inactive viewport conditionally only as a separate reversible clone experiment.
6. **Large UI textures and residency**: check actual loaded resources/VRAM if profiler supports it; especially 1448x1086 backgrounds. PNG bytes and mathematical RGBA estimates are not measured VRAM. Never blindly pack full-screen panels into an atlas.
7. **Scene lifetime**: repeat beach→Lake 2→River 2 travel and fishing in/out cycles. Detect persistent live effect/material/viewport instances or monotonic memory growth after stable warmup. Differentiate caching from leaks.
8. **Clean vendor import**: in clone only, check Nolka path/UID resolution and actual scene warnings; review packaging/license exposure separately (no unsupported license conclusions).

## Measurement discipline
- Save baseline before experiments. Controlled A/B: one change at a time, fixed window/camera/settings/weather, warmup, repeated runs (prefer >=3 captures of 60 seconds when feasible).
- Record p50/p95/p99 for frame times and meaningful CPU/GPU metrics when available; show samples, run variability, and stop criteria. Note when timing tool cannot measure a metric.
- Preserve pixel/visual parity with captures at beach and sea, small top-row ripple sprites, near-shore current tint, rain angle and nearest-filter sprites. Screenshot or direct human visual verification is required for art equivalence.
- Prioritize runtime evidence over exhaustive source listing. If no bottleneck is measured, say that no optimization is currently justified.

## Deliverables at audit_reports/verification_runtime/
- `RUN_ENVIRONMENT_AND_ISOLATION.md` — paths, engine/GPU/renderer, exact commands, any blockers.
- `BASELINE_METRICS.csv` and `BASELINE_SUMMARY.md` — only actual metrics, units, state and capture provenance; empty/NOT MEASURED rather than guessed numbers.
- `AB_EXPERIMENT_RESULTS.md` — results including noise/stop criteria and changes made only in disposable clone.
- `RENDER_AND_MEMORY_FINDINGS.md` — confirmed vs suspected, prioritized proposals, impact on visual fidelity and mobile.
- `NEXT_OPTIMIZATION_DECISION.md` — one proposed bounded optimization (or explicit no-action) with estimated engineering effort, test design, rollback.
- `READ_ONLY_VERIFICATION.md` — frozen original unchanged, excluding reports.

Do not implement production optimizations in this assignment.
