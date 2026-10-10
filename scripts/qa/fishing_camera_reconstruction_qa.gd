extends SceneTree
const Rig = preload("res://scripts/camera_rig.gd")
var checks := 0
var failures: Array[String] = []
var viewport: SubViewport
var rig: Node3D
var player: Node3D
var bait: Node3D
var camera: Camera3D
var neutral: Transform3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func tick(count := 1) -> void:
	for frame in range(count): rig._process(1.0/60)
func begin() -> void:
	rig.reset_fishing_follow()
	camera.transform = neutral
	bait.global_position = camera.project_position(Vector2(320,220),8)
	rig.set_fishing_fight_tracking(true,bait)
	check(rig.fishing_camera_state == rig.FishingCameraPresentationState.TRAVEL,"water entry explicitly begins TRAVEL")
	tick()
	check(rig.fishing_camera_state == rig.FishingCameraPresentationState.ANCHORED,"actual player projection latches authored anchor without timer")
func run() -> void:
	viewport = SubViewport.new(); viewport.size = Vector2i(640,480); root.add_child(viewport)
	player = Node3D.new(); viewport.add_child(player)
	bait = Node3D.new(); viewport.add_child(bait)
	rig = Rig.new(); camera = Camera3D.new(); camera.name = "Camera3D"; rig.add_child(camera)
	rig.target = player; viewport.add_child(rig); rig.set_process(false); camera.current = true
	camera.position = Vector3(0,4,6); camera.look_at(Vector3(0,-2,0)); neutral = camera.transform
	await process_frame
	begin()
	for cycle in range(4):
		for x in [0.12,0.88]:
			begin()
			bait.global_position = camera.project_position(Vector2(x*640,220),8)
			var physical := bait.global_transform
			var anchor := camera.unproject_position(player.global_position)
			var pitch := camera.global_basis.z.y
			var roll := camera.global_basis.x.y
			var before := camera.global_transform
			tick()
			check(not camera.global_transform.is_equal_approx(before),"horizontal edge requests yaw")
			check(rig._water_pan == Vector2.ZERO,"anchored horizontal edge never translates")
			tick(180)
			check(rig.fight_camera_tracking.inside(camera.unproject_position(bait.global_position),rig.fishing_safe_region_pixels(),0.5),"horizontal yaw restores safe boundary")
			check(camera.unproject_position(player.global_position).distance_to(anchor)<0.01,"player pivot remains at exact screen anchor during yaw")
			check(absf(camera.global_basis.z.y-pitch)<0.00001 and absf(camera.global_basis.x.y-roll)<0.00001,"pitch and roll unchanged")
			check(bait.global_transform == physical,"physical bait unchanged")
			var pose := camera.global_transform
			bait.global_position = camera.project_position(Vector2(320,220),8)
			tick(600)
			check(camera.global_transform.is_equal_approx(pose),"long current/center drift holds instead of recentering")
			rig.return_fishing_follow_to_target(true)
			check(camera.global_transform.is_equal_approx(pose),"retrieve starts without snapping")
			tick(600)
			check(camera.transform.is_equal_approx(neutral) and not rig.fishing_follow_returning,"same exponential return restores exact post-aim pose")
	# Small vertical violations are solved by ground-plane pan within the anchor.
	for y in [0.215,0.705]:
		begin()
		bait.global_position = camera.project_position(Vector2(320,y*480),8)
		var physical := bait.global_transform
		var basis := camera.global_basis
		var anchor := camera.unproject_position(player.global_position)
		tick(30)
		check(rig.framing_constraints_feasible,"near-edge vertical constraints are jointly feasible")
		check(camera.global_basis.is_equal_approx(basis),"vertical containment never changes any orientation axis")
		check(rig.fight_camera_tracking.inside(camera.unproject_position(bait.global_position),rig.fishing_safe_region_pixels(),0.5),"vertical pan keeps bait above HUD/below top")
		check(rig.fight_camera_tracking.inside(camera.unproject_position(player.global_position)/Vector2(640,480),rig.player_anchor_region(),0.001),"bounded pan preserves player anchor tolerance")
		check(bait.global_transform == physical,"vertical pan cannot alter physics")
		check(camera.unproject_position(player.global_position).distance_to(anchor)<0.01,"sightline vertical correction preserves the exact player anchor pixel")
		check(absf(rig._water_dolly)<=rig.anchored_dolly_limit+.00001,"sightline correction remains within its explicit bound")
		rig.return_fishing_follow_to_target(true); tick(600)
		check(camera.transform.is_equal_approx(neutral),"pan uses approved retrieve response")
	# Travel starts with an airborne displacement and retains it until an edge.
	rig.reset_fishing_follow(); camera.transform = neutral
	rig.global_position = Vector3(0,0,-2)
	bait.global_position = camera.project_position(Vector2(320,220),8)
	rig.set_fishing_fight_tracking(true,bait)
	var orientation := camera.global_basis
	tick(30)
	check(rig.fishing_camera_state == rig.FishingCameraPresentationState.TRAVEL,"off-anchor player holds TRAVEL despite elapsed time")
	var pan: Vector2 = rig._water_pan
	bait.global_position = camera.project_position(Vector2(320,(rig.travel_safe_frame.end.y+.01)*480),8)
	tick()
	check(rig._water_pan != pan and camera.global_basis.is_equal_approx(orientation),"travel vertical edge pans without yaw/pitch/roll")
	check(absf(rig._water_pan.x)<=rig.travel_translation_limit and absf(rig._water_pan.y)<=rig.travel_translation_limit,"travel pan bounded")
	for movement in range(30):
		if rig.fishing_camera_state == rig.FishingCameraPresentationState.ANCHORED: break
		bait.global_position = camera.project_position(Vector2(320,(rig.travel_safe_frame.end.y+.01)*480),8)
		tick()
	check(rig.fishing_camera_state == rig.FishingCameraPresentationState.ANCHORED,"successive downward travel brings real player into authored anchor and latches")
	check(camera.global_basis.is_equal_approx(orientation),"TRAVEL to ANCHORED transition has no rotation")
	var latched := camera.global_transform
	bait.global_position = camera.project_position(Vector2(320,220),8)
	tick(600)
	check(rig.fishing_camera_state == rig.FishingCameraPresentationState.ANCHORED and camera.global_transform.is_equal_approx(latched),"anchor latch never chatters back to travel")
	# Explicit incompatible physical state: preserve player and fail loudly.
	begin(); rig.fishing_correction_grace_seconds = .1
	bait.global_position = camera.project_position(Vector2(320,1000),8)
	tick(12)
	check(not rig.framing_constraints_feasible and rig.safe_containment_failures == 1,"infeasible constraints are reported, never hidden by pitch")
	check(rig.fishing_rotation_failures == 0 and rig.fishing_anchor_failures == 0,"rotation/player firewalls stay clean including impossible target")
	var hud := Control.new()
	hud.position = Vector2(300,230); hud.size = Vector2(40,20); viewport.add_child(hud)
	rig.fishing_hud_geometry.clear(); rig.fishing_hud_geometry.append(hud)
	rig.check_fishing_safe_invariant(Vector2(320,240),0.0)
	check(rig.fishing_hud_failures == 1,"live HUD overlap fails immediately without correction-delay grace")
	check(rig.fishing_hud_regions_pixels()[0] == hud.get_global_rect(),"HUD firewall uses actual gameplay-viewport geometry")
	rig.check_fishing_safe_invariant(Vector2(320,220),0.0)
	check(not rig._hud_failure_reported,"HUD diagnostic releases when target clears the actual panel")
	var single: Array[Vector2] = [Vector2(2,3),Vector2(2,3),Vector2(2,3)]
	check(preload("res://scripts/fishing_camera_framing.gd").nearest(single) == Vector2(2,3),"degenerate feasible polygon cannot falsely accept an outside translation")
	viewport.free()
	print("FISHING RECONSTRUCTION QA: ",checks-failures.size(),"/",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
