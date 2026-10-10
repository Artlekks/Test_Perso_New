extends Node3D

const GroundFraming = preload("res://scripts/fishing_camera_framing.gd")
const FightCameraTracking = preload("res://scripts/fishing_fight_camera_tracking.gd")

signal fishing_view_ready
signal exploration_view_ready
signal heading_changed(yaw: float)
signal exploration_view_started

@export var target: Node3D
@export var player_screen_notifier: VisibleOnScreenNotifier3D
@export var fishing_reference_camera: Camera3D
@export var fishing_pose_camera: Camera3D

@export var fishing_h_offset: float = 0.90
@export var fishing_v_offset: float = 0.65
## Optional host presentation adjustment; desktop keeps the authored value.
var mobile_fishing_vertical_offset: float = 0.0
@export_range(0.5, 1.5, 0.01) var fishing_distance_scale: float = 1.0
@export var aim_follow_speed: float = 6.0
@export var fishing_yaw_offset_degrees: float = -15.0
@export_range(-80.0, -5.0, 0.5) var fishing_pitch_degrees: float = -38.5
@export_category("Fishing Follow")
@export_range(0.1, 0.9, 0.05)
var fishing_follow_trigger_y_ratio: float = 0.50
# Screen-space tracking zone for the lure / hooked fish.
# The target may move freely until it reaches one of these boundaries.
# Values are ratios of the native viewport, so they stay correct if the
# game window is scaled.
#
# 0.58 = about y=139 on a 320x240 frame.
# 0.40 = about x=128 on a 320x240 frame.
@export_range(0.45, 0.75, 0.01)
var fishing_follow_bottom_y_ratio: float = 0.58
@export_range(0.20, 0.60, 0.01)
var fishing_follow_left_x_ratio: float = 0.40
## During a cast, follow begins near the outer-right screen edge.
## 0.76 = about X=243 on a native 320px-wide frame.
@export_range(0.60, 0.90, 0.01)
var fishing_follow_right_x_ratio: float = 0.76
## Upper cast boundary. The lure may travel freely until it reaches roughly
## the top 28% of the frame; after that the camera follows the casting arc.
## 0.28 = about Y=67 on a native 320x240 frame.
@export_range(0.15, 0.45, 0.01)
var fishing_follow_top_y_ratio: float = 0.28
@export_range(0.1, 2.0, 0.05)
var quick_cancel_camera_return_time: float = 0.85
## Return uses the tracker's existing exponential neutral response, not a duration.
@export_range(0.01, 0.2, 0.01) var retrieve_yaw_stop_degrees: float = 0.05

@export_category("Fight Camera Tracking")
## Outer activation edges, normalized to the active fishing viewport.
@export_range(0.0, 0.9, 0.01) var fight_safe_left: float = 0.18
@export_range(0.1, 1.0, 0.01) var fight_safe_right: float = 0.82
@export_range(0.0, 0.9, 0.01) var fight_safe_top: float = 0.22
## HUD begins around y=405/480; leave clearance for the fish sprite above it.
@export_range(0.1, 1.0, 0.01) var fight_safe_bottom: float = 0.70
## Search margin only; entering the legal rectangle immediately holds the shot.
@export_range(0.0, 0.2, 0.005) var fight_tracking_hysteresis: float = 0.02
## Preserve vertical HUD clearance independently of the wider lateral band.
@export_range(0.0, 0.1, 0.005) var fight_vertical_tracking_hysteresis: float = 0.025
@export_range(0.1, 20.0, 0.1) var fight_yaw_response: float = 6.0
@export_range(0.1, 20.0, 0.1) var fight_yaw_return_response: float = 2.0
@export_range(0.0, 90.0, 1.0) var fight_max_yaw_degrees: float = 55.0

var fight_camera_tracking = FightCameraTracking.new()
var _fight_tracking_active := false
var _fight_tracking_target: Node3D
var _fight_base_offsets := Vector2.ZERO
enum FishingCameraPresentationState { TRAVEL, ANCHORED, RETRIEVE_RETURN }
var fishing_camera_state := FishingCameraPresentationState.TRAVEL
@export_category("Two-stage Fishing Framing")
## Travel gets more bottom room, still above the HUD's ~405/480 start.
@export var travel_safe_frame := Rect2(0.18,0.22,0.64,0.56)
## Anchor is the physical player's projection in the authored post-aim shot.
## This offset tunes that shared reference without a shell-specific magic point.
@export var player_anchor_offset := Vector2.ZERO
@export var player_anchor_tolerance := Vector2(0.04,0.045)
@export_range(0.0,30.0,0.1) var travel_translation_limit := 6.0
@export_range(0.0,5.0,0.05) var anchored_translation_limit := 0.75
## Bounded sightline translation, a fraction of the authored optical distance.
## Unlike ground-only pan this preserves the exact player pixel at vertical edges.
@export_range(0.0,0.5,0.01) var anchored_dolly_limit := 0.25
@export_range(0.1,10.0,0.1) var fishing_correction_grace_seconds := 2.0
var fishing_player_anchor := Vector2.ZERO
var _water_pan := Vector2.ZERO
var _anchored_pan := Vector2.ZERO
var _retrieve_pan := Vector2.ZERO
var _water_dolly := 0.0
var _retrieve_dolly := 0.0
var framing_constraints_feasible := true
var fishing_rotation_failures := 0
var fishing_anchor_failures := 0
var fishing_hud_failures := 0
var fishing_hud_geometry: Array[CanvasItem] = []
var _hud_failure_reported := false
var _retrieve_start_offsets := Vector2.ZERO
var _retrieve_end_offsets := Vector2.ZERO
var _safe_violation_time := 0.0
var _safe_failure_reported := false
var safe_containment_failures := 0
@export var fishing_safe_debug_visible := true
const SAFE_TOLERANCE_PIXELS := 0.5
var _safe_overlay: Control
var _fight_base_valid := false
var _fight_base_camera_transform: Transform3D

## Once real Ryu re-enters the frame, stop fish-centric screen corrections.
## From then on, camera progress is driven by the remaining lure/fish distance.
@export_range(0.1, 2.0, 0.05)
var fishing_player_return_end_distance: float = 0.50
var fishing_aim_active: bool = false
var fishing_aim_target_yaw: float = 0.0
var fishing_aim_direction_to_rig_offset: float = 0.0
var exploration_h_offset: float = 0.0
var exploration_v_offset: float = 0.0
var exploration_yaw_before_fishing: float = 0.0
var exploration_camera_pitch_before_fishing: float = 0.0
var exploration_camera_transform_before_fishing: Transform3D
var _camera_transition_start_transform: Transform3D
var _camera_transition_target_transform: Transform3D
var is_rotating: bool = false
var _last_heading_yaw: float = 0.0
var fishing_follow_target: Node3D = null

var fishing_follow_direction: Vector3 = Vector3.ZERO
var fishing_follow_cast_origin: Vector3 = Vector3.ZERO
var fishing_follow_base_position: Vector3 = Vector3.ZERO

var fishing_follow_water_y: float = 0.0
var fishing_follow_activation_progress: float = 0.0
var fishing_follow_activation_height: float = 0.0
var fishing_follow_offset: float = 0.0

var fishing_follow_armed: bool = false
var fishing_follow_active: bool = false

