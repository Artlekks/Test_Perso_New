# Mobile Overlay Stability v1

The canonical 640×864 world viewport and authored cameras remain unchanged.
Short portrait windows keep the approved full-width bottom-aligned world crop.
Opening or scrolling a modal must never move GameplayImage or the world camera.

Previously `_surface_scroll` moved the same texture containing both the 3D world
and modal UI. A large menu changed that scroll to zero, visibly shifting the world.
The same sky crop removed the exploration compass and location strip.

The shell now composites three textures:

1. GameplayViewport: unchanged physical world, fishing HUD and bottom crop.
2. PinnedHudViewport: transparent exploration HUD pinned to the visible top.
3. OverlayViewport: transparent dialogue and menu presentation; only this image
   can scroll through canonical UI in a short Safari window.

CanvasLayer rendering bindings are centralized in the shell. Controllers retain
their original logical parents and input owner. Touch positions map through the
overlay image into the original gameplay viewport. Existing touch actions are
unchanged. Dialogue retains bottom anchoring; it does not initiate shell scrolling.
Exploration HUD's existing show/hide rules remain authoritative during fishing.
Its bottom help panel retains its previous displayed location and tween home.

Godot's CanvasLayer custom-viewport setter does not rebind the parent's draw-order
signal. The shell sets the binding outside the scene tree, preserving child order
and owner, so normal enter/exit notifications bind and disconnect correctly.
Persistent session UI returns to its original owner when the shell is destroyed.

At 390×844 with 47/34 fallback safe insets, gameplay is 390×526.5 logical pixels.
At 390×664, the full texture remains 390×526.5, clipped to a 390×347 display;
controls retain 236 pixels and bottom clearance. Web uses actual CSS env insets,
so a browser with zero insets has a taller display. No camera recentering occurs.

```powershell
& $Godot --path . --rendering-method gl_compatibility res://actors/mobile/MobileOverlayStabilityQA.tscn
& $Godot --path . --rendering-method gl_compatibility res://actors/mobile/MobileDialogueStateQA.tscn
& .\tools\mobile\build_mobile_playtest.ps1
```

The rendered fixture repeats merchant, fish trade, lure/crafting, Card Maker,
Triple Triad, inventory and dialogue, checks open/scroll/close world placement,
checks top HUD after fishing and scene replacement, and runs in Web as well as
native Compatibility. Safari hardware acceptance remains a separate visual check.
The build command uses Linux/WSL, validates project.binary/ECFG before publishing,
and leaves the existing HTTPS server running.
