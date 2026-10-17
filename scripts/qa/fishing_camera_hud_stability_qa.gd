extends SceneTree
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
## Real mobile scene, physical Caster/Bait and native rendered frame evidence.
const STEP := 1.0/60.0
const SIZES := [Vector2i(390,844),Vector2i(932,430),Vector2i(320,568),Vector2i(568,320)]
var checks := 0
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var fixture: SessionTestFixture
var fishing: Node
var rig: Node3D
var camera: Camera3D

func _initialize() -> void:
	if not Isolation.verify(["user://qa_camera_hud"]):
		quit(1)
		return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func settle() -> void:
	for frame in range(30): await process_frame

func action(id: StringName, down: bool) -> void:
	if down: Input.action_press(id)
	else: Input.action_release(id)
	var event := InputEventAction.new()
	event.action = id; event.pressed = down
	fishing._unhandled_input(event)

func visual_rect(node: CanvasItem) -> Rect2:
	var local: Rect2 = node.get_rect() if node is Sprite2D else Rect2(Vector2.ZERO,node.size)
	return node.get_global_transform_with_canvas()*local

func pose_metrics() -> Dictionary:
	var pivot: Vector3 = fishing.player.global_position
	var yaw: float = rig.fight_camera_tracking.yaw
	var without_yaw := Basis(Vector3.UP,-yaw)
	return {"distance":camera.global_position.distance_to(pivot),"optical_distance":camera.get_camera_transform().origin.distance_to(pivot),"fov":camera.fov,"size":camera.size,
		"pitch_degrees":rad_to_deg(asin(camera.global_basis.z.y)),"roll_degrees":rad_to_deg(asin(camera.global_basis.x.y)),
		"pitch_axis":camera.global_basis.z.y,"roll_axis":camera.global_basis.x.y,
		"yaw":yaw,"unorbited_offset":without_yaw*(camera.global_position-pivot),
		"optical_offsets":Vector2(camera.h_offset,camera.v_offset),
		"player":camera.unproject_position(pivot)/Vector2(camera.get_viewport().size)}

func stable(reference: Dictionary) -> bool:
	var now := pose_metrics()
	return absf(now.distance-reference.distance)<.0001 and now.fov==reference.fov and now.size==reference.size and absf(now.pitch_axis-reference.pitch_axis)<.00001 and absf(now.roll_axis-reference.roll_axis)<.00001 and now.unorbited_offset.distance_to(reference.unorbited_offset)<.0001 and now.optical_offsets==reference.optical_offsets and now.player.distance_to(reference.player)<.00001