# Original-game-style near-player return. There is deliberately no fixed
# duration: the camera advances only as the lure/fish comes closer to Ryu.
var fishing_player_return_active: bool = false
var fishing_player_return_start_camera_position: Vector3 = Vector3.ZERO
var fishing_player_return_start_distance: float = 0.0
var fishing_player_return_progress: float = 0.0

# Water contact is an explicit ownership boundary. Before contact the lure may
# drive cast framing. After contact, as soon as the real world-space Ryu is on
# screen, the camera must hand ownership back to the player-return rail and the
# fish/lure is never allowed to pull the rig sideways again for that cast.
var fishing_follow_has_reached_water: bool = false

# Hard ownership latch for the current cast. Once the real player has reclaimed
# the shot, fish/lure tracking can never own the rig again until the cast is
# explicitly reset or a new cast is armed. This is deliberately separate from
# `fishing_player_return_active`: the return is temporary, ownership is not.
var fishing_player_camera_locked: bool = false

var fishing_follow_returning: bool = false
var _fishing_follow_return_tween: Tween = null
var fishing_camera_frozen: bool = false
var _retrieve_yaw_return_active := false
var _retrieve_base_transform: Transform3D
var _retrieve_yaw: float = 0.0

func _ready() -> void:
	var camera: Camera3D = $Camera3D
	var layer := CanvasLayer.new()
	layer.name = "FishingSafeRegionDebug"
	layer.layer = 4
	add_child(layer)
	_safe_overlay = preload("res://scripts/ui/fishing_safe_region_debug.gd").new()
	_safe_overlay.rig = self
	layer.add_child(_safe_overlay)

	exploration_h_offset = camera.h_offset
	exploration_v_offset = camera.v_offset
	exploration_camera_pitch_before_fishing = camera.rotation.x
	exploration_camera_transform_before_fishing = camera.transform

func _process(_delta: float) -> void:
	if fishing_camera_frozen:
		return

	if target == null:
		return

	# Water has one composition owner; the airborne rail never writes through it.
	var follow_controls_position := false if _fight_tracking_active else _update_fishing_follow()

	# A quick-cancel return tween owns the rig position until it finishes.
	# Without this guard the normal target-follow line below would overwrite
	# the tween every frame and snap the camera home instantly.
	if not follow_controls_position and not fishing_follow_returning:
		global_position = target.global_position

	# During AIM the camera only responds to player-driven aim changes.
	# start_fishing_aim() seeds the neutral pose from the camera's current
	# fishing heading, so entering AIM itself never causes a second snap.
	if fishing_aim_active:
		rotation.y = lerp_angle(
			rotation.y,
			fishing_aim_target_yaw,
			clamp(aim_follow_speed * _delta, 0.0, 1.0)
		)

	if not is_equal_approx(rotation.y, _last_heading_yaw):
		_last_heading_yaw = rotation.y
		heading_changed.emit(rotation.y)

	if not _fight_tracking_active: _update_retrieve_yaw(_delta)
	_update_fight_camera_tracking(_delta)


func set_fishing_fight_tracking(active: bool, hooked_target: Node3D = null) -> void:
	_fight_tracking_active = active and is_instance_valid(hooked_target)
	_fight_tracking_target = hooked_target if _fight_tracking_active else null
	if _fight_tracking_active and not _fight_base_valid:
		var camera := get_node_or_null("Camera3D") as Camera3D
		if camera == null:
			_fight_tracking_active = false
			return
		_fight_base_camera_transform = camera.transform
		_fight_base_offsets = Vector2(camera.h_offset,camera.v_offset)
		_water_pan = Vector2(global_position.x-target.global_position.x,global_position.z-target.global_position.z)
		_water_dolly = 0.0
		_anchored_pan = Vector2.ZERO
		framing_constraints_feasible = true
		fishing_camera_state = FishingCameraPresentationState.TRAVEL
		var authored := global_transform*_fight_base_camera_transform
		authored.origin -= Vector3(_water_pan.x,0,_water_pan.y)
		authored.origin += authored.basis.x*camera.h_offset+authored.basis.y*camera.v_offset
		fishing_player_anchor = _project_fight_orbit(0.0,authored,camera.get_camera_projection(),target.global_position,target.global_position)+player_anchor_offset
		_safe_violation_time = 0.0
		_safe_failure_reported = false
		_fight_base_valid = true
		fight_camera_tracking.reset()
		# Water composition replaces the airborne rail, without snapping its pan.
		fishing_follow_armed = false
		fishing_follow_active = false
		fishing_player_return_active = false
		fishing_player_camera_locked = true
	# Inactive means hold the last shot for landing/result animations. Reset
	# belongs exclusively to the existing follow reset / exploration exit.


func _fight_orbit_transform(base: Transform3D, pivot: Vector3, yaw: float) -> Transform3D:
	var orbit := Basis(Vector3.UP, yaw)
	return Transform3D(orbit * base.basis, pivot + orbit * (base.origin - pivot))


func _project_fight_orbit(yaw: float, view_base: Transform3D, projection: Projection,
		pivot: Vector3, fish_position: Vector3) -> Vector2:
	# Equivalent to Camera3D.unproject_position(), using its active projection
	# and camera transform (including h/v offsets), without mutating the live
	# camera for every candidate orbit tested by the dead-zone solver.
	var view := _fight_orbit_transform(view_base, pivot, yaw)
	var local := view.affine_inverse() * fish_position
	# Ordinary off-viewport points retain their exact projected coordinates.
	# Across the camera plane perspective becomes singular, then mirrors the
	# left/right sign behind the camera. Extend it with signed bearing instead
	# of discarding both sides into the same sentinel or a visibility gate.
	# The tangent extension is continuous and monotonic, so a hidden target
	# still requests the orbit that turns toward its physical world position.
	var bearing := atan2(local.x, -local.z)
	const MAX_PROJECTION_TANGENT := 4.0
	var tangent_limit := atan(MAX_PROJECTION_TANGENT)
	if absf(bearing) > tangent_limit:
		var tangent_slope := 1.0 + MAX_PROJECTION_TANGENT * MAX_PROJECTION_TANGENT
		var extended_x := signf(bearing) * (MAX_PROJECTION_TANGENT + (absf(bearing) - tangent_limit) * tangent_slope)
		var forward_depth := maxf(Vector2(local.x, local.z).length() * cos(tangent_limit), 0.000001)
		return Vector2(0.5 + extended_x * projection.x.x * 0.5,
			0.5 - local.y / forward_depth * projection.y.y * 0.5)
	var clip: Vector4 = projection * Vector4(local.x, local.y, local.z, 1.0)
	if absf(clip.w) <= 0.000001:
		# Coincident with the optical origin: no useful lateral bearing exists.
		return Vector2(0.5, 0.5)
	return Vector2(clip.x / clip.w * 0.5 + 0.5, -clip.y / clip.w * 0.5 + 0.5)


func _water_base(pan: Vector2) -> Transform3D:
	var base := global_transform*_fight_base_camera_transform
	base.origin += Vector3(pan.x,0,pan.y)
	var camera: Camera3D = $Camera3D
	var sightline := base.origin+base.basis.x*camera.h_offset+base.basis.y*camera.v_offset-target.global_position
	base.origin += sightline*_water_dolly
	return base

