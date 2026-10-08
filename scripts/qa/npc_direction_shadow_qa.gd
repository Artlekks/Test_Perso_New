extends SceneTree
const CATALOG = preload("res://data/npc/catalog/npc_catalog.tres")
const Direction = preload("res://scripts/world/view_relative_direction.gd")
const Families = preload("res://scripts/world/world_shadow_families.gd")
var checks := 0
var failures: Array[String] = []
var rendered := false

func _initialize() -> void:
	var isolated := "CodexDirectionShadowQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	rendered = OS.get_cmdline_user_args().has("--rendered")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func settle() -> void:
	for frame in range(3): await process_frame

func run() -> void:
	var coverage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/npc/directional_coverage_v1.json"))
	check(coverage.size() == 36, "every catalogue entry audited")
	var rod_profile: NPCVisualProfile = CATALOG.get_entry(&"placeholder_14bf342a").profile
	check(rod_profile.animation_feet_from_left_px.pose_001 == 19.5 and rod_profile.animation_feet_from_bottom_px.pose_001 == 3, "alternate angler view anchors body feet, not low dangling lure")
	var fixture := Node3D.new()
	root.add_child(fixture)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20
	fixture.add_child(camera)
	camera.make_current()
	var actors: Array[CatalogueNPCActor] = []
	for entry in CATALOG.entries:
		var actor := entry.scene.instantiate() as CatalogueNPCActor
		fixture.add_child(actor)
		actor.position = Vector3((actors.size() % 6 - 2.5) * 2, 0, (floori(actors.size()/6.0) - 2.5) * 2)
		actors.append(actor)
		check(actor.visual_profile.shadow_family_resource != null, "clickable shared family " + String(entry.id))
		var p: GroundPresentation = actor.get_node("GroundPresentation")
		var sprite := p.sprite as AnimatedSprite3D
		var original := actor.global_transform
		var seen := {}
		for turn in range(8):
			camera.position = Vector3(sin(turn*PI/4)*12, 8, cos(turn*PI/4)*12)
			camera.look_at(Vector3.ZERO)
			await settle()
			check(Direction.sector(Vector3.BACK,camera.global_basis) == posmod(-turn,8), "independent yaw sector %s/%d" % [entry.id,turn])
			if not p.directional_pose.is_empty():
				var source: Dictionary = coverage[String(entry.id)].get("idle_map", {})
				if source.is_empty(): source = p._directions
				var requested := posmod(-turn,8)
				# Independent nearest-angle oracle, with explicit front-side ties.
				var best := ""
				var best_distance := 9
				for index in range(8):
					var d: String = Direction.DIRECTIONS[index]
					if not source.has(d): continue
					var separation := absi(index-requested)
					var distance := mini(separation,8-separation)
					if distance < best_distance or (distance == best_distance and requested in [2,6] and index in [0,1,7]):
						best=d
						best_distance=distance
				check(not best.is_empty() and sprite.animation == StringName(source[best].animation) and sprite.flip_h == source[best].get("flip_h",false), "authored view/mirror resolves %s/%d" % [entry.id,turn])
			seen[String(sprite.animation)+str(sprite.flip_h)] = true
			check(actor.global_transform.is_equal_approx(original), "view never moves actor")
			check(p.shadow.global_basis.is_equal_approx(Basis.IDENTITY) and p.shadow.global_position.is_equal_approx(actor.global_position+Vector3(0,p.shadow.ground_offset,0)), "shadow world-stable at every 45 degrees")
		check(seen.size() == 1 if coverage[String(entry.id)].one_view else seen.size() > 1, "static only for genuinely one-view sheet " + String(entry.id))
		if rendered:
			camera.position = actor.position+Vector3(0,2,3)
			camera.look_at(actor.position+Vector3(0,0.3,0))
			camera.size = 1.8
			await settle()
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://build/direction-shadow-captures")
			root.get_texture().get_image().save_png("res://build/direction-shadow-captures/"+String(entry.id)+".png")
			camera.size=20
	# The former four-diagonal bug is independent of the expanded Captain idle set.
	var diagonals := {"SE":{"animation":"front_r"},"SW":{"animation":"front_l"},"NE":{"animation":"back_r"},"NW":{"animation":"back_l"}}
	check(Direction.resolve(diagonals,0).animation == "front_r", "South chooses front")
	check(Direction.resolve(diagonals,6).animation == "front_l", "90-degree West chooses adjacent front, not North")
	check(Direction.resolve(diagonals,4).animation == "back_r", "180-degree view uses real back")
	var authored_wins := Direction.animation_map(CATALOG.get_entry(&"fisher_captain_01").profile.sprite_frames,"idle_",{"SE":{"animation":"idle_ne","flip_h":true}})
	check(authored_wins.SE.animation == "idle_se" and not authored_wins.SE.flip_h, "alias cannot replace authored direction")
	for animation in ["idle_n","idle_e","idle_s"]:
		check(is_equal_approx(CATALOG.get_entry(&"fisher_captain_01").profile.sprite_frames.get_animation_speed(animation),CATALOG.get_entry(&"fisher_captain_01").profile.sprite_frames.get_animation_speed("idle_se")), "new cardinal idle preserves existing timing " + animation)
	# Family mutations are in-memory only and restored. Every assigned catalogue
	# actor is measured, plus independent player/large/small/prop/item probes.
	var probes: Array[GroundPresentation] = []
	var independent_values := {}
	for family in Families.FAMILIES.values():
		independent_values[family.family]=Vector4(family.width,family.depth,family.opacity,family.ground_offset)
		var actor := Node3D.new()
		fixture.add_child(actor)
		var p := load("res://actors/WorldGroundPresentation.tscn").instantiate() as GroundPresentation
		p.profile = WorldActorPresentationProfile.new()
		p.profile.shadow_family_resource=family
		actor.add_child(p)
		probes.append(p)
	await settle()
	var standard: WorldShadowFamily = Families.resolve(&"humanoid_standard")
	var old := Vector4(standard.width,standard.depth,standard.opacity,standard.ground_offset)
	standard.width=0.37
	standard.depth=0.29
	standard.opacity=0.79
	await settle()
	for actor in actors:
		var p: GroundPresentation = actor.get_node("GroundPresentation")
		var family := p.profile.resolved_shadow_family()
		check(is_equal_approx(p.shadow.width,family.width) and is_equal_approx(p.shadow.depth,family.depth) and is_equal_approx(p.shadow.opacity,family.opacity), "family mutation propagates " + String(actor.visual_profile.npc_id))
	for p in probes:
		var family := p.profile.resolved_shadow_family()
		check(is_equal_approx(p.shadow.width,family.width) and is_equal_approx(p.shadow.depth,family.depth), "independent category "+String(family.family))
		if family != standard:
			check(Vector4(p.shadow.width,p.shadow.depth,p.shadow.opacity,p.shadow.ground_offset).is_equal_approx(independent_values[family.family]), "non-standard category unchanged " + String(family.family))
	var special: GroundPresentation = actors[0].get_node("GroundPresentation")
	var original_profile := special.profile
	special.profile = original_profile.duplicate()
	special.profile.shadow_scale_multiplier=1.5
	await settle()
	check(is_equal_approx(special.shadow.width,standard.width*1.5) and is_equal_approx(special.shadow.depth,standard.depth*1.5), "reusable profile multiplier works")
	special.profile=original_profile
	standard.width=old.x
	standard.depth=old.y
	standard.opacity=old.z
	standard.ground_offset=old.w
	await settle()
	fixture.free()
	# Exercise every current world presentation, including functional NPCs,
	# through the real scene lifecycle and moving Card Maker ownership.
	for scene_path in ["res://actors/FishingTestScene_V2.tscn","res://actors/locations/WyndiaOceanOutpost.tscn","res://actors/locations/LypLakeOutpost.tscn","res://actors/locations/RiverFishingOutpost.tscn","res://actors/locations/ChiquaSupplyOutpost.tscn"]:
		var scene: Node = load(scene_path).instantiate()
		root.add_child(scene)
		current_scene=scene
		await settle()
		var world_presentations := scene.find_children("GroundPresentation","GroundPresentation",true,false)
		standard.width=old.x+0.05
		await settle()
		for p: GroundPresentation in world_presentations:
			check(p.profile.shadow_family_resource != null, "world profile exposes family " + String(p.get_parent().name))
			var family := p.profile.resolved_shadow_family()
			check(is_equal_approx(p.shadow.width,family.width*p.profile.shadow_scale_multiplier), "family propagates to placed actor " + String(p.get_parent().name))
		standard.width=old.x
		var world_camera: Camera3D = scene.get_node("CameraRig/Camera3D")
		for turn in range(8):
			world_camera.global_position=Vector3(sin(turn*PI/4)*5,3,cos(turn*PI/4)*5)
			world_camera.look_at(Vector3.ZERO)
			await settle()
			for p: GroundPresentation in world_presentations:
				check(p.shadow.global_basis.is_equal_approx(Basis.IDENTITY) and p.shadow.global_position.is_equal_approx(p.global_position+Vector3(0,p.shadow.ground_offset,0)), "placed shadow stable " + String(p.get_parent().name))
		standard.width=old.x
		scene.free()
		current_scene=null
		await settle()
	print("NPC DIRECTION/SHADOW QA: %d/%d passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
