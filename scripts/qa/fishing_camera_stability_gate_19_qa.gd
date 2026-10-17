extends SceneTree
## Gate 19: responsive HUD safe-area geometry, camera-only containment,
## texture-safe artwork handoff, and cast-playback contract.
## Does not certify rendered pixels: an F5 comparison is still mandatory.
const Rig = preload("res://scripts/camera_rig.gd")
const Handoff = preload("res://scripts/fishing_rod_handoff.gd")
const Outpost = preload("res://actors/locations/DevelopmentFishingOutpost.tscn")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	for dimensions in [Vector2i(640,480),Vector2i(960,480),Vector2i(960,700),Vector2i(1116,834),Vector2i(480,700)]:
		await check_scene_geometry(dimensions)
		await check_projection_containment(dimensions)
	print("FISHING CAMERA STABILITY GATE 19: %d/%d passed; failures=%s" % [
		checks - failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)

func check_scene_geometry(dimensions: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.own_world_3d = true
	root.add_child(viewport)
	var game := Outpost.instantiate()
	viewport.add_child(game)
	await process_frame
	await process_frame
	var rig = game.get_node("CameraRig")
	var camera := game.get_node("CameraRig/Camera3D") as Camera3D
	var power = game.get_node("UI/FishingHud/PowerMeter")
	var depth = game.get_node("UI/FishingHud/PowerMeter/DepthMeter")
	var inset = game.get_node("UI/FishingHud/CharacterView")
	var caster = game.get_node("Game/Fishing/Caster")
	power._update_viewport_layout(0.0)
	rig.set_fishing_hud_geometry(power,depth)
	var box: Rect2 = rig._inset_follow_region_for_camera(camera)
	var bar: Rect2 = rig._hud_rest_rect(power.get_node("Root/PowerBarBG"),power,null)
	var gauge: Rect2 = rig._hud_rest_rect(depth.get_node("Frame"),null,depth)
	var artwork: Rect2 = rig._inset_artwork_rect()
	check(box.has_area(),"valid HUD anchored region %s" % dimensions)
	check(absf(box.position.y - 0.43) < 0.0001,"safe top at 43 percent height %s" % dimensions)
	check(box.end.y * dimensions.y < bar.position.y,"safe bottom before power bar %s" % dimensions)
	check(box.end.x * dimensions.x < gauge.position.x,"safe right before gauge %s" % dimensions)
	if artwork.has_area():
		check(box.position.x * dimensions.x > artwork.end.x,"safe left beyond inset artwork %s" % dimensions)
	check(box.size.y > 0.18,"safe region no longer a thin horizontal strip %s" % dimensions)
	check(caster.cast_flight_playback_speed > 0.0 and caster.cast_flight_playback_speed <= 0.65,
		"flight playback slower without reauthoring trajectory %s" % dimensions)
	# The live texture may be compressed by Godot's importer. This method
	# previously raised Cannot blit_rect on every frame of a long cast.
	var sprite = inset.source_sprite as AnimatedSprite3D
	if sprite != null:
		check(sprite.sprite_frames != null,"live artwork frames exist %s" % dimensions)
		if sprite.sprite_frames != null:
			var frame: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
			if frame != null:
				var art_image: Image = frame.get_image()
				# A compressed texture can be sampled repeatedly without triggering
				# get_used_rect on compressed image data in the handoff helper.
				if art_image != null:
					Handoff.is_billboard_art_projected_in_view(sprite,camera)
					Handoff.is_billboard_art_projected_in_view(sprite,camera)
					check(Handoff._sprite_opaque_bounds_cache.has(frame.get_instance_id()),
						"frame bounds cached after compressed-image-safe inspection %s" % dimensions)
	viewport.queue_free()
	await process_frame

func check_projection_containment(dimensions: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.own_world_3d = true
	root.add_child(viewport)
	var distant := Node3D.new()
	distant.position = Vector3(100,0,100)
	viewport.add_child(distant)
	var rig := Rig.new()
	rig.target = distant
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	viewport.add_child(rig)
	rig.set_process(false)
	camera.position = Vector3(0,7,12)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	await process_frame
	var size: Vector2 = Vector2(dimensions)
	var initial: Transform3D = camera.global_transform
	var baseline_fov: float = camera.fov
	var physical: Vector3
	for uv in [Vector2(.09,.58),Vector2(.91,.58),Vector2(.48,.10),Vector2(.48,.90),
		Vector2(.07,.08),Vector2(.93,.08),Vector2(.07,.92),Vector2(.93,.92)]:
		camera.global_transform = initial
		rig._inset_optical_pan = Vector3.ZERO
		rig._airborne_inset_pan = Vector3.ZERO
		rig._fight_base_valid = true
		rig._fight_base_camera_transform = camera.transform
		physical = camera.project_position(uv * size,18.0)
		var before: Vector3 = physical
		rig._pan_inset_camera_to_lure(camera,physical,size,1.0/30.0)
		var zone: Rect2 = rig._inset_follow_region_for_camera(camera)
		var actual: Vector2 = camera.unproject_position(physical)/size
		check(zone.grow(0.0002).has_point(actual),"no escape at edge %s %s (%s)" % [dimensions,uv,actual])
		check(physical.is_equal_approx(before),"bait physics unchanged %s %s" % [dimensions,uv])
		check(camera.global_basis.is_equal_approx(initial.basis),"tracking is translational, not yaw/zoom %s %s" % [dimensions,uv])
		check(is_equal_approx(camera.fov,baseline_fov),"tracking cannot change FOV %s %s" % [dimensions,uv])
	viewport.queue_free()
	await process_frame