func _optical_pose(base: Transform3D, camera: Camera3D) -> Transform3D:
	base.origin += base.basis.x*camera.h_offset+base.basis.y*camera.v_offset
	return base

func player_anchor_region() -> Rect2:
	# Even an unusually authored anchor must not authorize panning the feet off-screen.
	return Rect2(fishing_player_anchor-player_anchor_tolerance,player_anchor_tolerance*2.0).intersection(Rect2(.02,.02,.96,.96))

func fishing_safe_frames() -> Array[Rect2]:
	return [travel_safe_frame,Rect2(Vector2(fight_safe_left,fight_safe_top),Vector2(fight_safe_right-fight_safe_left,fight_safe_bottom-fight_safe_top))]

func fishing_safe_region() -> Rect2:
	return fishing_safe_frames()[0 if fishing_camera_state == FishingCameraPresentationState.TRAVEL else 1]

func fishing_safe_region_pixels() -> Rect2:
	var size: Vector2 = $Camera3D.get_viewport().get_visible_rect().size
	var region := fishing_safe_region()
	return Rect2(region.position*size,region.size*size)

func set_fishing_hud_geometry(power_view: Node, depth_view: Node) -> void:
	fishing_hud_geometry.clear()
	if is_instance_valid(power_view):
		var background := power_view.get_node_or_null("Root/PowerBarBG") as CanvasItem
		if background != null: fishing_hud_geometry.append(background)
	if is_instance_valid(depth_view):
		var frame := depth_view.get_node_or_null("Frame") as CanvasItem
		if frame != null: fishing_hud_geometry.append(frame)

func fishing_hud_regions_pixels() -> Array[Rect2]:
	var regions: Array[Rect2] = []
	for visual in fishing_hud_geometry:
		if not is_instance_valid(visual) or not visual.is_visible_in_tree(): continue
		if visual.get_viewport() != $Camera3D.get_viewport(): continue
		var rect: Rect2
		if visual is Sprite2D: rect = visual.get_rect()
		elif visual is Control: rect = Rect2(Vector2.ZERO,visual.size)
		else: continue
		regions.append(visual.get_global_transform_with_canvas()*rect)
	return regions

func _update_fight_camera_tracking(delta: float) -> void:
	if not _fight_tracking_active or not is_instance_valid(_fight_tracking_target): return
	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera == null or not camera.current or not _fight_base_valid: return
	var size := camera.get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0: return
	var physical := _fight_tracking_target.global_position
	var player_world := target.global_position
	var was_travel := fishing_camera_state == FishingCameraPresentationState.TRAVEL
	var base := _water_base(_water_pan)
	var yaw: float = 0.0 if was_travel else fight_camera_tracking.yaw
	if not was_travel:
		var project := _project_fight_orbit.bind(_optical_pose(base,camera),camera.get_camera_projection(),player_world,physical)
		# Horizontal violations alone request yaw. Vertical framing is separate.
		yaw = fight_camera_tracking.step(delta,project,fishing_safe_region(),fight_tracking_hysteresis,deg_to_rad(fight_max_yaw_degrees),fight_yaw_response,fight_yaw_return_response,0.0)
	var pose := _fight_orbit_transform(base,player_world,yaw)
	var point := _project_fight_orbit(0.0,_optical_pose(pose,camera),camera.get_camera_projection(),player_world,physical)
	var region := fishing_safe_region()
	if not fight_camera_tracking.inside(point,region,0.00001):
		# ANCHORED never translates for a horizontal edge: that belongs to yaw.
		var translate := was_travel or point.y < region.position.y or point.y > region.end.y
		if translate:
			if not was_travel: pose = _bounded_anchor_dolly(pose,camera,physical)
			var remaining := _project_fight_orbit(0.0,_optical_pose(pose,camera),camera.get_camera_projection(),player_world,physical)
			if was_travel or remaining.y < region.position.y-0.00001 or remaining.y > region.end.y+0.00001:
				pose = _bounded_ground_pan(pose,camera,physical,was_travel,delta)
	# One final production composition. No pitch, roll, optical offset or bait writes.
	camera.global_transform = pose
	if was_travel:
		var projected_player := camera.unproject_position(player_world)/size
		if fight_camera_tracking.inside(projected_player,player_anchor_region(),0.00001):
			fishing_camera_state = FishingCameraPresentationState.ANCHORED
			_anchored_pan = _water_pan
	check_fishing_safe_invariant(camera.unproject_position(physical),delta,camera.is_position_behind(physical))
	# Compare orientation in the base yaw frame rather than Euler angles.
	var expected := Basis(Vector3.UP,yaw)*(global_transform*_fight_base_camera_transform).basis
	if not camera.global_basis.is_equal_approx(expected):
		fishing_rotation_failures += 1
		if OS.is_debug_build(): push_error("FISHING TRACKING PITCH/ROLL VIOLATION")
	if fishing_camera_state == FishingCameraPresentationState.ANCHORED and not fight_camera_tracking.inside(camera.unproject_position(player_world)/size,player_anchor_region(),0.001):
		fishing_anchor_failures += 1
		if OS.is_debug_build(): push_error("FISHING PLAYER ANCHOR VIOLATION")

func _bounded_anchor_dolly(pose: Transform3D, camera: Camera3D, physical: Vector3) -> Transform3D:
	var optical := _optical_pose(pose,camera)
	var axis := (optical.origin-target.global_position)/(1.0+_water_dolly)
	var inverse := optical.affine_inverse()
	var local := inverse*physical
	var direction := inverse.basis*(-axis)
	var projection := camera.get_camera_projection()
	var origin := projection*Vector4(local.x,local.y,local.z,1)
	var slope := projection*Vector4(direction.x,direction.y,direction.z,0)
	var frame := fishing_safe_region()
	var low := -anchored_dolly_limit-_water_dolly
	var high := anchored_dolly_limit-_water_dolly
	var allowed_low := low
	var allowed_high := high
	for plane: Vector4 in [Vector4(0,1,0,frame.position.y*2-1),Vector4(0,-1,0,1-frame.end.y*2),Vector4(0,0,0,-1)]:
		var coefficient := plane.dot(slope)
		var bound := -plane.dot(origin)-(0.05 if plane == Vector4(0,0,0,-1) else 0.0)
		if absf(coefficient)<0.000001:
			if bound < 0: return pose
		elif coefficient > 0: high = minf(high,bound/coefficient)
		else: low = maxf(low,bound/coefficient)
	var correction := 0.0
	if low <= high:
		correction = clampf(0.0,low,high)
	else:
		# A bounded dolly may provide only part of the required clearance.
		# Use that improvement before solving the remaining bounded ground pan.
		var current := _project_fight_orbit(0.0,optical,projection,target.global_position,physical)
		var error := absf(current.y-clampf(current.y,frame.position.y,frame.end.y))
		for candidate in [allowed_low,allowed_high]:
			var trial := pose
			trial.origin += axis*candidate
			var point := _project_fight_orbit(0.0,_optical_pose(trial,camera),projection,target.global_position,physical)
			var candidate_error := absf(point.y-clampf(point.y,frame.position.y,frame.end.y))
			if candidate_error < error: correction = candidate; error = candidate_error
	pose.origin += axis*correction
	_water_dolly += correction
	framing_constraints_feasible = true
	return pose

