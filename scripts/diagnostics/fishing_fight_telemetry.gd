extends Node

## Opt-in observer only: no simulation, camera, visibility, input or save writes.
## F12 bookmarks a frame in the console. Shift+F12 hides/shows only this overlay.
var fishing: Node
var sample_interval := 0.25
var _elapsed := 0.0
var _label: Label
var _previous: Dictionary = {}
var _last_phase := -1
var _bookmark_pending := false

func _ready() -> void:
	process_priority = 200 # After CameraRig, fight shadow and FishingLineView (110).
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(6, 6)
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_label)
	print("[FIGHTTRACE] enabled: F12 bookmark; Shift+F12 overlay; observer only")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		if event.shift_pressed:
			_label.visible = not _label.visible
		else:
			_bookmark_pending = true

func _process(delta: float) -> void:
	if not is_instance_valid(fishing):
		return
	_elapsed += delta
	if _bookmark_pending:
		_bookmark_pending = false
		capture("F12_BOOKMARK") # Sample after the line/actor update in this frame.
	if fishing.phase != _last_phase or _elapsed >= sample_interval:
		var reason := "phase_change" if fishing.phase != _last_phase else "sample"
		_last_phase = fishing.phase
		_elapsed = 0.0
		capture(reason)

func xyz(point: Vector3) -> Array:
	return [snappedf(point.x, 0.00001), snappedf(point.y, 0.00001), snappedf(point.z, 0.00001)]

func position_snapshot(source: String, node: Node3D, camera: Camera3D) -> Dictionary:
	if not is_instance_valid(node):
		return {"source": source, "valid": false}
	var result := point_snapshot(source, node.global_position, camera)
	result.merge({"valid": true, "path": String(node.get_path()), "id": node.get_instance_id(),
		"class": node.get_class(), "visible": node.visible, "visible_in_tree": node.is_visible_in_tree(),
		"process_mode": node.process_mode, "processing": node.is_processing(), "physics_processing": node.is_physics_processing()})
	var previous: Dictionary = _previous.get(source, {})
	if previous.get("id", -1) == node.get_instance_id():
		result["world_delta"] = xyz(node.global_position - previous.world)
	_previous[source] = {"id": node.get_instance_id(), "world": node.global_position}
	return result

func point_snapshot(source: String, world: Vector3, camera: Camera3D) -> Dictionary:
	var result := {"source": source, "world": xyz(world)}
	if is_instance_valid(camera):
		var screen := camera.unproject_position(world)
		result["screen"] = [snappedf(screen.x, 0.01), snappedf(screen.y, 0.01)]
		result["behind_camera"] = camera.is_position_behind(world)
		result["inside_viewport"] = not result.behind_camera and camera.get_viewport().get_visible_rect().has_point(screen)
	return result

func sprites(node: Node, camera: Camera3D, output: Array) -> void:
	if not is_instance_valid(node):
		return
	if node is SpriteBase3D:
		var item := position_snapshot("sprite:" + String(node.get_path()), node, camera)
		item["alpha"] = node.modulate.a
		output.append(item)
	for child in node.get_children():
		sprites(child, camera, output)

