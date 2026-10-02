# Cursor read-only review prompt

Use this only after the clean candidate passes the Godot playtest.

> Review this Godot 4 fishing-game project as a senior gameplay/software architect. **Do not edit any files.** This is a read-only architecture audit. The project is currently working, so do not recommend rewrites merely for style.
>
> Focus on issues that materially affect **modularity, scalability, performance, dependency direction, state ownership, signals, data/resources, scene composition, duplicated responsibilities, and future maintenance** as the project grows to support lure selection/physics, fishing-spot rarity, scoring/king fish, fishing techniques, rods, inventory/trading, and more environments.
>
> For each meaningful issue, cite the exact script/scene/function or node path, explain the concrete failure/maintenance risk, and propose the smallest safe improvement. Separate findings into: **Fix now**, **Refactor before the next major systems**, and **Defer / not worth changing yet**.
>
> Specifically check whether `fishing.gd`, `encounter.gd`, `bait_V2.gd`, `fish_behavior.gd`, `tension.gd`, `FishData` / `FishBehaviorProfile`, `FishingSpotData`, and the main scene have clean ownership boundaries. Check for dead code, stale resources, runtime path lookups, unnecessary per-frame work, signal cycles, duplicated sources of truth, and hidden coupling.
>
> Do not revive the old deleted generic state-machine/controller approach unless you can demonstrate a concrete problem that the current simpler coordinator architecture cannot solve. Do not rank cosmetic naming/formatting above gameplay architecture.
>
> End with a short proposed architecture for the next 3–5 systems, but do not modify code.