func _bounded_ground_pan(pose: Transform3D, camera: Camera3D, physical: Vector3, travel: bool, delta: float) -> Transform3D:
	var limit := travel_translation_limit if travel else anchored_translation_limit
	var reference := Vector2.ZERO if travel else _anchored_pan
	# Pan is stored before yaw, then rotated with the player-pivot composition.
	var scale := 1.0+_water_dolly
	var remaining_min := (reference-Vector2.ONE*limit-_water_pan)*scale
	var remaining_max := (reference+Vector2.ONE*limit-_water_pan)*scale
	var yaw: float = fight_camera_tracking.yaw
	var rotation_2d := Transform2D(-yaw,Vector2.ZERO)
	var polygon: Array[Vector2] = [rotation_2d*remaining_min,rotation_2d*Vector2(remaining_max.x,remaining_min.y),rotation_2d*remaining_max,rotation_2d*Vector2(remaining_min.x,remaining_max.y)]
	var optical := _optical_pose(pose,camera)
	var projection := camera.get_camera_projection()
	if not travel:
		polygon = GroundFraming.screen_constraints(polygon,optical,projection,target.global_position,player_anchor_region())
	var player_safe := polygon.duplicate()
	var frame := fishing_safe_region()
	# Vertical-only constraints in ANCHORED; yaw owns horizontal edges.
	polygon = GroundFraming.screen_constraints(polygon,optical,projection,physical,frame,not travel)
	framing_constraints_feasible = not polygon.is_empty()
	if travel and not polygon.is_empty():
		# When one bounded pan can satisfy bait clearance and bring Ryu into
		# the authored anchor, choose that path. Otherwise travel with the bait.
		# The transition still depends on the actual resulting player projection.
		var anchored_path := GroundFraming.screen_constraints(polygon,optical,projection,target.global_position,player_anchor_region().grow(-.001))
		if not anchored_path.is_empty(): polygon = anchored_path
	if polygon.is_empty():
		# Preserve player/translation bounds. The containment firewall reports the
		# unsatisfiable physical state rather than tilting or moving gameplay actors.
		polygon = player_safe
		if polygon.is_empty(): return pose
		var best := Vector2.ZERO
		var error := INF
		for candidate in polygon:
			var trial := pose
			trial.origin += Vector3(candidate.x,0,candidate.y)
			var p := _project_fight_orbit(0.0,_optical_pose(trial,camera),projection,target.global_position,physical)
			var e: float = fight_camera_tracking.violation(p,fishing_safe_region())
			if e < error: best = candidate; error = e
		pose.origin += Vector3(best.x,0,best.y)
		_water_pan += rotation_2d.affine_inverse()*best/scale
		return pose
	# Travel's feasible pan progresses toward the authored player shot, even
	# before the complete anchor region becomes reachable. Never pan while safe.
	var wanted := rotation_2d*(-_water_pan) if travel else Vector2.ZERO
	var correction := GroundFraming.nearest(polygon,wanted)
	# Reuse the established exponential response for the initial pan. Anchored
	# vertical clearance remains immediate and bounded; its player pixel holds.
	if travel: correction *= 1.0-exp(-fight_yaw_response*delta)
	pose.origin += Vector3(correction.x,0,correction.y)
	_water_pan += rotation_2d.affine_inverse()*correction/scale
	return pose

func check_fishing_safe_invariant(point: Vector2, delta: float, behind := false) -> void:
	# Live HUD geometry, not duplicated shell pixel constants. HUD overlap is
	# immediate; only a safe-frame edge gets the bounded correction grace.
	var overlaps_hud := false
	for hud in fishing_hud_regions_pixels():
		if hud.grow(2.0).has_point(point): overlaps_hud = true
	if overlaps_hud and not _hud_failure_reported:
		fishing_hud_failures += 1
		if OS.is_debug_build(): push_error("FISHING HUD OVERLAP VIOLATION: projected=%s" % point)
	_hud_failure_reported = overlaps_hud
	var region := fishing_safe_region_pixels()
	if behind or not fight_camera_tracking.inside(point,region,SAFE_TOLERANCE_PIXELS):
		_safe_violation_time += delta
		if _safe_violation_time >= fishing_correction_grace_seconds and not _safe_failure_reported:
			_safe_failure_reported = true
			safe_containment_failures += 1
			if OS.is_debug_build(): push_error("FISHING SAFE REGION VIOLATION: state=%s target=%s projected=%s region=%s yaw=%s feasible=%s" % [FishingCameraPresentationState.keys()[fishing_camera_state],_fight_tracking_target,point,region,fight_camera_tracking.yaw,framing_constraints_feasible])
	else:
		_safe_violation_time = 0.0
		_safe_failure_reported = false


func _clear_fight_camera_tracking(restore_pose: bool = true) -> void:
	var camera := get_node_or_null("Camera3D") as Camera3D
	if restore_pose and _fight_base_valid and camera != null:
		camera.transform = _fight_base_camera_transform
		camera.h_offset = _fight_base_offsets.x
		camera.v_offset = _fight_base_offsets.y
	_water_pan = Vector2.ZERO
	_water_dolly = 0.0
	_anchored_pan = Vector2.ZERO
	_fight_base_valid = false
	_fight_tracking_active = false
	_fight_tracking_target = null
	fight_camera_tracking.reset()

func arm_fishing_follow(
	track_target: Node3D,
	cast_direction: Vector3,
	water_y: float
) -> void:
	if not is_instance_valid(track_target):
		return

	_stop_fishing_follow_return(false)

	var direction := cast_direction
	direction.y = 0.0

	if direction.length_squared() == 0.0:
		return

	direction = direction.normalized()

	fishing_follow_target = track_target
	fishing_follow_direction = direction
	fishing_follow_cast_origin = track_target.global_position
	fishing_follow_water_y = water_y

	fishing_follow_activation_progress = 0.0
	fishing_follow_activation_height = 0.0
	fishing_follow_offset = 0.0

	fishing_follow_armed = true
	fishing_follow_active = false
	fishing_player_return_active = false
	fishing_player_return_start_camera_position = Vector3.ZERO
	fishing_player_return_start_distance = 0.0
	fishing_player_return_progress = 0.0
	fishing_follow_has_reached_water = false
	fishing_player_camera_locked = false


func notify_fishing_target_landed() -> void:
	# Fishing owns the gameplay phase, so it tells the camera exactly when the
	# cast has entered the water. This avoids guessing from lure depth and makes
	# the camera handoff deterministic on every cast, including consecutive casts.
	fishing_follow_has_reached_water = true
	_try_begin_fishing_player_return()


