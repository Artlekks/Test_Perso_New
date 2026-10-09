extends SceneTree
const Presentation = preload("res://scripts/world/ground_presentation.gd")
const Shadow = preload("res://scripts/world/world_blob_shadow.gd")
var checks := 0
var failures: Array[String] = []
var rendered := false
var captures := "user://grounding-captures"
func _initialize() -> void:
	rendered = OS.get_cmdline_user_args().has("--rendered")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): captures = arg.trim_prefix("--capture-dir=")
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func strip(node: Node) -> void:
	if node is CanvasLayer: node.visible = false
	if node is Label3D: node.visible = false
	if node is BeachGatheringNode3D: return
	if node.get_script() in [Presentation, Shadow]: return
	for child in node.get_children(): strip(child)
	node.set_script(null)
func settle() -> void:
	for i in 3: await process_frame
func test_gathering_sensor(shape: CollisionShape3D, preserved_center: Vector3, label: String) -> void:
	# Exercise the actual Area broadphase against the pre-migration boundary,
	# independently of the scene transform assertions. This probe is not a player
	# and cannot trigger gathering, inventory or interaction routing.
	var area := shape.get_parent() as Area3D
	var probe := CharacterBody3D.new()
	probe.collision_layer = 1
	probe.collision_mask = 0
	var probe_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.001
	probe_shape.shape = sphere
	probe.add_child(probe_shape)
	root.add_child(probe)
	var radius: float = shape.shape.radius
	probe.global_position = preserved_center + Vector3(0, radius - 0.001, 0)
	for i in 6: await physics_frame
	check(area.overlaps_body(probe), label + " preserved sensor upper boundary detects body")
	probe.global_position = preserved_center + Vector3(0, radius + 0.01, 0)
	for i in 6: await physics_frame
	check(not area.overlaps_body(probe), label + " outside preserved sensor boundary rejects body")
	probe.free()
func test_actor(actor: Node3D) -> void:
	var presentation := actor.get_node("GroundPresentation") as GroundPresentation
	var shadow := presentation.shadow
	var sprite := presentation.sprite
	check(presentation.profile != null, "%s has authored profile" % actor.name)
	check(actor.find_children("*", "WorldBlobShadow", true, false).size() == 1, "%s exactly one shadow" % actor.name)
	check(not shadow.get_parent() is SpriteBase3D and shadow.get_parent().get_parent() == presentation, "%s independent shadow hierarchy" % actor.name)
	if sprite != null:
		check(sprite.position.is_zero_approx() and sprite.scale == Vector3.ONE, "%s normalized sprite-local transform" % actor.name)
		check(not sprite.no_depth_test, "%s retains world occlusion" % actor.name)
	else:
		check(presentation.profile.category == 3, "%s native ground prop profile" % actor.name)
	check(presentation.global_position.is_equal_approx(actor.global_position), "%s physical root anchor" % actor.name)
	check(shadow.global_basis.is_equal_approx(Basis.IDENTITY), "%s flat world shadow" % actor.name)
	check(shadow.global_position.is_equal_approx(actor.global_position + Vector3(0, presentation.profile.resolved_shadow_family().ground_offset, 0)), "%s centered root-relative shadow" % actor.name)
	check(shadow.width == shadow.depth and shadow.opacity < 0.8, "%s compact soft category shadow" % actor.name)
	check(shadow.material_override is ShaderMaterial and shadow.material_override.render_priority == -120, "%s reusable radial material under actors" % actor.name)
	var original := shadow.global_transform
	for turn in 8:
		actor.rotation.y = turn * PI / 4
		if sprite is AnimatedSprite3D:
			sprite.flip_h = turn % 2 == 1
			sprite.frame = turn % sprite.sprite_frames.get_frame_count(sprite.animation)
		await settle()
		check(shadow.global_transform.is_equal_approx(original), "%s facing/flip/frame %d leaves shadow fixed" % [actor.name,turn])
	actor.rotation.y = 0
	var old := actor.position
	actor.position += Vector3(0.4, 0, 0.2)
	await settle()
	check(shadow.global_position.is_equal_approx(actor.global_position + Vector3(0, shadow.ground_offset, 0)), "%s shadow follows moving root" % actor.name)
	actor.position = old
	await settle()
	if sprite is AnimatedSprite3D:
		for animation in sprite.sprite_frames.get_animation_names():
			sprite.animation = animation
			presentation.apply_frame()
			var tex = sprite.sprite_frames.get_frame_texture(animation, sprite.frame)
			var padding = presentation.profile.animation_feet_from_bottom_px.get(String(animation), presentation.profile.feet_from_bottom_px)
			check(is_equal_approx(sprite.offset.y + float(padding), tex.get_height() * 0.5), "%s sheet feet registration %s" % [actor.name,animation])
			var feet_x: float = presentation.profile.animation_feet_from_left_px.get(String(animation), presentation.profile.feet_from_left_px)
			for flipped in [false, true]:
				sprite.flip_h = flipped
				presentation.apply_frame()
				var expected_x: float = tex.get_width() * 0.5 - feet_x if feet_x >= 0 else 0.0
				if flipped: expected_x = -expected_x
				check(is_equal_approx(sprite.offset.x, expected_x), "%s declared sheet stance mirrors correctly %s/%s" % [actor.name,animation,flipped])
