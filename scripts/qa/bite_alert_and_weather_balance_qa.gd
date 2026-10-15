extends SceneTree
## Focused regression: original six-frame asset, alert lifecycle, smaller ripple,
## conservative weather balance, and clock-driven time condition (isolated).
const AlertScript = preload("res://scripts/fishing_bite_alert.gd")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const EnvironmentCatalogScript = preload("res://scripts/fishing_environment_catalog.gd")
const ConditionScript = preload("res://scripts/database/fishing_environment_condition_definition.gd")
const EnvironmentScript = preload("res://scripts/fishing_environment_service.gd")
const CatalogPath: String = "res://data/bof4/environment/all_environment_conditions.tres"
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
        push_error("Bite / balance QA: " + description)

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
    var alert: CanvasLayer = fishing.get("_bite_alert") as CanvasLayer
    check(alert != null and alert.get_script() == AlertScript, "Production fishing owns the projected alert")
    if alert == null:
        _finish()
        return
    var sprite: AnimatedSprite2D = alert.get_node_or_null("OriginalExclamationFrames") as AnimatedSprite2D
    check(sprite != null and sprite.sprite_frames != null, "Alert frames configured")
    if sprite == null or sprite.sprite_frames == null:
        _finish()
        return
    if sprite != null and sprite.sprite_frames != null:
        check(sprite.sprite_frames.get_frame_count(&"Alert") == 6, "Six original 32x33 frames")
        check(not sprite.sprite_frames.get_animation_loop(&"Alert"), "Alert pops once and stays visible through window")
        var frame_texture: Texture2D = sprite.sprite_frames.get_frame_texture(&"Alert", 0)
        check(frame_texture is AtlasTexture and frame_texture.get_size() == Vector2(32, 33), "Original 32x33 atlas frame")
    check(not alert.call("is_bite_window_visible") and not sprite.visible, "Alert hidden outside bite window")
    alert.call("show_bite_window")
    await process_frame
    check(alert.call("is_bite_window_visible") and sprite.is_playing(), "Alert starts on bite window")
    var actor_point: Vector2 = camera.unproject_position(player.global_position)
    var alert_point: Vector2 = alert.call("get_alert_screen_position")
    check(alert_point.y < actor_point.y and absf(alert_point.x - actor_point.x) < 150.0, "Projected alert stays above player")
    player.rotation.y += PI
    await process_frame
    alert_point = alert.call("get_alert_screen_position")
    check(alert.call("is_bite_window_visible") and alert_point.y < camera.unproject_position(player.global_position).y, "Alert stays above player when facing changes")
    alert.call("hide_bite_window")
    check(not alert.call("is_bite_window_visible") and not sprite.is_playing() and not sprite.visible, "Alert stops and clears on resolution")
    var ripple_script: GDScript = load("res://scripts/ripple_view.gd") as GDScript
    var ripple: Node = ripple_script.new()
    check(is_equal_approx(float(ripple.get("ripple_pixel_size")), 0.0013125), "Surface ripple is 75% of previous size")
    ripple.free()
    var catalog: EnvironmentCatalogScript = load(CatalogPath) as EnvironmentCatalogScript
    check(catalog != null, "Authored environment catalog loads")
    if catalog != null:
        for weather_id in [&"calm", &"rain", &"tempest"]:
            check(catalog.has_condition(weather_id), "Weather exists: " + str(weather_id))
        var rain: ConditionScript = catalog.get_condition_by_id(&"rain")
        var tempest: ConditionScript = catalog.get_condition_by_id(&"tempest")
        check(float(rain.bite_activity_multiplier) <= 1.05, "Rain no longer universal +12%")
        check(float(tempest.bite_activity_multiplier) <= 1.05, "Storm no longer universal +25%")
        check(float(tempest.quality_bonus_roll_chance) <= 0.05, "Storm trophy bonus reduced")
        var service: Node = EnvironmentScript.new()
        root.add_child(service)
        service.call("configure", catalog)
        # With no global GameClock, explicit test scenarios still work.
        var clock: Node = root.get_node_or_null("GameClock")
        if clock == null:
            check(bool(service.call("activate_condition", &"night")), "Manual night scenario remains available without clock")
            var ids: PackedStringArray = service.call("get_active_condition_ids")
            check(ids.has("night"), "No-clock QA respects manual night condition")
        else:
            var snapshot: Dictionary = clock.call("get_snapshot")
            var hour: int = int(snapshot.get("hour", 12))
            var expected: String = "night" if hour >= 20 or hour < 5 else ("dawn" if hour < 8 else "")
            var ids: PackedStringArray = service.call("get_active_condition_ids")
            check(expected.is_empty() or ids.has(expected), "Live clock chooses expected time condition")
        service.queue_free()
    _finish()

func _finish() -> void:
    print("BITE ALERT + BALANCE QA: %d/%d passed" % [checks - failures.size(), checks])
    for failure in failures:
        print("FAIL: " + failure)
    Isolation.emit_result("bite_alert_and_weather_balance_qa", checks - failures.size(), checks,
        failures.size(), Node.get_orphan_node_ids().size())
    quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
    print("QA_PROCESS_FINALIZED")
