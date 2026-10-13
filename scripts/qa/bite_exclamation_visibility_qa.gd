extends SceneTree
## Focused asset/layout/animation smoke test. No scene or fishing data replaced.
const BiteAlertScript = preload("res://scripts/fishing_bite_alert.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var failures: PackedStringArray = PackedStringArray()
    var world_player: Node3D = Node3D.new()
    root.add_child(world_player)
    var indicator: AnimatedSprite3D = BiteAlertScript.new() as AnimatedSprite3D
    world_player.add_child(indicator)
    if indicator.sprite_frames == null or indicator.sprite_frames.get_frame_count(&"Alert") != 6:
        failures.append("Expected six original alert frames")
    if indicator.pixel_size < 0.009:
        failures.append("Indicator too small compared with character sprite")
    if indicator.fixed_size:
        failures.append("Indicator should follow the character's perspective scale")
    if indicator.position.y < 1.0:
        failures.append("Indicator not above the Ryu sprite")
    if indicator.visible:
        failures.append("Indicator visible outside bite opportunity")
    indicator.call("show_bite_window")
    if not indicator.visible or not indicator.is_playing():
        failures.append("Indicator failed to start on bite window")
    world_player.rotation.y = PI
    if not indicator.visible:
        failures.append("Indicator disappeared on facing direction change")
    indicator.call("hide_bite_window")
    if indicator.visible or indicator.is_playing():
        failures.append("Indicator failed to hide after bite resolution")
    var checks: int = 8
    print("BITE EXCLAMATION VISIBILITY QA: %d/%d passed" % [checks - failures.size(), checks])
    for failure in failures:
        push_error("Bite exclamation visibility: " + failure)
    quit(0 if failures.is_empty() else 1)
