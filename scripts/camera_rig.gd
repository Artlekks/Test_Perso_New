extends Node3D

const GroundFraming = preload("res://scripts/fishing_camera_framing.gd")
const FightCameraTracking = preload("res://scripts/fishing_fight_camera_tracking.gd")
const FishingRodHandoff = preload("res://scripts/fishing_rod_handoff.gd")

signal fishing_view_ready
signal exploration_view_ready
signal heading_changed(yaw: float)
signal exploration_view_started

@export var target: Node3D
@export var player_screen_notifier: VisibleOnScreenNotifier3D
@export var fishing_reference_camera: Camera3D
@export var fishing_pose_camera: Camera3D

@export var fishing_h_offset: float = 0.90
@export var fishing_v_offset: float = 0.40
@export_category("Fishing Player / Fixed HUD Clearance")
## Extra gap between Ryu's projected body and the stationary power bar.
## The chosen fishing camera offset is captured at entry, before the cast;
## it is NOT animated or recomputed during the lure's flight/retrieval.
@export_range(0.0, 32.0, 1.0) var fishing_player_to_bar_gap_pixels: float = 12.0
## Approximate right-side footprint around the feet reference, in native
## gameplay-viewport pixels. Art tuning only; no change to physical collisions.
@export_range(10.0, 60.0, 1.0) var fishing_player_body_right_pixels: float = 32.0
## Safety cap on the entry-only adjustment to the authored lens position.
@export_range(0.0, 3.0, 0.05) var fishing_home_extra_offset_limit: float = 1.5
## Optional host presentation adjustment; desktop keeps the authored value.
var mobile_fishing_vertical_offset: float = 0.0
# The desktop host may reveal extra world ABOVE the authored 480px image.
# This optical shift keeps the authored lower-left player slot at its bottom
# distance without changing the lure, the camera follow's X/Z, or UI offsets.
var _desktop_vertical_extra_offset: float = 0.0
var _desktop_vertical_last_height: int = -1
var _desktop_vertical_is_fishing: bool = false
var _desktop_vertical_last_is_fishing: bool = false
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
## G19: Begin the cast's camera follow before it reaches the HUD. 0.43 is
## 7% of viewport height ABOVE the horizontal midpoint (Y grows downwards).
## These are response thresholds, never changes to the physical lure path.
@export_range(0.50, 0.90, 0.01)
var fishing_follow_right_x_ratio: float = 0.70
@export_range(0.35, 0.65, 0.01)
var fishing_follow_top_y_ratio: float = 0.43
@export_range(0.1, 2.0, 0.05)
var quick_cancel_camera_return_time: float = 0.85
## Return uses the tracker's existing exponential neutral response, not a duration.
@export_range(0.01, 0.2, 0.01) var retrieve_yaw_stop_degrees: float = 0.05
## On a completed reel, restore the pre-cast fishing angle in a single
## predictable eased transition rather than a multi-second exponential tail.
@export_range(0.8, 3.0, 0.05) var completed_reel_camera_return_seconds: float = 1.50

@export_category("Fight Camera Tracking")
## Outer activation edges, normalized to the active fishing viewport.
@export_range(0.0, 0.9, 0.01) var fight_safe_left: float = 0.18
@export_range(0.1, 1.0, 0.01) var fight_safe_right: float = 0.82
@export_range(0.0, 0.9, 0.01) var fight_safe_top: float = 0.22
## Lower water-lure limit is fixed at 70% height, above the power meter.
@export_range(0.1, 1.0, 0.01) var fight_safe_bottom: float = 0.70
## Search margin only; entering the legal rectangle immediately holds the shot.
@export_range(0.0, 0.2, 0.005) var fight_tracking_hysteresis: float = 0.02
## Preserve vertical HUD clearance independently of the wider lateral band.
@export_range(0.0, 0.1, 0.005) var fight_vertical_tracking_hysteresis: float = 0.025
@export_range(0.1, 20.0, 0.1) var fight_yaw_response: float = 6.0
@export_range(0.1, 20.0, 0.1) var fight_yaw_return_response: float = 2.0
@export_range(0.0, 90.0, 1.0) var fight_max_yaw_degrees: float = 55.0
## Soft horizontal follow band: the bait has room to steer, but the shot
## starts traveling before it reaches the hard yellow safety rectangle.
## Slightly right-of-center is intentional (original-game composition).
@export_range(0.20, 0.60, 0.01) var fishing_comfort_left: float = 0.38
@export_range(0.40, 0.80, 0.01) var fishing_comfort_right: float = 0.68
@export_range(0.0, 30.0, 1.0) var fishing_power_bar_clearance_pixels: float = 12.0

@export_range(0.0, 30.0, 1.0) var free_lure_max_yaw_degrees: float = 7.0
@export_category("Free D Waterline Camera")
## The rotating camera takes over screen clearance; the physical D arc
## never changes direction just because it approaches the depth meter.
## Hard safety cap only; a long D-held reel must not stall at the old 18-degree limit.
@export_range(0.0, 85.0, 1.0) var free_d_waterline_max_yaw_degrees: float = 70.0
## Maximum permitted correction when the lure risks falling behind the HUD.
@export_range(0.1, 15.0, 0.5) var free_d_waterline_max_speed_degrees: float = 9.0
## Once the bait reaches the boundary, continue the slow orbit while D is held
## even when the camera has successfully brought it back above that boundary.
@export_range(0.1, 8.0, 0.1) var free_d_waterline_cruise_degrees: float = 3.0
## Begin correcting before the lure reaches the top edge of the depth meter.
@export_range(0.005, 0.10, 0.005) var free_d_waterline_anticipation: float = 0.045

@export_category("Distant Lure / Character Inset Framing")
## When the real rod is out of view, track the lure by moving the camera,
## not by turning the D arc or moving the physical bait.
## Tight native-viewport rectangle, taken from the BOF4 red-box reference.
## A/D and retrieval do not modify their physical arc to satisfy these edges.
@export_range(0.1, 0.7, 0.01) var inset_follow_left: float = 0.30
@export_range(0.3, 0.9, 0.01) var inset_follow_right: float = 0.76
@export_range(0.1, 0.7, 0.01) var inset_follow_top: float = 0.57
@export_range(0.4, 0.9, 0.01) var inset_follow_bottom: float = 0.69
@export_category("Responsive Inset Containment / HUD Anchors")
## G19: left side starts immediately beyond the inset artwork; right side
## ends before the real depth gauge. Both use the live responsive HUD layout;
## top starts 7% of viewport height above center and bottom clears the bar.
@export_range(0.0, 0.6, 0.005) var inset_left_gap_bar_width: float = 0.025
@export_range(0.0, 0.6, 0.005) var inset_right_gap_bar_width: float = 0.085
@export_range(0.0, 0.6, 0.005) var inset_bottom_gap_bar_width: float = 0.23
@export_range(0.05, 0.5, 0.005) var inset_height_bar_width: float = 0.225
## Per-frame bound protects against pathological ray/horizon jumps.
@export_range(0.1, 8.0, 0.1) var inset_follow_max_step_world: float = 2.0
## Preemptive follow stays smooth while the bait is inside the hard red box.
## The hard border itself cannot be speed-limited: speed limits allowed the
## bait to leave the box before the camera caught up.
@export_range(0.5, 20.0, 0.5) var inset_follow_pan_speed: float = 7.0
## Pan begins slightly BEFORE reaching the hard frame; use the exact projected
## water-plane correction if a single frame would violate a hard boundary.
@export_range(0.0, 0.07, 0.005) var inset_follow_preemptive_margin: float = 0.025
## Only the painted rod may end the inset phase. Return-rail ownership alone
## must not disable its camera pan (Gate 09 did exactly that).
var _real_player_view_engaged: bool = false
## Pan is held while the inset is shown, then blended out along the remaining
## distance-driven return rail. Rebase at the actual rod-visibility handoff.
var _inset_pan_at_return: Vector2 = Vector2.ZERO
var _inset_pan_release_started: bool = false
var _inset_containment_violation_active: bool = false
var _inset_pan_release_start_progress: float = 0.0

var fight_camera_tracking = FightCameraTracking.new()
var _fight_tracking_active := false
var _fight_tracking_target: Node3D
var _fight_base_offsets := Vector2.ZERO
@export_category("Hooked Fish Upper-Screen Safety")
## Optical presentation shift ONLY. The fish/bait world position never moves.
@export_range(0.0, 6.0, 0.1) var hooked_top_clearance_max_lens_shift: float = 4.0
@export_range(0.5, 25.0, 0.5) var hooked_top_clearance_lens_speed: float = 12.0
@export_range(0.0, 20.0, 1.0) var hooked_top_clearance_pixels: float = 5.0
var _hooked_top_clearance_shift: float = 0.0
enum FishingCameraPresentationState { TRAVEL, ANCHORED, RETRIEVE_RETURN }
var fishing_camera_state := FishingCameraPresentationState.TRAVEL
@export_category("Two-stage Fishing Framing")
## Legacy travel reference (overlay hidden). No camera reposition at contact.
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
var _fishing_rotation_error_reported := false
@export_range(0.05, 2.0, 0.05) var fishing_rotation_diagnostic_tolerance_degrees: float = 0.25
var fishing_anchor_failures := 0
var _fishing_anchor_error_reported := false
var fishing_hud_failures := 0
var fishing_hud_geometry: Array[CanvasItem] = []
var _hud_failure_reported := false
var _retrieve_start_offsets := Vector2.ZERO
var _retrieve_end_offsets := Vector2.ZERO
var _safe_violation_time := 0.0
var _safe_failure_reported := false
var safe_containment_failures := 0
@export var fishing_safe_debug_visible := false
const SAFE_TOLERANCE_PIXELS := 0.5
var _safe_overlay: Control
var _fight_base_valid := false
var _fight_base_camera_transform: Transform3D
# Landing is not a new camera pose. Store the water-contact position once
# and wait for actual reel motion before permitting the small tracking yaw.
var _water_contact_bait_position := Vector3.ZERO
var _water_tracking_has_moved := false

