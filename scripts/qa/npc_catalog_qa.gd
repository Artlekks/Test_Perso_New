extends SceneTree
const CATALOG = preload("res://data/npc/catalog/npc_catalog.tres")
var checks := 0
var failures: Array[String] = []
var checked_atlases := {}
var atlas_images := {}

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	var ids := {}
	for entry in CATALOG.entries:
		check(not ids.has(entry.id), "unique ID " + String(entry.id))
		ids[entry.id] = true
		check(entry.profile != null and entry.profile.sprite_frames != null, "profile and frames " + String(entry.id))
		var profile = entry.profile
		check(profile.collider_profile != null and profile.shadow_enabled, "collider and shadow profiles")
		check(profile.sprite_frames.has_animation(profile.default_animation), "default animation exists")
		for pose in profile.directional_aliases:
			for direction in profile.directional_aliases[pose]:
				check(profile.sprite_frames.has_animation(profile.directional_aliases[pose][direction].animation), "alias exists")
		for animation in profile.sprite_frames.get_animation_names():
			for frame in range(profile.sprite_frames.get_frame_count(animation)):
				var texture = profile.sprite_frames.get_frame_texture(animation, frame)
				check(texture != null, "valid frame")
				if texture is AtlasTexture:
					check(Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), "region in source")
					var key: String = texture.atlas.resource_path + str(texture.region)
					if not checked_atlases.has(key):
						checked_atlases[key] = true
						if not atlas_images.has(texture.atlas.resource_path):
							var atlas: Image = texture.atlas.get_image()
							if atlas.is_compressed(): atlas.decompress()
							atlas_images[texture.atlas.resource_path] = atlas
						var image: Image = atlas_images[texture.atlas.resource_path].get_region(Rect2i(texture.region))
						var guide := false
						for y in image.get_height():
							for x in image.get_width():
								var color := image.get_pixel(x, y)
								if color.a > 0 and color.r > 0.95 and color.b > 0.95 and color.g < 0.08: guide = true
						check(not guide, "extracted frame excludes magenta guides " + key)
		var actor = entry.scene.instantiate()
		root.add_child(actor)
		await process_frame
		check(actor.position == Vector3.ZERO, "root stays Y=0")
		check(actor.get_node("GroundPresentation").profile == profile, "production grounding owns presentation")
		check(actor.find_children("*", "WorldBlobShadow", true, false).size() == 1, "one shadow")
		check(actor.platform_floor_layers == 0 and actor.platform_wall_layers == 0, "non-pushing policy")
		check(actor.get_node("CollisionShape3D").disabled == not profile.collider_profile.hard_blocking, "family collision contract")
		var policy := WorldActorPresentation.new()
		policy._expand_actor_footprint(actor)
		check(is_equal_approx(actor.get_node("CollisionShape3D").shape.radius, profile.collider_profile.radius), "family footprint survives production presentation policy")
		policy.free()
		actor.free()
	var player := CharacterBody3D.new()
	player.name = "CollisionProbePlayer"
	player.add_to_group("fishing_player")
	player.collision_layer = 2
	player.position = Vector3(0, 0, 0.7)
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 0.16
	shape.position.y = 0.25
	player.add_child(shape)
	root.add_child(player)
	var mover = CATALOG.get_entry(&"fisher_captain_01").scene.instantiate()
	root.add_child(mover)
	var original := player.global_position
	var blocked := false
	for frame in range(120):
		await physics_frame
		if not mover.try_autonomous_motion(Vector3(0, 0, 0.01)): blocked = true
	check(blocked and mover.position.z < player.position.z - 0.3, "catalogue physical mover is stopped by player")
	check(player.global_position.distance_to(original) < 0.00001, "catalogue actor cannot displace player")
	mover.free()
	player.free()
	var preview = load("res://actors/npc/NPC_Catalogue_Preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	check(preview.actors.size() == CATALOG.entries.size(), "preview contains every entry")
	if OS.get_cmdline_user_args().has("--rendered"):
		var directory := "build/npc-captures"
		DirAccess.make_dir_recursive_absolute(directory)
		for index in range(4):
			preview.angle = index * PI / 2
			preview._update_camera()
			for actor in preview.actors: actor.set_preview_pose("walk" if index % 2 else "idle")
			for frame in range(5): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join("catalogue_%d.png" % index))
	preview.free()
	print("NPC Catalogue QA: %d/%d passed" % [checks-failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