func capture(reason := "sample") -> Dictionary:
	var caster: Node = fishing.caster
	var encounter: Node = fishing.encounter
	var rig: Node = fishing.camera_rig
	var camera := get_viewport().get_camera_3d()
	var bait := caster.get("active_bait") as Node3D
	var shadow := encounter.get("active_fight_shadow") as Node3D
	var line := fishing.get_node_or_null("FishingLineView")
	var tracking_target := rig.get("_fight_tracking_target") as Node3D
	var candidates: Array = [position_snapshot("Caster.active_bait.global_position", bait, camera),
		position_snapshot("Encounter.active_fight_shadow.global_position", shadow, camera),
		position_snapshot("CameraRig._fight_tracking_target.global_position", tracking_target, camera)]
	if is_instance_valid(shadow):
		candidates.append(position_snapshot("FightShadow._fight_bait.global_position", shadow.get("_fight_bait") as Node3D, camera))
	if is_instance_valid(line):
		# This is the endpoint actually passed to the line mesh on its last update,
		# not a guessed/recomputed surface marker.
		if line.get("_has_previous_bait_position"):
			candidates.append(point_snapshot("FishingLineView._previous_bait_position (mesh endpoint)", line.get("_previous_bait_position"), camera))
		if line.has_surface_entry():
			candidates.append(point_snapshot("FishingLineView._surface_entry_position (water split)", line.get_surface_entry_position(), camera))
		candidates.append(position_snapshot("FishingLineView.rod_tip.global_position", line.rod_tip, camera))
		for candidate in candidates:
			if String(candidate.source).begins_with("FishingLineView.") and not candidate.has("path"):
				candidate["path"] = String(line.get_path())
	if is_instance_valid(bait):
		candidates.append(position_snapshot("Caster.reel_target.global_position (screen-space marker)", caster.reel_target, camera))
		candidates.append(point_snapshot("Caster.get_active_bait_surface_position (physical XZ)", caster.get_active_bait_surface_position(), camera))
		candidates.append(point_snapshot("Caster.get_active_bait_visual_surface_position (camera ray)", caster.get_active_bait_visual_surface_position(), camera))
	var presentation: Array = []
	sprites(shadow, camera, presentation)
	var bait_presentation: Array = []
	sprites(bait, camera, bait_presentation)
	var fish_presented := false
	for sprite in presentation:
		fish_presented = fish_presented or (sprite.visible_in_tree and sprite.alpha > 0.01)
	var tracker = rig.get("fight_camera_tracking")
	var yaw: float = tracker.yaw
	var requested: float = tracker.requested_yaw
	var direction := "none" if absf(requested - yaw) < 0.0001 else ("right" if requested < yaw else "left")
	var report := {"reason": reason, "frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(),
		"time_ms": Time.get_ticks_msec(), "phase": fishing.Phase.keys()[fishing.phase],
		"FIGHT": fishing.phase == fishing.Phase.FIGHT, "hooked": encounter.lifecycle.is_hooked(),
		"cast_serial": encounter.lifecycle.cast_serial, "fish_visible": fish_presented,
		"visibility_meaning": "sprite flags and alpha; does not prove GPU pixels or occlusion",
		"tracking_owner": rig.get("_fight_tracking_active"), "camera_frozen": rig.fishing_camera_frozen,
		"camera_current": camera != null and camera.current, "camera_tracking_yaw_degrees": rad_to_deg(yaw),
		"requested_yaw_degrees": rad_to_deg(requested), "requested_yaw_direction": direction,
		"edge_correction_active": tracker.tracking, "yaw_limited": tracker.limited,
		"D": Input.is_action_pressed("ds_right"), "A": Input.is_action_pressed("ds_left"),
		"K": Input.is_action_pressed("enter_fishing"), "steering_axis": Input.get_axis("ds_left", "ds_right"),
		"target_source": "CameraRig._fight_tracking_target.global_position", "candidates": candidates,
		"presentation": presentation, "bait_presentation": bait_presentation,
		"fish_instance": "FishInstance is RefCounted stats, not a Node3D position",
		"encounter": {"player_steering": encounter.player_steering, "player_reeling": encounter.player_reeling,
			"fish_lateral": encounter.current_fish_lateral, "fight_intent": encounter.current_fight_intent.duplicate(true)}}
	if is_instance_valid(bait):
		report["bait_mechanics"] = {"reeling": bait.reeling, "frozen": bait.simulation_frozen,
			"steering": bait.reel_steering, "steering_target": bait.reel_steering_target,
			"fish_lateral": bait.fish_lateral, "fish_depth_intent": bait.fish_depth_intent,
			"fish_pull_strength": bait.fish_pull_strength, "twitch_velocity": xyz(bait.twitch_velocity),
			"water_y": bait.water_y, "bottom_y": bait.bottom_y, "fight_max_distance": bait.fight_max_distance}
	if is_instance_valid(camera):
		# The optical origin has no projectable pixel; do not unproject the
		# camera through itself (Godot reports p.d == 0 for that operation).
		report["camera"] = {"path": String(camera.get_path()), "world": xyz(camera.global_position),
			"basis": [xyz(camera.global_basis.x), xyz(camera.global_basis.y), xyz(camera.global_basis.z)]}
	var target: Dictionary = candidates[2]
	report["target_world"] = target.get("world", null)
	report["target_screen"] = target.get("screen", null)
	report["active_bait_world"] = candidates[0].get("world", null)
	report["fish_actor_world"] = candidates[1].get("world", null)
	report["line_endpoint_world"] = xyz(line.get("_previous_bait_position")) if is_instance_valid(line) and line.get("_has_previous_bait_position") else null
	if reason != "sample" or report.FIGHT or is_instance_valid(bait):
		print("[FIGHTTRACE] ", JSON.stringify(report))
	_label.text = "FIGHT %s  hooked %s  presented %s  owner %s  frozen %s\nD %s A %s K %s  yaw %.2f -> %.2f (%s)  limited %s\ntarget %s\nworld %s  screen %s\nbait %s\nactor %s\nline %s\nF12: bookmark  Shift+F12: overlay" % [report.FIGHT, report.hooked, fish_presented,
		report.tracking_owner, report.camera_frozen, report.D, report.A, report.K, rad_to_deg(yaw), rad_to_deg(requested), direction,
		report.yaw_limited, target.get("path", "unavailable"), target.get("world", []), target.get("screen", []),
		candidates[0].get("world", []), candidates[1].get("world", []),
		line.get("_previous_bait_position") if is_instance_valid(line) else "unavailable"]
	return report