## Once real Ryu re-enters the frame, stop fish-centric screen corrections.
## From then on, camera progress is driven by the remaining lure/fish distance.
@export_range(0.1, 2.0, 0.05)
var fishing_player_return_end_distance: float = 0.50
var fishing_aim_active: bool = false
var fishing_aim_target_yaw: float = 0.0
## Captured from the authored fishing-entry pose, not the latest cast bearing.
## Every completed reel and quick cancel returns to this same heading.
var _fishing_neutral_yaw: float = 0.0
var _fishing_neutral_yaw_valid: bool = false
## Exact heading at release of THIS cast, independent of earlier AIM steering.
## Restoring entry yaw after I caused the unrelated beach-facing rotation.
var _fishing_cast_start_yaw: float = 0.0
var _fishing_cast_start_valid: bool = false
var _retrieve_return_duration: float = 1.50
var _aim_heading_return_active: bool = false
var _aim_heading_return_start: float = 0.0
var _aim_heading_return_elapsed: float = 0.0
var _aim_heading_return_duration: float = 0.0
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
# Accumulated AIRBORNE camera-only pan; baked into the water camera pose
# at splashdown, so the inset rectangle does not change ownership abruptly.
var _airborne_inset_pan: Vector3 = Vector3.ZERO
# Optical translation in WORLD space. Unlike the legacy ground-only _water_pan,
# this also supports vertical camera-plane corrections without moving the lure.
# Retained across the inset -> real character handoff, then eased out on recovery.
var _inset_optical_pan: Vector3 = Vector3.ZERO
var _retrieve_start_optical_pan: Vector3 = Vector3.ZERO
# The real, exact camera pose at K/cast; the splashdown camera is NOT home.
var _cast_home_camera_local: Transform3D = Transform3D.IDENTITY
var _cast_home_camera_offsets: Vector2 = Vector2.ZERO
var _cast_home_rig_position: Vector3 = Vector3.ZERO
var _cast_home_pose_valid: bool = false
var _retrieve_start_camera_world: Transform3D = Transform3D.IDENTITY
# Optical inset compensation is released as the real player comes back.
var _inset_pan_handoff_world: Vector3 = Vector3.ZERO
var _inset_handoff_distance: float = 0.0
var inset_containment_failures: int = 0

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
var _retrieve_start_yaw: float = 0.0
var _retrieve_start_pan: Vector2 = Vector2.ZERO
# Full reel recovers the parent position together with lens yaw/pan.
# Teleporting the parent to Ryu at bait-disappear time was the camera jump.
var _retrieve_start_world_position: Vector3 = Vector3.ZERO
var _retrieve_end_world_position: Vector3 = Vector3.ZERO
var _retrieve_start_dolly: float = 0.0
var _retrieve_original_offsets: Vector2 = Vector2.ZERO
var _retrieve_yaw_return_elapsed: float = 0.0
# Latched only for this waterborne D retrieve; resets at the next cast/exit.
# The HUD threshold starts the orbit, but no longer acts as a stop switch.
var _free_d_orbit_engaged: bool = false
var _free_d_orbit_direction: float = 0.0
## Shared rotation-only near-player mode for either A or D. The legacy
## D names remain to keep the approved follow-through QA inspectable.
var _free_orbit_steering_sign: float = 0.0

func _ready() -> void:
	# The responsive HUD positions itself in _process (default priority 0).
	# Sample its final same-frame geometry AFTER layout but BEFORE the
	# CharacterView's late handoff check (priority 1000).
	process_priority = 200
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

	# Exactly one owner at a time: flight follow until contact, then water
	# tracking (including its distance-driven return). Do NOT pin the rig to
	# Ryu on every water frame: that silently cancels long-cast travel.
	# Follow/return rail runs ONCE each frame, including water tracking.
	# Previously the free and hooked tracking paths each advanced it again,
	# competing with the inset pan and sometimes snapping the shot home.
	var follow_controls_position: bool = _update_fishing_follow(_delta)

	# A quick-cancel return tween owns the rig position until it finishes.
	# Without this guard the normal target-follow line below would overwrite
	# the tween every frame and snap the camera home instantly.
	if not _fight_tracking_active and not follow_controls_position and not fishing_follow_returning:
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
	# AIM never competes with the return to the original fishing angle.
	_update_aim_heading_return(_delta)

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
		if camera == null or target == null:
			_fight_tracking_active = false
			return

		if not _tracks_free_lure():
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
			_fishing_rotation_error_reported = false
			_fishing_anchor_error_reported = false
			fight_camera_tracking.reset()
			# Water composition replaces the airborne rail, without snapping its pan.
			fishing_follow_armed = false
			fishing_follow_active = false
			fishing_player_return_active = false
			# A hooked fish does not give the real character ownership just by
			# changing targets. The inset must still pan while Ryu is offscreen.
			if _is_fishing_player_inside_frame():
				begin_fishing_player_return()
			return
		# Capture the airborne camera in the SAME rig-local frame. On a long
		# cast the rig is displaced toward the lure, and moving its parent back
		# to Ryu here would immediately destroy the water-contact composition.
		# The distance-driven return rail owns that translation after landing.
		_fight_base_offsets = Vector2(camera.h_offset,camera.v_offset)
		_fight_base_camera_transform = camera.transform
		_water_pan = Vector2.ZERO
		_water_dolly = 0.0
		_anchored_pan = Vector2.ZERO
		framing_constraints_feasible = true
		fishing_camera_state = FishingCameraPresentationState.ANCHORED
		var authored: Transform3D = _optical_pose(camera.global_transform,camera)
		# Long casts retain the home player anchor sampled before flight;
		# projecting Ryu while he is offscreen would produce an impossible
		# anchor region and poison the water-camera diagnostics.
		if global_position.distance_squared_to(target.global_position) <= 0.000001:
			fishing_player_anchor = _project_fight_orbit(
				0.0,authored,camera.get_camera_projection(),
				target.global_position,target.global_position
			)+player_anchor_offset
		_water_contact_bait_position = _fishing_tracking_position()
		_water_tracking_has_moved = false
		_safe_violation_time = 0.0
		_safe_failure_reported = false
		_fight_base_valid = true
		_fishing_rotation_error_reported = false
		_fishing_anchor_error_reported = false
		fight_camera_tracking.reset()
		# End airborne tracking, preserving the airborne camera pose. An
		# offscreen Ryu is NOT a reason to start player-owned framing.
		fishing_follow_armed = false
		fishing_follow_active = false
		fishing_follow_has_reached_water = true
		# This used to call begin_fishing_player_return() UNCONDITIONALLY.
		# At splashdown, even an entirely offscreen Ryu would inherit camera
		# ownership, cancelling the inset tracker and breaking the red zone.
		# Only the shared projected-player contract may trigger this handoff.
		_try_begin_fishing_player_return()
	# Inactive: keep the last frame for catch/result. Reset on next cast/exit.

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
	var frame := fishing_safe_frames()[0 if fishing_camera_state == FishingCameraPresentationState.TRAVEL else 1]
	# The authored lower edge is only an upper limit: a real visible power
	# bar can pull the boundary farther upward. Read the actual CanvasLayer geometry (works in all shells).
	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera == null: return frame
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0: return frame
	if not fishing_hud_geometry.is_empty():
		var bar := fishing_hud_geometry[0]
		if is_instance_valid(bar) and bar.is_visible_in_tree() and bar.get_viewport() == camera.get_viewport():
			var bar_rect := Rect2()
			var bar_sprite := bar as Sprite2D
			var bar_control := bar as Control
			if bar_sprite != null: bar_rect = bar_sprite.get_global_transform_with_canvas()*bar_sprite.get_rect()
			elif bar_control != null: bar_rect = bar_control.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,bar_control.size)
			# Only the actual power bar controls the lower cutoff; the depth
			# meter may be elsewhere and must not move the horizontal boundary.
			if bar_rect.position.x < viewport_size.x and bar_rect.end.x > 0.0 and bar_rect.position.y < viewport_size.y and bar_rect.end.y > 0.0:
				var bottom := (bar_rect.position.y-fishing_power_bar_clearance_pixels)/viewport_size.y
				if bottom > frame.position.y+0.05:
					frame.size.y = minf(frame.end.y,bottom)-frame.position.y
	return frame

func fishing_horizontal_comfort_region(hard: Rect2) -> Rect2:
	# Only the horizontal axis uses the narrower follow band. The HUD ceiling
	# and top boundary remain hard; A/D must not steer the camera vertically.
	var left := clampf(fishing_comfort_left,hard.position.x+0.01,hard.end.x-0.02)
	var right := clampf(fishing_comfort_right,left+0.01,hard.end.x-0.01)
	return Rect2(Vector2(left,hard.position.y),Vector2(right-left,hard.size.y))

func _tracks_free_lure() -> bool:
	return (is_instance_valid(_fight_tracking_target)
		and _fight_tracking_target.has_method("is_free_lure_framing_active")
		and bool(_fight_tracking_target.is_free_lure_framing_active()))

func free_lure_viewport_region() -> Rect2:
	# Physical visibility guard, independent of the inner camera response band.
	var camera: Camera3D = $Camera3D
	var size := camera.get_viewport().get_visible_rect().size
	var region := Rect2(0.025,0.05,0.95,0.90)
	var hud_regions := fishing_hud_regions_pixels()
	if size.y > 0.0 and not hud_regions.is_empty():
		region.size.y = maxf(0.0,minf(region.end.y,(hud_regions[0].position.y-fishing_power_bar_clearance_pixels)/size.y)-region.position.y)
	return region