func begin_fishing_player_return() -> void:
	# This is an ownership transition, not merely a movement request. The old
	# implementation required `fishing_follow_active`, which meant a waterborne
	# cast that was still only ARMED could ignore the player's screen re-entry.
	# Later, a hard A/D pull could then activate the tracking boundary and steal
	# the camera again. Latch player ownership first, regardless of whether the
	# lure had already activated camera follow.
	if target == null:
		return

	if fishing_player_camera_locked:
		return

	fishing_player_camera_locked = true

	# From this line onward fish-centric tracking is permanently disabled for
	# this cast. The rig may still need to travel home, but the fish can never
	# move it sideways again.
	fishing_follow_armed = false
	fishing_follow_active = false

	if not is_instance_valid(fishing_follow_target):
		_lock_fishing_camera_to_player()
		return

	var tracked_position := fishing_follow_target.global_position
	var distance := _get_flat_player_distance(tracked_position)

	# If the rig is already at its fishing-home anchor, do not create a return
	# state at all. This is the exact short-cast / visible-Ryu case that used to
	# remain armed and become breakable later.
	if global_position.distance_squared_to(target.global_position) <= 0.000001:
		_lock_fishing_camera_to_player()
		return

	fishing_player_return_active = true
	fishing_player_return_start_camera_position = global_position
	fishing_player_return_start_distance = maxf(
		distance,
		fishing_player_return_end_distance + 0.001
	)
	fishing_player_return_progress = 0.0


func reset_fishing_follow() -> void:
	_clear_fight_camera_tracking()
	fishing_player_camera_locked = false
	_stop_fishing_follow_return(false)
	_clear_fishing_follow_state()

	if target != null:
		global_position = target.global_position


func return_fishing_follow_to_target(completed_retrieve: bool = false) -> void:
	var return_yaw: float = fight_camera_tracking.yaw
	var return_base := _fight_base_camera_transform
	var return_offsets := Vector2($Camera3D.h_offset,$Camera3D.v_offset)
	var return_end_offsets := _fight_base_offsets
	var return_pan := _water_pan
	var return_dolly := _water_dolly
	var return_orbit := completed_retrieve and _fight_base_valid
	_clear_fight_camera_tracking(not return_orbit)
	fishing_player_camera_locked = false

	# Reuse the existing return owner. Quick cancel retains its translation
	# behavior; full retrieve additionally glides the tracked child-camera yaw
	# back to its captured base pose. Neither keeps a discarded bait target.
	_clear_fishing_follow_state()
	_stop_fishing_follow_return(false)

	if target == null:
		return

	var destination := target.global_position

	if completed_retrieve:
		global_position = destination
		if return_orbit:
			_retrieve_base_transform = return_base
			_retrieve_yaw = return_yaw
			_retrieve_start_offsets = return_offsets
			_retrieve_end_offsets = return_end_offsets
			_retrieve_pan = return_pan
			_retrieve_dolly = return_dolly
			fishing_camera_state = FishingCameraPresentationState.RETRIEVE_RETURN
			_retrieve_yaw_return_active = absf(return_yaw) > deg_to_rad(retrieve_yaw_stop_degrees) or return_offsets.distance_to(return_end_offsets)>0.0001 or return_pan.length()>0.0001 or absf(return_dolly)>0.00001
			fishing_follow_returning = _retrieve_yaw_return_active
			if not _retrieve_yaw_return_active:
				$Camera3D.transform = return_base
		return

	if quick_cancel_camera_return_time <= 0.0 or global_position.distance_squared_to(destination) <= 0.000001:
		global_position = destination
		return
	fishing_follow_returning = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", destination, quick_cancel_camera_return_time)
	tween.tween_callback(_finish_fishing_follow_return)
	_fishing_follow_return_tween = tween


func _clear_fishing_follow_state() -> void:
	fishing_follow_target = null

	fishing_follow_direction = Vector3.ZERO
	fishing_follow_cast_origin = Vector3.ZERO
	fishing_follow_base_position = Vector3.ZERO

	fishing_follow_water_y = 0.0
	fishing_follow_activation_progress = 0.0
	fishing_follow_activation_height = 0.0
	fishing_follow_offset = 0.0

	fishing_follow_armed = false
	fishing_follow_active = false
	fishing_player_return_active = false
	fishing_player_return_start_camera_position = Vector3.ZERO
	fishing_player_return_start_distance = 0.0
	fishing_player_return_progress = 0.0
	fishing_follow_has_reached_water = false


func _lock_fishing_camera_to_player() -> void:
	# The cast may continue, but camera ownership is now final. Clear every
	# fish-tracking degree of freedom while preserving the ownership latch.
	_clear_fishing_follow_state()
	fishing_player_camera_locked = true

	if target != null:
		global_position = target.global_position


func _update_retrieve_yaw(delta: float) -> void:
	if not _retrieve_yaw_return_active:
		return
	_retrieve_yaw = lerpf(_retrieve_yaw, 0.0, 1.0 - exp(-fight_yaw_return_response * delta))
	var factor := 1.0-exp(-fight_yaw_return_response*delta)
	_retrieve_start_offsets = _retrieve_start_offsets.lerp(_retrieve_end_offsets,factor)
	_retrieve_pan = _retrieve_pan.lerp(Vector2.ZERO,factor)
	_retrieve_dolly = lerpf(_retrieve_dolly,0.0,factor)
	var pose := _retrieve_base_transform
	pose.origin += global_basis.inverse()*Vector3(_retrieve_pan.x,0,_retrieve_pan.y)
	pose.origin += (pose.origin+pose.basis.x*_retrieve_end_offsets.x+pose.basis.y*_retrieve_end_offsets.y)*_retrieve_dolly
	$Camera3D.transform = _fight_orbit_transform(pose, Vector3.ZERO, _retrieve_yaw)
	$Camera3D.h_offset = _retrieve_start_offsets.x
	$Camera3D.v_offset = _retrieve_start_offsets.y
	if absf(_retrieve_yaw) <= deg_to_rad(retrieve_yaw_stop_degrees) and _retrieve_start_offsets.distance_to(_retrieve_end_offsets)<0.0001 and _retrieve_pan.length()<0.0001 and absf(_retrieve_dolly)<0.00001:
		_finish_fishing_follow_return()


func _finish_fishing_follow_return() -> void:
	_finish_retrieve_yaw_return()
	fishing_follow_returning = false
	_fishing_follow_return_tween = null

	if target != null:
		global_position = target.global_position


func _finish_retrieve_yaw_return() -> void:
	if _retrieve_yaw_return_active:
		$Camera3D.transform = _retrieve_base_transform
		$Camera3D.h_offset = _retrieve_end_offsets.x
		$Camera3D.v_offset = _retrieve_end_offsets.y
		_retrieve_yaw_return_active = false


func _stop_fishing_follow_return(snap_to_target: bool, restore_yaw: bool = true) -> void:
	if restore_yaw:
		_finish_retrieve_yaw_return()
	else:
		_retrieve_yaw_return_active = false
	if (
		_fishing_follow_return_tween != null
		and _fishing_follow_return_tween.is_valid()
	):
		_fishing_follow_return_tween.kill()

	_fishing_follow_return_tween = null
	fishing_follow_returning = false

	if snap_to_target and target != null:
		global_position = target.global_position


