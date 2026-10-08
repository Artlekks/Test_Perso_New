extends SceneTree
## Loads the authored playable scenes; never touches the player's save.
const CATALOG = preload("res://data/npc/catalog/npc_catalog.tres")
const ShadowFamilies = preload("res://scripts/world/world_shadow_families.gd")
var checks := 0
var failures: Array[String] = []
var rendered := false

func _initialize() -> void:
	var isolated := "CodexWorldPopulationQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	rendered = OS.get_cmdline_user_args().has("--rendered")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/npc/world_population_v1.json"))
	check(CATALOG.entries.size() == 36, "catalogue remains 36 entries")
	for entry in CATALOG.entries:
		check(manifest.entries.has(String(entry.id)), "metadata exists " + String(entry.id))
		check(not entry.placeholder_roles.is_empty() and entry.importance_tier in ["A", "B", "C"], "role and tier resolve")
		check(not entry.suggested_locations.is_empty() and not entry.art_status.is_empty(), "location/art status explicit")
		check(Array(entry.placeholder_roles) == manifest.entries[String(entry.id)].placeholder_roles, "resource metadata matches ingestion source")
	var scenes := {}
	for placement in manifest.placements: scenes[placement.scene] = true
	for path in scenes:
		var packed := load("res://" + path) as PackedScene
		check(packed != null, "authored scene loads " + path)
		var scene := packed.instantiate()
		root.add_child(scene)
		current_scene = scene
		for frame in range(8): await physics_frame
		var world := scene.get_node("World")
		var ids := {}
		var added := 0
		for placement in manifest.placements:
			if placement.scene != path: continue
			var entry = CATALOG.get_entry(StringName(placement.catalogue_id))
			check(entry != null, "placement catalogue ID resolves")
			check(not ids.has(placement.catalogue_id), "unique visual placement in location")
			ids[placement.catalogue_id] = true
			var actor := scene.get_node(placement.node) as CatalogueNPCActor
			check(actor != null and actor.scene_file_path == entry.scene.resource_path, "authored normalized instance")
			check(actor.position == Vector3(placement.position[0], 0, placement.position[2]), "root placement Y=0")
			check(actor.visual_profile == entry.profile and actor.get_node("GroundPresentation").profile == entry.profile, "grounding owned by shared profile")
			check(actor.visual_profile.collider_profile != null and ShadowFamilies.FAMILIES.has(actor.visual_profile.shadow_family), "collider/shadow families resolve")
			check(actor.find_children("*", "WorldBlobShadow", true, false).size() == 1, "one ground shadow")
			check(actor.platform_floor_layers == 0 and actor.platform_wall_layers == 0 and not actor.patrol_enabled, "stationary non-platform actor")
			check(actor.get_node("InteractionArea").monitoring and actor.get_node("InteractionArea/CollisionShape3D").shape != null, "original interaction area preserved")
			check(not actor.has_method("begin_world_interaction") and not actor.has_method("open_game_by_id"), "visual adds no gameplay provider")
			for other in world.get_children():
				if other == actor or not other is Node3D: continue
				if other.get_script() == load("res://scripts/world/location_travel_point.gd"):
					check(actor.global_position.distance_to(other.global_position) > 0.65 + entry.profile.collider_profile.radius + 0.05, "travel activation disc unobstructed by " + actor.name)
				elif other.get_node_or_null("InteractionArea") != null and not other is CatalogueNPCActor:
					check(actor.global_position.distance_to(other.global_position) > entry.profile.collider_profile.radius + 0.35, "provider approach remains clear " + other.name)
			for gathering in world.find_children("*", "BeachGatheringNode3D", true, false):
				check(actor.global_position.distance_to(gathering.global_position) > entry.profile.collider_profile.radius + 0.14, "gathering foot point remains clear " + gathering.name)
			added += 1
		check(world.find_children("Population*", "CatalogueNPCActor", false, false).size() == added, "no extra unlisted population actors")
		# Inspect provider identities to catch accidental duplicate gameplay instances.
		var providers := {}
		for node in world.get_children():
			if node is CatalogueNPCActor or node.scene_file_path.is_empty(): continue
			if node.get_node_or_null("InteractionArea") == null: continue
			var identity := node.scene_file_path
			if node.get_script() == load("res://scripts/world/location_travel_point.gd"):
				identity += ":" + String(node.destination_id)
			if node.get("economy_context") != null:
				identity += ":" + node.economy_context.resource_path
			check(not providers.has(identity), "no duplicate existing provider " + identity)
			providers[identity] = true
		var player: CharacterBody3D = scene.get_node("Player/CharacterBody3D")
		var original := player.global_position
		for frame in range(120): await physics_frame
		check(player.global_position.distance_to(original) < 0.00001, "idle player unchanged in populated " + path)
		if rendered:
			var camera: Camera3D = scene.get_node("CameraRig/Camera3D")
			# QA-only overview; production camera and actors remain unmodified.
			camera.global_position = Vector3(0, 3, 4)
			camera.look_at(Vector3(0, 0, 0.4))
			for frame in range(4): await process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://build/population-captures")
			root.get_texture().get_image().save_png("res://build/population-captures/" + path.get_file().get_basename() + ".png")
		scene.free()
		current_scene = null
		await process_frame
	# Exercise actual physics for every newly placed hard body, with the player
	# also resolving slide collisions each tick; shape-existence checks are not enough.
	for placement in manifest.placements:
		var entry = CATALOG.get_entry(StringName(placement.catalogue_id))
		if not entry.profile.collider_profile.hard_blocking: continue
		var actor := entry.scene.instantiate() as CatalogueNPCActor
		root.add_child(actor)
		var player := CharacterBody3D.new()
		player.collision_layer = 2
		player.collision_mask = 17
		player.platform_floor_layers = 0
		player.platform_wall_layers = 0
		player.add_to_group("fishing_player")
		player.position = Vector3(0, 0, 0.8)
		var shape := CollisionShape3D.new()
		shape.shape = CapsuleShape3D.new()
		shape.shape.radius = 0.16
		shape.shape.height = 0.4
		shape.position.y = 0.2
		player.add_child(shape)
		root.add_child(player)
		var original := player.global_position
		var blocked := false
		var maximum_displacement := 0.0
		for frame in range(120):
			await physics_frame
			if not actor.try_autonomous_motion(Vector3(0, 0, 0.01)): blocked = true
			player.velocity = Vector3.ZERO
			player.move_and_slide()
			maximum_displacement = maxf(maximum_displacement, player.global_position.distance_to(original))
		check(blocked and actor.global_position.z < player.global_position.z - 0.25, "new hard actor cannot pass through player " + String(entry.id))
		check(maximum_displacement < 0.00001, "new actor passive player displacement < epsilon " + String(entry.id))
		print("CONTACT ", entry.id, " max passive displacement=", maximum_displacement)
		actor.free()
		player.free()
	print("NPC WORLD POPULATION QA: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