func _fishing_tracking_position() -> Vector3:
	# A sinking lure's depth is gameplay data, not a request to pan the camera
	# downward through the power meter. Track its actual water-surface position.
	# Fallback keeps ordinary QA targets / future actors compatible.
	if not is_instance_valid(_fight_tracking_target): return Vector3.ZERO
	if _fight_tracking_target.has_method("get_surface_position"):
		return _fight_tracking_target.get_surface_position()
	return _fight_tracking_target.global_position

func fishing_safe_region_pixels() -> Rect2:
	var size: Vector2 = $Camera3D.get_viewport().get_visible_rect().size
	var region := fishing_safe_region()
	return Rect2(region.position*size,region.size*size)

## Scene references are captured once. Frame geometry is sampled live, AFTER
## PowerMeterView's responsive layout has moved the bar, depth gauge and inset.
var _inset_view: Control
var _power_hud_view: Node
var _depth_hud_view: Node
var _inset_hud_geometry_error_reported: bool = false

func set_fishing_hud_geometry(power_view: Node, depth_view: Node) -> void:
	fishing_hud_geometry.clear()
	_power_hud_view = power_view
	_depth_hud_view = depth_view
	_inset_view = null
	if is_instance_valid(power_view):
		_inset_view = power_view.get_node_or_null("../CharacterView") as Control
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
	if _tracks_free_lure():
		_update_free_lure_camera_tracking(delta)
		return
	if not _fight_tracking_active or not is_instance_valid(_fight_tracking_target): return
	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera == null or not camera.current or not _fight_base_valid: return
	var size := camera.get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0: return
	var physical := _fight_tracking_target.global_position
	var player_world := target.global_position
	# The return rail already updated in _process(), before the camera is
	# composed. Never advance it twice, including when a fish gets hooked.
	var was_travel := fishing_camera_state == FishingCameraPresentationState.TRAVEL
	var inset_owns_camera: bool = _inset_camera_owns_framing()
	var base := _water_base(_water_pan)
	base.origin += _inset_optical_pan
	var yaw: float = 0.0 if was_travel else fight_camera_tracking.yaw
	if not was_travel and not inset_owns_camera:
		var project := _project_fight_orbit.bind(_optical_pose(base,camera),camera.get_camera_projection(),player_world,physical)
		# Horizontal violations alone request yaw. Vertical framing is separate.
		var previous_yaw: float = fight_camera_tracking.yaw
		yaw = fight_camera_tracking.step(delta,project,fishing_safe_region(),fight_tracking_hysteresis,deg_to_rad(fight_max_yaw_degrees),fight_yaw_response,fight_yaw_return_response,0.0)
		var candidate_pose: Transform3D = _fight_orbit_transform(base,player_world,yaw)
		var player_uv: Vector2 = _project_fight_orbit(
			0.0,_optical_pose(candidate_pose,camera),camera.get_camera_projection(),
			player_world,player_world
		)
		if not FishingRodHandoff.is_player_projection_ready(player_uv):
			fight_camera_tracking.yaw = previous_yaw
			yaw = previous_yaw
	var pose := _fight_orbit_transform(base,player_world,yaw)
	var point := _project_fight_orbit(0.0,_optical_pose(pose,camera),camera.get_camera_projection(),player_world,physical)
	var region := fishing_safe_region()
	if was_travel and not fight_camera_tracking.inside(point,region,0.00001):
		pose = _bounded_ground_pan(pose,camera,physical,true,delta)
	# Once ANCHORED, depth/shore/HUD violations must not change distance or
	# translate the shot. Preserve diagnostics when yaw alone cannot frame it.
	if not was_travel:
		framing_constraints_feasible = fight_camera_tracking.inside(
			_project_fight_orbit(0.0,_optical_pose(pose,camera),camera.get_camera_projection(),player_world,physical),region,0.001)
	# Yaw-only fight framing is insufficient when a hooked fish surges ABOVE
	# the visible top-safe line. Move the optical window, not the physical fish.
	# The same lens correction is absent for a freely steered lure (its physical
	# projection contract is handled elsewhere).
	camera.global_transform = pose
	_update_hooked_fish_top_clearance(camera,physical,delta)
	if inset_owns_camera:
		_pan_inset_camera_to_lure(camera,_fishing_tracking_position(),size,delta)
	if was_travel:
		var projected_player := camera.unproject_position(player_world)/size
		if fight_camera_tracking.inside(projected_player,player_anchor_region(),0.00001):
			fishing_camera_state = FishingCameraPresentationState.ANCHORED
			_anchored_pan = _water_pan
	check_fishing_safe_invariant(camera.unproject_position(physical),delta,camera.is_position_behind(physical))
	# Compare orientation in the base yaw frame rather than Euler angles.
	# Compare the actual world-camera frame with the authored yaw-only pose.
	# Direct Basis.is_equal_approx() is scale/rounding-sensitive and produced
	# a red error every frame on long casts despite visually stable orientation.
	_check_fishing_tracking_orientation(camera, pose.basis)
	if fishing_camera_state == FishingCameraPresentationState.ANCHORED and not fishing_player_return_active and global_position.distance_squared_to(player_world) <= 0.000001 and not fight_camera_tracking.inside(camera.unproject_position(player_world)/size,player_anchor_region(),0.001):
		fishing_anchor_failures += 1
		if OS.is_debug_build() and not _fishing_anchor_error_reported:
			_fishing_anchor_error_reported = true
			push_error("FISHING PLAYER ANCHOR VIOLATION")

static func hooked_top_lens_target(
	projected_y: float, safe_top_y: float, pixels_per_lens_unit: float,
	max_lens_shift: float
) -> float:
	# Never move the physical bait. A positive v_offset moves the image down
	# in the verified Godot camera projection used by this fishing rig.
	if pixels_per_lens_unit <= 0.0001:
		return 0.0
	return clampf((safe_top_y-projected_y)/pixels_per_lens_unit,
		0.0,maxf(max_lens_shift,0.0))


func _update_hooked_fish_top_clearance(
	camera: Camera3D, fish_world: Vector3, delta: float
) -> void:
	# Called only while a fish is hooked / the camera tracks a non-free-lure.
	# Remove last frame's optical correction before measuring the new desired
	# correction. This avoids feeding our own shift back into the solver.
	var base_offset: float = camera.v_offset - _hooked_top_clearance_shift
	camera.v_offset = base_offset
	var screen: Vector2 = camera.unproject_position(fish_world)
	var viewport: Vector2 = camera.get_viewport().get_visible_rect().size
	if viewport.y <= 0.0:
		camera.v_offset = base_offset + _hooked_top_clearance_shift
		return
	var top_y: float = fishing_safe_region().position.y * viewport.y + hooked_top_clearance_pixels
	# Derive pixels-per-lens-unit from the real active Camera3D projection;
	# resizing, h_offset and camera yaw are already accounted for here.
	const PROBE: float = 0.10
	camera.v_offset = base_offset + PROBE
	var derivative: float = (camera.unproject_position(fish_world).y-screen.y) / PROBE
	var desired: float = hooked_top_lens_target(screen.y,top_y,derivative,
		hooked_top_clearance_max_lens_shift)
	_hooked_top_clearance_shift = move_toward(_hooked_top_clearance_shift,
		desired,maxf(hooked_top_clearance_lens_speed,0.1)*maxf(delta,0.0))
	camera.v_offset = base_offset + _hooked_top_clearance_shift


static func solve_free_d_waterline_yaw(
	current_yaw: float, project: Callable, boundary_y: float,
	delta: float, max_yaw_degrees: float, max_speed_degrees: float
) -> float:
	# Closed-loop projection control: choose the *actual* yaw direction that
	# raises the lure on-screen. The old implementation used X and assumed
	# a fixed 0.85 deg/s rotation, so it could not compensate its Y descent.
	if delta <= 0.0 or not project.is_valid():
		return current_yaw
	var current: Vector2 = project.call(current_yaw)
	if current.y <= boundary_y:
		return current_yaw
	var probe := deg_to_rad(0.5)
	var high: Vector2 = project.call(current_yaw + probe)
	var low: Vector2 = project.call(current_yaw - probe)
	var response_plus: float = high.y - current.y
	var response_minus: float = low.y - current.y
	var direction: float = 0.0
	var improvement: float = 0.0
	if response_plus < response_minus and response_plus < -0.000001:
		direction = 1.0
		improvement = -response_plus
	elif response_minus < -0.000001:
		direction = -1.0
		improvement = -response_minus
	if direction == 0.0:
		return current_yaw
	# Aim for the amount needed to restore the lower-safe frame, limited
	# to a small, explicitly authored player-pivot orbit. No teleport yaw.
	var needed: float = (current.y-boundary_y) * probe / maxf(improvement,0.000001)
	var limit: float = deg_to_rad(max_yaw_degrees)
	var target_yaw: float = clampf(current_yaw+direction*needed,-limit,limit)
	return move_toward(current_yaw,target_yaw,deg_to_rad(max_speed_degrees)*delta)


static func free_d_waterline_turn_direction(current_yaw: float, project: Callable) -> float:
	# Choose the sign using the actual world/camera projection. A hardcoded
	# clockwise sign is incorrect for different shores and casting headings.
	if not project.is_valid():
		return 0.0
	var middle: Vector2 = project.call(current_yaw)
	var probe: float = deg_to_rad(0.5)
	var plus: Vector2 = project.call(current_yaw + probe)
	var minus: Vector2 = project.call(current_yaw - probe)
	var best: float = minf(plus.y, minus.y)
	if best >= middle.y - 0.000001:
		return 0.0
	return 1.0 if plus.y <= minus.y else -1.0


