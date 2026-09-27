extends Node3D

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

var fishing_follow_returning: bool = false
var _fishing_follow_return_tween: Tween = null
var fishing_camera_frozen: bool = false

func _ready() -> void:
	var camera: Camera3D = $Camera3D

	exploration_h_offset = camera.h_offset
	exploration_v_offset = camera.v_offset
	exploration_camera_pitch_before_fishing = camera.rotation.x
	exploration_camera_transform_before_fishing = camera.transform

func _process(_delta: float) -> void:
	if fishing_camera_frozen:
		return

	if target == null:
		return

	var follow_controls_position := _update_fishing_follow()

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


func notify_fishing_target_landed() -> void:
	# Fishing owns the gameplay phase, so it tells the camera exactly when the
	# cast has entered the water. This avoids guessing from lure depth and makes
	# the camera handoff deterministic on every cast, including consecutive casts.
	fishing_follow_has_reached_water = true
	_try_begin_fishing_player_return()


func begin_fishing_player_return() -> void:
	if (
		not fishing_follow_active
		or target == null
		or not is_instance_valid(fishing_follow_target)
	):
		return

	var tracked_position := fishing_follow_target.global_position
	var distance := _get_flat_player_distance(tracked_position)

	fishing_player_return_active = true
	fishing_player_return_start_camera_position = global_position
	fishing_player_return_start_distance = maxf(
		distance,
		fishing_player_return_end_distance + 0.001
	)
	fishing_player_return_progress = 0.0


func reset_fishing_follow() -> void:
	_stop_fishing_follow_return(false)
	_clear_fishing_follow_state()

	if target != null:
		global_position = target.global_position


func return_fishing_follow_to_target() -> void:
	# Quick-cancel path: stop tracking the discarded lure, but preserve the
	# current camera position and glide the rig back to Ryu instead of
	# snapping there in a single frame.
	_clear_fishing_follow_state()
	_stop_fishing_follow_return(false)

	if target == null:
		return

	var destination := target.global_position

	if quick_cancel_camera_return_time <= 0.0:
		global_position = destination
		return

	if global_position.distance_squared_to(destination) <= 0.000001:
		global_position = destination
		return

	fishing_follow_returning = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		self,
		"global_position",
		destination,
		quick_cancel_camera_return_time
	)
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


func _finish_fishing_follow_return() -> void:
	fishing_follow_returning = false
	_fishing_follow_return_tween = null

	if target != null:
		global_position = target.global_position


func _stop_fishing_follow_return(snap_to_target: bool) -> void:
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
	if not fishing_follow_active:
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
	return fishing_player_return_active


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
	):
		global_position = player_position
		_clear_fishing_follow_state()


func _enforce_fishing_tracking_zone(
	world_position: Vector3
) -> void:
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
		fishing_v_offset,
		0.5
	)

	await tween.finished
	camera.transform = fishing_target_transform
	fishing_view_ready.emit()


func exit_fishing_view() -> void:
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