func _update_fishing_follow() -> bool:
	# Absolute invariant: once player ownership is latched for this cast, no
	# lure/fish position, tracking boundary, or A/D spam may move the rig again.
	# During the distance-driven return we still advance toward home; once home
	# we pin the rig to the player every frame until the cast is reset.
	if fishing_player_camera_locked:
		if fishing_player_return_active:
			if is_instance_valid(fishing_follow_target):
				_update_fishing_player_return(
					fishing_follow_target.global_position
				)
			else:
				_lock_fishing_camera_to_player()
		else:
			if target != null:
				global_position = target.global_position

		return true

	if not fishing_follow_armed and not fishing_follow_active:
		return false

	if not is_instance_valid(fishing_follow_target):
		if fishing_player_return_active:
			if target != null:
				global_position = target.global_position
			_clear_fishing_follow_state()
			return true

		if fishing_follow_active:
			global_position = (
				fishing_follow_base_position
				+ fishing_follow_direction * fishing_follow_offset
			)

			return true

		fishing_follow_armed = false
		return false

	var current_position := fishing_follow_target.global_position

	# Keep a geometric fallback for safety, but the normal path is the explicit
	# notify_fishing_target_landed() call from Fishing.
	if (
		not fishing_follow_has_reached_water
		and current_position.y <= fishing_follow_water_y + 0.05
	):
		fishing_follow_has_reached_water = true

	# This is the key ownership rule: once the lure is in the water and the real
	# Ryu is visible, fish-centric screen corrections are over for this cast.
	# It does not matter whether Ryu ever left the frame, so consecutive casts
	# cannot get stuck waiting for a screen_entered edge that will never fire.
	_try_begin_fishing_player_return()

	if fishing_player_return_active:
		_update_fishing_player_return(current_position)
		return true

	if fishing_follow_armed:
		var camera: Camera3D = $Camera3D

		# Ignore the height of the casting arc when deciding
		# when the camera should begin following.
		var projected_position := current_position
		projected_position.y = fishing_follow_water_y

		if not camera.is_position_behind(projected_position):
			var screen_position := camera.unproject_position(
				projected_position
			)

			var viewport_size := (
				get_viewport().get_visible_rect().size
			)
			var viewport_height := viewport_size.y
			var viewport_width := viewport_size.x

			var bottom_limit_y := (
				viewport_height
					* fishing_follow_bottom_y_ratio
			)
			var top_limit_y := (
				viewport_height
					* fishing_follow_top_y_ratio
			)
			var left_limit_x := (
				viewport_width
					* fishing_follow_left_x_ratio
			)
			var right_limit_x := (
				viewport_width
					* fishing_follow_right_x_ratio
			)
			var actual_screen_position := camera.unproject_position(
				current_position
			)
			var has_reached_water := (
				current_position.y
					<= fishing_follow_water_y + 0.05
			)

			# BOF4-style cast framing:
			# - rightward casts trigger around 76% of screen width;
			# - high casts trigger before the lure reaches the top edge.
			# Once either threshold is reached the camera travels with the
			# airborne arc rather than allowing the lure to leave the frame.
			if (
				screen_position.x >= right_limit_x
				or actual_screen_position.y <= top_limit_y
				or (
					has_reached_water
					and (
						screen_position.y >= bottom_limit_y
						or screen_position.x <= left_limit_x
						or screen_position.x >= right_limit_x
					)
				)
			):
				fishing_follow_armed = false
				fishing_follow_active = true

				fishing_follow_base_position = global_position

				fishing_follow_activation_progress = (
					current_position
						- fishing_follow_cast_origin
				).dot(fishing_follow_direction)
				fishing_follow_activation_height = (
					current_position.y
				)

	# A short cast can become active only after touching the water. Re-check the
	# ownership rule immediately so there is not even one frame where the left /
	# right screen boundary can drag Ryu after he is already visible.
	_try_begin_fishing_player_return()
	if fishing_player_return_active:
		_update_fishing_player_return(current_position)
		return true

	if not fishing_follow_active:
		return false

	var current_progress := (
		current_position
			- fishing_follow_cast_origin
	).dot(fishing_follow_direction)

	fishing_follow_offset = maxf(
		current_progress
			- fishing_follow_activation_progress,
		0.0
	)

	var airborne_height_offset := maxf(
		current_position.y - fishing_follow_activation_height,
		0.0
	)

	global_position = (
		fishing_follow_base_position
			+ fishing_follow_direction * fishing_follow_offset
			+ Vector3.UP * airborne_height_offset
	)

	# Keep the lure / hooked fish inside a loose central screen-space zone.
	# It is still free to move naturally inside the zone; the camera only
	# corrects once it tries to cross the lower or left boundary.
	_enforce_fishing_tracking_zone(current_position)

	return true
	

func should_hand_off_fishing_follow_to_player(
	player_inside_frame: bool
) -> bool:
	# Player ownership is based on gameplay phase + visibility, not whether the
	# camera happened to have crossed a tracking threshold already. This closes
	# the ARMED-but-not-ACTIVE hole that allowed a later lateral pull to steal
	# the shot.
	if fishing_player_camera_locked:
		return false

	if fishing_player_return_active:
		return false

	if not fishing_follow_has_reached_water:
		return false

	return player_inside_frame


func _try_begin_fishing_player_return() -> bool:
	var player_inside_frame := _is_fishing_player_inside_frame()
	if not should_hand_off_fishing_follow_to_player(player_inside_frame):
		return false

	begin_fishing_player_return()
	return fishing_player_camera_locked


func _get_flat_player_distance(
	world_position: Vector3
) -> float:
	if target == null:
		return 0.0

	var player_position := target.global_position
	return Vector2(
		world_position.x - player_position.x,
		world_position.z - player_position.z
	).length()


func _is_fishing_player_inside_frame() -> bool:
	# Use the same world-space visibility source as FishingCharacterView. The
	# previous point-projection fallback could disagree with the visible sprite
	# because it tested only the player's origin, which made the handoff flaky.
	if is_instance_valid(player_screen_notifier):
		return player_screen_notifier.is_on_screen()

	if target == null:
		return false

	var camera: Camera3D = $Camera3D
	var player_position: Vector3 = target.global_position

	if camera.is_position_behind(player_position):
		return false

	var viewport_size: Vector2 = (
		get_viewport().get_visible_rect().size
	)
	var screen_position: Vector2 = camera.unproject_position(
		player_position
	)

	return (
		screen_position.x >= 0.0
		and screen_position.x <= viewport_size.x
		and screen_position.y >= 0.0
		and screen_position.y <= viewport_size.y
	)


func get_fishing_follow_debug_snapshot() -> Dictionary:
	return {
		"armed": fishing_follow_armed,
		"active": fishing_follow_active,
		"player_return_active": fishing_player_return_active,
		"player_camera_locked": fishing_player_camera_locked,
		"return_progress": fishing_player_return_progress,
		"follow_offset": fishing_follow_offset,
		"has_reached_water": fishing_follow_has_reached_water,
		"player_inside_frame": _is_fishing_player_inside_frame(),
	}


func _update_fishing_player_return(
	tracked_position: Vector3
) -> void:
	if target == null:
		return

	var player_position := target.global_position
	var current_distance := _get_flat_player_distance(
		tracked_position
	)

	var return_travel := maxf(
		fishing_player_return_start_distance
			- fishing_player_return_end_distance,
		0.001
	)

	var raw_progress := clampf(
		(
			fishing_player_return_start_distance
				- current_distance
		) / return_travel,
		0.0,
		1.0
	)

	# If the fish surges away again, the camera pauses where it is instead of
	# reversing away from Ryu. It resumes only when the fish gets closer again.
	fishing_player_return_progress = maxf(
		fishing_player_return_progress,
		raw_progress
	)

	global_position = fishing_player_return_start_camera_position.lerp(
		player_position,
		fishing_player_return_progress
	)

	if (
		current_distance <= fishing_player_return_end_distance
		or fishing_player_return_progress >= 0.9999
		or global_position.distance_squared_to(player_position) <= 0.000001
	):
		_lock_fishing_camera_to_player()