static func advance_free_d_followthrough_yaw(
	current_yaw: float, direction: float, screen_y: float, boundary_y: float,
	improvement_per_radian: float, delta: float, cruise_deg: float,
	max_speed_deg: float, max_yaw_deg: float
) -> float:
	# After the first waterline crossing, do not let the feedback loop stop
	# turning just because the screen-space error momentarily becomes zero.
	# Retain a continuous gentle orbit until physical retrieval completes.
	if delta <= 0.0 or absf(direction) < 0.5:
		return current_yaw
	var speed_deg: float = minf(maxf(cruise_deg, 0.0), maxf(max_speed_deg, 0.0))
	if screen_y > boundary_y and improvement_per_radian > 0.000001:
		var error_radians: float = (screen_y - boundary_y) / improvement_per_radian
		var desired_speed_deg: float = rad_to_deg(error_radians) / delta
		speed_deg = minf(maxf(max_speed_deg, 0.0), maxf(speed_deg, desired_speed_deg))
	var cap: float = deg_to_rad(maxf(max_yaw_deg, 0.0))
	return clampf(current_yaw + signf(direction) * deg_to_rad(speed_deg) * delta, -cap, cap)


func _free_d_waterline_limit(camera: Camera3D, size: Vector2) -> float:
	# Depth-meter top edge is presentation geometry. It is allowed to move
	# the camera but is NEVER read by the bait's physics solver.
	var limit: float = 0.765
	var hud: Array[Rect2] = fishing_hud_regions_pixels()
	if hud.size() >= 2:
		limit = clampf(hud[1].position.y / size.y - 0.008,0.45,0.90)
	elif hud.size() == 1:
		limit = clampf(hud[0].position.y / size.y - 0.008,0.45,0.90)
	if not hud.is_empty():
		# The green-arc/red-line trigger sits roughly a BAR HEIGHT above
		# the power bar, rather than at the already-obscured gauge pixels.
		limit = minf(limit,clampf((hud[0].position.y - hud[0].size.y*1.1)/size.y,0.40,0.90))
	return limit


## Compute the BOF4 red frame from the *rendered* HUD. Widths/gaps scale
## together with the actual bar art, and positions follow the existing responsive
## layout. In cramped windows gaps shrink proportionally before constraining the
## visual lure; they never modify the physical bait or any UI element.
static func inset_region_from_hud_pixels(
	viewport_size: Vector2, bar: Rect2, meter: Rect2, character: Rect2,
	left_gap: float, right_gap: float, bottom_gap: float, band_height: float
) -> Rect2:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or bar.size.x <= 0.0:
		return Rect2()
	var hud_unit: float = bar.size.x
	var left_space: float = maxf(0.0,left_gap)*hud_unit
	var right_space: float = maxf(0.0,right_gap)*hud_unit
	var corridor: float = meter.position.x-character.end.x
	var minimum_width: float = maxf(12.0,hud_unit*0.12)
	if corridor < minimum_width:
		return Rect2() # HUD itself overlaps: no honest inset band exists.
	if left_space+right_space > corridor-minimum_width:
		var fraction: float = maxf(0.0,(corridor-minimum_width)/maxf(left_space+right_space,0.001))
		left_space *= fraction
		right_space *= fraction
	var left: float = maxf(character.end.x+left_space,viewport_size.x*0.015)
	var right: float = minf(meter.position.x-right_space,viewport_size.x*0.985)
	var bottom: float = minf(bar.position.y-maxf(0.0,bottom_gap)*hud_unit,viewport_size.y*0.985)
	var top: float = maxf(bottom-maxf(0.0,band_height)*hud_unit,viewport_size.y*0.015)
	if right-left < 8.0 or bottom-top < 8.0:
		return Rect2()
	return Rect2(Vector2(left,top),Vector2(right-left,bottom-top))


func _hud_canvas_rect(visual: CanvasItem) -> Rect2:
	if not is_instance_valid(visual):
		return Rect2()
	# Hidden HUD widgets still define the upcoming inset rest geometry.
	var local: Rect2
	if visual is Sprite2D:
		local = (visual as Sprite2D).get_rect()
	elif visual is Control:
		var widget := visual as Control
		local = Rect2(Vector2.ZERO,widget.size)
	else:
		return Rect2()
	return visual.get_global_transform_with_canvas()*local


func _hud_rest_rect(visual: CanvasItem, owner: Node, animated_control: Control) -> Rect2:
	var rect: Rect2 = _hud_canvas_rect(visual)
	if not rect.has_area():
		return rect
	# The HUD slides into place when K is pressed. Measuring its transient
	# 220-pixel slide (or a meter arriving from the right) moves the red box
	# while the bait is already in water. Always use the final responsive
	# REST position set by PowerMeterView, not the animated display position.
	if is_instance_valid(animated_control) and animated_control.has_method("set_layout_rest"):
		var resting: Vector2 = animated_control.get("rest_position")
		rect.position += resting - animated_control.position
	elif is_instance_valid(owner) and owner.has_method("_update_viewport_layout"):
		var root: Control = owner.get_node_or_null("Root") as Control
		if root != null:
			var resting: Vector2 = owner.get("_rest_position")
			rect.position += resting - root.position
	return rect


func _inset_artwork_rect() -> Rect2:
	if not is_instance_valid(_inset_view):
		return Rect2()
	var grid := _inset_view.get_node_or_null("Grid") as CanvasItem
	var result: Rect2 = _hud_rest_rect(grid,null,_inset_view)
	# Include the actual animated rod/body artwork if it extends beyond the
	# inset's frame. Its frame texture supplies a conservative pixel footprint.
	var character := _inset_view.get_node_or_null("Character") as AnimatedSprite2D
	if character != null and character.sprite_frames != null:
		var texture: Texture2D = character.sprite_frames.get_frame_texture(character.animation,character.frame)
		if texture != null:
			var dimension: Vector2 = texture.get_size()
			var art: Rect2 = Rect2(-dimension*0.5 if character.centered else Vector2.ZERO,dimension)
			var drawn: Rect2 = character.get_global_transform_with_canvas()*art
			var rest: Vector2 = _inset_view.get("rest_position")
			drawn.position += rest - _inset_view.position
			result = result.merge(drawn) if result.has_area() else drawn
	return result


func _inset_follow_region_for_camera(camera: Camera3D) -> Rect2:
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var fallback: Rect2 = inset_follow_region(
		inset_follow_left,inset_follow_right,
		inset_follow_top,inset_follow_bottom,fishing_safe_region())
	# Keep the fallback responsive too: the ceiling is 7% of the height above
	# midline, independent of the length of the power-bar sprite.
	var fallback_bottom: float = fallback.end.y
	fallback = Rect2(Vector2(fallback.position.x,0.43),
		Vector2(fallback.size.x,maxf(0.04,fallback_bottom-0.43)))
	if size.x <= 0.0 or size.y <= 0.0 or fishing_hud_geometry.size() < 2:
		return fallback
	var bar: Rect2 = _hud_rest_rect(fishing_hud_geometry[0],_power_hud_view,null)
	var meter: Rect2 = _hud_rest_rect(fishing_hud_geometry[1],null,_depth_hud_view as Control)
	var grid: CanvasItem = null
	if is_instance_valid(_inset_view):
		grid = _inset_view.get_node_or_null("Grid") as CanvasItem
	var character: Rect2 = _hud_rest_rect(grid,null,_inset_view)
	# Before the HUD elements finish entering the scene use the existing
	# fallback. Once all three are drawn, there is no hardcoded UV rectangle.
	if not bar.has_area() or not meter.has_area() or not character.has_area():
		return fallback
	var pixel_frame: Rect2 = inset_region_from_hud_pixels(
		size,bar,meter,character,inset_left_gap_bar_width,
		inset_right_gap_bar_width,inset_bottom_gap_bar_width,inset_height_bar_width)
	# The grid gives the BOF4 authored spacing. The animation may extend its
	# fishing rod beyond that grid; never let the bait cross the rod artwork.
	var artwork: Rect2 = _inset_artwork_rect()
	if pixel_frame.has_area() and artwork.has_area():
		var painted_left: float = maxf(pixel_frame.position.x,artwork.end.x+bar.size.x*0.01)
		if painted_left < pixel_frame.end.x-8.0:
			pixel_frame = Rect2(Vector2(painted_left,pixel_frame.position.y),
				Vector2(pixel_frame.end.x-painted_left,pixel_frame.size.y))
		else:
			pixel_frame = Rect2()
	if not pixel_frame.has_area():
		if not _inset_hud_geometry_error_reported:
			_inset_hud_geometry_error_reported = true
			push_error("FISHING INSET HUD GEOMETRY CONFLICT: no red box between character, power bar and depth meter")
		return fallback
	_inset_hud_geometry_error_reported = false
	# The bar-width-height rectangle used in earlier gates was too SHORT.
	# Extend upward to the requested responsive midline-relative ceiling,
	# leaving the lower edge anchored above the power bar.
	var bottom_uv: float = pixel_frame.end.y / size.y
	var top_uv: float = 0.43
	if bottom_uv - top_uv <= 0.015:
		return fallback
	return Rect2(Vector2(pixel_frame.position.x / size.x,top_uv),
		Vector2(pixel_frame.size.x / size.x,bottom_uv-top_uv))


## Lower Y on screen is higher visually. Never allow the red region's upper
## edge ABOVE the gameplay midpoint, even on short/tall responsive windows.
## This does not extend the bottom toward the bar or change lure physics.
static func clamp_inset_ceiling(frame: Rect2, ceiling_uv: float) -> Rect2:
	if not frame.has_area():
		return frame
	var top: float = maxf(frame.position.y,ceiling_uv)
	var bottom: float = frame.end.y
	if bottom-top <= 0.01:
		# Keep a nonempty safe region even on tiny windows. The caller already
		# reports impossible HUD geometry; a degenerate box would pan erratically.
		top = maxf(frame.position.y,bottom-0.01)
	return Rect2(Vector2(frame.position.x,top),Vector2(frame.size.x,bottom-top))


