extends SceneTree
## Gate 16: actual Node3D / Camera3D / SubViewport transitions (headless).
## Rendered screenshots and input-driven casting still require in-game QA.
const Rig = preload("res://scripts/camera_rig.gd")
const View = preload("res://scripts/fishing_character_view.gd")
const Handoff = preload("res://scripts/fishing_rod_handoff.gd")

var passed := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, context: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(context)
		push_error(context)

func run() -> void:
	for size in [Vector2i(640,480),Vector2i(960,480),Vector2i(960,800)]:
		await check_return_to_cast_pose(size)
		await check_character_visibility_reacquire(size)
	print("FISHING CAMERA RETURN / INSET GATE 16: %d/%d passed; failures=%s" % [
		passed, passed + failures.size(), failures])
	quit(0 if failures.is_empty() else 1)

func check_return_to_cast_pose(size: Vector2i) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	root.add_child(vp)
	var player := Node3D.new()
	vp.add_child(player)
	var rig := Rig.new()
	rig.target = player
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.2,3.2,7.2)
	camera.h_offset = 0.9
	camera.v_offset = 0.4
	rig.add_child(camera)
	vp.add_child(rig)
	rig.set_process(false)
	camera.current = true
	var lure := Node3D.new()
	lure.position = Vector3(2,0,-7)
	vp.add_child(lure)
	await process_frame
	rig.rotation.y = 0.2
	var home_rig := rig.global_position
	var home_yaw := rig.rotation.y
	var home_local := camera.transform
	var home_offsets := Vector2(camera.h_offset,camera.v_offset)
	rig.arm_fishing_follow(lure,Vector3.FORWARD,0.0)
	# Long-cast water camera with optical translation, A/D orbit and nonhome yaw.
	rig.global_position += Vector3(3.2,1.0,-3.8)
	camera.rotate_y(0.45)
	camera.global_position += Vector3(-1.5,0.8,-2.0)
	camera.h_offset += 0.2
	camera.v_offset -= 0.1
	rig.rotation.y += 0.35
	var leaving := camera.global_transform
	rig._fight_base_valid = true
	rig.return_fishing_follow_to_target(true)
	check(camera.global_transform.is_equal_approx(leaving),
		"no jump on bait disappearance %s" % size)
	for i in range(100):
		rig._update_aim_heading_return(0.025)
		rig._update_retrieve_yaw(0.025)
	check(not rig._retrieve_yaw_return_active and not rig.fishing_follow_returning,
		"finished return %s" % size)
	check(rig.global_position.is_equal_approx(home_rig),"home rig position %s" % size)
	check(absf(wrapf(rig.rotation.y-home_yaw,-PI,PI)) < 0.00001,
		"home cast yaw %s" % size)
	check(camera.transform.is_equal_approx(home_local),"exact pre-K lens pose %s" % size)
	check(Vector2(camera.h_offset,camera.v_offset).is_equal_approx(home_offsets),
		"exact pre-K optical offsets %s" % size)
	vp.queue_free()
	await process_frame

func check_character_visibility_reacquire(size: Vector2i) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	root.add_child(vp)
	var player := Node3D.new()
	vp.add_child(player)
	var ground := Node3D.new()
	ground.name = "GroundPresentation"
	player.add_child(ground)
	var anchor := Node3D.new()
	anchor.name = "VisualAnchor"
	ground.add_child(anchor)
	var sprite := AnimatedSprite3D.new()
	sprite.name = "AnimatedSprite3D"
	sprite.pixel_size = 0.035
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var frames := SpriteFrames.new()
	var art := Image.create(64,64,false,Image.FORMAT_RGBA8)
	art.fill(Color.TRANSPARENT)
	art.fill_rect(Rect2i(24,24,16,16),Color.WHITE)
	frames.add_frame("default",ImageTexture.create_from_image(art))
	sprite.sprite_frames = frames
	anchor.add_child(sprite)
	var notifier := VisibleOnScreenNotifier3D.new()
	player.add_child(notifier)
	var rig := Rig.new()
	rig.target = player
	rig.player_screen_notifier = notifier
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	vp.add_child(rig)
	rig.set_process(false)
	camera.current = true
	var inset := View.new()
	inset.source_sprite = sprite
	inset.player_screen_notifier = notifier
	var inset_sprite := AnimatedSprite2D.new()
	inset_sprite.name = "Character"
	inset.add_child(inset_sprite)
	vp.add_child(inset)
	await process_frame
	player.global_position = camera.project_position(Vector2(-140,size.y*0.5),10.0)
	inset._on_bait_landed(Vector3.ZERO)
	check(inset.visible,"offscreen actor gets inset %s" % size)
	# Transparent padding of the sprite quad has entered but its painted
	# pixels are still outside. The inset MUST survive this frame.
	player.global_position = camera.project_position(Vector2(-20,size.y*0.5),10.0)
	check(not Handoff.is_player_view_ready(notifier,camera),
		"alpha padding is not a visible actor pixel %s" % size)
	inset._process(0.0)
	check(inset.visible,"inset stays during transparent-edge appearance %s" % size)
	player.global_position = camera.project_position(Vector2(-1,size.y*0.5),10.0)
	check(Handoff.is_player_view_ready(notifier,camera),
		"first painted pixel is detected %s" % size)
	inset._process(0.0)
	check(not inset.visible,"no simultaneous world and inset actors %s" % size)
	player.global_position = camera.project_position(Vector2(-140,size.y*0.5),10.0)
	inset._process(0.0)
	check(inset.visible,"inset reappears if camera loses real actor %s" % size)
	vp.queue_free()
	await process_frame
