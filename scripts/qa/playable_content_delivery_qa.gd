extends SceneTree
## Real scene, Area, router, dialogue, deck and mastery paths; isolated saves.
const SceneRoot = preload("res://scripts/gameplay_scene_root.gd")
const Manifest = "res://data/world/provider_bindings_v1.json"
var checks := 0
var failures: Array[String] = []
var fixture: SessionTestFixture
var session: Node
var mobile := false

func _initialize() -> void:
	var isolated := "CodexPlayableContentQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated): quit(1); return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	mobile = OS.get_cmdline_user_args().has("--mobile")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func settle() -> void:
	for frame in range(8): await physics_frame

func game() -> Node: return SceneRoot.resolve(self)

func finish_dialogue() -> void:
	for line in range(30):
		if not session.dialogue_service.is_active(): break
		session.dialogue_service.advance()
	await settle()
	check(not session.dialogue_service.is_active(), "dialogue releases conversation ownership")

func travel(location: String) -> void:
	DeveloperPlaytestService.current().set_enabled(true)
	var world := root.get_node("WorldLocations")
	if String(world.current_location.location_id) != location:
		check(world.request_travel(StringName(location)).success, "DEV travel to " + location)
		while world.transitioning: await process_frame
	await settle()
	check(String(world.current_location.location_id) == location, "authored location arrival " + location)

func approach(provider: Node3D, key: int) -> void:
	var player: CharacterBody3D = game().get_node("Player/CharacterBody3D")
	# Prove a real clear approach, rather than assuming every encounter can be
	# approached from the same side (the original Beach shop occupies one side).
	var preferred := Vector3.RIGHT if provider.global_position.x < -1 else Vector3.LEFT
	var side := Vector3.ZERO
	for candidate in [preferred, Vector3.FORWARD, Vector3.BACK, -preferred]:
		var start := player.global_transform
		start.origin = provider.global_position + candidate * 0.75
		if not player.test_move(start, -candidate * 0.2): side = candidate; break
	check(side != Vector3.ZERO, "unobstructed physical approach to " + str(provider.get_path()))
	player.global_position = provider.global_position + side * 0.55
	player.rotation.y = atan2(-side.x, -side.z)
	player.velocity = Vector3.ZERO
	await settle()
	check(provider.interaction_area.overlaps_body(player), "physical Area detects player " + str(provider.get_path()))
	if OS.get_cmdline_user_args().has("--rendered"):
		await RenderingServer.frame_post_draw
		var folder := "res://build/mobile-web/content-delivery-rendered"
		DirAccess.make_dir_recursive_absolute(folder)
		game().get_viewport().get_texture().get_image().save_png(folder.path_join(String(provider.get_parent().name) + ".png"))
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	var router := game().get_node("Game/Exploration/WorldInteractionRouter")
	router.handle_event(event)
	event.pressed = true
	check(WorldInteractionRouter.select_target(player, get_nodes_in_group("world_interaction_targets"), event) == provider, "deterministic eligible target " + str(provider.get_path()))
	check(router.handle_event(event), "production routed interaction " + str(provider.get_path()))
	event.pressed = false
	router.handle_event(event)

func start_cards(provider: Node3D, developer: bool) -> void:
	var cards := game().get_node("UI/TripleTriadGame")
	await approach(provider, KEY_C)
	check(session.dialogue_service.is_active(), "card encounter greeting " + String(provider.opponent_id))
	await finish_dialogue()
	check(cards.is_open(), "physical encounter opens cards " + String(provider.opponent_id))
	var deck: Array = cards.deck_setup._deck.duplicate()
	check(deck.size() == 5, "five-card deck available " + String(provider.opponent_id))
	cards._on_deck_confirmed(deck)
	check(cards._session.phase != cards.PHASE_DECK_SETUP and cards._live_match.get_starting_player_cards().size() == 5, "actual match starts " + String(provider.opponent_id))
	check(cards._developer_test_match == developer, "practice/owned deck boundary")
	cards.close_game()
	await settle()
	check(not paused, "card close releases modal ownership")

func learn_prerequisites(service: FishingMasteryService, id: StringName) -> void:
	var technique := service.get_catalog().get_technique(id)
	for prerequisite in technique.prerequisite_ids:
		learn_prerequisites(service, StringName(prerequisite))
	if not service.has_technique(id):
		check(service.learn_technique(id, technique.teacher_id, false).get("success", false), "authored prerequisite fixture " + String(id))