## Flight and water share the exact same horizontal and top boundaries.
## The lower edge starts generous during airborne travel, then converges to
## the WATER boundary as altitude approaches zero. A distinct 95% -> water
## edge on the contact frame caused the visible splashdown camera jump.
static func flight_follow_region(inset: Rect2, ceiling_uv: float, approach_weight: float = 1.0) -> Rect2:
	var top: float = ceiling_uv
	var bottom: float = lerpf(inset.end.y,0.95,clampf(approach_weight,0.0,1.0))
	return Rect2(Vector2(inset.position.x,top),
		Vector2(inset.size.x,maxf(0.01,bottom-top)))


## Screen-space target bands belong only to the camera. This never changes
## bait movement, the authored fishing HUD or the window's resolution.
static func inset_follow_region(
	left: float, right: float, top: float, bottom: float,
	hard: Rect2
) -> Rect2:
	var safe_left: float = clampf(left, hard.position.x + 0.01, hard.end.x - 0.04)
	var safe_right: float = clampf(right, safe_left + 0.02, hard.end.x - 0.01)
	var safe_top: float = clampf(top, hard.position.y + 0.01, hard.end.y - 0.04)
	var safe_bottom: float = clampf(bottom, safe_top + 0.02, hard.end.y - 0.01)
	return Rect2(Vector2(safe_left,safe_top),Vector2(safe_right-safe_left,safe_bottom-safe_top))


## Central response region lives INSIDE the immutable hard red area.
## When motion is slow, we follow toward this smaller comfort region.
## When motion is fast, we must first satisfy the hard outer region now.
static func inset_comfort_region(hard: Rect2, margin: float) -> Rect2:
	var m: float = minf(maxf(margin, 0.0), minf(hard.size.x, hard.size.y)*0.45)
	return Rect2(hard.position + Vector2(m,m), hard.size - Vector2(m,m)*2.0)


func _inset_camera_owns_framing() -> bool:
	# A past visibility event cannot retire the inset for the whole cast.
	# Camera travel can take the REAL actor out of frame again (particularly
	# on a long throw or after a desktop resize). The HUD and camera use the
	# same final projected-artwork condition every frame.
	var actor_visible: bool = _is_fishing_player_inside_frame()
	if not actor_visible:
		_real_player_view_engaged = false
	elif not _real_player_view_engaged:
		_real_player_view_engaged = true
		_inset_pan_handoff_world = _inset_optical_pan
		_inset_handoff_distance = maxf(_get_flat_player_distance(_fishing_tracking_position()),
			fishing_player_return_end_distance + 0.001)
		if fishing_follow_has_reached_water and not fishing_player_camera_locked:
			begin_fishing_player_return()
	return not actor_visible


func is_inset_presentation_active() -> bool:
	return _inset_camera_owns_framing()



func _pan_inset_camera_to_lure(camera: Camera3D, surface_bait: Vector3, size: Vector2, delta: float = -1.0, during_flight: bool = false, flight_frame: Rect2 = Rect2()) -> void:
	# Screen-plane projection: a correction along the camera's local X/Y
	# translates the visible water-contact point without yaw, zoom or changing
	# its forward depth. Ground-plane ray intersections could be unavailable near
	# the horizon and silently abandon the top/corner safety requirements.
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var hard: Rect2 = (flight_frame if during_flight and flight_frame.has_area()
		else _inset_follow_region_for_camera(camera))
	var comfort: Rect2 = inset_comfort_region(hard,inset_follow_preemptive_margin)
	var point: Vector2 = camera.unproject_position(surface_bait)/size
	var behind: bool = camera.is_position_behind(surface_bait)
	if not behind and comfort.has_point(point):
		return
	var target_uv: Vector2 = comfort.get_center() if behind else Vector2(
		clampf(point.x,comfort.position.x,comfort.end.x),
		clampf(point.y,comfort.position.y,comfort.end.y))
	var local_point: Vector3 = camera.global_transform.affine_inverse()*surface_bait
	var depth: float = -local_point.z
	if depth <= camera.near + 0.001:
		# A behind-camera target is not solvable by 2D pan. Report it rather than
		# pretending a ray/water-plane intersection succeeded.
		_report_inset_containment_failure(camera,surface_bait,hard,"behind camera")
		return
	var projected_world: Vector3 = camera.project_position(target_uv*size,depth)
	var correction: Vector3 = surface_bait-projected_world
	if not correction.is_finite():
		_report_inset_containment_failure(camera,surface_bait,hard,"non-finite correction")
		return
	# During flight there is NO red-box invariant yet: the inset is hidden.
	# Pre-align toward the future landing box smoothly rather than making a
	# single large camera jump in the last 0.4 m above the water. When inset
	# ownership begins at splashdown, the hard same-frame guard resumes.
	var motion: Vector3 = correction
	if during_flight:
		# Casting never receives an unbounded one-frame camera correction.
		# Earlier activation avoids the huge late-splash correction that made
		# the accepted casting arc appear to jump in Gates 15 and 16.
		motion = correction.limit_length(inset_follow_pan_speed*maxf(delta,0.0))
	elif delta >= 0.0 and hard.has_point(point):
		var limit: float = minf(inset_follow_max_step_world,
			inset_follow_pan_speed*maxf(delta,0.0))
		motion = correction.limit_length(limit)
	elif delta < 0.0 and hard.has_point(point):
		motion = correction.limit_length(inset_follow_max_step_world)
	if not _fight_base_valid and fishing_follow_active:
		_airborne_inset_pan += motion
		global_position += motion
	else:
		_inset_optical_pan += motion
		camera.global_position += motion
	if not during_flight and hard.grow(0.00001).has_point(camera.unproject_position(surface_bait)/size):
		_inset_containment_violation_active = false
	if not during_flight and not hard.grow(0.00001).has_point(camera.unproject_position(surface_bait)/size):
		# A partial comfort move is valid only when still within the hard bounds.
		if not hard.has_point(point):
			_report_inset_containment_failure(camera,surface_bait,hard,"pan did not converge")


func _report_inset_containment_failure(camera: Camera3D, point: Vector3, hard: Rect2, why: String) -> void:
	# Count the incident and preserve the failure, but do not issue the same red
	# debugger error 30 times/second while one unresolved frame state persists.
	if _inset_containment_violation_active:
		return
	_inset_containment_violation_active = true
	inset_containment_failures += 1
	if OS.is_debug_build():
		push_error("FISHING INSET CONTAINMENT VIOLATION: %s projected=%s bounds=%s" % [
			why,camera.unproject_position(point)/camera.get_viewport().get_visible_rect().size,hard])



## Two deliberately different camera modes: a tight translated inset band and
## a wider yaw-only band once the real rod is visible. No physical bait changes.
static func free_lure_rotation_region(hard: Rect2, waterline: float, anticipation: float) -> Rect2:
	var left: float = clampf(0.24, hard.position.x + 0.01, hard.end.x - 0.04)
	var right: float = clampf(0.80, left + 0.02, hard.end.x - 0.01)
	var bottom: float = clampf(minf(0.75,waterline - anticipation), hard.position.y + 0.05, hard.end.y + 0.06)
	return Rect2(Vector2(left,hard.position.y),Vector2(right-left,bottom-hard.position.y))


static func free_lure_rotation_error(point: Vector2, band: Rect2) -> float:
	var dx: float = point.x - clampf(point.x,band.position.x,band.end.x)
	var dy: float = maxf(0.0,point.y-band.end.y)
	return Vector2(dx,dy).length()


static func free_lure_outside_rotation_region(point: Vector2, band: Rect2) -> bool:
	return free_lure_rotation_error(point,band) > 0.00001


static func free_lure_rotation_turn_direction(yaw: float, project: Callable, band: Rect2) -> float:
	# Choose the yaw sign that *actually reduces* the boundary error in the
	# active camera projection. This is equally valid for left and right arcs.
	var probe: float = deg_to_rad(0.5)
	var center: Vector2 = project.call(yaw)
	var plus: Vector2 = project.call(yaw+probe)
	var minus: Vector2 = project.call(yaw-probe)
	var now: float = free_lure_rotation_error(center,band)
	var positive: float = free_lure_rotation_error(plus,band)
	var negative: float = free_lure_rotation_error(minus,band)
	if positive >= now - 0.000001 and negative >= now - 0.000001:
		return 0.0
	return 1.0 if positive <= negative else -1.0


