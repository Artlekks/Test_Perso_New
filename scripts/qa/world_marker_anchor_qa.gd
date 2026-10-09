extends "res://scripts/qa/world_grounding_standard_qa.gd"
## Actual renderer checks supplement world transforms with visible glyph pixels.
var inventory: Array[String] = []
var maximum_screen_drift := 0.0
var maximum_follow_error := 0.0
var glyph_pixels := 0

func _initialize() -> void:
	var isolated := "CodexWorldMarkerQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Isolated userdata unavailable; refusing gameplay marker QA")
		quit(1)
		return
	super._initialize()

func strip(node: Node) -> void:
	if node is WorldRequestMarker: return
	super.strip(node)

func center(visual: Label) -> Vector2:
	return visual.position + visual.size * visual.scale * 0.5

func inspect_actor(path: String) -> void:
	var actor := load(path).instantiate() as Node3D
	strip(actor)
	actor.set_process_input(true)
	root.add_child(actor)
	await settle()
	var p := actor.get_node("GroundPresentation") as GroundPresentation
	var anchor := actor.get_node("WorldMarkerAnchor") as WorldMarkerAnchor
	inventory.append(path)
	check(anchor.get_parent() == actor and not anchor.top_level, path + " root-owned physical anchor")
	check(anchor.profile == p.profile and anchor.height == p.profile.marker_height, path + " profile owns marker height")
	check(anchor.global_position.is_equal_approx(actor.global_position + Vector3.UP * anchor.height), path + " physical height above feet")
	anchor.configure(actor, p.profile)
	check(anchor.canvas.get_child_count() == anchor.source_labels.size(), path + " idempotent one visual per source")
	for i in anchor.source_labels.size():
		var source := anchor.source_labels[i]
		var visual := anchor.visuals[i]
		check(source.layers == 0 and visual.get_parent() == anchor.canvas, path + " no duplicate 3D icon")
		check(visual.mouse_filter == Control.MOUSE_FILTER_IGNORE and anchor.canvas.layer == 1, path + " world marker cannot steal interaction input")
		check(source.get_parent() == actor or source.get_parent().get_parent() == actor, path + " existing controller paths preserved")
	var request := actor.get_node_or_null("RequestMarker") as WorldRequestMarker
	if request != null:
		for state in [&"available", &"accepted", &"ready_to_turn_in", &"locked"]:
			request.set_request_state(state)
			await settle()
			var i := anchor.source_labels.find(request.label)
			check(anchor.visuals[i].visible == request.label.visible and (not request.label.visible or anchor.visuals[i].text == request.label.text), path + " request state " + String(state))
		request.set_request_state(&"available")
		actor.set_process_input(false)
		await settle()
		check(not anchor.visuals[anchor.source_labels.find(request.label)].visible, path + " existing modal visibility gate preserved")
	actor.free()

func rendered_orbit(path: String, camera_basis: Basis) -> void:
	var actor := load(path).instantiate() as Node3D
	strip(actor)
	actor.set_process_input(true)
	root.add_child(actor)
	await settle()
	var p := actor.get_node("GroundPresentation") as GroundPresentation
	var anchor := actor.get_node("WorldMarkerAnchor") as WorldMarkerAnchor
	var source := actor.get_node_or_null("RequestMarker/Label3D") as Label3D
	if source == null: source = actor.get_node("PromptLabel3D") as Label3D
	var request := actor.get_node_or_null("RequestMarker") as WorldRequestMarker
	if request != null: request.set_request_state(&"available")
	source.visible = true
	var visual := anchor.visuals[anchor.source_labels.find(source)]
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var local_before := anchor.position
	var world_before := anchor.global_position
	var actor_before := actor.global_transform
	var offset := camera_basis.z * 2.2 - camera_basis.x * 0.35 - camera_basis.y * 0.25
	var metrics: Array[Dictionary] = []
	for step in 17:
		var orbit := Basis(Vector3.UP, step * TAU / 16.0)
		camera.global_transform = Transform3D(orbit * camera_basis, actor.global_position + orbit * offset)
		# Allow actual renderer updates to settle, not only SceneTree callbacks.
		await create_timer(0.08).timeout
		check(anchor.position.is_equal_approx(local_before) and anchor.global_position.is_equal_approx(world_before), actor.name + " local/world anchor fixed at yaw " + str(step * 22.5))
		check(actor.global_transform.is_equal_approx(actor_before), actor.name + " orbit does not move actor")
		var feet := camera.unproject_position(actor.global_position)
		var icon := center(visual)
		var expected := camera.unproject_position(actor.global_position + camera.global_basis.y * anchor.height)
		maximum_screen_drift = maxf(maximum_screen_drift, absf(icon.x - feet.x))
		check(absf(icon.x - feet.x) < 0.01 and icon.y < feet.y and icon.is_equal_approx(expected), actor.name + " projected visual stays overhead")
		check(visual.visible and visual.rotation == 0 and visual.text == source.text and visual.modulate == source.modulate, actor.name + " icon faces camera with authored text/color")
		if rendered:
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(captures.path_join("%s-orbit-%02d.png" % [actor.name, step])) == OK, "rendered actor and marker capture")
			# Isolate the real glyph for readback; no synthetic marker geometry.
			p.sprite.hide()
			await create_timer(0.05).timeout
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var rect := Rect2(visual.position, visual.size * visual.scale).grow(3).intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
			var min_x := image.get_width()
			var max_x := -1
			var count := 0
			for y in range(int(rect.position.y), int(ceil(rect.end.y))):
				for x in range(int(rect.position.x), int(ceil(rect.end.x))):
					var color := image.get_pixel(x, y)
					if color.r > 0.8 and color.g > 0.55 and color.b < 0.85:
						count += 1
						min_x = mini(min_x, x)
						max_x = maxi(max_x, x)
			glyph_pixels += count
			check(count > 0 and absf((min_x + max_x + 1) * 0.5 - feet.x) < 2.0, actor.name + " actual glyph visible/centered through full orbit")
			metrics.append({"yaw":step * 22.5,"anchor":str(anchor.global_position),"feet_screen":str(feet),"icon_screen":str(icon),"glyph_pixels":count})
			p.sprite.show()
	actor.position += Vector3(0.18, 0, -0.09)
	check(anchor.global_position.is_equal_approx(actor.global_position + Vector3.UP * anchor.height), actor.name + " root movement inherited immediately")
	await create_timer(0.02).timeout
	check(center(visual).is_equal_approx(camera.unproject_position(actor.global_position + camera.global_basis.y * anchor.height)), actor.name + " moving actor has no presentation lag")
	if rendered:
		var output := FileAccess.open(captures.path_join(actor.name + "-metrics.json"), FileAccess.WRITE)
		output.store_string(JSON.stringify(metrics, "\t"))
	camera.free()
	actor.free()

