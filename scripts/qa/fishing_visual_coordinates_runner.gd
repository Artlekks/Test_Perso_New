extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const Catalog = preload("res://data/bof4/progression/all_progression.tres")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("Fishing visual coordinates: " + label)

func settle() -> void:
	for frame in range(16):
		await process_frame

func check_rank(view: Node, points: int, id: String, name: String) -> void:
	view._set_record_text({"fishing_points": points, "rank_id": id, "rank_name": name})
	var panel: Rect2 = view._rank_panel_rect()
	var badge: TextureRect = view.rank_badge
	var rank_text: Label = view._rank_text
	var points_text: Label = view._record_label
	var rank_rect := Rect2(badge.position, badge.size * badge.scale) if badge.visible else Rect2(rank_text.position, rank_text.size)
	var points_rect := Rect2(points_text.position, points_text.size)
	check(panel.encloses(rank_rect), "%s rank fits authored panel" % name)
	check(panel.encloses(points_rect), "%s points fit authored panel" % name)
	check(not rank_rect.intersects(points_rect), "%s rank and points do not overlap" % name)
	check(points_text.text == str(points), "%s displays exact lifetime points" % name)
	check(badge.visible or rank_text.text == name, "%s uses its actual rank identity" % name)
	if rank_text.visible:
		var font: Font = rank_text.get_theme_font("font")
		check(font.get_string_size(rank_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			rank_text.get_theme_font_size("font_size")).x <= rank_text.size.x,
			"%s fallback lettering fits" % name)
	else:
		check(badge.texture != null and badge.texture.resource_path.to_lower().contains(id.replace("_plus", "+")),
			"%s uses matching authored badge" % name)

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	check(Catalog.get_rank_name(176) == "Beginner" and str(Catalog.get_rank_id(176)) == "beginner",
		"176 total points is Beginner under authored thresholds")
	check(Catalog.get_rank_name(200) == "Beginner+" and str(Catalog.get_rank_id(200)) == "beginner_plus",
		"200 total points starts Beginner+")
	check(Catalog.get_rank_name(500) == "Beginner++", "500 total points starts Beginner++")
	var shell: Node = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(shell)
	current_scene = shell
	await settle()
	var fishing: Node = shell.game.get_node("Game/Fishing")
	var view: Node = fishing.fishing_catch_view
	check(view.root.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"catch composition inherits nearest filtering")
	for item in [view.fish_portrait, view.fish_name_label, view.fish_size_label,
		view.fish_points_label, view.record_badge, view.rank_badge, view._rank_text, view._record_label]:
		check(item.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"catch element %s samples nearest" % item.name)
	check(shell.image.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"desktop gameplay viewport is displayed with nearest filtering")
	for window_width in [788, 1608]:
		root.size = Vector2i(window_width, 900)
		await settle()
		shell._layout()
		view._center_composed_result()
		check(view.root.scale.x > 0 and view.root.scale.x <= 1.0,
			"catch layout fits desktop width %d without magnifying text" % window_width)
		for rank in Catalog.ranks:
			check_rank(view, rank.min_points, str(rank.rank_id), rank.display_name)
	var bait: Node3D = load("res://actors/bait_V2.tscn").instantiate()
	shell.game.add_child(bait)
	bait.set_physics_process(false)
	var camera: Camera3D = fishing.camera_rig.get_node("Camera3D")
	var middle: Vector2 = camera.get_viewport().get_visible_rect().size * 0.5
	var ray_origin: Vector3 = camera.project_ray_origin(middle)
	var ray_direction: Vector3 = camera.project_ray_normal(middle)
	bait.global_position = ray_origin + ray_direction * (-ray_origin.y / ray_direction.y)
	bait.global_position.y = -1.8
	fishing.caster.active_bait = bait
	var alert: CanvasLayer = fishing._bite_alert
	alert.show_bite_window()
	alert._update_screen_position()
	var contact: Vector3 = fishing.caster.get_active_bait_surface_position()
	check(contact.x == bait.global_position.x and contact.z == bait.global_position.z,
		"lure contact preserves physical X/Z when submerged")
	check(alert.get_alert_screen_position().distance_to(expected_player_head(fishing, camera)
		+ alert.screen_offset) < 0.01, "bite alert belongs to player's head")
	var thrash: Node = fishing.get_node("FishThrashVisual")
	var thrash_anchor: Dictionary = thrash._resolve_screen_anchor(camera)
	check(thrash.caster == fishing.caster and thrash.encounter == fishing.encounter
		and thrash.fishing_line_view == fishing.get_node("FishingLineView"),
		"fish thrash scene binds actual caster, encounter, and line")
	check(fishing.encounter.is_connected("fish_thrash_started",
		Callable(thrash, "_on_fish_thrash_started")),
		"fish thrash receives the real encounter signal")
	check(bool(thrash_anchor.get("valid", false)) and Vector2(thrash_anchor.get("position",
		Vector2.ZERO)).distance_to(camera.unproject_position(contact)) < 0.01,
		"fish thrash starts at lure water contact")
	check(thrash.animated_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"fish thrash artwork samples nearest")
	var ripple: Node3D = bait.ripple_view
	ripple.configure(bait, bait.water_y)
	check(absf(ripple.global_position.x - bait.global_position.x) < 0.001
		and absf(ripple.global_position.z - bait.global_position.z) < 0.001,
		"ripple stays at lure X/Z")
	check(absf(ripple.global_position.y - bait.water_y - ripple.surface_offset) < 0.001,
		"ripple stays on water plane")
	check(not ripple.ripple_sprite.sprite_frames.get_animation_loop(&"Ripple")
		and not ripple.ripple_sprite.sprite_frames.get_animation_loop(&"BiteSplash"),
		"ripple and bite splash are one-shot animations")
	check(ripple.ripple_sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
		"ripple sprite samples nearest")
	var splash: Node3D = load("res://actors/FishingSurfaceSplash.tscn").instantiate()
	shell.game.add_child(splash)
	splash.configure(Vector3(bait.global_position.x, bait.water_y, bait.global_position.z), 0.7, true)
	splash.set_follow_position_provider(fishing.caster.get_active_bait_visual_surface_position)
	check(absf(splash.global_position.x - bait.global_position.x) < 0.001
		and absf(splash.global_position.z - bait.global_position.z) < 0.001,
		"fight splash stays at lure X/Z")
	check(absf(splash.global_position.y - bait.water_y - splash.fight_surface_y_bias
		- splash.surface_offset) < 0.001, "fight splash stays at water plane")
	var splash_sprite: AnimatedSprite3D = splash.get_node("EffectSprite")
	check(splash_sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
		"splash sprite samples nearest")
	check(not splash_sprite.sprite_frames.get_animation_loop(&"Effect"),
		"fight splash is one shot")
	var old_contact: Vector3 = contact
	bait.global_position += Vector3(0.5, 0, -0.4)
	camera.rotate_y(0.08)
	alert._update_screen_position()
	ripple._update_position()
	splash._update_follow_anchor()
	contact = fishing.caster.get_active_bait_surface_position()
	check(alert.get_alert_screen_position().distance_to(expected_player_head(fishing, camera)
		+ alert.screen_offset) < 0.01, "bite alert follows character head after camera movement")
	check(contact.distance_to(old_contact) > 0.5
		and Vector2(ripple.global_position.x, ripple.global_position.z).distance_to(
			Vector2(contact.x, contact.z)) < 0.001,
		"ripple follows moved contact without camera drift")
	check(Vector2(splash.global_position.x, splash.global_position.z).distance_to(
		Vector2(contact.x, contact.z)) < 0.001,
		"thrash follows moved contact without camera drift")
	var inset := fishing.power_meter_view.get_node_or_null("../CharacterView") as Control
	if inset != null:
		inset.call("show_character")
		alert._update_screen_position()
		check(alert.get_alert_screen_position().distance_to(expected_player_head(fishing, camera, inset)
			+ alert.screen_offset) < 0.01, "offscreen inset receives bite alert above its head")
		inset.call("hide_character")
	alert.hide_bite_window()
	splash.queue_free()
	fishing.caster.active_bait = null
	bait.queue_free()
	current_scene = null
	shell.queue_free()
	await settle()
	var orphans := Node.get_orphan_node_ids()
	print("FISHING VISUAL COORDINATES: %d/%d %s" % [checks - failures.size(), checks, failures])
	Isolation.emit_result("fishing_visual_coordinates_runner", checks - failures.size(), checks,
		failures.size(), orphans.size())
	quit(0 if failures.is_empty() and orphans.is_empty() else 1)

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