func _update_free_lure_camera_tracking(delta: float) -> void:
	# The character inset tracks by pan; once the rod is truly visible,
	# A and D BOTH use a rotation-only player-pivot follow-through.
	# Free-lure physical arcs remain untouched.
	if not _fight_tracking_active or not is_instance_valid(_fight_tracking_target):
		return
	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera == null or not camera.current or not _fight_base_valid or target == null:
		return
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var player_world: Vector3 = target.global_position
	var surface_bait: Vector3 = _fishing_tracking_position()
	# _update_fishing_follow() is the SINGLE owner of the return rail.
	# Calling it again here used to apply two positional corrections per frame,
	# and could force a jump even while the CharacterView inset was visible.
	# Keep the same latched pan if a resolved fight hands back an empty lure.
	var base: Transform3D = _water_base(_water_pan)
	base.origin += _inset_optical_pan
	var projection: Projection = camera.get_camera_projection()
	var project: Callable = _project_fight_orbit.bind(
		_optical_pose(base,camera),projection,player_world,surface_bait
	)

	# Orbiting waits for real water travel; the inset's red-box containment
	# is independent and may correct even on the first splashdown frame.
	if not _water_tracking_has_moved:
		var delta_flat := Vector2(
			surface_bait.x-_water_contact_bait_position.x,
			surface_bait.z-_water_contact_bait_position.z
		)
		_water_tracking_has_moved = delta_flat.length_squared() > 0.09*0.09

	var yaw: float = fight_camera_tracking.yaw
	var inset_owns_camera: bool = _inset_camera_owns_framing()
	if _water_tracking_has_moved and not inset_owns_camera:
		var point: Vector2 = project.call(yaw)
		var steering: float = 0.0
		if _fight_tracking_target.has_method("get_reel_steering_for_camera"):
			steering = float(_fight_tracking_target.call("get_reel_steering_for_camera"))
		var sign_now: float = signf(steering) if absf(steering) > 0.5 else 0.0
		# In real-Ryu view, the lure may move a little farther than in the
		# inset box. The lower edge remains above the actual power bar.
		var near_band: Rect2 = free_lure_rotation_region(
			fishing_safe_region(), _free_d_waterline_limit(camera,size),
			free_d_waterline_anticipation
		)
		if sign_now != 0.0 and sign_now != _free_orbit_steering_sign:
			# Switching A <-> D must change direction, not reuse the other
			# side's latched yaw sign or force the bait to move sideways.
			_free_d_orbit_engaged = false
			_free_d_orbit_direction = 0.0
		if sign_now != 0.0:
			_free_orbit_steering_sign = sign_now
		if not free_lure_outside_rotation_region(point,near_band):
			# The red/wider screen band is a boundary, not a continuous
			# auto-orbit request. Stop yaw once the lure is safely back.
			_free_d_orbit_engaged = false
			_free_d_orbit_direction = 0.0
		if sign_now != 0.0 and not _free_d_orbit_engaged and free_lure_outside_rotation_region(point,near_band):
			var direction: float = free_lure_rotation_turn_direction(yaw,project,near_band)
			if direction != 0.0:
				_free_d_orbit_engaged = true
				_free_d_orbit_direction = direction
		if sign_now != 0.0 and _free_d_orbit_engaged:
			# Shared A/D orbit: solve horizontal and lower-edge violations
			# with projection feedback, while preserving continuous follow-through
			# after the bait re-enters the allowed area.
			var probe: float = deg_to_rad(0.5)
			var rotated: Vector2 = project.call(yaw + _free_d_orbit_direction * probe)
			var violation: float = free_lure_rotation_error(point,near_band)
			var improved: float = free_lure_rotation_error(rotated,near_band)
			var response: float = maxf(0.0,(violation-improved)/probe)
			var proposed_yaw: float = advance_free_d_followthrough_yaw(
				yaw, _free_d_orbit_direction, violation, 0.0,
				response, delta, free_d_waterline_cruise_degrees,
				free_d_waterline_max_speed_degrees,
				free_d_waterline_max_yaw_degrees
			)
			# Never sacrifice real-Ryu visibility just to chase the lure. The
			# camera is not permitted to pan after this handoff, so reject
			# yaw that would push his body out of the actual scene viewport.
			var trial_player_uv: Vector2 = _project_fight_orbit(
				0.0, _optical_pose(
					_fight_orbit_transform(base, player_world, proposed_yaw), camera
				), projection, player_world, player_world
			)
			if FishingRodHandoff.is_player_projection_ready(trial_player_uv):
				yaw = proposed_yaw
				fight_camera_tracking.yaw = yaw
		# No translation/dolly or physical lure corrections in real-Ryu view.

	var intended_pose := _fight_orbit_transform(base,player_world,yaw)
	camera.global_transform = intended_pose
	if inset_owns_camera:
		_pan_inset_camera_to_lure(camera, surface_bait, size, delta)
		# A translated camera is still an authored yaw/pitch pose, so the
		# orientation diagnostic must compare its basis, not its position.
	fishing_camera_state = FishingCameraPresentationState.ANCHORED
	framing_constraints_feasible = true

	# Existing diagnostics remain. The yellow rectangle is an overlay; it
	# does not authorize moving the fisherman or hiding a framing failure.
	var projected_bait: Vector2 = camera.unproject_position(surface_bait)
	check_fishing_safe_invariant(
		projected_bait,delta,camera.is_position_behind(surface_bait)
	)
	var projected_player: Vector2 = camera.unproject_position(player_world)/size
	# During a long-cast return, Ryu is intentionally outside the view and
	# the character inset represents him. Check the authored anchor only
	# after the camera has actually come home.
	if not fishing_player_return_active and global_position.distance_squared_to(player_world) <= 0.000001 and not fight_camera_tracking.inside(projected_player,player_anchor_region(),0.001):
		fishing_anchor_failures += 1
		if OS.is_debug_build() and not _fishing_anchor_error_reported:
			_fishing_anchor_error_reported = true
			push_error("FISHING PLAYER ANCHOR VIOLATION")
	_check_fishing_tracking_orientation(camera, intended_pose.basis)

func _check_fishing_tracking_orientation(camera: Camera3D, expected_basis: Basis) -> void:
	# Test directions, not raw matrix components: harmless parent scale or
	# floating-point reparenting must not be reported as pitch/roll movement.
	var actual := camera.global_basis.orthonormalized()
	var expected := expected_basis.orthonormalized()
	var up_dot := clampf(actual.y.normalized().dot(expected.y.normalized()), -1.0, 1.0)
	var forward_dot := clampf(actual.z.normalized().dot(expected.z.normalized()), -1.0, 1.0)
	var deviation := rad_to_deg(maxf(acos(up_dot), acos(forward_dot)))
	if deviation <= fishing_rotation_diagnostic_tolerance_degrees:
		return
	# Genuine orientation mismatch remains a QA failure; only the duplicated
	# push_error per frame is suppressed. Never hide the counter or adjust the lens.
	fishing_rotation_failures += 1
	if not _fishing_rotation_error_reported and OS.is_debug_build():
		_fishing_rotation_error_reported = true
		push_error("FISHING TRACKING PITCH/ROLL VIOLATION: %.3f deg (max %.3f deg)" % [deviation, fishing_rotation_diagnostic_tolerance_degrees])


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
	var region: Rect2 = fishing_safe_region_pixels()
	# Free-lure physical steering already enforces the tighter BOF retrieve
	# corridor. This camera's old 30-70% QA rectangle is a *tracking*
	# reference, not a valid reason to emit a red runtime error when the
	# visible lure crosses it. Still reject off-screen bait and any descent
	# into the real power bar; preserve the original invariant for hooked
	# fish and QA targets.
	if not _real_player_view_engaged and fishing_follow_has_reached_water and _fight_tracking_active:
		var inset: Rect2 = _inset_follow_region_for_camera($Camera3D)
		var size: Vector2 = $Camera3D.get_viewport().get_visible_rect().size
		var inset_pixels := Rect2(inset.position*size,inset.size*size)
		if behind or not inset_pixels.grow(0.05).has_point(point):
			_report_inset_containment_failure($Camera3D,_fishing_tracking_position(),inset,"frame check")
		else:
			_inset_containment_violation_active = false
		return
	if _tracks_free_lure():
		var viewport_size: Vector2 = $Camera3D.get_viewport().get_visible_rect().size
		var normalized := free_lure_viewport_region()
		region = Rect2(normalized.position*viewport_size,normalized.size*viewport_size)
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
	_inset_optical_pan = Vector3.ZERO
	_water_dolly = 0.0
	_anchored_pan = Vector2.ZERO
	_fight_base_valid = false
	_fishing_rotation_error_reported = false
	_fishing_anchor_error_reported = false
	_water_tracking_has_moved = false
	_water_contact_bait_position = Vector3.ZERO
	_fight_tracking_active = false
	_fight_tracking_target = null
	_hooked_top_clearance_shift = 0.0
	_free_d_orbit_engaged = false
	_free_d_orbit_direction = 0.0
	_free_orbit_steering_sign = 0.0
	fight_camera_tracking.reset()

func arm_fishing_follow(
	track_target: Node3D,
	cast_direction: Vector3,
	water_y: float
) -> void:
	if not is_instance_valid(track_target):
		return
	_stop_fishing_follow_return(false)
	_free_d_orbit_engaged = false
	_free_d_orbit_direction = 0.0
	_free_orbit_steering_sign = 0.0
	_inset_pan_at_return = Vector2.ZERO
	_inset_pan_release_started = false
	_inset_pan_release_start_progress = 0.0
	_inset_containment_violation_active = false
	_real_player_view_engaged = false
	_inset_hud_geometry_error_reported = false
	# Follow ONLY when the airborne lure crosses the authored tracking
	# boundary. Short casts leave the player frame untouched; long casts
	# carry the camera forward and may reveal the character-view inset.
	# The water handoff preserves the last airborne camera pose.
	fishing_follow_target = track_target
	fishing_follow_direction = Vector3(cast_direction.x,0.0,cast_direction.z).normalized()
	fishing_follow_cast_origin = track_target.global_position
	fishing_follow_water_y = water_y
	fishing_follow_base_position = global_position
	_airborne_inset_pan = Vector3.ZERO
	_inset_optical_pan = Vector3.ZERO
	# A quick cancel returns to the angle at which the player actually cast,
	# not the unrelated fishing-entry heading before pre-cast A/D aiming.
	_fishing_cast_start_yaw = rotation.y
	_cast_home_camera_local = $Camera3D.transform
	_cast_home_camera_offsets = Vector2($Camera3D.h_offset,$Camera3D.v_offset)
	_cast_home_rig_position = global_position
	_cast_home_pose_valid = true
	_inset_handoff_distance = 0.0
	_inset_pan_handoff_world = Vector3.ZERO
	_fishing_cast_start_valid = true
	# Establish the home player pixel once, while the rig is still at the
	# approved fishing composition (Ryu lower-left).
	var follow_camera := get_node_or_null("Camera3D") as Camera3D
	if follow_camera != null and target != null:
		var viewport_size := follow_camera.get_viewport().get_visible_rect().size
		if viewport_size.x > 0.0 and viewport_size.y > 0.0:
			fishing_player_anchor = follow_camera.unproject_position(target.global_position) / viewport_size + player_anchor_offset
	fishing_follow_activation_progress = 0.0
	fishing_follow_activation_height = 0.0
	fishing_follow_offset = 0.0
	fishing_follow_armed = true
	fishing_follow_active = false
	fishing_player_return_active = false
	fishing_follow_has_reached_water = false
	fishing_player_camera_locked = false

