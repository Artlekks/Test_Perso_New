FISHINGGAME STABILIZATION — GATE 01 (ISOLATED CANDIDATE)

Source snapshot: 2026-10-16 15:47:04 (+04:00)
Branch: dev/qa-work; baseline commit e5f6b7025570313ae5ed94c3529d48d820bedb90
Base-layout-file SHA256: 98ceeb3143771f02190f63c3101a0b1ceddf9f8fb53c71f1f7a111d6ba06578b

This zip includes exactly ONE production replacement script:
  scripts/ui/seaside_shell_layout.gd
And one NEW QA script:
  scripts/qa/desktop_fishing_resize_contract_qa.gd

Design intent:
  During a live fishing session, host-window resizing must preserve BOTH
  dimensions of the existing SubViewport. A resizable floating image may
  grow/shrink on the desktop, but the gameplay camera projection must stay
  fixed until fishing exits. Outside fishing, tall floating window expansion
  still works. Docked, unlocked view remains the canonical 640x480.

This intentionally DOES NOT fix the deeper coupling: bait_V2 and
fishing_screen_water_bounds still adjust physical lure travel by reading
Camera3D's current screen projection. That is the NEXT architecture boundary.
It also does not fix final splash positioning or perfect HUD layout.

Verification:
  1. Close F5. Back up QA_Work (your snapshot already exists).
  2. Extract these scripts preserving the scripts/ paths into QA_Work.
  3. Godot 4.7.2 headless: --headless --path <QA_Work> --script res://scripts/qa/desktop_fishing_resize_contract_qa.gd
  4. Only if that passes, play one float-window resize while a cast is active.

IMPORTANT: This is source-reviewed and checked for structural scope, NOT
Godot-compiled or Windows-runtime-verified. No claim that full fishing is fixed.
Do not commit yet.