func run() -> void:
	for frame in range(2): await process_frame
	if not Isolation.verify_root_clock(self): quit(1); return
	var desktop := OS.get_cmdline_user_args().has("--desktop")
	var sizes: Array = [Vector2i(1280,900),Vector2i(640,900)] if desktop else SIZES
	var output_dir := "user://qa_camera_hud/"+("desktop" if desktop else "mobile")
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = SIZES[0]
	fixture = SessionTestFixture.new()
	var host: Control
	if desktop:
		OS.set_environment("FISHING_COMPANION_IPC",ProjectSettings.globalize_path("user://qa_camera_hud/desktop-ipc"))
		host=load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
		root.add_child(host); current_scene=host
		fixture.tree=self; fixture.scene=host
		fixture.session=SessionComposition.acquire(self); fixture.owns_session=true
	else: host=fixture.mount(self,true)
	await settle()
	fishing = host.game.get_node("Game/Fishing")
	rig = fishing.camera_rig
	camera = rig.get_node("Camera3D")
	fishing.player.global_basis = host.game.get_node("World/FishZone_V2/WaterFacing").global_basis
	fishing.game_mode.enter_fishing(host.game.get_node("World/FishZone_V2"))
	for frame in range(600):
		if fishing.phase == fishing.Phase.AIM: break
		await process_frame
	check(fishing.phase == fishing.Phase.AIM,"normal fishing entry completes")
	for attempt in range(6):
		if fishing.phase == fishing.Phase.IN_WATER: break
		action(&"enter_fishing",true); await process_frame; action(&"enter_fishing",false)
		await create_timer(.8).timeout
		if fishing.phase in [fishing.Phase.THROW,fishing.Phase.BAIT_FLYING]: await create_timer(2.0).timeout
	check(fishing.phase == fishing.Phase.IN_WATER,"real cast/landing reaches water")
	var bait: Node3D = fishing.caster.active_bait
	check(is_instance_valid(bait),"real physical bait exists")
	if not is_instance_valid(bait): quit(1); return
	bait.set_physics_process(false)
	bait.current_service = null
	fishing.encounter.bite_timer.stop(); fishing.encounter.bite_window_timer.stop()
	fishing.set_process(false); rig.set_process(false)
	var landing: Vector3 = bait.global_position
	for dimensions in sizes:
		root.size = dimensions; await settle(); host._layout(); await settle()
		var size := Vector2(host.gameplay_viewport.size)
		var power: Node = fishing.power_meter_view
		check(power._layout_size == size,"HUD measures actual gameplay viewport")
		var depth: Node = fishing.depth_meter_view
		var power_rect := visual_rect(power.get_node("Root/PowerBarBG"))
		var depth_rect := visual_rect(depth.get_node("Frame"))
		check(Rect2(Vector2.ZERO,size).encloses(power_rect) and Rect2(Vector2.ZERO,size).encloses(depth_rect),"HUD entirely inside actual world viewport")
		check(absf(power_rect.position.x-power._rest_position.x)<.01,"power gauge fixed to native HUD resting position")
		check(absf(depth.rest_position.x-power._rest_position.x-357.0)<.0001,"approved gauge gap and artwork scale preserved")
		check(power.root.scale == Vector2(.35,.35) and depth.scale == Vector2(.36,.36),"no independent texture stretch")
		var x_before := Vector2(power._rest_position.x, depth.rest_position.x)
		var original_h_offset: float = camera.h_offset
		camera.h_offset = original_h_offset + 0.45
		# Force a fresh layout calculation rather than passing only because
		# the cache sees an unchanged viewport size.
		power._layout_size = Vector2.ZERO
		power._update_viewport_layout()
		check(Vector2(power._rest_position.x, depth.rest_position.x) == x_before,
			"camera projection changes cannot shift power or depth gauge")
		camera.h_offset = original_h_offset
		power._update_viewport_layout()
		var metrics := pose_metrics()
		var physical_start: Vector3 = bait.global_position
		bait.global_position = camera.project_position(Vector2(size.x*.94,160),8)
		var orbit_stable := true
		for frame in range(90):
			rig._process(STEP)
			orbit_stable = orbit_stable and stable(metrics)
		check(absf(rig.fight_camera_tracking.yaw)>0.0001,"real waterborne bait requests modest edge yaw")
		check(absf(rig.fight_camera_tracking.yaw)<=deg_to_rad(rig.free_lure_max_yaw_degrees)+.00001,"edge yaw remains capped at approved seven degrees")
		check(orbit_stable,"actual yaw preserves distance, optical offsets, pitch, roll and player pixel")
		# Exercise existing complete-retrieve unwind without a new reset owner.
		rig.return_fishing_follow_to_target(true)
		for frame in range(600): rig._process(STEP)
		bait.global_position = physical_start
		fishing._sync_fight_camera_tracking()
		metrics = pose_metrics()
		for id in [&"ds_left",&"ds_right",&"enter_fishing"]:
			for combined in [false,true]:
				bait.global_position = landing
				action(id,true)
				if combined: action(&"enter_fishing",true)
				var unchanged := true
				for frame in range(90):
					bait._physics_process(STEP); rig._process(STEP)
					unchanged = unchanged and stable(metrics)
				check(unchanged,"A/D/K and combined retrieve leave non-yaw pose and anchor fixed")
				action(id,false); action(&"enter_fishing",false); fishing._process(STEP)
			check(visual_rect(power.get_node("Root/PowerBarBG"))==power_rect and visual_rect(depth.get_node("Frame"))==depth_rect,"reeling does not move HUD layout")
		bait.global_position = landing
		# Use the real physical bait with combat presentation, without replacing
		# fight mechanics. A depth violation must not invoke the former dolly.
		bait.set_fight_mode(true)
		bait.global_position = camera.project_position(Vector2(size.x*.5,480*.705),8)
		var combat := pose_metrics()
		rig._process(STEP)
		check(stable(combat),"hooked vertical violation cannot zoom/pan established camera")
		check(rig._water_dolly == 0.0 and rig._water_pan == Vector2.ZERO,"production anchored dolly/pan remain zero")
		bait.set_fight_mode(false); bait.global_position = landing
		var sprite: AnimatedSprite3D = fishing.player.get_node("GroundPresentation/VisualAnchor/AnimatedSprite3D")
		var sprite_rect := Rect2()
		var body_right := -INF
		if DisplayServer.get_name() != "headless":
			# Measure the actually rendered sprite, including shader billboarding
			# and transparent atlas margins, rather than guessing a world quad.
			paused = true
			await RenderingServer.frame_post_draw
			var shown: Image = host.gameplay_viewport.get_texture().get_image()
			sprite.visible = false
			# Same engine frame: shader TIME and other actors cannot contaminate
			# the visibility difference with a moving background.
			RenderingServer.force_draw(false,0.0)
			var hidden: Image = host.gameplay_viewport.get_texture().get_image()
			var foot: Vector2 = camera.unproject_position(fishing.player.global_position)
			var count := 0
			for y in range(maxi(0,int(foot.y)-180),mini(int(size.y),int(foot.y)+10)):
				for x in range(maxi(0,int(foot.x)-100),mini(int(size.x),int(foot.x)+100)):
					if shown.get_pixel(x,y).is_equal_approx(hidden.get_pixel(x,y)): continue
					if count == 0: sprite_rect = Rect2(Vector2(x,y),Vector2.ONE)
					else: sprite_rect = sprite_rect.expand(Vector2(x,y))
					count += 1
					if y>=power_rect.position.y and y<=power_rect.end.y: body_right=maxf(body_right,x+1.0)
			check(count > 0,"rendered actor silhouette measured")
			check(is_finite(body_right) and power_rect.position.x-body_right>=4.0,"actual visible body stays clear of power bar at HUD height")
			sprite.visible = true
			RenderingServer.force_draw(false,0.0)
			paused = false
		var stance_right: float = power.fishing_stance_right_pixels()
		var former_power_x: float = 175.0+532.0*(size.x/640.0-1.0)
		measurements.append({"css":dimensions,"world":size,"camera":pose_metrics(),"sprite_frame_rect":Rect2(sprite_rect.position/size,sprite_rect.size/size),"power":Rect2(power_rect.position/size,power_rect.size/size),"depth":Rect2(depth_rect.position/size,depth_rect.size/size),"stance_right_px":stance_right,"character_gap_before":former_power_x-stance_right,"character_gap_after":power_rect.position.x-stance_right,"bar_meter_gap":depth_rect.position.x-power_rect.end.x})
		if is_finite(body_right):
			measurements[-1]["visible_body_right_at_hud_px"]=body_right
			measurements[-1]["visible_body_gap_before"]=former_power_x-body_right
			measurements[-1]["visible_body_gap_after"]=power_rect.position.x-body_right
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output_dir+"/fishing-%dx%d.png" % [dimensions.x,dimensions.y])
	var file := FileAccess.open(output_dir+"/measurements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements,"  ")); file.close()
	fixture.release(); await settle()
	print("CAMERA HUD STABILITY QA: ",checks-failures.size(),"/",checks," failures=",failures)
	Isolation.emit_result("fishing_camera_hud_stability_qa", checks - failures.size(),
		checks, failures.size(), Node.get_orphan_node_ids().size())
	quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
