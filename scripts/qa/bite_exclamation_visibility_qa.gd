extends SceneTree
## Focused asset/layout/animation smoke test. No scene or fishing data replaced.
const BiteAlertScript = preload("res://scripts/fishing_bite_alert.gd")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
var checks: int = 0
var failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
    if not Isolation.verify():
        quit(1)
        return
    call_deferred("_run")

func check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures.append(description)
        push_error("Bite exclamation visibility: " + description)

func _run() -> void:
    await process_frame
    if not Isolation.verify_root_clock(self):
        quit(1)
        return
    var game: Node3D = load("res://actors/FishingTestScene_V2.tscn").instantiate() as Node3D
    root.add_child(game)
    current_scene = game
    for frame in range(4):
        await process_frame
    var fishing: Node = game.get_node("Game/Fishing")
    var player: Node3D = fishing.player
    var camera: Camera3D = fishing.camera_rig.get_node("Camera3D")
    var indicator: CanvasLayer = fishing.get("_bite_alert") as CanvasLayer
    check(indicator != null and indicator.get_script() == BiteAlertScript, "Production fishing installs projected CanvasLayer")
    if indicator == null:
        _finish()
        return
    var sprite: AnimatedSprite2D = indicator.get_node_or_null("OriginalExclamationFrames") as AnimatedSprite2D
    check(sprite != null and sprite.sprite_frames != null, "Production alert owns animation sprite")
    if sprite == null or sprite.sprite_frames == null:
        _finish()
        return
    check(sprite.sprite_frames.get_frame_count(&"Alert") == 6, "Expected six original alert frames")
    check(sprite.sprite_frames.get_frame_texture(&"Alert", 0) is AtlasTexture, "Original sheet supplies alert frames")
    check(sprite.scale.x >= 1.5 and sprite.scale.y >= 1.5, "Indicator has readable on-screen scale")
    check(indicator.get_viewport() == game.get_viewport(), "Indicator follows gameplay viewport projection")
    check(not indicator.call("is_bite_window_visible") and not sprite.visible, "Indicator hidden outside bite opportunity")
    indicator.call("show_bite_window")
    await process_frame
    check(indicator.call("is_bite_window_visible") and sprite.is_playing(), "Indicator starts on bite window")
    var point: Vector2 = indicator.call("get_alert_screen_position")
    var player_point: Vector2 = camera.unproject_position(player.global_position)
    check(point.y < player_point.y and absf(point.x - player_point.x) < 150.0, "Indicator projected above Ryu sprite")
    var region: Rect2 = Rect2(Vector2.ZERO, Vector2(game.get_viewport().get_visible_rect().size))
    check(region.has_point(point), "Indicator remains inside gameplay viewport")
    player.rotation.y += PI
    await process_frame
    point = indicator.call("get_alert_screen_position")
    check(indicator.call("is_bite_window_visible") and region.has_point(point) and point.y < camera.unproject_position(player.global_position).y, "Indicator remains above player after facing reversal")
    indicator.call("hide_bite_window")
    check(not indicator.call("is_bite_window_visible") and not sprite.is_playing() and not sprite.visible, "Indicator hides after bite resolution")
    _finish()

func _finish() -> void:
    print("BITE EXCLAMATION VISIBILITY QA: %d/%d passed" % [checks - failures.size(), checks])
    for failure in failures:
        print("FAIL: " + failure)
    Isolation.emit_result("bite_exclamation_visibility_qa", checks - failures.size(), checks,
        failures.size(), Node.get_orphan_node_ids().size())
    quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
    print("QA_PROCESS_FINALIZED")