func lesson(provider: Node3D) -> void:
	var authored := provider.technique as FishingMasteryTechniqueDefinition
	check(authored == session.mastery_service.get_catalog().get_technique(authored.technique_id), "lesson uses canonical authored resource")
	var state := FishingUnlockState.new()
	var service := FishingMasteryService.new()
	state._initialized = true
	root.add_child(state)
	root.add_child(service)
	service.configure(session.mastery_service.get_catalog(), state)
	provider._mastery_service = service
	DeveloperPlaytestService.current().set_enabled(false)
	await approach(provider, KEY_K)
	check(session.dialogue_service.is_active() and not service.has_technique(authored.technique_id), "Normal lesson explains missing prerequisites without granting " + String(authored.technique_id))
	await finish_dialogue()
	for prerequisite in authored.prerequisite_ids: learn_prerequisites(service, StringName(prerequisite))
	await approach(provider, KEY_K)
	check(session.dialogue_service.is_active() and service.has_technique(authored.technique_id), "Normal world lesson teaches after authored prerequisites " + String(authored.technique_id))
	await finish_dialogue()
	provider._mastery_service = session.mastery_service
	service.free()
	state.free()
	DeveloperPlaytestService.current().set_enabled(true)
	check(not session.mastery_service.has_technique(authored.technique_id), "DEV fixture begins without granted lesson")
	await approach(provider, KEY_K)
	check(session.dialogue_service.is_active() and session.mastery_service.has_technique(authored.technique_id), "DEV world lesson teaches through live session " + String(authored.technique_id))
	await finish_dialogue()
	check(session.mastery_service.has_capability(authored.technique_id), "canonical capability unlocked")

func clear_paths(actor: Node3D) -> void:
	check(actor is CatalogueNPCActor and not actor.patrol_enabled, "normalized stationary catalogue actor")
	check(actor.get_node("GroundPresentation").profile == actor.visual_profile, "shared visual profile retained")
	check(is_equal_approx(actor.get_node("CollisionShape3D").position.y, actor.visual_profile.collider_profile.height * 0.5), "physical feet collider family")
	var beach := game().get_node("World/beach/Beach") as MeshInstance3D
	var triangles := beach.mesh.get_faces()
	var radius: float = actor.visual_profile.collider_profile.radius
	for offset in [Vector3.ZERO, Vector3.RIGHT * radius, Vector3.LEFT * radius, Vector3.FORWARD * radius, Vector3.BACK * radius]:
		var point: Vector3 = actor.global_position + offset
		var on_land := false
		for vertex in range(0, triangles.size(), 3):
			var polygon := PackedVector2Array()
			for corner in range(3):
				var world: Vector3 = beach.global_transform * triangles[vertex + corner]
				polygon.append(Vector2(world.x, world.z))
			if Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), polygon): on_land = true; break
		check(on_land, "encounter footprint lies on authored beach mesh")
	for node in game().get_node("World").get_children():
		if not node is Node3D or node == actor: continue
		if node.has_method("interact_from_world") or (node is CatalogueNPCActor and node.visual_profile.collider_profile.hard_blocking):
			var delta: Vector3 = node.global_position - actor.global_position
			delta.y = 0
			var other_radius := 0.24
			if node is CatalogueNPCActor: other_radius = node.visual_profile.collider_profile.radius
			check(delta.length() > radius + other_radius + 0.05, "distinct non-overlapping actor footprints " + String(node.name))
	# Capsule samples across the central travel/shop lane and casting bank must
	# remain clear of every new actor body. Existing bodies are intentionally ignored.
	var player: CharacterBody3D = game().get_node("Player/CharacterBody3D")
	for lane_z in [0.0, 0.25]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player.get_node("CollisionShape3D").shape
		query.collision_mask = 16
		for step in range(18):
			query.transform = Transform3D(Basis.IDENTITY, Vector3(-1.7 + step * 0.21, 0.4, lane_z))
			var hits := actor.get_world_3d().direct_space_state.intersect_shape(query)
			check(not hits.any(func(hit): return hit.collider == actor), "new actor does not obstruct shop/travel/fishing lane")
	for lane_x in [-1.2, -1.0, 0.9, 1.5]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player.get_node("CollisionShape3D").shape
		query.collision_mask = 16
		for step in range(8):
			query.transform = Transform3D(Basis.IDENTITY, Vector3(lane_x, 0.4, 0.25 + step * 0.1))
			var hits := actor.get_world_3d().direct_space_state.intersect_shape(query)
			check(not hits.any(func(hit): return hit.collider == actor), "shop/travel approach axes remain clear")

