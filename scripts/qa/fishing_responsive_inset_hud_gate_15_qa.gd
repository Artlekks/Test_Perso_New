extends SceneTree
## Gate 15: containment geometry is defined by rendered bar, depth frame,
## and animated character inset, not by viewport-relative percentage guesses.
## Requires an actual Godot run; no rendered screenshot acceptance is claimed.
const Rig = preload("res://scripts/camera_rig.gd")

var passed: int = 0
var failed: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(description)
		push_error(description)

func run() -> void:
	await process_frame
	for size in [Vector2i(320,240),Vector2i(640,480),Vector2i(960,480),Vector2i(960,900),Vector2i(480,960)]:
		await test_hud_geometry_and_pan(size)
	test_narrow_hud_corridor()
	print("FISHING RESPONSIVE INSET HUD GATE 15: %d/%d passed; failures=%s" % [
		passed,passed+failed.size(),failed])
	quit(0 if failed.is_empty() else 1)

func test_hud_geometry_and_pan(size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	root.add_child(viewport)
	var player := Node3D.new()
	player.position = Vector3(100,0,100) # Explicitly offscreen.
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
	# Reference screenshot's 320x240 logical art dimensions and offsets.
	# A second case moves the HUD as wide/tall hosts do, rather than
	# relying on identical normalized viewport coordinates.
	var hud_scale: float = 1.0 if size.x >= 640 else 0.65
	var bar_width: float = 173.0*hud_scale
	var base_left: float = (float(size.x)-320.0*hud_scale)*0.5
	var bottom: float = float(size.y)-37.0*hud_scale
	var bar := ColorRect.new()
	bar.position = Vector2(base_left+86.0*hud_scale,bottom)
	bar.size = Vector2(bar_width,24.0*hud_scale)
	viewport.add_child(bar)
	var meter := ColorRect.new()
	meter.position = Vector2(base_left+269.0*hud_scale,float(size.y)-66.0*hud_scale)
	meter.size = Vector2(24.0,55.0)*hud_scale
	viewport.add_child(meter)
	var inset := Control.new()
	inset.position = Vector2(base_left+46.0*hud_scale,float(size.y)-65.0*hud_scale)
	inset.size = Vector2(40.0,50.0)*hud_scale
	viewport.add_child(inset)
	var grid := ColorRect.new()
	grid.name = "Grid"
	grid.size = Vector2(28.0,50.0)*hud_scale
	inset.add_child(grid)
	rig._inset_view = inset
	rig.fishing_hud_geometry.append(bar)
	rig.fishing_hud_geometry.append(meter)
	await process_frame

	var hard: Rect2 = rig._inset_follow_region_for_camera(camera)
	var rect: Rect2 = Rect2(hard.position*Vector2(size),hard.size*Vector2(size))
	var unit: float = bar.size.x
	check(is_equal_approx(rect.position.x-grid.global_position.x-grid.size.x,
		unit*rig.inset_left_gap_bar_width),"left anchored to inset artwork %s" % size)
	check(is_equal_approx(meter.position.x-rect.end.x,
		unit*rig.inset_right_gap_bar_width),"right anchored to depth frame %s" % size)
	check(is_equal_approx(bar.position.y-rect.end.y,
		unit*rig.inset_bottom_gap_bar_width),"bottom anchored to power bar %s" % size)
	check(is_equal_approx(rect.size.y,unit*rig.inset_height_bar_width),"top relative to HUD band %s" % size)

	# Move every gauge in the same frame to mimic responsive layout changes.
	var previous := rect
	var translate := Vector2(7.0,-6.0)
	bar.position += translate
	meter.position += translate
	inset.position += translate
	var revised: Rect2 = rig._inset_follow_region_for_camera(camera)
	var pixel_revised: Rect2 = Rect2(revised.position*Vector2(size),revised.size*Vector2(size))
	check(pixel_revised.position.distance_to(previous.position+translate)<0.01,
		"red frame follows resized/repositioned HUD %s" % size)
	check(pixel_revised.size.distance_to(previous.size)<0.01,
		"responsive move preserves red box size %s" % size)

	# An animated rod can extend beyond the static inset grid. Its actual
	# frame rectangle must then override the nominal left margin.
	var rod := AnimatedSprite2D.new()
	rod.name = "Character"
	var frames := SpriteFrames.new()
	var artwork := Image.create(20,20,false,Image.FORMAT_RGBA8)
	artwork.fill(Color.WHITE)
	frames.add_frame("default",ImageTexture.create_from_image(artwork))
	rod.sprite_frames = frames
	rod.position = Vector2(grid.size.x+unit*rig.inset_left_gap_bar_width+6.0,15.0)
	inset.add_child(rod)
	var rod_region: Rect2 = rig._inset_follow_region_for_camera(camera)
	check(rod_region.position.x*float(size.x)>pixel_revised.position.x+5.0,
		"visible rod art extends left containment border %s" % size)
	rod.queue_free()
	await process_frame
	revised = rig._inset_follow_region_for_camera(camera)

	# At all eight edges/corners, camera translates the *rendered* water
	# contact point into the new live HUD corridor in the very same frame.
	rig._fight_base_valid = true
	rig._fight_base_camera_transform = camera.transform
	for uv in [Vector2(-.04,.62),Vector2(1.04,.65),Vector2(.5,.02),Vector2(.52,.97),
		Vector2(-.04,.02),Vector2(1.04,.02),Vector2(-.04,.97),Vector2(1.04,.97)]:
		var world: Vector3 = camera.project_position(uv*Vector2(size),20.0)
		var original: Vector3 = world
		var basis_before: Basis = camera.global_basis
		rig._pan_inset_camera_to_lure(camera,world,Vector2(size),1.0/60.0)
		var corrected := camera.unproject_position(world)/Vector2(size)
		check(revised.grow(0.0001).has_point(corrected),"dynamic HUD red frame %s %s => %s" % [size,uv,corrected])
		check(camera.global_basis.is_equal_approx(basis_before),"camera pan does not turn %s %s" % [size,uv])
		check(world.is_equal_approx(original),"physical bait unchanged %s %s" % [size,uv])
	check(rig.inset_containment_failures==0,"no inset safety failures %s" % size)
	viewport.queue_free()
	await process_frame

func test_narrow_hud_corridor() -> void:
	# When the HUD tightens, reduce whitespace but never cross the gauges.
	var area: Rect2 = Rig.inset_region_from_hud_pixels(
		Vector2(320,240),Rect2(80,190,170,20),Rect2(205,162,24,55),
		Rect2(100,165,80,45),0.16,0.265,0.23,0.185)
	check(area.has_area(),"narrow non-overlapping HUD still has a valid bait band")
	check(area.position.x>=180 and area.end.x<=205,"narrow margins shrink within HUD clearance")
	var collision: Rect2 = Rig.inset_region_from_hud_pixels(
		Vector2(320,240),Rect2(80,190,170,20),Rect2(183,162,24,55),
		Rect2(100,165,80,45),0.16,0.265,0.23,0.185)
	check(not collision.has_area(),"fully colliding HUD cannot silently claim valid containment")