func live_patrol() -> void:
	var game: Node3D = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await create_timer(0.3).timeout
	var actor := game.get_node("World/FishingCardMakerNPC") as Node3D
	var anchor := actor.get_node("WorldMarkerAnchor") as WorldMarkerAnchor
	var camera := root.get_camera_3d()
	var start := actor.global_position
	actor.get_node("RequestSource").set_process(false)
	actor.get_node("RequestMarker").set_request_state(&"available")
	actor._begin_next_patrol_leg()
	for frame in 24:
		await create_timer(0.02).timeout
		check(anchor.global_position.is_equal_approx(actor.global_position + Vector3.UP * anchor.height), "actual Card Maker collision-safe patrol anchor follows")
		check(anchor.visuals[1].visible, "actual moving request icon is rendered, not an empty visibility test")
		for visual in anchor.visuals:
			if not visual.visible: continue
			var expected := camera.unproject_position(actor.global_position + camera.global_basis.y * anchor.height)
			maximum_follow_error = maxf(maximum_follow_error, center(visual).distance_to(expected))
			check(center(visual).distance_to(expected) < 0.01, "actual patrol visible marker follows this rendered frame")
	check(actor.global_position.distance_to(start) > 0.01, "real patrol moved, not a static shape test")
	game.free()

func run() -> void:
	root.size = Vector2i(640, 480)
	if rendered: DirAccess.make_dir_recursive_absolute(captures)
	var fixture_camera := Camera3D.new()
	root.add_child(fixture_camera)
	fixture_camera.position = Vector3(0, 1, 3)
	fixture_camera.look_at(Vector3.ZERO)
	fixture_camera.current = true
	for directory in ["res://actors", "res://actors/locations"]:
		for filename in DirAccess.get_files_at(directory):
			if not filename.ends_with(".tscn"): continue
			var path: String = directory.path_join(filename)
			var packed := load(path) as PackedScene
			var candidate := packed.instantiate()
			var eligible := candidate is Node3D and candidate.has_node("GroundPresentation") and (candidate.has_node("PromptLabel3D") or candidate.has_node("RequestMarker"))
			candidate.free()
			if eligible: await inspect_actor(path)
	check(inventory.size() == 24, "all 24 marker-bearing actor bases/derived traders inventoried")
	fixture_camera.free()
	var scene: Node3D = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	var camera_basis: Basis = scene.get_node("CameraRig").basis * scene.get_node("CameraRig/Camera3D").basis
	scene.free()
	for path in ["res://actors/FishingCardMakerNPC.tscn", "res://actors/FishingMasterStillWaterNPC.tscn", "res://actors/BeachCrafterNPC.tscn"]:
		await rendered_orbit(path, camera_basis)
	await live_patrol()
	print("MARKER INVENTORY: ", JSON.stringify(inventory))
	print("WORLD MARKER QA: %d/%d; maximum horizontal screen drift=%s px; live follow error=%s px; rendered glyph pixels=%d" % [checks-failures.size(), checks, maximum_screen_drift, maximum_follow_error, glyph_pixels])
	quit(0 if failures.is_empty() else 1)
