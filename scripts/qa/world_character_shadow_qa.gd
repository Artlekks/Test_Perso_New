extends SceneTree

## Save-free structural and transform QA. This does not judge rendered pixels.
## godot --headless --path . --script res://scripts/qa/world_character_shadow_qa.gd
const BlobShadowScript = preload("res://scripts/world/world_blob_shadow.gd")
const DIRECTIONS := ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(label)
		push_error(label)


func _strip(node: Node, preserve_movers: bool = false) -> void:
	if node.get_script() == BlobShadowScript:
		return
	if preserve_movers and node.name == &"FishingCardMakerNPC":
		return
	for child: Node in node.get_children():
		_strip(child, preserve_movers)
	if preserve_movers and node.name in [
		&"BeachCritter", &"BeachCritter2", &"WorldActorPresentation", &"DepthFloor"
	]:
		return
	node.set_script(null)


func _settle() -> void:
	for i in range(3):
		await process_frame
	await physics_frame


func _shadows(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		if child.get_script() == BlobShadowScript:
			result.append(child)
		result.append_array(_shadows(child))
	return result


func _check_actor(actor: Node3D, ground_y: float) -> void:
	var shadows := _shadows(actor)
	_check(shadows.size() == 1, "%s exactly one shared shadow" % actor.name)
	_check(actor.find_children("ShadowSprite3D", "", true, false).is_empty(), "%s no legacy shadow" % actor.name)
	if shadows.size() != 1:
		return
	var shadow := shadows[0] as BlobShadowScript
	_check(shadow.get_parent().name == &"ShadowAnchor" and shadow.get_parent().get_parent() == actor, "%s root/anchor/shadow hierarchy" % actor.name)
	_check((shadow.get_parent() as Node3D).position.is_zero_approx(), "%s physical root anchor" % actor.name)
	var ancestor: Node = shadow.get_parent()
	var below_sprite: bool = false
	while ancestor != null:
		below_sprite = below_sprite or ancestor is AnimatedSprite3D
		ancestor = ancestor.get_parent()
	_check(not below_sprite, "%s independent of AnimatedSprite3D" % actor.name)
	_check(shadow.global_basis.is_equal_approx(Basis.IDENTITY), "%s flat world orientation" % actor.name)
	_check(is_equal_approx(shadow.global_position.x, actor.global_position.x) and is_equal_approx(shadow.global_position.z, actor.global_position.z), "%s shadow centered at physical root" % actor.name)
	_check(is_equal_approx(shadow.global_position.y, ground_y + shadow.ground_offset), "%s ground lift" % actor.name)
	var material := shadow.material_override as StandardMaterial3D
	_check(material != null and material.render_priority == -120 and not material.no_depth_test, "%s shadow below sprites with depth testing" % actor.name)
	_check(material != null and material.albedo_texture.resource_path == "res://assets/sprites/shared/Shadow.png", "%s shared existing art" % actor.name)
	_check(is_equal_approx(shadow.opacity, 0.65) and is_equal_approx(material.albedo_color.a, 0.65), "%s darker shared opacity" % actor.name)
	_check(is_equal_approx(shadow.ground_offset, 0.006), "%s ground offset unchanged" % actor.name)
	if not (actor is CharacterBody3D) and not actor.name.begins_with("BeachCritter") and actor.name != &"BeachFishingCritter":
		_check(is_equal_approx(shadow.width, 0.26) and is_equal_approx(shadow.depth, 0.30), "%s compact humanoid defaults" % actor.name)


func _run() -> void:
	# Inspect every authored character scene, including scenes outside the main
	# level. They work without the scene controller and do not create physics.
	var authored_count: int = 0
	for filename: String in DirAccess.get_files_at("res://actors"):
		if not filename.ends_with(".tscn"):
			continue
		var path := "res://actors/" + filename
		var source := FileAccess.get_file_as_string(path)
		_check(not source.contains("ShadowSprite3D"), "%s legacy node/override removed" % filename)
		if filename == "WorldBlobShadow.tscn" or not source.contains("res://actors/WorldBlobShadow.tscn"):
			continue
		authored_count += 1
		var actor: Node3D = load(path).instantiate()
		_strip(actor)
		root.add_child(actor)
		await _settle()
		_check_actor(actor, actor.global_position.y)
		actor.free()
	_check(authored_count == 20, "all twenty authored character scenes covered")

	var scene: Node3D = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	_strip(scene, true)
	root.add_child(scene)
	current_scene = scene
	await _settle()
	var world := scene.get_node("World") as Node3D
	var ground := world.get_node("beach/Beach") as Node3D
	var actors: Array[Node3D] = []
	for child: Node in world.get_children():
		if child is Node3D and child.find_child("AnimatedSprite3D", true, false) != null:
			actors.append(child as Node3D)
	var player := scene.get_node("Player/CharacterBody3D") as CharacterBody3D
	actors.append(player)
	_check(actors.size() == 21 and _shadows(scene).size() == 21, "twenty-one runtime characters, no sibling duplicates")
	for actor: Node3D in actors:
		_check_actor(actor, ground.global_position.y)
	var presentation := scene.get_node("WorldActorPresentation")
	presentation._setup_actor_presentation()
	await _settle()
	_check(_shadows(scene).size() == 21, "presentation setup does not duplicate shadows")

	var player_shadow := player.get_node("ShadowAnchor/WorldBlobShadow") as BlobShadowScript
	var sprite := player.get_node("AnimatedSprite3D") as AnimatedSprite3D
	var player_position := player.global_position
	var expected := player_shadow.global_transform
	var camera_rig := scene.get_node("CameraRig") as Node3D
	var original_offset := sprite.offset
	for index in range(8):
		player.rotation.y = float(index) * PI / 4.0
		camera_rig.rotation.y = float(index) * PI / 4.0
		var animation := StringName("Idle_" + DIRECTIONS[index])
		_check(sprite.sprite_frames.has_animation(animation), "player %s animation exists" % DIRECTIONS[index])
		sprite.play(animation)
		sprite.flip_h = index % 2 == 1
		sprite.offset = original_offset + Vector2(index * 2, index * 3)
		await _settle()
		_check(player_shadow.global_transform.is_equal_approx(expected), "player %s facing/camera/flip/offset cannot shift shadow" % DIRECTIONS[index])
		_check(player.global_position.is_equal_approx(player_position), "player %s root unchanged" % DIRECTIONS[index])
	player.rotation = Vector3.ZERO
	sprite.offset = original_offset
	_check(is_equal_approx(player_shadow.width, 0.24) and is_equal_approx(player_shadow.depth, 0.28), "player size override")
	for name: String in ["BeachCritter", "BeachCritter2"]:
		var shadow := world.get_node(name + "/ShadowAnchor/WorldBlobShadow") as BlobShadowScript
		_check(is_equal_approx(shadow.width, 0.14) and is_equal_approx(shadow.depth, 0.16), "%s size override by scene composition" % name)
	# Optional Inspector stance offsets remain one physical position even when
	# the actor/camera changes direction. No scene uses a nonzero offset yet.
	var player_anchor := player.get_node("ShadowAnchor") as Node3D
	player_anchor.position = Vector3(0.025, 0.0, 0.015)
	for index in range(8):
		player.rotation.y = float(index) * PI / 4.0
		camera_rig.rotation.y = float(index) * PI / 4.0
		await _settle()
		_check(player_shadow.global_position.is_equal_approx(expected.origin + player_anchor.position), "fixed stance offset does not rotate for player %s" % DIRECTIONS[index])
		_check(player_shadow.global_basis.is_equal_approx(Basis.IDENTITY), "offset shadow remains flat for player %s" % DIRECTIONS[index])
	player.rotation = Vector3.ZERO
	player_anchor.position = Vector3.ZERO
	await _settle()

	var maker := world.get_node("FishingCardMakerNPC") as FishingCardMakerNPC
	var maker_shadow := maker.get_node("ShadowAnchor/WorldBlobShadow") as BlobShadowScript
	maker.set_physics_process(false)
	_check(not maker.smoke_enabled, "Card Maker smoke remains disabled")
	for leg in range(5):
		maker._begin_next_patrol_leg()
		while maker._moving:
			maker._process_patrol_leg(1.0 / 60.0)
			await _settle()
			_check(is_equal_approx(maker_shadow.global_position.x, maker.global_position.x) and is_equal_approx(maker_shadow.global_position.z, maker.global_position.z), "Card Maker shadow follows walking leg %d" % leg)
		_check_actor(maker, ground.global_position.y)
		maker._stop_patrol()
		maker._play_idle(&"se")
		await _settle()
		var stopped := maker_shadow.global_transform
		maker._play_idle(&"nw")
		paused = true
		await _settle()
		_check(maker_shadow.global_transform.is_equal_approx(stopped), "Card Maker stable when stopped/turning/tree paused on leg %d" % leg)
		paused = false
	# Inspector controls must be instance-local, not mutate another actor's mesh.
	var merchant_shadow := world.get_node("BeachMerchantNPC/ShadowAnchor/WorldBlobShadow") as BlobShadowScript
	var merchant_size := (merchant_shadow.mesh as PlaneMesh).size
	maker_shadow.width = 0.73
	maker_shadow.depth = 0.31
	maker_shadow.opacity = 0.22
	maker_shadow.ground_offset = 0.012
	_check((maker_shadow.mesh as PlaneMesh).size.is_equal_approx(Vector2(0.73, 0.31)), "exported width/depth update mesh")
	_check(is_equal_approx((maker_shadow.material_override as StandardMaterial3D).albedo_color.a, 0.22), "exported opacity updates material")
	_check((merchant_shadow.mesh as PlaneMesh).size.is_equal_approx(merchant_size), "per-actor overrides do not leak to other shadows")
	_check(is_equal_approx(maker_shadow.global_position.y, ground.global_position.y + 0.012), "exported ground offset updates world height")
	var old_shadow: WeakRef = weakref(maker_shadow)
	maker.queue_free()
	await _settle()
	_check(old_shadow.get_ref() == null, "shadow freed with actor despite top-level transform")
	print("World Character Shadow QA: %d checks, %d failures" % [_checks, _failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