func notify_fishing_target_landed() -> void:
	# Fishing owns the gameplay phase, so it tells the camera exactly when the
	# cast has entered the water. This avoids guessing from lure depth and makes
	# the camera handoff deterministic on every cast, including consecutive casts.
	fishing_follow_has_reached_water = true
	_try_begin_fishing_player_return()


func begin_fishing_player_return() -> void:
	# Once the REAL rod is visible, camera translation is over for this cast.
	# A and D may rotate the shot while the lure keeps arcing back to Ryu.
	# Do NOT run a distance-driven positional rail while the lure is active:
	# that was returning the camera to the starting view before the bait left.
	if target == null or fishing_player_camera_locked:
		return
	fishing_player_camera_locked = true
	fishing_follow_armed = false
	fishing_follow_active = false
	# Once the first real-character pixel appears, return toward the actor
	# WITH the lure, not suddenly after it disappears. The length of this rail
	# is defined by remaining lure distance, so K/A/D all converge at home.
	fishing_player_return_active = true
	fishing_player_return_start_camera_position = global_position
	fishing_player_return_start_distance = maxf(
		_get_flat_player_distance(_fishing_tracking_position()),
		fishing_player_return_end_distance + 0.001)
	fishing_player_return_progress = 0.0
	_inset_pan_handoff_world = _inset_optical_pan
	_inset_handoff_distance = fishing_player_return_start_distance
	_inset_pan_release_started = true
	_inset_pan_at_return = _water_pan
	_inset_pan_release_start_progress = 0.0


func reset_fishing_follow() -> void:
	_clear_fight_camera_tracking()
	fishing_player_camera_locked = false
	_stop_fishing_follow_return(false)
	_clear_fishing_follow_state()

	if target != null:
		global_position = target.global_position


func return_fishing_follow_to_target(completed_retrieve: bool = false) -> void:
	# Handoff point is where the camera happens to be when the bait disappears.
	# It must NEVER be mistaken for the next casting pose.
	fishing_aim_active = false
	var camera: Camera3D = $Camera3D
	var current_world: Transform3D = camera.global_transform
	var current_offsets: Vector2 = Vector2(camera.h_offset,camera.v_offset)
	var home_local: Transform3D = _cast_home_camera_local if _cast_home_pose_valid else camera.transform
	var home_offsets: Vector2 = _cast_home_camera_offsets if _cast_home_pose_valid else current_offsets
	var home_rig_pos: Vector3 = _cast_home_rig_position if _cast_home_pose_valid else (target.global_position if target != null else global_position)
	# Never let old water/framing writes run during the recovery transition.
	_clear_fight_camera_tracking(false)
	fishing_player_camera_locked = false
	_clear_fishing_follow_state()
	_stop_fishing_follow_return(false)
	_retrieve_return_duration = (completed_reel_camera_return_seconds if completed_retrieve
		else quick_cancel_camera_return_time)
	_start_aim_heading_return(_retrieve_return_duration)
	_retrieve_start_camera_world = current_world
	_retrieve_base_transform = home_local
	_retrieve_start_offsets = current_offsets
	_retrieve_end_offsets = home_offsets
	_retrieve_start_world_position = global_position
	_retrieve_end_world_position = home_rig_pos
	_retrieve_yaw_return_elapsed = 0.0
	fishing_camera_state = FishingCameraPresentationState.RETRIEVE_RETURN
	_retrieve_yaw_return_active = true
	fishing_follow_returning = true
	if _retrieve_return_duration <= 0.001:
		_finish_fishing_follow_return()


## Public read-only state for Fishing. AIM is held until ALL camera degrees
## of freedom (tracked child yaw, parent yaw and return translation) finish.
func restore_fishing_camera_during_fade() -> void:
	# Called only when the result overlay has FULLY covered the game. A
	# visible 1.5-second recovery after hook-off/line-break was incorrect.
	# Restore the complete camera rig and optical pose atomically under black.
	fishing_aim_active = false
	_stop_fishing_follow_return(false)
	_clear_fight_camera_tracking(true)
	_clear_fishing_follow_state()
	fishing_player_camera_locked = false
	_real_player_view_engaged = false
	if _cast_home_pose_valid:
		global_position = _cast_home_rig_position
		$Camera3D.transform = _cast_home_camera_local
		$Camera3D.h_offset = _cast_home_camera_offsets.x
		$Camera3D.v_offset = _cast_home_camera_offsets.y
	elif target != null:
		global_position = target.global_position
	if _fishing_cast_start_valid:
		rotation.y = _fishing_cast_start_yaw
	elif _fishing_neutral_yaw_valid:
		rotation.y = _fishing_neutral_yaw
	fishing_camera_state = FishingCameraPresentationState.ANCHORED


func is_fishing_aim_return_complete() -> bool:
	return (
		not _retrieve_yaw_return_active
		and not _aim_heading_return_active
		and not fishing_follow_returning
	)


func _start_aim_heading_return(duration: float) -> void:
	_aim_heading_return_elapsed = 0.0
	_aim_heading_return_duration = maxf(duration, 0.001)
	_aim_heading_return_start = rotation.y
	var restore_yaw: float = _fishing_cast_start_yaw if _fishing_cast_start_valid else _fishing_neutral_yaw
	_aim_heading_return_active = (
		(_fishing_cast_start_valid or _fishing_neutral_yaw_valid)
		and absf(wrapf(restore_yaw - rotation.y, -PI, PI))
			> deg_to_rad(retrieve_yaw_stop_degrees)
	)
	if not _aim_heading_return_active and (_fishing_cast_start_valid or _fishing_neutral_yaw_valid):
		rotation.y = restore_yaw


func _update_aim_heading_return(delta: float) -> void:
	if not _aim_heading_return_active:
		return
	_aim_heading_return_elapsed += maxf(delta, 0.0)
	var amount: float = completed_reel_return_ease(
		_aim_heading_return_elapsed, _aim_heading_return_duration
	)
	var restore_yaw: float = _fishing_cast_start_yaw if _fishing_cast_start_valid else _fishing_neutral_yaw
	rotation.y = lerp_angle(_aim_heading_return_start, restore_yaw, amount)
	if amount >= 1.0:
		rotation.y = restore_yaw
		_aim_heading_return_active = false


func _clear_fishing_follow_state() -> void:
	fishing_follow_target = null

	fishing_follow_direction = Vector3.ZERO
	fishing_follow_cast_origin = Vector3.ZERO
	fishing_follow_base_position = Vector3.ZERO
	_airborne_inset_pan = Vector3.ZERO

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


static func completed_reel_return_ease(elapsed: float, duration: float) -> float:
	var t: float = clampf(elapsed/maxf(duration,0.001),0.0,1.0)
	return t*t*(3.0-2.0*t)


func _update_retrieve_yaw(delta: float) -> void:
	if not _retrieve_yaw_return_active:
		return
	_retrieve_yaw_return_elapsed += maxf(delta,0.0)
	var progress: float = completed_reel_return_ease(
		_retrieve_yaw_return_elapsed,_retrieve_return_duration)
	# Advance rig translation and parent yaw with one clock. The optical
	# camera path interpolates from the ACTUAL outgoing lens transform to the
	# exact original cast-local pose in the currently rotating parent.
	global_position = _retrieve_start_world_position.lerp(_retrieve_end_world_position,progress)
	var camera: Camera3D = $Camera3D
	var final_world: Transform3D = global_transform * _retrieve_base_transform
	camera.global_transform = _retrieve_start_camera_world.interpolate_with(final_world,progress)
	var offsets: Vector2 = _retrieve_start_offsets.lerp(_retrieve_end_offsets,progress)
	camera.h_offset = offsets.x
	camera.v_offset = offsets.y
	if _retrieve_yaw_return_elapsed >= _retrieve_return_duration:
		_finish_fishing_follow_return()


func _finish_fishing_follow_return() -> void:
	_finish_retrieve_yaw_return()
	fishing_follow_returning = false
	_fishing_follow_return_tween = null

	global_position = _retrieve_end_world_position


func _finish_retrieve_yaw_return() -> void:
	if _retrieve_yaw_return_active:
		$Camera3D.transform = _retrieve_base_transform
		$Camera3D.h_offset = _retrieve_end_offsets.x
		$Camera3D.v_offset = _retrieve_end_offsets.y
		_retrieve_yaw_return_active = false


func _stop_fishing_follow_return(snap_to_target: bool, restore_yaw: bool = true) -> void:
	_aim_heading_return_active = false
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