func _enforce_fishing_tracking_zone(
	world_position: Vector3
) -> void:
	if fishing_player_camera_locked:
		return

	# Hard invariant: after water contact, a visible real Ryu owns the framing.
	# The old left/right limits behaved like an invisible collider: crossing one
	# let the fish drag the whole camera sideways. Never run those corrections in
	# the player-owned state, even if another lifecycle signal is delayed.
	if (
		fishing_follow_has_reached_water
		and _is_fishing_player_inside_frame()
	):
		return

	# Correct twice because a perspective camera can couple horizontal and
	# vertical screen movement slightly. Two small passes keep both limits
	# respected without locking the target rigidly to a single screen point.
	for _i in range(2):
		_enforce_fishing_bottom_screen_limit(world_position)
		_enforce_fishing_left_screen_limit(world_position)
		_enforce_fishing_right_screen_limit(world_position)


func _enforce_fishing_right_screen_limit(
	world_position: Vector3
) -> void:
	var camera: Camera3D = $Camera3D
	if camera.is_position_behind(world_position):
		return

	var viewport_width := get_viewport().get_visible_rect().size.x
	if viewport_width <= 0.0:
		return

	var limit_x := viewport_width * fishing_follow_right_x_ratio
	var start_screen_x := camera.unproject_position(world_position).x
	if start_screen_x <= limit_x:
		return

	var start_rig_position := global_position
	var camera_right := camera.global_transform.basis.x
	camera_right.y = 0.0
	if camera_right.length_squared() <= 0.000001:
		return
	camera_right = camera_right.normalized()

	var probe_distance := 0.25
	var correction_axis := -camera_right

	global_position = start_rig_position - camera_right * probe_distance
	var negative_x := camera.unproject_position(world_position).x
	global_position = start_rig_position + camera_right * probe_distance
	var positive_x := camera.unproject_position(world_position).x
	global_position = start_rig_position

	if positive_x < negative_x:
		correction_axis = camera_right

	var probe_x := minf(negative_x, positive_x)
	if probe_x >= start_screen_x:
		return

	var low_distance := 0.0
	var high_distance := probe_distance
	var high_x := probe_x

	for _i in range(10):
		if high_x <= limit_x:
			break
		low_distance = high_distance
		high_distance *= 2.0
		global_position = start_rig_position + correction_axis * high_distance
		high_x = camera.unproject_position(world_position).x

	if high_x > limit_x:
		return

	for _i in range(8):
		var mid_distance := (low_distance + high_distance) * 0.5
		global_position = start_rig_position + correction_axis * mid_distance
		var mid_x := camera.unproject_position(world_position).x
		if mid_x > limit_x:
			low_distance = mid_distance
		else:
			high_distance = mid_distance

	global_position = start_rig_position + correction_axis * high_distance


func _enforce_fishing_left_screen_limit(
	world_position: Vector3
) -> void:
	var camera: Camera3D = $Camera3D

	if camera.is_position_behind(world_position):
		return

	var viewport_width := get_viewport().get_visible_rect().size.x
	if viewport_width <= 0.0:
		return

	var limit_x := viewport_width * fishing_follow_left_x_ratio
	var start_screen_x := camera.unproject_position(world_position).x

	if start_screen_x >= limit_x:
		return

	var start_rig_position := global_position

	# Use the camera's screen-right direction projected onto the water plane.
	# Probe both signs so this remains robust if the authored camera heading
	# changes at another fishing spot.
	var camera_right := camera.global_transform.basis.x
	camera_right.y = 0.0

	if camera_right.length_squared() <= 0.000001:
		return

	camera_right = camera_right.normalized()

	var probe_distance := 0.25
	var correction_axis := -camera_right

	global_position = start_rig_position - camera_right * probe_distance
	var negative_x := camera.unproject_position(world_position).x

	global_position = start_rig_position + camera_right * probe_distance
	var positive_x := camera.unproject_position(world_position).x

	global_position = start_rig_position

	if positive_x > negative_x:
		correction_axis = camera_right

	var probe_x := maxf(negative_x, positive_x)
	if probe_x <= start_screen_x:
		# Neither direction improves the horizontal framing.
		return

	# Expand until the target is inside the allowed zone, then binary-search
	# the smallest camera correction necessary.
	var low_distance := 0.0
	var high_distance := probe_distance
	var high_x := probe_x

	for _i in range(10):
		if high_x >= limit_x:
			break

		low_distance = high_distance
		high_distance *= 2.0
		global_position = (
			start_rig_position
				+ correction_axis * high_distance
		)
		high_x = camera.unproject_position(world_position).x

	if high_x < limit_x:
		return

	for _i in range(8):
		var mid_distance := (low_distance + high_distance) * 0.5
		global_position = (
			start_rig_position
				+ correction_axis * mid_distance
		)

		var mid_x := camera.unproject_position(world_position).x
		if mid_x < limit_x:
			low_distance = mid_distance
		else:
			high_distance = mid_distance

	global_position = (
		start_rig_position
			+ correction_axis * high_distance
	)


func _enforce_fishing_bottom_screen_limit(
	world_position: Vector3
) -> void:
	var camera: Camera3D = $Camera3D

	if camera.is_position_behind(world_position):
		return

	var viewport_height := get_viewport().get_visible_rect().size.y
	if viewport_height <= 0.0:
		return

	var limit_y := viewport_height * fishing_follow_bottom_y_ratio
	var start_screen_y := camera.unproject_position(world_position).y

	if start_screen_y <= limit_y:
		return

	var start_rig_position := global_position
	var cast_axis := fishing_follow_direction

	if cast_axis.length_squared() <= 0.000001:
		return

	cast_axis = cast_axis.normalized()

	# Normally moving the rig backwards along the cast axis pushes the lure
	# upward on screen. Probe both directions anyway so this remains correct
	# if a fishing spot/camera is authored with an unusual orientation.
	var probe_distance := 0.25
	var correction_axis := -cast_axis

	global_position = start_rig_position - cast_axis * probe_distance
	var backward_y := camera.unproject_position(world_position).y

	global_position = start_rig_position + cast_axis * probe_distance
	var forward_y := camera.unproject_position(world_position).y

	global_position = start_rig_position

	if forward_y < backward_y:
		correction_axis = cast_axis

	var probe_y := minf(backward_y, forward_y)
	if probe_y >= start_screen_y:
		# Neither direction can improve the framing from this camera pose.
		return

	# Find a distance that places the target above the limit, then binary-search
	# the smallest correction. This gives a hard screen-space boundary without
	# snapping the camera farther than necessary.
	var low_distance := 0.0
	var high_distance := probe_distance
	var high_y := probe_y

	for _i in range(10):
		if high_y <= limit_y:
			break

		low_distance = high_distance
		high_distance *= 2.0
		global_position = (
			start_rig_position
				+ correction_axis * high_distance
		)
		high_y = camera.unproject_position(world_position).y

	if high_y > limit_y:
		# Extremely unusual geometry: keep the strongest safe correction found
		# instead of allowing the tracked target to disappear under the HUD.
		return

	for _i in range(8):
		var mid_distance := (low_distance + high_distance) * 0.5
		global_position = (
			start_rig_position
				+ correction_axis * mid_distance
		)

		var mid_y := camera.unproject_position(world_position).y
		if mid_y > limit_y:
			low_distance = mid_distance
		else:
			high_distance = mid_distance

	global_position = (
		start_rig_position
			+ correction_axis * high_distance
	)