func run() -> void:
	fixture = SessionTestFixture.new()
	fixture.mount(self, mobile, true)
	await settle()
	session = fixture.session
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(Manifest)).providers.filter(func(row): return String(row.path).contains("/Cards") or String(row.path).contains("/Lesson"))
	check(rows.size() == 12, "ten missing opponents plus two missing lessons delivered")
	var all_card_ids := {}
	for row in JSON.parse_string(FileAccess.get_file_as_string(Manifest)).providers:
		if not row.get("refs", {}).has("opponent_id"): continue
		check(not all_card_ids.has(row.refs.opponent_id), "no duplicate physical opponent provider across all locations")
		all_card_ids[row.refs.opponent_id] = true
	check(all_card_ids.size() == 11, "entire registered opponent roster has one physical encounter")
	var ids := {}
	var opponent_count := 0
	var lesson_count := 0
	for row in rows:
		await travel(row.location_id)
		var provider: Node3D = game().get_node(row.path)
		clear_paths(provider.get_parent())
		var cards := game().get_node("UI/TripleTriadGame")
		if row.refs.has("opponent_id"):
			opponent_count += 1
			var id := StringName(row.refs.opponent_id)
			check(not ids.has(id), "one physical encounter per opponent")
			ids[id] = true
			var profile: Resource = cards.opponent_registry.get_opponent(id)
			check(profile != null and provider.opponent_profile == null, "canonical registry ID, no duplicate deck")
			check(not cards.opponent_registry.get_availability(id, 1, &"", &"", {"card_game_unlocked":false}).available, "Normal card-case gate " + String(id))
			var normal := {"card_game_unlocked":true, "total_player_wins":999, "beaten_opponent_ids":profile.unlock_after_opponent_ids}
			check(cards.opponent_registry.get_availability(id, profile.required_player_rank, &"", &"", normal).available, "authored Normal rank/prerequisite gate opens")
			if profile.required_player_rank > 1: check(not cards.opponent_registry.get_availability(id, profile.required_player_rank - 1, &"", &"", normal).available, "Normal lower rank rejected")
			if not profile.unlock_after_opponent_ids.is_empty():
				normal.beaten_opponent_ids = PackedStringArray()
				check(not cards.opponent_registry.get_availability(id, 99, &"", &"", normal).available, "Normal prerequisite wins required")
			DeveloperPlaytestService.current().set_enabled(false)
			await settle()
			check(not cards.get_opponent_availability(id).available, "live fresh Normal encounter locked")
			await approach(provider, KEY_C)
			check(not cards.is_open() and not session.dialogue_service.is_active(), "Normal locked encounter does not open conversation or match")
			DeveloperPlaytestService.current().set_enabled(true)
			await settle()
			await start_cards(provider, true)
			check(cards._collection_backend.get_owned_cards().is_empty(), "practice match never grants owned cards")
		else:
			lesson_count += 1
			await lesson(provider)
	check(opponent_count == 10 and lesson_count == 2, "exact missing content coverage")
	# Repeat every real card encounter in Normal with legitimately unlocked
	# isolated collection/progression fixtures, through the same interaction flow.
	var cards := game().get_node("UI/TripleTriadGame")
	check(cards.claim_salvaged_card_case().success, "normal authored starter case")
	cards._progression.record_result(1, 1, null, 100000)
	for profile in cards.opponent_registry.opponents: cards._world_gateway._encounter_records.record_result(profile.opponent_id, 1, 1, 2)
	for row in rows:
		if not row.refs.has("opponent_id"): continue
		await travel(row.location_id)
		DeveloperPlaytestService.current().set_enabled(false)
		await settle()
		await start_cards(game().get_node(row.path), false)
	# Travel replaces the fixture's original scene. Release the current scene,
	# or the mobile shell, through its real owner rather than a stale reference.
	if not mobile: fixture.scene = current_scene
	fixture.release()
	await settle()
	check(Node.get_orphan_node_ids().is_empty(), "no retained project orphan nodes")
	print("Playable Content Delivery QA (%s): %d/%d passed" % ["mobile" if mobile else "native", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