func _update_fishing_follow(delta: float = 0.0) -> bool:
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
			# No pan after real-Ryu handoff. Active water framing is rotation
			# only, even when the character is fully visible in the scene.
			if target != null and not _fight_tracking_active:
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

	# The physical bait may reach water BEFORE the throw animation switches
	# the fishing phase to IN_WATER. Do not guess a landing here and reclaim
	# the camera before _enter_in_water() has captured the airborne pose.
	# The only geometry fallback runs AFTER water tracking is active.
	if (
		_fight_tracking_active
		and not fishing_follow_has_reached_water
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

			# G18: Following starts at halfway up the viewport or before the
			# far-right HUD boundary, never after the lure reaches the top icons.
			# The physical cast and approved line arc remain unchanged.
			if (
				# Begin the forward follow while there is still room to pan
				# smoothly before the hard rectangle's right/top boundaries.
				(screen_position.x >= right_limit_x - viewport_width * 0.06
					or actual_screen_position.x >= right_limit_x - viewport_width * 0.06)
				or actual_screen_position.y <= top_limit_y + viewport_height * 0.12
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
			+ _airborne_inset_pan
	)

	# G18: Track the ACTUAL airborne bait as soon as the camera starts its
	# follow, whether Ryu is still partially visible or already offscreen.
	# The previous 'surface_bait.y = water_y' ignored the height of the cast,
	# allowing it to sail near the top HUD. Flight uses the same HUD-anchored
	# horizontal bounds, a half-screen ceiling, and an expanded lower edge.
	# No bait/world physics or scene/HUD positions are modified.
	if not fishing_follow_has_reached_water:
		var viewport_size: Vector2 = $Camera3D.get_viewport().get_visible_rect().size
		var inset_box: Rect2 = _inset_follow_region_for_camera($Camera3D)
		# Converge the FLIGHT lower edge to the water region BEFORE splashdown.
		# Slow playback gives the bounded camera response enough time to arrive.
		var altitude: float = maxf(0.0,current_position.y-fishing_follow_water_y)
		var flight_box: Rect2 = flight_follow_region(inset_box,fishing_follow_top_y_ratio,
			clampf(altitude/2.5,0.0,1.0))
		_pan_inset_camera_to_lure($Camera3D,current_position,viewport_size,delta,true,flight_box)
	else:
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


func is_real_player_handoff_ready() -> bool:
	return fishing_follow_has_reached_water and _is_fishing_player_inside_frame()


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
		var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
		return FishingRodHandoff.is_player_view_ready(player_screen_notifier, camera)

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

	return FishingRodHandoff.is_player_projection_ready(screen_position / viewport_size)


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
	# The return rail must NEVER fight the CharacterView's red-box tracking.
	# Waiting here is intentional: the relative lure/player distance closes
	# naturally while the optical inset pans with the bait. When Ryu's REAL
	# rod becomes visible, seed a NEW smooth return from the actual pose.
	if not _real_player_view_engaged:
		if not _is_fishing_player_inside_frame():
			return
		_real_player_view_engaged = true
		fishing_player_return_start_camera_position = global_position
		fishing_player_return_start_distance = maxf(
			_get_flat_player_distance(tracked_position),
			fishing_player_return_end_distance + 0.001)
		fishing_player_return_progress = 0.0
		_inset_pan_release_started = true
		_inset_pan_at_return = _water_pan
		_inset_pan_release_start_progress = 0.0

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
	# While Ryu is still replaced by the inset, the distant lure owns pan
	# completely. Do NOT overwrite the pan each frame with the splashdown
	# value: doing so cancels the very correction that keeps the red box safe.
	if not _inset_pan_release_started and _is_fishing_player_inside_frame():
		_real_player_view_engaged = true
		_inset_pan_release_started = true
		_inset_pan_at_return = _water_pan
		_inset_pan_release_start_progress = fishing_player_return_progress
	if _inset_pan_release_started:
		var remaining: float = maxf(1.0 - _inset_pan_release_start_progress, 0.0001)
		var phase: float = clampf(
			(fishing_player_return_progress - _inset_pan_release_start_progress) / remaining,
			0.0, 1.0
		)
		_water_pan = _inset_pan_at_return.lerp(Vector2.ZERO, phase)
		_inset_optical_pan = _inset_pan_handoff_world * (1.0 - phase)
	# The same remaining-distance rail moves the real 3D camera home. Keep
	# this separate from K/A/D lure physics and from the yaw-only arc guard.
	global_position = fishing_player_return_start_camera_position.lerp(
		player_position, fishing_player_return_progress
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


func _home_fishing_h_offset_for_fixed_hud(
		camera: Camera3D, fishing_local_pose: Transform3D,
		final_rig_yaw: float) -> float:
	# Unlike the lure, the real fisherman must reclaim a *screen-space*
	# character slot that is clear of the stationary meters. Compute this
	# ONCE at fishing entry using the authored pose and actual HUD bounds.
	# Never pan the shot or move the gauges while reeling.
	if target == null or fishing_hud_geometry.is_empty():
		return fishing_h_offset
	var bar := fishing_hud_geometry[0] as Sprite2D
	if not is_instance_valid(bar) or bar.get_viewport() != camera.get_viewport():
		return fishing_h_offset
	var bar_box: Rect2 = bar.get_global_transform_with_canvas() * bar.get_rect()
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or bar_box.position.x <= 0.0:
		return fishing_h_offset
	var desired_player_x := bar_box.position.x - fishing_player_body_right_pixels - fishing_player_to_bar_gap_pixels
	# Do not derive the camera home from CharacterView.position. That inset
	# slides 220 px offscreen while showing/hiding and its position therefore
	# depends on the frame at which K was pressed. Using that animated value
	# made otherwise identical casts start with Ryu at different screen X's.
	# The fixed meter's *left edge* is the stable clearance boundary. The
	# inset is presentation-only and may never alter the fishing camera pose.
	# Avoid driving the real player offscreen when the viewport is narrow.
	desired_player_x = clampf(desired_player_x, fishing_player_body_right_pixels + 4.0, viewport_size.x - 4.0)
	var rig_basis := Basis(Vector3.UP, final_rig_yaw)
	var view := Transform3D(
		rig_basis * fishing_local_pose.basis,
		target.global_position + rig_basis * fishing_local_pose.origin
	)
	view.origin += view.basis.x * fishing_h_offset
	view.origin += view.basis.y * (fishing_v_offset + mobile_fishing_vertical_offset)
	var projection: Projection = camera.get_camera_projection()
	var predicted_x := _project_fight_orbit(0.0, view, projection,
		target.global_position, target.global_position).x * viewport_size.x
	if predicted_x <= desired_player_x:
		return fishing_h_offset
	# Camera3D.h_offset translates the optical viewpoint along its right
	# axis. Solve from two projections instead of hardcoding pixels-per-unit;
	# this works for alternate resolutions, FOVs and fishing poses.
	var probe := view
	const PROBE_STEP := 0.1
	probe.origin += probe.basis.x * PROBE_STEP
	var probe_x := _project_fight_orbit(0.0, probe, projection,
		target.global_position, target.global_position).x * viewport_size.x
	var slope := (probe_x - predicted_x) / PROBE_STEP
	if slope >= -0.0001:
		return fishing_h_offset
	var extra_offset := clampf((desired_player_x - predicted_x) / slope,
		0.0, fishing_home_extra_offset_limit)
	return fishing_h_offset + extra_offset


func set_desktop_vertical_composition_height(logical_height: int) -> void:
	# The host calls this AFTER setting SubViewport height and camera FOV.
	# Keep the reference 960x480 composition in the BOTTOM 480 logical pixels
	# of a taller world; additional water/sky becomes visible above it.
	if target == null:
		return
	if logical_height == _desktop_vertical_last_height and _desktop_vertical_is_fishing == _desktop_vertical_last_is_fishing:
		return
	var view_camera := get_node_or_null("Camera3D") as Camera3D
	if view_camera == null or not view_camera.is_inside_tree():
		return
	var base_offset: float = view_camera.v_offset - _desktop_vertical_extra_offset
	var previous_extra: float = _desktop_vertical_extra_offset
	var desired_extra: float = 0.0
	if logical_height > 480 and _desktop_vertical_is_fishing:
		# Sample the actual perspective at the player's physical anchor. This
		# avoids guessing a world-units-per-pixel constant or changing camera
		# distance/zoom. Camera3D.v_offset is a local optical translation.
		view_camera.v_offset = base_offset
		var first_y: float = view_camera.unproject_position(target.global_position).y
		view_camera.v_offset = base_offset + 0.1
		var slope: float = (view_camera.unproject_position(target.global_position).y - first_y) / 0.1
		view_camera.v_offset = base_offset
		if slope > 0.0001:
			desired_extra = clampf((float(logical_height) - 480.0) * 0.5 / slope, 0.0, 24.0)
	var adjustment: float = desired_extra - previous_extra
	_desktop_vertical_extra_offset = desired_extra
	_desktop_vertical_last_height = logical_height
	_desktop_vertical_last_is_fishing = _desktop_vertical_is_fishing
	view_camera.v_offset = base_offset + desired_extra
	# Bait reads this PRESENTATION-only lens translation and removes it from
	# physical screen-corridor projection. Never feed window height to physics.
	view_camera.set_meta("desktop_vertical_presentation_offset", desired_extra)
	# Stored fight/return camera anchors must receive the SAME optical shift,
	# otherwise a later handoff silently cancels the resizing correction.
	if _fight_base_valid:
		_fight_base_offsets.y += adjustment
	if _retrieve_yaw_return_active:
		_retrieve_start_offsets.y += adjustment
		_retrieve_original_offsets.y += adjustment
		_retrieve_end_offsets.y += adjustment


func enter_fishing_view() -> void:
	_fishing_neutral_yaw_valid = false
	_fishing_cast_start_valid = false
	_aim_heading_return_active = false
	# Compute fishing's taller-viewport inset anchor, but let the normal
	# fishing entry tween (rather than a resize event) show the transition.
	_desktop_vertical_is_fishing = true
	var pre_entry_vertical_offset: float = $Camera3D.v_offset
	set_desktop_vertical_composition_height(get_viewport().get_visible_rect().size.y)
	$Camera3D.v_offset = pre_entry_vertical_offset
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
	# Record BEFORE the entry tween: AIM A/D and subsequent casts must not
	# overwrite this baseline with their current bearing.
	_fishing_neutral_yaw = target_yaw
	_fishing_neutral_yaw_valid = true
	var fishing_home_h_offset := _home_fishing_h_offset_for_fixed_hud(
		camera, fishing_target_transform, target_yaw)

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
		fishing_home_h_offset,
		0.5
	)

	tween.parallel().tween_property(
		camera,
		"v_offset",
		fishing_v_offset + mobile_fishing_vertical_offset + _desktop_vertical_extra_offset,
		0.5
	)

	await tween.finished
	camera.transform = fishing_target_transform
	fishing_view_ready.emit()


func exit_fishing_view() -> void:
	_fishing_neutral_yaw_valid = false
	_fishing_cast_start_valid = false
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
	_desktop_vertical_is_fishing = false
	_desktop_vertical_extra_offset = 0.0
	_desktop_vertical_last_is_fishing = false
	camera.set_meta("desktop_vertical_presentation_offset",0.0)
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
