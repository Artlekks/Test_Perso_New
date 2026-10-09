extends RefCounted
## One canonical projection and HUD anchor policy for desktop and the touch shell.
## Run before children become ready so HUD tween destinations use the final anchors.
static func prepare(game: Node) -> void:
	var extra_height := 384.0
	_adapt_gameplay_hud(game, extra_height)
	for camera in game.find_children("*", "Camera3D", true, false):
		if not camera.has_meta("mobile_original_projection"):
			camera.set_meta("mobile_original_projection", {"aspect": camera.keep_aspect, "fov": camera.fov, "size": camera.size})
		var original: Dictionary = camera.get_meta("mobile_original_projection")
		if original.aspect == Camera3D.KEEP_HEIGHT:
			# Equivalent horizontal FOV of the authored desktop 640x480 shot.
			camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(original.fov) * 0.5) * 640.0 / 480.0))
			camera.size = original.size * 640.0 / 480.0
		camera.keep_aspect = Camera3D.KEEP_WIDTH
	var rig := game.get_node_or_null("CameraRig")
	if rig != null:
		_adapt_fishing_composition(rig, extra_height)
		for property in ["fight_safe_top", "fight_safe_bottom", "fishing_follow_top_y_ratio", "fishing_follow_bottom_y_ratio", "fishing_follow_trigger_y_ratio"]:
			var key: String = "mobile_original_" + property
			if not rig.has_meta(key):
				rig.set_meta(key, rig.get(property))
			rig.set(property, (float(rig.get_meta(key)) * 480.0 + extra_height * 0.5) / 864.0)

static func _bottom_anchor(control: Control) -> void:
	if control == null or control.has_meta("mobile_grounded_hud"):
		return
	control.set_meta("mobile_grounded_hud", true)
	var top := control.anchor_top * 480.0 + control.offset_top
	var bottom := control.anchor_bottom * 480.0 + control.offset_bottom
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_top = top - 480.0
	control.offset_bottom = bottom - 480.0

static func _adapt_gameplay_hud(game: Node, extra_height: float) -> void:
	# Production HUD visibility/tweens are unchanged; only their anchors move.
	for path in ["UI/ExplorationHud/Root/HelpPanel", "UI/FishingHud/CharacterView", "UI/FishingHud/PowerMeter/Root", "UI/FishingHud/PowerMeter/DepthMeter"]:
		_bottom_anchor(game.get_node_or_null(path) as Control)
	var info := game.get_node_or_null("UI/FishingHud/FishingInfoView")
	if info != null:
		if not info.has_meta("mobile_notice_home"):
			info.set_meta("mobile_notice_home", info.exploration_position)
		info.exploration_position = info.get_meta("mobile_notice_home") + Vector2(0, extra_height)

static func _adapt_fishing_composition(rig: Node, extra_height: float) -> void:
	var camera := rig.get_node_or_null("Camera3D") as Camera3D
	var pose := rig.get_node_or_null("FishingCameraPose") as Camera3D
	if camera == null or pose == null:
		return
	if not rig.has_meta("mobile_desktop_camera_distance"):
		rig.set_meta("mobile_desktop_camera_distance", camera.position.length())
	var original: Dictionary = camera.get_meta("mobile_original_projection")
	var desktop := Projection.create_perspective(original.fov, 640.0 / 480.0, camera.near, camera.far, original.aspect == Camera3D.KEEP_WIDTH)
	var view := pose.transform
	view.origin *= float(rig.get_meta("mobile_desktop_camera_distance")) * rig.fishing_distance_scale / view.origin.length()
	view.origin += view.basis.x * rig.fishing_h_offset + view.basis.y * rig.fishing_v_offset
	var feet := view.affine_inverse() * Vector3.ZERO
	var clip := desktop * Vector4(feet.x, feet.y, feet.z, 1)
	var desktop_y := (1.0 - clip.y / clip.w) * 0.5
	# KEEP_WIDTH adds equal vertical space above/below. Shift composition by
	# the additional pixels needed to retain the authored normalized foot Y.
	rig.mobile_fishing_vertical_offset = extra_height * (desktop_y - 0.5) * 2.0 * (-feet.z) / (480.0 * desktop.y.y)
	rig.set_meta("mobile_desktop_foot_y", desktop_y)

