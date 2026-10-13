extends SceneTree
## Focused regression: original six-frame asset, alert lifecycle, smaller ripple,
## conservative weather balance, and clock-driven time condition (isolated).
const AlertScript = preload("res://scripts/fishing_bite_alert.gd")
const EnvironmentCatalogScript = preload("res://scripts/fishing_environment_catalog.gd")
const ConditionScript = preload("res://scripts/database/fishing_environment_condition_definition.gd")
const EnvironmentScript = preload("res://scripts/fishing_environment_service.gd")
const CatalogPath: String = "res://data/bof4/environment/all_environment_conditions.tres"
var checks: int = 0
var failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
    call_deferred("_run")

func check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures.append(description)
        push_error("Bite / balance QA: " + description)

func _run() -> void:
    var player: Node3D = Node3D.new()
    root.add_child(player)
    var alert: AnimatedSprite3D = AlertScript.new() as AnimatedSprite3D
    player.add_child(alert)
    check(alert.sprite_frames != null, "Alert frames configured")
    if alert.sprite_frames != null:
        check(alert.sprite_frames.get_frame_count(&"Alert") == 6, "Six original 32x33 frames")
        check(not alert.sprite_frames.get_animation_loop(&"Alert"), "Alert pops once and stays visible through window")
    alert.call("show_bite_window")
    check(alert.visible and alert.is_playing(), "Alert starts on bite window")
    player.rotation.y = PI
    check(alert.visible, "Alert stays above the player when facing reverses")
    alert.call("hide_bite_window")
    check(not alert.visible and not alert.is_playing(), "Alert stops and clears on resolution")
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
    player.queue_free()
    print("BITE ALERT + BALANCE QA: %d/%d passed" % [checks - failures.size(), checks])
    for failure in failures:
        print("FAIL: " + failure)
    quit(0 if failures.is_empty() else 1)
