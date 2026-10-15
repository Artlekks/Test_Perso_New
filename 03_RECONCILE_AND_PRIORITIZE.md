# CODEX HIGH / TECH LEAD — CROSS-AUDIT RECONCILIATION

Read the **complete** software and technical-art reports for the **same frozen baseline**. This is a decision-design task, not a code modification request. Review each high-severity claim against its cited source. Reject or downgrade findings without verifiable impact. Correct any contradictory recommendations. Add missing risks when reports disagree, with evidence.

## Resolve these likely cross-cutting decisions

1. Desktop F5 vs standalone companion: canonical launched runtime and isolated dev-scene path; distinction between desktop chrome and in-game HUD; preserve mobile behavior.
2. Weather/visual source-of-truth: one weather/wind/current state for simulation/UI/VFX, plus safe per-location and manual preview controls.
3. Visual tuning: exported `.gd` properties vs scene overrides vs shared `.tres` config Resources vs optional editor plugin. Define exactly which edits become persisted and what constitutes the source of truth.
4. Atlas/resource pipeline: only recommend merging textures with actual scene-graph or profiler evidence of draw-call/resource savings, and account for load-lifetime/memory risks.
5. Architecture changes: prefer stabilizing interfaces and removing verified duplicate responsibility before inventing new global service layers.
6. Test quality: improve QA fixtures and targeted integration contracts without creating a larger fake testing ecosystem than the real gameplay.
7. Visual approvals: no change to approved camera, wind/current/rain appearance without explicit signoff and before/after validation.

## Output: `audit_reports/reconciliation/`

- `PRIORITIZED_ROADMAP.md` with P0 blocking, P1 essential before new features, P2 valuable while developing, P3 future polish. Each item: origin IDs, proof, dependencies, scope, expected gain, rough effort, risk, tests and rollback.
- `ARCHITECTURE_STANDARDS.md` describing 4 pillars + testability, ownership, scene/Resource conventions, code/data separation, performance budgets (measured vs provisional), editor tooling policy, test policies and safe UI-platform responsibilities.
- `DECISION_LOG.md` with accept/reject/defer for every material software/TA recommendation and why.
- `FIRST_IMPLEMENTATION_BATCH.md`: propose just **one safe first batch**, ideally addressing the F5/desktop launch mismatch or another clearly verified high-value blocker. Include exact allowed files, tests, acceptance criteria and rollback plan; DO NOT IMPLEMENT until approved.

Use firm, practical judgment. Do not aim for architectural perfection or an endless rewrite. A strong foundation is one where future changes are easy, measurable, and safe. Clearly identify what must still be human-tested rather than claiming automated QA covers it.
