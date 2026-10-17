extends SceneTree
## Executes the real desktop companion/game and exercises the production
## Encounter -> Fishing bite opportunity -> original PNG alert path.
## Does not require the actual random bite scheduler to fire during testing.
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
var checks: int = 0
var failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	call_deferred("_run")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("Bite projection QA: " + description)

func _run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
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
	var camera: Camera3D = fishing.camera_rig.get_node("Camera3D")
	var bait: Node3D = load("res://actors/bait_V2.tscn").instantiate()
	game.add_child(bait)
	bait.set_physics_process(false)
	var middle: Vector2 = game.get_viewport().get_visible_rect().size * 0.5
	var ray_origin: Vector3 = camera.project_ray_origin(middle)
	var ray_direction: Vector3 = camera.project_ray_normal(middle)
	bait.global_position = ray_origin + ray_direction * (-ray_origin.y / ray_direction.y)
	fishing.caster.active_bait = bait
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
	# The isolated headless renderer has no image texture to capture. Projection
	# and visibility are asserted below; desktop appearance remains manual QA.
	_check(point.distance_to(expected_player_head(fishing, camera) + alert.screen_offset) < 0.01,
		"Bite alert projects the real player's head, not the lure")
	bait.global_position += Vector3(0.35, 0.0, -0.2)
	camera.rotate_y(0.08)
	await process_frame
	var new_point: Vector2 = alert.call("get_alert_screen_position")
	_check(region.has_point(new_point) and new_point.distance_to(
		expected_player_head(fishing, camera) + alert.screen_offset) < 0.01,
		"Alert follows the actor's head after camera rotation, not the lure")
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
	fishing.caster.active_bait = null
	bait.queue_free()
	current_scene = null
	host.queue_free()
	for frame in range(4):
		await process_frame
	print("BITE PROJECTION QA: %d/%d passed" % [checks - failures.size(), checks])
	for failure in failures:
		print("FAIL: " + failure)
	Isolation.emit_result("bite_exclamation_projection_qa", checks - failures.size(), checks,
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