func run() -> void:
	# Every authored character, including inherited regional merchant families.
	var files := DirAccess.get_files_at("res://actors")
	var actors := 0
	for filename in files:
		if not filename.ends_with(".tscn"): continue
		var source := FileAccess.get_file_as_string("res://actors/" + filename)
		if not source.contains("ground_component"): continue
		var actor = load("res://actors/" + filename).instantiate()
		strip(actor)
		root.add_child(actor)
		await settle()
		await test_actor(actor)
		actors += 1
		actor.free()
	check(actors == 24, "twenty character bases, gathering base and three native ground props inventoried")
	for filename in DirAccess.get_files_at("res://actors/locations"):
		if not filename.ends_with(".tscn"): continue
		var regional = load("res://actors/locations/" + filename).instantiate()
		strip(regional)
		root.add_child(regional)
		await settle()
		for presentation in regional.find_children("GroundPresentation", "Node3D", true, false):
			check(presentation.shadow.material_override is ShaderMaterial, filename + " inherited radial shadow without legacy override")
			check(presentation.shadow.global_position.is_equal_approx(presentation.global_position + Vector3(0,presentation.profile.resolved_shadow_family().ground_offset,0)), filename + " inherited root contact shadow")
		regional.free()
	var scene = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	strip(scene)
	root.add_child(scene)
	scene.get_node("World/FishZone_V2").hide()
	await settle()
	var baseline = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation/qa_physics_baseline.json"))
	for row in baseline:
		var shape = scene.get_node(row.path) as CollisionShape3D
		check(shape.global_position.is_equal_approx(Vector3(row.position[0],row.position[1],row.position[2])), row.path + " physics world position unchanged")
		check(str(shape.global_basis) == row.basis and shape.disabled == row.disabled, row.path + " physics basis/state unchanged")
		check(shape.get_parent().collision_layer == row.layer and shape.get_parent().collision_mask == row.mask, row.path + " layer/mask unchanged")
		if String(row.path).begins_with("World/BeachGatheringCircuit/"):
			await test_gathering_sensor(shape, Vector3(row.position[0],row.position[1],row.position[2]), row.path)
	for presentation in scene.find_children("GroundPresentation", "Node3D", true, false):
		check(is_zero_approx(presentation.get_parent().global_position.y), str(presentation.get_parent().name) + " normalized physical root Y")
		check(presentation.get_parent().find_children("ShadowSprite3D", "", true, false).is_empty(), "no manually transformed legacy shadow")
	var items = scene.get_node("World/BeachGatheringCircuit")
	for item in items.get_children():
		var p = item.get_node("GroundPresentation")
		check(p.profile.category == 2 and p.profile.shadow_width < 0.15 and p.profile.shadow_opacity == 0.35, str(item.name) + " small contact shadow profile")
		check(item.find_children("*", "PhysicsBody3D", true, false).is_empty(), str(item.name) + " remains non-blocking")
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	var npc = scene.get_node("World/BeachMerchantNPC")
	var shadow = npc.get_node("GroundPresentation/ShadowAnchor/WorldBlobShadow")
	var original: Transform3D = shadow.global_transform
	if rendered: DirAccess.make_dir_recursive_absolute(captures)
	for angle in 4:
		camera.global_position = npc.global_position + Vector3(sin(angle * PI / 2) * 1.5, 1.0, cos(angle * PI / 2) * 1.5)
		camera.look_at(npc.global_position + Vector3(0, 0.2, 0))
		await settle()
		check(shadow.global_transform.is_equal_approx(original), "stationary NPC camera orbit %d keeps shadow fixed" % angle)
		if rendered:
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(captures.path_join("npc-orbit-%d.png" % angle)) == OK, "rendered orbit capture")
	var item_profile = load("res://data/presentation/excluded.tres")
	var p = npc.get_node("GroundPresentation")
	p.profile = item_profile
	p.apply_profile()
	check(not p.shadow.visible, "waterborne/airborne excluded category has no shadow")
	scene.free()
	print("WORLD GROUNDING/SHADOW QA: %d/%d" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
