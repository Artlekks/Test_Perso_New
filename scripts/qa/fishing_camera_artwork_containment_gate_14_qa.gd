extends SceneTree
## Gate 14: actual SubViewport projections, tracking transforms, sprite artwork,
## inset visibility, and immediate screen-space constraints. No input simulation
## or screenshots are claimed here; the desktop rendered acceptance remains manual.
const Rig = preload("res://scripts/camera_rig.gd")
const CharacterView = preload("res://scripts/fishing_character_view.gd")
const Handoff = preload("res://scripts/fishing_rod_handoff.gd")

var passed: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, context: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(context)
		push_error(context)

func run() -> void:
	test_authoritative_scene_wiring()
	for size in [Vector2i(320,240),Vector2i(640,480),Vector2i(960,480),Vector2i(960,900)]:
		await test_water_pan(size)
		await test_real_artwork_first_pixel(size)
	print("FISHING CAMERA ARTWORK / CONTAINMENT GATE 14: %d/%d passed; failures=%s" % [
		passed,passed+failures.size(),failures])
	quit(0 if failures.is_empty() else 1)

func test_water_pan(size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	root.add_child(viewport)
	var player := Node3D.new()
	player.position = Vector3(100,0,100)
	viewport.add_child(player)
	var rig := Rig.new()
	rig.target = player
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	viewport.add_child(rig)
	rig.set_process(false)
	camera.current = true
	camera.position = Vector3(0,8,12)
	camera.look_at(Vector3.ZERO)
	await process_frame
	var initial_basis := camera.global_basis
	var hard: Rect2 = Rig.inset_follow_region(rig.inset_follow_left,rig.inset_follow_right,
		rig.inset_follow_top,rig.inset_follow_bottom,rig.fishing_safe_region())
	rig._fight_base_camera_transform = camera.transform
	rig._fight_base_valid = true
	for uv in [Vector2(-.08,.62),Vector2(1.08,.64),Vector2(.50,.05),Vector2(.52,.94),
		Vector2(-.12,.02),Vector2(1.12,.02),Vector2(-.12,.96),Vector2(1.12,.96)]:
		var world: Vector3 = camera.project_position(uv*Vector2(size),18.0)
		var old_world := world
		rig._pan_inset_camera_to_lure(camera,world,Vector2(size),1.0/60.0)
		var corrected := camera.unproject_position(world)/Vector2(size)
		verify(hard.grow(.0001).has_point(corrected),"hard inset edge/corner %s %s => %s" % [size,uv,corrected])
		verify(camera.global_basis.is_equal_approx(initial_basis),"pan cannot rotate %s %s" % [size,uv])
		verify(world.is_equal_approx(old_world),"pan cannot move physical bait %s %s" % [size,uv])
		# A second composed frame must retain precisely the same pan, not
		# overwrite it with the unmodified base pose.
		var recomposed: Transform3D = rig._water_base(rig._water_pan)
		recomposed.origin += rig._inset_optical_pan
		camera.global_transform = recomposed
		verify(hard.grow(.0001).has_point(camera.unproject_position(world)/Vector2(size)),
			"water camera offset survives recompose %s %s" % [size,uv])
	verify(rig.inset_containment_failures == 0,"zero inset invariant failures %s" % size)
	viewport.queue_free()
	await process_frame

func test_real_artwork_first_pixel(size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	root.add_child(viewport)
	var player := Node3D.new()
	viewport.add_child(player)
	var ground := Node3D.new()
	ground.name = "GroundPresentation"
	player.add_child(ground)
	var anchor := Node3D.new()
	anchor.name = "VisualAnchor"
	ground.add_child(anchor)
	var source := AnimatedSprite3D.new()
	source.name = "AnimatedSprite3D"
	source.pixel_size = .035
	var frames := SpriteFrames.new()
	var art := Image.create(64,64,false,Image.FORMAT_RGBA8)
	art.fill(Color.WHITE)
	frames.add_frame("default",ImageTexture.create_from_image(art))
	source.sprite_frames = frames
	anchor.add_child(source)
	var notifier := VisibleOnScreenNotifier3D.new()
	player.add_child(notifier)
	var rig := Rig.new()
	rig.target = player
	rig.player_screen_notifier = notifier
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	viewport.add_child(rig)
	rig.set_process(false)
	camera.current = true
	var inset := CharacterView.new()
	inset.source_sprite = source
	inset.player_screen_notifier = notifier
	var drawn := AnimatedSprite2D.new()
	drawn.name = "Character"
	inset.add_child(drawn)
	viewport.add_child(inset)
	await process_frame
	# Entire visible body offscreen; inset must be usable and have authority.
	player.position = camera.project_position(Vector2(-170,size.y*.5),10.0)
	inset._on_bait_landed(Vector3.ZERO)
	verify(not Handoff.is_player_view_ready(notifier,camera),"offscreen art %s" % size)
	verify(inset.visible,"inset shown when world art absent %s" % size)
	# Feet/origin remain outside the viewport (and the old 10% threshold),
	# yet the 64px sprite has crossed the LEFT edge by a small amount.
	player.position = camera.project_position(Vector2(-32,size.y*.5),10.0)
	verify(Handoff.is_player_view_ready(notifier,camera),"sprite first visible edge %s" % size)
	inset._process(0.0)
	verify(not inset.visible,"no two character copies on first visible pixel %s" % size)
	verify(rig._real_player_view_engaged,"camera agrees with inset handoff %s" % size)
	# After bait returned, a tween must never display another inset over art.
	inset._on_bait_returned()
	inset._process(0.0)
	verify(not inset.visible,"returned/cancelled bait cannot reintroduce inset %s" % size)
	viewport.queue_free()
	await process_frame

func test_authoritative_scene_wiring() -> void:
	# Inspect the REAL active gameplay scene, not an invented test-only hierarchy.
	var packed: PackedScene = load("res://actors/FishingTestScene_V2.tscn") as PackedScene
	verify(packed != null,"real fishing scene loads")
	if packed == null:
		return
	var instance: Node = packed.instantiate()
	var rig := instance.get_node_or_null("CameraRig")
	var camera := instance.get_node_or_null("CameraRig/Camera3D")
	var view := instance.get_node_or_null("UI/FishingHud/CharacterView")
	var sprite := instance.get_node_or_null("Player/CharacterBody3D/GroundPresentation/VisualAnchor/AnimatedSprite3D")
	var notifier := instance.get_node_or_null("Player/CharacterBody3D/RyuScreenNotifier")
	var caster := instance.get_node_or_null("Game/Fishing/Caster")
	verify(rig != null and camera != null,"real camera rig and lens present")
	verify(view != null and sprite != null and notifier != null,"real inset/sprite/notifier hierarchy present")
	verify(caster != null,"real caster remains attached")
	instance.free()
