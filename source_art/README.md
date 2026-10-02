# Source Art

This directory contains editable authoring files and dormant visual references that are intentionally **not** runtime dependencies. `source_art/.gdignore` keeps Godot from importing/scanning them as game assets.

Runtime exports belong under `assets/`. When an asset is edited here, export only the runtime file that the game actually consumes and keep its runtime path domain-specific.

Do not delete source files merely because they have no `res://` reference. Delete them only when the underlying editable source/reference is intentionally being discarded.
