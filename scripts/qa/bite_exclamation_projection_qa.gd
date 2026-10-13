extends SceneTree
## Executes the real desktop companion/game and exercises the production
## Encounter -> Fishing bite opportunity -> original PNG alert path.
## Does not require the actual random bite scheduler to fire during testing.
var checks: int = 0
var failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "BiteExclamationProjectionQA-%d" % Time.get_ticks_usec())
	call_deferred("_run")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("Bite projection QA: " + description)

func _run() -> void:
	var host: Node = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	for i in range(8):
		await process_frame
	var game: Node = host.get("game") as Node
	_check(is_instance_valid(game), "Desktop gameplay instance exists")
	if not is_instance_valid(game):
		quit(1)
		return
	var fishing: Node = game.get_node("Game/Fishing")
	var alert: CanvasLayer = fishing.get("_bite_alert") as CanvasLayer
	_check(is_instance_valid(alert), "Production fishing installs projected CanvasLayer")
	if not is_instance_valid(alert):
		quit(1)
		return
	var sprite: AnimatedSprite2D = alert.get_node("OriginalExclamationFrames") as AnimatedSprite2D
	_check(sprite.sprite_frames.get_frame_count(&"Alert") == 6, "Six frames from original 192x33 image")
	_check(not sprite.sprite_frames.get_animation_loop(&"Alert"), "Alert pops once, not a loop")
	_check(sprite.sprite_frames.get_frame_texture(&"Alert", 3) is AtlasTexture, "Original atlas frame used")
	_check(sprite.scale.x >= 1.5, "Exclamation burst has readable on-screen scale")
	_check(not sprite.visible, "Alert hidden before bite")
	_check(alert.get_viewport() == game.get_viewport(), "Alert is in gameplay viewport")
	# The same handler the actual Encounter.bite_opportunity_started signal
	# invokes. Use real signal, and bypass random encounter delay only.
	fishing.set_process(false)
	fishing.set("phase", fishing.Phase.IN_WATER)
	fishing.encounter.bite_opportunity_started.emit()
	await process_frame
	_check(alert.call("is_bite_window_visible"), "Real Encounter signal makes alert visible")
	_check(sprite.is_playing(), "Six-frame animation begins on real bite event")
	var point: Vector2 = alert.call("get_alert_screen_position")
	var region: Rect2 = Rect2(Vector2.ZERO, Vector2(game.get_viewport().get_visible_rect().size))
	_check(region.has_point(point), "Projected sprite appears within gameplay viewport")
	var frame_image: Image = game.get_viewport().get_texture().get_image()
	if frame_image != null and not frame_image.is_empty():
		var screenshot_path: String = "user://bite-exclamation-visible.png"
		var saved: Error = frame_image.save_png(screenshot_path)
		if saved == OK:
			print("SCREENSHOT: " + ProjectSettings.globalize_path(screenshot_path))
	var camera: Camera3D = fishing.camera_rig.get_node("Camera3D")
	var actor_screen: Vector2 = camera.unproject_position(fishing.player.global_position)
	_check(point.y < actor_screen.y and absf(point.x - actor_screen.x) < 150.0, "Alert is above Ryu, not elsewhere on screen")
	fishing.player.rotation.y += 0.4
	await process_frame
	var new_point: Vector2 = alert.call("get_alert_screen_position")
	_check(region.has_point(new_point), "Alert remains on screen after player turns")
	# Remains visible for remaining timing window, after animation completes.
	for i in range(55):
		await process_frame
	_check(alert.call("is_bite_window_visible"), "Burst stays readable while window remains open")
	fishing.encounter.bite_missed.emit()
	await process_frame
	_check(not alert.call("is_bite_window_visible"), "Bite missed hides alert")
	alert.call("show_bite_window")
	fishing.encounter.bite_triggered.emit()
	_check(not alert.call("is_bite_window_visible"), "Hook event hides alert")
	print("BITE PROJECTION QA: %d/%d passed" % [checks - failures.size(), checks])
	for failure in failures:
		print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
