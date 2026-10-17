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
    var camera: Camera3D = fishing.camera_rig.get_node("Camera3D")
    var bait: Node3D = load("res://actors/bait_V2.tscn").instantiate() as Node3D
    game.add_child(bait)
    bait.set_physics_process(false)
    var center: Vector2 = game.get_viewport().get_visible_rect().size * 0.5
    var ray_origin: Vector3 = camera.project_ray_origin(center)
    var ray_normal: Vector3 = camera.project_ray_normal(center)
    bait.global_position = ray_origin + ray_normal * (-ray_origin.y / ray_normal.y)
    fishing.caster.active_bait = bait
    var indicator: CanvasLayer = fishing.get("_bite_alert") as CanvasLayer
    var visual_offset: Vector2 = indicator.get("screen_offset")
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
    check(point.distance_to(expected_player_head(fishing, camera) + visual_offset) < 0.01,
        "Indicator projects the player's head, not the bait")
    var region: Rect2 = Rect2(Vector2.ZERO, Vector2(game.get_viewport().get_visible_rect().size))
    check(region.has_point(point), "Indicator remains inside gameplay viewport")
    bait.global_position += Vector3(0.35, 0, -0.2)
    await process_frame
    point = indicator.call("get_alert_screen_position")
    check(indicator.call("is_bite_window_visible") and region.has_point(point)
        and point.distance_to(expected_player_head(fishing, camera) + visual_offset) < 0.01,
        "Indicator stays over actor head while the lure moves")
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

func expected_player_head(fishing: Node, camera: Camera3D, inset: Control = null) -> Vector2:
    if is_instance_valid(inset) and inset.visible:
        var sprite2d := inset.get_node("Character") as AnimatedSprite2D
        var inset_art := sprite2d.sprite_frames.get_frame_texture(sprite2d.animation, sprite2d.frame)
        var local_head := sprite2d.offset + Vector2(0.0, -inset_art.get_height() * 0.5 if sprite2d.centered else 0.0)
        return (sprite2d.get_global_transform_with_canvas() * local_head).round()
    var sprite3d := fishing.player.get_node("GroundPresentation/VisualAnchor/AnimatedSprite3D") as AnimatedSprite3D
    var art := sprite3d.sprite_frames.get_frame_texture(sprite3d.animation, sprite3d.frame)
    var head := sprite3d.global_position
    if art != null:
        head += camera.global_basis.y * art.get_height() * sprite3d.pixel_size * 0.46 * sprite3d.global_basis.get_scale().y
    return camera.unproject_position(head).round()
