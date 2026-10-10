extends Node
## Renderable/Web-exportable player journey using real cast/session/bait ownership.
var checks := 0
var failures: Array[String] = []
var host: Node
var mobile := false
var capture := false
var passive: Node
func _ready() -> void:
	mobile = OS.has_feature("web") or OS.get_cmdline_user_args().has("--mobile")
	capture = OS.get_cmdline_user_args().has("--rendered") or OS.has_feature("web")
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","SafeRectangleQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func until(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec()+(180000 if OS.has_feature("web") else 30000)
	var phase_last := -1
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		if OS.has_feature("web") and is_instance_valid(host) and is_instance_valid(host.game):
			var f: Node = host.game.get_node("Game/Fishing")
			# IAB throttles rendering while tool calls run. This fixture owns its
			# orchestration wait budget; production Passive timeout is unchanged.
			if passive.state == passive.State.STARTING: passive._start_time = Time.get_ticks_msec()
			if f.phase != phase_last:
				phase_last = f.phase
				print("JOURNEY PHASE ",f.phase," passive=",passive.state," power=",f.power.value," paused=",get_tree().paused)
		await get_tree().process_frame
	var ok: bool = predicate.call()
	check(ok,label)
	return ok
func water_endpoint(camera: Camera3D, pixel: Vector2, water_y: float) -> Vector3:
	var origin := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	var distance := (water_y-origin.y)/ray.y
	check(distance>0.0,"fixture endpoint is on the forward water plane")
	return origin+ray*distance
func capture_stage(camera: Camera3D, label: String) -> void:
	await get_tree().process_frame
	if capture and not OS.has_feature("web"):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/mobile-web/bof4-v2/captures")
		get_viewport().get_texture().get_image().save_png("res://build/mobile-web/bof4-v2/captures/%s-%s.png" % ["mobile" if mobile else "desktop",label])
func travel_journey(fishing: Node, rig: Node3D, camera: Camera3D, bait: Node3D, water_y: float) -> void:
	# A deterministic airborne pan seeds a long-cast handoff. The real cast/session
	# above remains the owner; only fixture camera/physical endpoints are injected.
	var anchor: Vector2 = rig.fishing_player_anchor
	rig.reset_fishing_follow()
	var pose := camera.get_camera_transform()
	var polygon: Array[Vector2] = [Vector2(-6,-6),Vector2(6,-6),Vector2(6,6),Vector2(-6,6)]
	# In the authored cast rail Ryu returns from the bottom of the frame.
	# Seeding him above the anchor reverses that physical travel direction.
	var entry_region := Rect2(anchor+Vector2(0,.08)-Vector2(.001,.001),Vector2(.002,.002))
	polygon = preload("res://scripts/fishing_camera_framing.gd").screen_constraints(polygon,pose,camera.get_camera_projection(),rig.target.global_position,entry_region)
	check(not polygon.is_empty(),"authored long-cast entry can frame the actual player before anchor")
	if polygon.is_empty(): return
	var offset: Vector2 = preload("res://scripts/fishing_camera_framing.gd").nearest(polygon)
	rig.global_position += Vector3(offset.x,0,offset.y)
	bait.global_position = water_endpoint(camera,Vector2(320,230),water_y)
	fishing._sync_fight_camera_tracking()
	rig._process(1.0/60)
	check(rig.fishing_camera_state == rig.FishingCameraPresentationState.TRAVEL,"long-cast water handoff begins TRAVEL when player is not anchored")
	var orientation := camera.global_basis
	await capture_stage(camera,"travel")
	for step in range(30):
		if rig.fishing_camera_state == rig.FishingCameraPresentationState.ANCHORED: break
		bait.global_position = water_endpoint(camera,Vector2(320,(rig.travel_safe_frame.end.y+.02)*480),water_y)
		var physical := bait.global_transform
		rig._process(1.0/60)
		check(camera.global_basis.is_equal_approx(orientation),"rendered downward TRAVEL never yaws/pitches/rolls")
		check(bait.global_transform == physical,"TRAVEL translation leaves physical target untouched")
		if step%5 == 0: print("TRAVEL STEP ",step," pan=",rig._water_pan," player=",camera.unproject_position(rig.target.global_position)," bait=",camera.unproject_position(bait.global_position)," state=",rig.fishing_camera_state)
		await get_tree().process_frame
	check(rig.fishing_camera_state == rig.FishingCameraPresentationState.ANCHORED,"actual rendered player enters authored region and latches ANCHORED")
	check(camera.global_basis.is_equal_approx(orientation),"rendered stage transition preserves orientation")
	var transition_target := bait.global_transform
	rig._process(1.0/60)
	check(rig.fight_camera_tracking.inside(camera.unproject_position(bait.global_position),rig.fishing_safe_region_pixels(),.5),"new anchored frame contains the same physical target after handoff")
	check(bait.global_transform == transition_target,"handoff never substitutes or moves physical target")
	check(camera.global_basis.is_equal_approx(orientation),"vertical handoff clearance does not rotate")
	check(rig.fight_camera_tracking.inside(camera.unproject_position(rig.target.global_position)/Vector2(640,480),rig.player_anchor_region(),.001),"handoff vertical clearance preserves actual player anchor")
	await capture_stage(camera,"anchored")
	bait.global_position = water_endpoint(camera,Vector2(320,230),water_y)
	rig._process(1.0/60)
	var held := camera.global_transform
	for frame in range(120): rig._process(1.0/60)
	check(camera.global_transform.is_equal_approx(held) and rig.fishing_camera_state == rig.FishingCameraPresentationState.ANCHORED,"rendered anchored safe state holds without stage chatter")
 
func run() -> void:
	var tree := get_tree()
	var path := "res://actors/mobile/MobilePortraitHarness.tscn" if mobile else "res://actors/desktop/DesktopCompanion.tscn"
	host = load(path).instantiate()
	if mobile: host.isolated_playtest_save = false
	add_child(host)
	if mobile:
		preload("res://scripts/qa/mobile_qa_canvas.gd").prepare(tree)
		if DisplayServer.get_name() != "headless" and not OS.has_feature("web"): tree.root.size = Vector2i(390,844)
	await tree.create_timer(1.0).timeout
	var game: Node = host.game
	var fishing: Node = game.get_node("Game/Fishing")
	var rig: Node3D = fishing.camera_rig
	var camera: Camera3D = rig.get_node("Camera3D")
	passive = host.passive if not mobile else preload("res://scripts/gameplay/passive_fishing_controller.gd").new()
	if mobile:
		passive.host = host
		add_child(passive)
	passive.require_focus_confirmation = false
	passive.focus_seconds = 9999
	var ids := [game.get_instance_id(),tree.root.get_node("FishingSessionServices").get_instance_id()]
	for cycle in range(2 if OS.has_feature("web") else 3):
		if mobile and cycle == 1 and DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
			tree.root.size = Vector2i(844,390)
			await tree.process_frame
		check(passive.begin(),"real Passive entry accepted cycle %d" % cycle)
		if not await until(func(): return passive.state == passive.State.FOCUS,"real cast lands in water cycle %d" % cycle): break
		var bait: Node3D = fishing.caster.active_bait
		var water_y: float = bait.get_water_surface_y()
		check(is_instance_valid(bait) and rig._fight_tracking_target == bait,"physical bait owns water tracking")
		check(rig.fishing_camera_state == rig.FishingCameraPresentationState.ANCHORED,"real cast enters anchored state when the actual player is already at the authored anchor")
		# First exercise real autonomous/current physics before deterministic edge injection.
		for frame in range(90):
			await tree.process_frame
			check(rig.fight_camera_tracking.inside(camera.unproject_position(bait.global_position),rig.fishing_safe_region_pixels(),0.5),"real current/Passive frame contained")
		# Deterministic physical endpoints make all vertical/corner regressions reproducible.
		# Only fixture simulation is frozen; the production camera remains the system under test.
		bait.set_physics_process(false)
		fishing.caster.set_physics_process(false)
		rig.set_process(false)
		if cycle == 0: await travel_journey(fishing,rig,camera,bait,water_y)
		var points := [Vector2(.12,.45),Vector2(.88,.45),Vector2(.5,.215),Vector2(.5,.705),Vector2(.12,.215),Vector2(.88,.215),Vector2(.12,.705),Vector2(.88,.705)]
		for index in range(points.size()):
			rig.reset_fishing_follow()
			# Use a real water-plane endpoint rather than an arbitrary aerial point.
			var endpoint_pixel: Vector2 = points[index]*Vector2(640,480)
			var ray_origin := camera.project_ray_origin(endpoint_pixel)
			var ray := camera.project_ray_normal(endpoint_pixel)
			var ray_distance := (water_y-ray_origin.y)/ray.y
			check(ray_distance>0.0,"edge fixture resolves a forward physical water endpoint")
			var world := ray_origin+ray*ray_distance
			bait.global_position = camera.project_position(Vector2(320,220),2.0)
			fishing._sync_fight_camera_tracking()
			rig._process(1.0/60.0)
			print("AUTHORED PLAYER ANCHOR ",rig.fishing_player_anchor," state=",rig.fishing_camera_state)
			bait.global_position = world
			fishing._sync_fight_camera_tracking()
			for frame in range(180):
				rig._process(1.0/60.0)
				check(bait.global_position.is_equal_approx(world),"camera never moves physical bait")
				check(camera.global_basis.is_equal_approx(Basis(Vector3.UP,rig.fight_camera_tracking.yaw)*(rig.global_transform*rig._fight_base_camera_transform).basis),"no dynamic pitch/roll on any edge")
			check(not camera.is_position_behind(world) and rig.fight_camera_tracking.inside(camera.unproject_position(world),rig.fishing_safe_region_pixels(),0.5),"edge/corner %d contained after smooth correction" % index)
			check(rig.fight_camera_tracking.inside(camera.unproject_position(rig.target.global_position)/Vector2(640,480),rig.player_anchor_region(),.001),"player stays in authored anchor")
			var held := camera.transform
			var offsets := Vector2(camera.h_offset,camera.v_offset)
			bait.global_position = camera.project_position(Vector2(320,220),2.0)
			for frame in range(12): rig._process(1.0/60.0)
			check(camera.transform.is_equal_approx(held) and Vector2(camera.h_offset,camera.v_offset).is_equal_approx(offsets),"central region holds all camera correction axes")
			check(camera.unproject_position(bait.global_position).y<336.5,"bait center above bottom HUD")
			check(absf(rig.fight_camera_tracking.yaw)<=deg_to_rad(55.0),"yaw cap unchanged")
			check(absf(rig._water_dolly)<=rig.anchored_dolly_limit+.00001,"vertical sightline translation remains bounded")
			if capture and cycle == 0:
				bait.global_position = world
				rig._process(1.0/60.0)
				await tree.process_frame
				if not OS.has_feature("web"):
					await RenderingServer.frame_post_draw
					var rendered := camera.get_viewport().get_texture().get_image()
					var pixel := rendered.get_pixel(115,106)
					check(pixel.r>.9 and pixel.g>.9 and pixel.b<.1,"rendered yellow guide matches 18/22 percent corner on canonical surface")
					DirAccess.make_dir_recursive_absolute("res://build/mobile-web/safe-rectangle/captures")
					get_viewport().get_texture().get_image().save_png("res://build/mobile-web/safe-rectangle/captures/%s-%d.png" % ["mobile" if mobile else "desktop",index])
			print("SAFE EDGE ",index," world=",world," screen=",camera.unproject_position(world)," region=",rig.fishing_safe_region_pixels()," pan=",rig._water_pan," dolly=",rig._water_dolly," player=",camera.unproject_position(rig.target.global_position)," feasible=",rig.framing_constraints_feasible)
		# Exercise the authored physical depth envelope, not just surface sprites.
		for depth_ratio in [0.0,0.5,1.0]:
			rig.reset_fishing_follow()
			var submerged := water_endpoint(camera,Vector2(320,216),water_y)
			submerged.y = lerpf(water_y,fishing.game_mode.active_fish_zone.get_bottom_y(),depth_ratio)
			bait.global_position = water_endpoint(camera,Vector2(320,216),water_y)
			fishing._sync_fight_camera_tracking(); rig._process(1.0/60)
			bait.global_position = submerged
			var physical := bait.global_transform
			for frame in range(180): rig._process(1.0/60)
			var visible_pose := camera.global_transform
			check(rig.fight_camera_tracking.inside(camera.unproject_position(submerged),rig.fishing_safe_region_pixels(),.5),"authored depth ratio %s remains in usable frame" % depth_ratio)
			check(bait.global_transform == physical,"submerged framing cannot move mechanics target")
			rig.reset_fishing_follow()
			bait.global_position = water_endpoint(camera,Vector2(320,216),water_y)
			fishing._sync_fight_camera_tracking(); rig._process(1.0/60)
			bait.global_position = submerged; bait.visible = false
			for frame in range(180): rig._process(1.0/60)
			check(camera.global_transform.is_equal_approx(visible_pose),"authored submerged depth has identical hidden/visible camera composition")
			bait.visible = true
		check(rig.safe_containment_failures == 0,"no containment firewall failures")
		check(rig.fishing_rotation_failures == 0 and rig.fishing_anchor_failures == 0 and rig.fishing_hud_failures == 0,"rotation/player/live-HUD firewalls remain clean")
		if OS.get_cmdline_user_args().has("--prove-firewall"):
			rig.check_fishing_safe_invariant(Vector2(320,600),rig.fishing_correction_grace_seconds+.01)
			print("EXPECTED FIREWALL FAILURE COUNT: ",rig.safe_containment_failures)
			tree.quit(1 if rig.safe_containment_failures == 1 else 2)
			return
		check(rig._safe_overlay.rig == rig and rig._safe_overlay.get_parent().layer == 4,"yellow guide reads real rig below modal layers")
		passive.cancel("fixture retrieve",false)
		fishing._cancel_water_cast_to_aim()
		rig.set_process(true)
		fishing.caster.set_physics_process(true)
		if not await until(func(): return fishing.phase == fishing.Phase.AIM,"retrieve returns to AIM"): break
		if not await until(func(): return not rig.fishing_follow_returning,"original exponential retrieve return completes"): break
		check([game.get_instance_id(),tree.root.get_node("FishingSessionServices").get_instance_id()] == ids,"same scene/session through repeated cast/retrieve")
	if OS.has_feature("web"):
		# Leave a normal physical cast rendered for browser acceptance, not an injected off-world endpoint.
		check(passive.begin(),"Web acceptance cast begins")
		if await until(func(): return passive.state == passive.State.FOCUS,"Web acceptance cast reaches water"):
			print("WEB SAFE RECTANGLE ACCEPTANCE READY")
		print("SAFE RECTANGLE JOURNEY QA: ",checks-failures.size(),"/",checks," failures=",failures)
		return
	print("SAFE RECTANGLE JOURNEY QA: ",checks-failures.size(),"/",checks," failures=",failures)
	host.queue_free()
	if mobile: passive.queue_free()
	var session := tree.root.get_node_or_null("FishingSessionServices")
	if session != null: session.queue_free()
	await tree.process_frame
	tree.quit(0 if failures.is_empty() else 1)