func rotate_quarter_turn(direction: int) -> void:
	if is_rotating:
		return

	is_rotating = true

	var target_yaw := rotation.y + deg_to_rad(90.0 * direction)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		self,
		"rotation:y",
		target_yaw,
		0.3
	)

	await tween.finished
	is_rotating = false


func enter_fishing_view() -> void:
	exploration_yaw_before_fishing = rotation.y

	var camera: Camera3D = $Camera3D
	exploration_camera_pitch_before_fishing = camera.rotation.x
	exploration_camera_transform_before_fishing = camera.transform

	if target == null:
		fishing_view_ready.emit()
		return

	# Fishing heading and fishing framing are intentionally independent.
	# The reference camera preserves the Step One heading behaviour, while
	# FishingCameraPose stores the exact local pose chosen during Remote
	# runtime tuning. Exploration can now be changed without disturbing it.
	var fishing_heading_transform: Transform3D = camera.transform
	if is_instance_valid(fishing_reference_camera):
		fishing_heading_transform = fishing_reference_camera.transform

	var fishing_target_transform: Transform3D
	if is_instance_valid(fishing_pose_camera):
		fishing_target_transform = fishing_pose_camera.transform
	else:
		var reference_pitch: float = (
			fishing_heading_transform.basis.get_euler().x
		)
		var fishing_pitch_delta: float = (
			deg_to_rad(fishing_pitch_degrees)
			- reference_pitch
		)
		fishing_target_transform = _orbit_transform(
			fishing_heading_transform,
			fishing_pitch_delta
		)

	# Preserve the exploration camera distance when entering fishing.
	# The authored fishing pose still defines the viewing direction and
	# rotation, but it must not dolly closer and make the character larger.
	var exploration_distance: float = (
		exploration_camera_transform_before_fishing.origin.length()
	)
	var fishing_pose_distance: float = (
		fishing_target_transform.origin.length()
	)
	if fishing_pose_distance > 0.0001:
		fishing_target_transform.origin *= (
			exploration_distance
			* fishing_distance_scale
			/ fishing_pose_distance
		)

	var player_forward := target.global_transform.basis.z
	player_forward.y = 0.0
	player_forward = player_forward.normalized()

	# Calculate fishing yaw from the fishing reference as well. Otherwise
	# a local yaw change made only for exploration would still rotate the
	# fishing shot.
	var reference_global_basis: Basis = (
		global_transform.basis
		* fishing_heading_transform.basis
	)
	var camera_forward := -reference_global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()

	var yaw_difference := camera_forward.signed_angle_to(
		player_forward,
		Vector3.UP
	)

	var target_yaw := rotation.y + yaw_difference
	target_yaw += deg_to_rad(fishing_yaw_offset_degrees)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		self,
		"rotation:y",
		target_yaw,
		0.7
	)

	_prepare_camera_transition(
		camera.transform,
		fishing_target_transform
	)

	tween.parallel().tween_method(
		_apply_camera_transition,
		0.0,
		1.0,
		0.7
	)

	tween.parallel().tween_property(
		camera,
		"h_offset",
		fishing_h_offset,
		0.5
	)

	tween.parallel().tween_property(
		camera,
		"v_offset",
		fishing_v_offset + mobile_fishing_vertical_offset,
		0.5
	)

	await tween.finished
	camera.transform = fishing_target_transform
	fishing_view_ready.emit()


func exit_fishing_view() -> void:
	_stop_fishing_follow_return(false, false)
	# Keep the current tracked pose as the start of the existing exit tween.
	_clear_fight_camera_tracking(false)
	var camera: Camera3D = $Camera3D

	exploration_view_started.emit()

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.parallel().tween_property(
		self,
		"rotation:y",
		exploration_yaw_before_fishing,
		0.7
	)

	_prepare_camera_transition(
		camera.transform,
		exploration_camera_transform_before_fishing
	)

	tween.parallel().tween_method(
		_apply_camera_transition,
		0.0,
		1.0,
		0.7
	)

	tween.parallel().tween_property(
		camera,
		"h_offset",
		exploration_h_offset,
		0.5
	)

	tween.parallel().tween_property(
		camera,
		"v_offset",
		exploration_v_offset,
		0.5
	)

	await tween.finished
	camera.transform = exploration_camera_transform_before_fishing
	exploration_view_ready.emit()


func _orbit_transform(
	source_transform: Transform3D,
	angle: float
) -> Transform3D:
	var orbit_axis: Vector3 = source_transform.basis.x.normalized()
	var orbit := Basis(orbit_axis, angle)

	return Transform3D(
		orbit * source_transform.basis,
		orbit * source_transform.origin
	)


func _prepare_camera_transition(
	start_transform: Transform3D,
	target_transform: Transform3D
) -> void:
	_camera_transition_start_transform = start_transform
	_camera_transition_target_transform = target_transform


func _apply_camera_transition(weight: float) -> void:
	var camera: Camera3D = $Camera3D
	camera.transform = _camera_transition_start_transform.interpolate_with(
		_camera_transition_target_transform,
		weight
	)



func start_fishing_aim(direction: Vector3) -> void:
	# Preserve the exact fishing camera heading when AIM begins.
	# We store the angular relationship between the neutral cast direction
	# and the rig, then reuse it for every later A/D aim update.
	var center_direction := direction
	center_direction.y = 0.0

	if center_direction.length_squared() == 0.0:
		center_direction = Vector3.FORWARD
	else:
		center_direction = center_direction.normalized()

	var direction_yaw := atan2(
		center_direction.x,
		center_direction.z
	)

	fishing_aim_direction_to_rig_offset = wrapf(
		rotation.y - direction_yaw,
		-PI,
		PI
	)

	fishing_aim_target_yaw = rotation.y
	fishing_aim_active = true


func set_fishing_aim_direction(direction: Vector3) -> void:
	if not fishing_aim_active:
		return

	var desired_direction := direction
	desired_direction.y = 0.0

	if desired_direction.length_squared() == 0.0:
		return

	desired_direction = desired_direction.normalized()

	var desired_direction_yaw := atan2(
		desired_direction.x,
		desired_direction.z
	)

	var mapped_rig_yaw := (
		desired_direction_yaw
		+ fishing_aim_direction_to_rig_offset
	)

	# Pick the equivalent angle nearest the rig's current heading so crossing
	# +/-180 degrees can never create a full-circle camera spin.
	fishing_aim_target_yaw = rotation.y + wrapf(
		mapped_rig_yaw - rotation.y,
		-PI,
		PI
	)


func stop_fishing_aim() -> void:
	fishing_aim_active = false


func set_fishing_camera_frozen(active: bool) -> void:
	fishing_camera_frozen = active
