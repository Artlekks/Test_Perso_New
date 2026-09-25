extends Node3D

signal fishing_view_ready
signal exploration_view_ready
signal heading_changed(yaw: float)
signal exploration_view_started

@export var target: Node3D
@export var fishing_reference_camera: Camera3D
@export var fishing_pose_camera: Camera3D

@export var fishing_h_offset: float = 0.9
@export var fishing_v_offset: float = 0.6
@export_range(0.5, 1.5, 0.01) var fishing_distance_scale: float = 1.0
@export var aim_follow_speed: float = 6.0
@export var fishing_yaw_offset_degrees: float = -15.0
@export_range(-80.0, -5.0, 0.5) var fishing_pitch_degrees: float = -38.5
@export_category("Fishing Follow")
@export_range(0.1, 0.9, 0.05)
var fishing_follow_trigger_y_ratio: float = 0.50
@export_range(0.1, 2.0, 0.05)
var quick_cancel_camera_return_time: float = 0.85
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
var fishing_follow_offset: float = 0.0

var fishing_follow_armed: bool = false
var fishing_follow_active: bool = false
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
	fishing_follow_offset = 0.0

	fishing_follow_armed = true
	fishing_follow_active = false


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
	fishing_follow_offset = 0.0

	fishing_follow_armed = false
	fishing_follow_active = false


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
		if fishing_follow_active:
			global_position = (
				fishing_follow_base_position
				+ fishing_follow_direction * fishing_follow_offset
			)

			return true

		fishing_follow_armed = false
		return false

	var current_position := fishing_follow_target.global_position

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

			var viewport_height := (
				get_viewport().get_visible_rect().size.y
			)

			var trigger_y := (
				viewport_height
				* fishing_follow_trigger_y_ratio
			)

			if screen_position.y <= trigger_y:
				fishing_follow_armed = false
				fishing_follow_active = true

				fishing_follow_base_position = global_position

				fishing_follow_activation_progress = (
					current_position
						- fishing_follow_cast_origin
				).dot(fishing_follow_direction)

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

	global_position = (
		fishing_follow_base_position
			+ fishing_follow_direction * fishing_follow_offset
	)

	return true
	
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
