extends "res://scripts/qa/world_grounding_standard_qa.gd"
const Direction = preload("res://scripts/world/view_relative_direction.gd")
## Source-alpha measurements remain usable on headless renderers.
func run() -> void:
	for turn in 8:
		check(Direction.sector(Vector3.BACK, Basis(Vector3.UP, turn * PI / 4)) == posmod(-turn, 8), "view-relative eight sectors %d" % turn)
		for count in [8, 4, 2, 1]:
			var available := {}
			for index in count: available[Direction.DIRECTIONS[index * (8 / count)]] = {"animation": str(index)}
			check(not Direction.resolve(available, turn).is_empty(), "%d-direction fallback %d" % [count,turn])
			var expected := 0
			var closest := 9
			for index in count:
				var difference := absi(index * (8 / count) - turn)
				var separation := mini(difference, 8-difference)
				if separation < closest:
					closest = separation
					expected = index
			check(Direction.resolve(available, turn).animation == str(expected), "%d-direction chooses nearest authored view %d" % [count, turn])
	check(Direction.resolve({}, 3).is_empty(), "missing art produces no fabricated animation")
	var reference_player := CharacterBody3D.new()
	reference_player.set_script(preload("res://scripts/exploration_player_v2.gd"))
	var director := Node.new()
	director.name = "SpriteDirector"
	reference_player.add_child(director)
	root.add_child(reference_player)
	reference_player.set_physics_process(false)
	var rig := Node3D.new()
	rig.set_script(preload("res://scripts/camera_rig.gd"))
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 1.0, 1.5)
	camera.rotation.x = -atan2(0.8, 1.5)
	rig.add_child(camera)
	root.add_child(rig)
	camera.current = true
	reference_player.camera_reference = camera
	for yaw in 8:
		rig.rotation.y = yaw * PI / 4
		for direction in 8:
			var facing := Direction.world_vector(Direction.DIRECTIONS[direction])
			reference_player._update_facing_from_world(facing)
			check(reference_player.last_dir == Direction.DIRECTIONS[Direction.sector(facing, camera.global_basis)], "existing player direction matches shared convention %d/%d" % [yaw,direction])
	var exploration = preload("res://scripts/exploration.gd").new()
	var mode = preload("res://scripts/game_mode.gd").new()
	exploration.game_mode = mode
	exploration.camera_rig = rig
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(6, 6)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.68, 0.63, 0.47)
	ground.material_override = material
	root.add_child(ground)
	var rows: Array = []
	for filename in ["ExplorationPlayer_V2", "BeachMerchantNPC", "BeachCrafterNPC", "FishingCardMakerNPC", "TripleTriadOpponentNPC", "FishingMasterStillWaterNPC", "BeachFishingCritter"]:
		var path := "res://actors/%s.tscn" % filename
		if not ResourceLoader.exists(path):
			check(false, path + " exists")
			continue
		var actor = load(path).instantiate()
		strip(actor)
		root.add_child(actor)
		await settle()
		var p = actor.get_node_or_null("GroundPresentation")
		if p == null: p = actor.find_child("GroundPresentation", true, false)
		var physical = p.get_parent()
		rig.target = physical
		rig.rotation.y = 0
		if OS.get_cmdline_user_args().has("--baseline-footprints"):
			p.profile = p.profile.duplicate()
			p.profile.animation_feet_from_left_px = {}
			p.profile.shadow_width = {"ExplorationPlayer_V2":0.24, "FishingCardMakerNPC":0.36, "FishingMasterStillWaterNPC":0.32, "BeachFishingCritter":0.14}.get(filename, 0.38)
			p.profile.shadow_depth = p.profile.shadow_width
			p.apply_profile()
		var sprite = p.sprite as AnimatedSprite3D
		if filename == "ExplorationPlayer_V2": sprite.animation = &"Idle_S"
		if not p.profile.directional_animation_prefixes.is_empty(): p.set_directional_pose("idle", Vector3.BACK)
		sprite.pause()
		var original: Transform3D = p.shadow.global_transform
		var physical_transform: Transform3D = physical.global_transform
		for turn in 4:
			if turn > 0:
				var event := InputEventKey.new()
				event.physical_keycode = KEY_Q
				event.pressed = true
				exploration._unhandled_input(event)
				await create_timer(0.35).timeout
			await settle()
			if filename == "ExplorationPlayer_V2":
				sprite.animation = StringName("Idle_" + Direction.DIRECTIONS[Direction.sector(Vector3.BACK, camera.global_basis)])
				p.apply_frame()
			var texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
			var image := Image.load_from_file(texture.atlas.resource_path).get_region(Rect2i(texture.region)) if texture is AtlasTexture else Image.load_from_file(texture.resource_path)
			var used := image.get_used_rect()
			var padding := image.get_height() - used.end.y
			var left := image.get_width()
			var right := 0
			for y in range(maxi(0, used.end.y - 8), used.end.y):
				for x in image.get_width():
					if image.get_pixel(x, y).a > 0.0:
						left = mini(left, x)
						right = maxi(right, x + 1)
			var feet_x: float = ((left + right) * 0.5 - image.get_width() * 0.5) * sprite.pixel_size
			if sprite.flip_h: feet_x = -feet_x
			feet_x += sprite.offset.x * sprite.pixel_size
			var feet_y: float = (sprite.offset.y - image.get_height() * 0.5 + padding) * sprite.pixel_size
			var feet_world: Vector3 = p.visual_anchor.global_position + camera.global_basis.y * feet_y + camera.global_basis.x * feet_x
			var root_screen := camera.unproject_position(physical.global_position)
			var feet_screen := camera.unproject_position(feet_world)
			rows.append({"actor": filename, "turn": turn, "animation": sprite.animation, "alpha_padding": padding, "physical_world": str(physical.global_position), "declared_feet_world": str(p.visual_anchor.global_position), "alpha_feet_world": str(feet_world), "shadow_world": str(p.shadow.global_position), "root_screen": str(root_screen), "declared_screen": str(camera.unproject_position(p.visual_anchor.global_position)), "alpha_feet_screen": str(feet_screen), "shadow_screen": str(camera.unproject_position(p.shadow.global_position)), "feet_root_pixels": feet_screen.distance_to(root_screen), "shadow_width": p.shadow.width})
			# The last eight alpha rows contain the stance; the bottom row alone
			# can contain only one raised/walking foot, not the body center.
			var contact_radius: float = (right - left) * 0.5 * sprite.pixel_size
			var contact_left := camera.unproject_position(feet_world - camera.global_basis.x * contact_radius)
			var contact_right := camera.unproject_position(feet_world + camera.global_basis.x * contact_radius)
			check(absf(feet_screen.y-root_screen.y) < 4.0 and root_screen.x >= contact_left.x-4.0 and root_screen.x <= contact_right.x+4.0, filename + " source-alpha contact span within four screen pixels")
			check(p.shadow.global_transform.is_equal_approx(original), filename + " orbit leaves shadow physically fixed")
			check(physical.global_transform.is_equal_approx(physical_transform), filename + " Q rotation leaves physical root unchanged")
			if not p.directional_pose.is_empty():
				var chosen := Direction.resolve(p._directions, Direction.sector(Vector3.BACK, camera.global_basis))
				check(sprite.animation == StringName(chosen.animation), filename + " selects view-relative authored animation")
			if rendered:
				DirAccess.make_dir_recursive_absolute(captures)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(captures.path_join("%s-%d.png" % [filename, turn]))
		for turn in 4:
			var event := InputEventKey.new()
			event.physical_keycode = KEY_E
			event.pressed = true
			exploration._unhandled_input(event)
			await create_timer(0.35).timeout
			check(p.shadow.global_transform.is_equal_approx(original) and physical.global_transform.is_equal_approx(physical_transform), filename + " E counter-orbit keeps root/shadow fixed")
		if not p.directional_pose.is_empty():
			p.set_directional_pose("walk", Vector3.BACK)
			sprite.set_frame_and_progress(2, 0.35)
			sprite.pause()
			var phase: float = (sprite.frame + sprite.frame_progress) / sprite.sprite_frames.get_frame_count(sprite.animation)
			var event := InputEventKey.new()
			event.physical_keycode = KEY_Q
			event.pressed = true
			exploration._unhandled_input(event)
			await create_timer(0.35).timeout
			check(is_equal_approx((sprite.frame + sprite.frame_progress) / sprite.sprite_frames.get_frame_count(sprite.animation), phase) and not sprite.is_playing(), filename + " camera turn preserves walk phase and paused state")
			check(physical.global_transform.is_equal_approx(physical_transform), filename + " view changes never move physical actor")
			p.profile = p.profile.duplicate()
			p.profile.default_directional_pose = "idle"
			p.directional_pose = ""
			p._explicit_world_facing = false
			p.apply_profile()
			await settle()
			check(p.directional_pose == "idle" and p.world_facing.is_equal_approx(physical.global_basis.z), filename + " static art opt-in comes only from profile")
			p.set_local_directional_pose("idle", Vector3.BACK)
			check(p.world_facing.is_equal_approx(Vector3.BACK), filename + " standalone scene parent needs no Node3D")
		rig.target = null
		actor.free()
	exploration.free()
	mode.free()
	var output := "user://presentation-measurements.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--measurements="): output = arg.trim_prefix("--measurements=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	print("PRESENTATION TUNING QA: %d/%d; measurements %s" % [checks-failures.size(), checks, output])
	quit(0 if failures.is_empty() else 1)
