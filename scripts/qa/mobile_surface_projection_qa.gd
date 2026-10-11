extends SceneTree
## Actual projection, CSS/backing-pixel input and constrained-control fixtures.
const Surface = preload("res://scripts/ui/canonical_game_surface.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","CodexMobileSurface-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for frame in range(12): await process_frame
func capture(viewport: Viewport, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://build/mobile-web/ui-v3/"+name+".png")

func check_original_sea(host: Node, camera: Camera3D, fill: Node3D) -> void:
	if DisplayServer.get_name() == "headless": return
	var was_paused := paused
	paused = true
	var sea: MeshInstance3D = host.game.get_node("World/beach/Sea")
	var data := sea.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	fill.show()
	await RenderingServer.frame_post_draw
	var extended: Image = host.gameplay_viewport.get_texture().get_image()
	fill.hide()
	await RenderingServer.frame_post_draw
	var authored: Image = host.gameplay_viewport.get_texture().get_image()
	var samples := 0
	for face in range(0,indices.size(),3):
		var center := (vertices[indices[face]]+vertices[indices[face+1]]+vertices[indices[face+2]])/3
		if center.z > -1: continue
		var world := sea.global_transform*center
		var pixel := Vector2i(camera.unproject_position(world))
		if camera.is_position_behind(world) or not Rect2i(Vector2i.ZERO,host.gameplay_viewport.size).has_point(pixel): continue
		var a := extended.get_pixelv(pixel)
		var b := authored.get_pixelv(pixel)
		check(Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length() < .002,"extension cannot occlude/retexture authored sea at triangle centroid")
		samples += 1
	check(samples > 0,"rendered continuity sampled real visible sea triangles")
	fill.show()
	paused = was_paused
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/mobile-web/ui-v3"))
	var host = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	host.isolated_playtest_save = false
	host.developer_playtest_default_enabled = false
	root.add_child(host)
	current_scene = host
	await settle()
	var camera: Camera3D = host.gameplay_viewport.get_camera_3d()
	var rig: Node = host.game.get_node("CameraRig")
	rig.set_process(false)
	var player: Node3D = host.game.get_node("Player/CharacterBody3D")
	player.set_physics_process(false)
	var actor := player.global_transform
	var pose := camera.global_transform
	var lens := camera.get_camera_projection()
	var original_point := camera.unproject_position(player.global_position)
	var original_layers: Dictionary = {}
	for layer in host.game.find_children("*","CanvasLayer",true,false):
		original_layers[layer] = layer.visible
		layer.hide()
	await capture(host.gameplay_viewport,"world-640")
	root.size = Vector2i(844,390)
	await settle()
	host._layout()
	await settle()
	check(host.gameplay_viewport.size == Vector2i(960,480),"960x480 renders a true wider world")
	var wide := camera.get_camera_projection()
	check(is_equal_approx(wide.y.y,lens.y.y),"vertical field and apparent actor pixel scale unchanged")
	check(is_equal_approx(wide.x.x,lens.x.x*640.0/960.0),"horizontal field expands rather than stretching")
	var point := camera.unproject_position(player.global_position)
	check(absf(point.y-original_point.y) < .001 and absf(point.x-original_point.x-160) < .001,"original world points retain Y and gain symmetric 160px margins")
	check(camera.global_transform.is_equal_approx(pose) and player.global_transform.is_equal_approx(actor),"camera pitch/roll/position and physical player unchanged")
	var extra_world := camera.project_position(Vector2(880,240),3)
	await capture(host.gameplay_viewport,"world-960")
	if DisplayServer.get_name() != "headless":
		var wide_image: Image = host.gameplay_viewport.get_texture().get_image()
		for sample in [Vector2i(4,4),Vector2i(240,4),Vector2i(955,4),Vector2i(4,475),Vector2i(955,475)]:
			var color := wide_image.get_pixelv(sample)
			check(color.r+color.g+color.b > .05,"wide world backing covers finite mesh edge: %s" % sample)
	var fill: Node = host.game.get_node("World/MobileLandscapeGroundExtension")
	check(fill is Node3D and fill.get_child_count() == 13 and fill.visible,"outskirts are scene-owned edge meshes")
	for child in fill.get_children():
		if str(child.name).begins_with("Inland_"): continue
		var source: MeshInstance3D = host.game.get_node("World/beach/"+str(child.name).get_slice("_",0))
		check(child is MeshInstance3D and child.mesh == source.mesh and child.material_override == source.material_override,"edge continuation reuses exact mesh UVs, depth and material")
	for offset in [Vector3.ZERO,Vector3(.4,0,-.4),Vector3(-.4,0,.4)]:
		camera.global_transform = pose
		camera.global_position += offset
		var sea: MeshInstance3D = host.game.get_node("World/beach/Sea")
		camera.look_at(sea.global_transform*sea.get_aabb().get_center())
		await check_original_sea(host,camera,fill)
		await capture(host.gameplay_viewport,"sea-continuity-%d" % checks)
	camera.global_transform = pose
	rig.fishing_player_anchor = Vector2(.22,.86)
	var old_anchor: Vector2 = rig.fishing_player_anchor
	root.size = Vector2i(390,844)
	await settle()
	host._layout()
	await settle()
	check(host.gameplay_viewport.size == Vector2i(640,480),"portrait restores canonical 4:3")
	check(camera.unproject_position(extra_world).x > 640,"additional landscape world genuinely lies outside portrait frame")
	check(rig.fishing_player_anchor.is_equal_approx(Vector2(.5+(old_anchor.x-.5)*1.5,old_anchor.y)),"cached fishing anchor remaps with projection, without camera reset")
	check(not fill.visible,"landscape outskirts extension does not change portrait")
	for layer in original_layers: layer.visible = original_layers[layer]
	# Emulate the iPhone's 3x backing canvas using the actual Window transform.
	root.size = Vector2i(1170,2532)
	Surface.configure_css_window(root,Vector2i(390,844))
	await settle()
	host._layout()
	await settle()
	check(host.size.is_equal_approx(Vector2(390,844)),"3x backing canvas retains CSS-sized shell")
	var backing_scale := root.get_final_transform().x.length()
	check(is_equal_approx(backing_scale,3),"fixture actually exercises 3x backing scaling")
	var hit: Rect2 = host.controls.buttons.X
	check(hit.size.x*backing_scale/3 >= 44,"X renders at least 44 CSS pixels, not 44 backing pixels")
	check(host.controls.stick_zone.size.x*backing_scale/3 >= 100,"stick retains at least 100 CSS pixels")
	var events: Array[bool] = []
	host.controls.action_requested.connect(func(event): events.append(event.pressed))
	for pressed in [true,false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 82
		touch.position = root.get_final_transform()*host.controls.get_global_transform_with_canvas()*hit.get_center()
		touch.pressed = pressed
		Input.parse_input_event(touch)
		await settle()
	check(events == [true,false],"3x actual ScreenTouch transform produces one balanced X action")
	check(not Input.is_action_pressed("world_card_challenge"),"3x touch release clears gameplay action")
	for dimensions in [Vector2i(320,568),Vector2i(375,667)]:
		root.size = dimensions
		Surface.configure_css_window(root,dimensions)
		await settle()
		host._layout()
		await settle()
		check(host.shell.regions.fallback == "scroll_controls","short portrait explicitly scrolls controls")
		check(is_equal_approx(host.gameplay_window.size.x,dimensions.x-12),"short portrait keeps full game width")
		# Scroll the empty center seam through the real GUI event path, not only
		# the scroll_vertical property used to position the following captures.
		host.controls_scroll.scroll_vertical = 0
		await settle()
		var seam: Vector2 = host.controls_scroll.global_position+Vector2(dimensions.x*.5,90)
		var down := InputEventScreenTouch.new()
		down.index = 83
		down.position = seam
		down.pressed = true
		Input.parse_input_event(down)
		await settle()
		for step in range(1,5):
			var drag := InputEventScreenDrag.new()
			drag.index = 83
			drag.position = seam-Vector2(0,step*12)
			drag.relative = Vector2(0,-12)
			Input.parse_input_event(drag)
			await settle()
		down.position = seam-Vector2(0,48)
		down.pressed = false
		Input.parse_input_event(down)
		await settle()
		check(host.controls_scroll.scroll_vertical > 0,"short portrait scroll is operable by real touch drag")
		host.controls_scroll.scroll_vertical = 42
		await settle()
		for id in ["X","Y","A","B"]:
			var target: Rect2 = host.controls.buttons[id]
			target.position += host.controls.global_position
			check(host.controls_scroll.get_global_rect().encloses(target),"all face controls can be shown together in short portrait: "+id)
			check(not host._control_scroll_seam_clear(target.get_center()),"scroll seam cannot steal face input: "+id)
		await capture(root,"controls-scroll-%dx%d" % [dimensions.x,dimensions.y])
		host.controls_scroll.scroll_vertical = 1000
		await settle()
		for id in ["Settings","Equipment"]: check(host.safe_rect.encloses(host.shell.utility[id].get_global_rect()),"short portrait footer reachable: "+id)
		await capture(root,"controls-footer-%dx%d" % [dimensions.x,dimensions.y])
	current_scene = null
	host.queue_free()
	await settle()
	var services := root.get_node_or_null("FishingSessionServices")
	if services != null: services.queue_free()
	await settle()
	print("MOBILE SURFACE PROJECTION QA: ",checks-failures.size(),"/",checks," ",failures)
	quit(0 if failures.is_empty() else 1)
