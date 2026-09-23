extends Node3D
class_name FishShadowActor

signal expired(shadow: FishShadowActor)

@export_category("Movement")
@export_range(0.05, 3.0, 0.05)
var move_speed: float = 0.55

@export_range(0.5, 12.0, 0.1)
var turn_response: float = 3.8

@export_range(0.05, 1.0, 0.05)
var target_reach_distance: float = 0.18

@export_range(0.0, 1.0, 0.05)
var pause_chance: float = 0.38

@export_range(0.0, 3.0, 0.05)
var pause_time_min: float = 0.8

@export_range(0.0, 3.0, 0.05)
var pause_time_max: float = 2.6

@export_category("Body Motion")
@export_range(0.02, 0.25, 0.005)
var segment_spacing: float = 0.090

@export_range(0.1, 12.0, 0.1)
var swim_wave_speed: float = 4.2

@export_range(0.0, 12.0, 0.5)
var head_sway_degrees: float = 2.0

@export_range(0.0, 20.0, 0.5)
var middle_sway_degrees: float = 7.0

@export_range(0.0, 30.0, 0.5)
var tail_sway_degrees: float = 13.0

@export_category("Depth / Visibility")
@export_range(0.1, 3.0, 0.05)
var base_visual_scale: float = 1.0

@export_range(0.05, 1.0, 0.05)
var shallow_opacity: float = 0.82

@export_range(0.0, 1.0, 0.05)
var deep_opacity: float = 0.32

@export_range(0.1, 1.0, 0.05)
var deep_scale_multiplier: float = 0.76

@export_range(0.2, 5.0, 0.1)
var depth_response: float = 1.35

@export_range(0.5, 12.0, 0.1)
var depth_change_time_min: float = 2.4

@export_range(0.5, 12.0, 0.1)
var depth_change_time_max: float = 5.2

@export_range(0.0, 0.1, 0.005)
var shallow_plane_height: float = 0.045

@export_range(0.0, 0.1, 0.005)
var deep_plane_height: float = 0.018

@export_category("Pre-Bite / Lure Interest")
## A visible fish is a real opportunity, but it still chooses whether to care.
@export_range(0.0, 1.0, 0.05)
var seek_bait_chance: float = 0.62

## The lure has to be brought reasonably close before the fish even watches it.
@export_range(0.25, 8.0, 0.1)
var seek_detection_radius: float = 1.65

@export_range(0.1, 2.0, 0.05)
var watch_time_min: float = 0.45

@export_range(0.1, 2.0, 0.05)
var watch_time_max: float = 0.90

@export_range(0.4, 2.0, 0.05)
var seek_speed_multiplier: float = 0.90

@export_range(0.05, 1.0, 0.05)
var inspect_distance: float = 0.28

@export_range(0.05, 1.0, 0.05)
var inspect_radius: float = 0.14

@export_range(0.1, 2.0, 0.05)
var inspect_target_change_time: float = 0.70

@export_range(0.2, 6.0, 0.1)
var inspect_duration_min: float = 2.0

@export_range(0.2, 6.0, 0.1)
var inspect_duration_max: float = 4.0

## A fish must visibly inspect for a moment before it can become a bite candidate.
@export_range(0.0, 3.0, 0.05)
var bite_ready_delay_min: float = 0.65

@export_range(0.0, 3.0, 0.05)
var bite_ready_delay_max: float = 1.20

@export_range(0.2, 6.0, 0.1)
var rejected_interest_cooldown_min: float = 1.5

@export_range(0.2, 6.0, 0.1)
var rejected_interest_cooldown_max: float = 3.0

@export_range(0.3, 3.0, 0.05)
var inspect_speed_multiplier: float = 0.48

@export_category("Hooked Fight")
## Legacy fallback only. While the head texture is available, the real
## center-to-nose distance is derived automatically from the Sprite3D width.
## This avoids hand-tuning the attachment point when the sprite scale changes.
@export_range(0.0, 0.15, 0.005)
var fight_nose_anchor_distance: float = 0.065

@export_range(0.5, 12.0, 0.1)
var fight_sway_speed: float = 4.8

@export_range(0.0, 1.0, 0.05)
var fight_depth_ratio: float = 0.22

@export_range(0.5, 3.0, 0.05)
var fight_wave_multiplier: float = 1.35

@export_range(0.1, 2.0, 0.05)
var fight_release_fade_time: float = 0.55

@export_category("Hooked Fight Orientation")
## 0 = face fully against bait travel, 1 = travel with bait.
@export_range(0.0, 1.0, 0.05)
var fight_resisting_follow_alignment: float = 0.92

@export_range(0.0, 1.0, 0.05)
var fight_exhausted_follow_alignment: float = 0.97

@export_range(0.0, 1.0, 0.05)
var fight_spent_follow_alignment: float = 1.0

@export_category("Hooked Fight Close Catch")
## Near Ryu, readability wins over free fight-facing. The fish head is blended
## toward the reel target so it cannot visually flip backward into the player.
@export_range(0.5, 5.0, 0.1)
var fight_close_align_start_distance: float = 3.0

@export_range(0.1, 3.0, 0.1)
var fight_close_align_full_distance: float = 1.4

@export_range(0.5, 4.0, 0.1)
var fight_close_turn_multiplier: float = 1.8

@export_range(0.0, 2.0, 0.05)
var fight_resisting_wave_activity: float = 1.0

@export_range(0.0, 2.0, 0.05)
var fight_exhausted_wave_activity: float = 0.58

@export_range(0.0, 2.0, 0.05)
var fight_spent_wave_activity: float = 0.30

@export_range(0.05, 1.0, 0.05)
var fight_thrash_visual_time: float = 0.36

@export_range(1.0, 2.5, 0.05)
var fight_thrash_wave_boost: float = 1.55

@export_category("Lifetime")
@export_range(0.05, 3.0, 0.05)
var fade_in_time: float = 0.40

@export_range(0.05, 3.0, 0.05)
var fade_out_time: float = 1.0

@onready var head_segment: Node3D = $HeadSegment
@onready var middle_segment: Node3D = $MiddleSegment
@onready var tail_segment: Node3D = $TailSegment
@onready var head_sprite: Sprite3D = $HeadSegment/Sprite3D
@onready var middle_sprite: Sprite3D = $MiddleSegment/Sprite3D
@onready var tail_sprite: Sprite3D = $TailSegment/Sprite3D

var fish_data: FishData = null
var swim_bounds: FishSwimBounds = null
var water_surface_y: float = 0.0

var _target_world_position: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _current_velocity: Vector3 = Vector3.ZERO
var _head_direction: Vector3 = Vector3.FORWARD
var _pause_remaining: float = 0.0
var _swim_time: float = 0.0
var _rng := RandomNumberGenerator.new()

var _depth_ratio: float = 0.3
var _target_depth_ratio: float = 0.3
var _depth_change_remaining: float = 0.0

var _age: float = 0.0
var _life_remaining: float = 10.0
var _expiring: bool = false
var _expire_fade_override: float = -1.0
var _expired_emitted: bool = false

enum PreBiteState {
	ROAM,
	WATCH,
	APPROACH,
	INSPECT,
}

var _bait: Node3D = null
var _observed_bait_id: int = 0
var _pre_bite_state: int = PreBiteState.ROAM
var _pre_bite_timer: float = 0.0
var _bite_ready_timer: float = 0.0
var _interest_cooldown: float = 0.0
var _inspect_target_timer: float = 0.0
var _inspect_offset: Vector3 = Vector3.ZERO

var _fight_tracking: bool = false
var _fight_bait: Node3D = null
var _fight_last_bait_position: Vector3 = Vector3.ZERO
var _fight_motion_direction: Vector3 = Vector3.ZERO
var _fight_size_multiplier: float = 1.0
var _fight_follow_alignment: float = 0.05
var _fight_wave_activity: float = 1.0
var _fight_thrash_time_left: float = 0.0
var _fight_thrash_intensity: float = 0.0


func configure(
	new_fish_data: FishData,
	new_swim_bounds: FishSwimBounds,
	new_water_surface_y: float,
	initial_depth_ratio: float,
	new_speed: float,
	new_scale: float,
	new_lifetime: float,
	seed_value: int
) -> void:
	fish_data = new_fish_data
	swim_bounds = new_swim_bounds
	water_surface_y = new_water_surface_y
	move_speed = maxf(new_speed, 0.05)
	base_visual_scale = maxf(new_scale, 0.1)
	_life_remaining = maxf(new_lifetime, fade_in_time + fade_out_time + 0.25)
	_depth_ratio = clampf(initial_depth_ratio, 0.0, 1.0)
	_target_depth_ratio = _depth_ratio

	_rng.seed = seed_value
	_place_at_random_point()
	_pick_new_target()
	_pick_new_depth_target()
	_place_body()
	_update_visuals()


func get_fish_data() -> FishData:
	return fish_data


func is_interested_in_bait() -> bool:
	return (
		_pre_bite_state != PreBiteState.ROAM
		and is_instance_valid(_bait)
		and not _expiring
	)


func is_interested_near(world_position: Vector3, max_distance: float) -> bool:
	# Encounter only sees the shadow as a bite candidate after the player has
	# had time to watch the fish approach and inspect the lure.
	if _pre_bite_state != PreBiteState.INSPECT:
		return false
	if _bite_ready_timer > 0.0:
		return false
	if not is_instance_valid(_bait) or _expiring:
		return false

	var offset := global_position - world_position
	offset.y = 0.0
	return offset.length() <= max_distance


func is_pre_bite_active_near(world_position: Vector3, max_distance: float) -> bool:
	if _pre_bite_state == PreBiteState.ROAM:
		return false
	if not is_instance_valid(_bait) or _expiring:
		return false

	var offset := global_position - world_position
	offset.y = 0.0
	return offset.length() <= max_distance


func get_pre_bite_state_name() -> String:
	match _pre_bite_state:
		PreBiteState.WATCH:
			return "WATCH"
		PreBiteState.APPROACH:
			return "APPROACH"
		PreBiteState.INSPECT:
			return "INSPECT"
		_:
			return "ROAM"


func is_hooked_tracking() -> bool:
	return _fight_tracking and is_instance_valid(_fight_bait)


func attach_to_hooked_bait(
	bait: Node3D,
	hooked_fish_data: FishData = null,
	size_multiplier: float = 1.0
) -> void:
	if not is_instance_valid(bait):
		return

	if hooked_fish_data != null:
		fish_data = hooked_fish_data

	_fight_tracking = true
	_fight_bait = bait
	_bait = bait
	_observed_bait_id = bait.get_instance_id()
	_pre_bite_state = PreBiteState.ROAM
	_pre_bite_timer = 0.0
	_bite_ready_timer = 0.0
	_interest_cooldown = 0.0
	_inspect_target_timer = 0.0
	_inspect_offset = Vector3.ZERO
	_pause_remaining = 0.0
	_has_target = false

	# A hooked fish must not expire simply because its former ambient lifetime ran out.
	_expiring = false
	_expire_fade_override = -1.0
	_life_remaining = maxf(_life_remaining, 9999.0)
	_age = maxf(_age, fade_in_time)

	_fight_size_multiplier = clampf(size_multiplier, 0.70, 1.45)
	_fight_follow_alignment = fight_resisting_follow_alignment
	_fight_wave_activity = fight_resisting_wave_activity
	_fight_thrash_time_left = 0.0
	_fight_thrash_intensity = 0.0
	_depth_ratio = minf(_depth_ratio, fight_depth_ratio)
	_target_depth_ratio = fight_depth_ratio
	_depth_change_remaining = 9999.0

	_fight_last_bait_position = bait.global_position
	_fight_motion_direction = _head_direction

	var target := bait.global_position
	target.y = _get_visual_plane_y()
	global_position = target
	_current_velocity = Vector3.ZERO


func release_from_hooked_bait(dive_away: bool = true) -> void:
	if not _fight_tracking:
		return

	_fight_tracking = false
	_fight_bait = null
	_bait = null
	_observed_bait_id = 0
	_fight_size_multiplier = 1.0
	_fight_thrash_time_left = 0.0
	_fight_thrash_intensity = 0.0
	_expiring = true
	_expire_fade_override = fight_release_fade_time
	_life_remaining = minf(_life_remaining, fight_release_fade_time)

	if dive_away:
		_target_depth_ratio = 1.0
		_pick_new_target()


func set_fight_visual_state(state_name: StringName) -> void:
	match state_name:
		&"spent":
			_fight_follow_alignment = fight_spent_follow_alignment
			_fight_wave_activity = fight_spent_wave_activity
		&"exhausted":
			_fight_follow_alignment = fight_exhausted_follow_alignment
			_fight_wave_activity = fight_exhausted_wave_activity
		_:
			_fight_follow_alignment = fight_resisting_follow_alignment
			_fight_wave_activity = fight_resisting_wave_activity


func play_fight_thrash(intensity: float) -> void:
	if not _fight_tracking:
		return

	_fight_thrash_intensity = clampf(intensity, 0.0, 1.0)
	_fight_thrash_time_left = fight_thrash_visual_time


func consume_for_bite() -> void:
	_pre_bite_state = PreBiteState.ROAM
	_expiring = true
	_expire_fade_override = 0.28
	_life_remaining = minf(_life_remaining, _expire_fade_override)
	_target_depth_ratio = 1.0


func abandon_bait_and_dive() -> void:
	_pre_bite_state = PreBiteState.ROAM
	_expiring = true
	_expire_fade_override = 0.85
	_life_remaining = minf(_life_remaining, _expire_fade_override)
	_target_depth_ratio = 1.0
	_pick_new_target()


func request_expire() -> void:
	if _expiring:
		return
	_expiring = true
	_life_remaining = minf(_life_remaining, fade_out_time)
	_target_depth_ratio = maxf(_target_depth_ratio, 0.82)


func _process(delta: float) -> void:
	if swim_bounds == null:
		return

	_age += delta
	_swim_time += delta
	_update_lifetime(delta)

	if _expired_emitted:
		return

	_update_depth(delta)

	if _fight_tracking:
		_update_hooked_motion(delta)
		_place_body()
		_update_visuals()
		return

	_update_bait_interest(delta)
	_update_motion(delta)
	_place_body()
	_update_visuals()


func _update_lifetime(delta: float) -> void:
	if _fight_tracking:
		return

	_life_remaining -= delta

	if _life_remaining > 0.0:
		return

	if _expired_emitted:
		return

	_expired_emitted = true
	expired.emit(self)
	queue_free()


func _update_depth(delta: float) -> void:
	if _fight_tracking:
		_target_depth_ratio = fight_depth_ratio
		var fight_response := clampf(1.0 - exp(-depth_response * 2.0 * delta), 0.0, 1.0)
		_depth_ratio = lerpf(_depth_ratio, _target_depth_ratio, fight_response)
		return

	_depth_change_remaining -= delta

	if _depth_change_remaining <= 0.0 and not _expiring:
		_pick_new_depth_target()

	var response := clampf(1.0 - exp(-depth_response * delta), 0.0, 1.0)
	_depth_ratio = lerpf(_depth_ratio, _target_depth_ratio, response)


func _pick_new_depth_target() -> void:
	_depth_change_remaining = _rng.randf_range(
		depth_change_time_min,
		maxf(depth_change_time_max, depth_change_time_min)
	)

	var preferred_min := 0.15
	var preferred_max := 0.65

	if fish_data != null:
		preferred_min = clampf(
			minf(fish_data.preferred_depth_min, fish_data.preferred_depth_max),
			0.0,
			1.0
		)
		preferred_max = clampf(
			maxf(fish_data.preferred_depth_min, fish_data.preferred_depth_max),
			0.0,
			1.0
		)

	var roll := _rng.randf()

	# Occasionally come close to the surface or dive deep enough to nearly
	# vanish. Most of the time, stay around the species' preferred band.
	if roll < 0.22:
		_target_depth_ratio = _rng.randf_range(0.05, 0.30)
	elif roll > 0.78:
		_target_depth_ratio = _rng.randf_range(0.72, 1.0)
	else:
		_target_depth_ratio = _rng.randf_range(preferred_min, preferred_max)


func _update_bait_interest(delta: float) -> void:
	var candidate := get_tree().get_first_node_in_group("bait") as Node3D

	if not is_instance_valid(candidate):
		_clear_bait_interest()
		return

	var candidate_id := candidate.get_instance_id()

	if candidate_id != _observed_bait_id:
		_bait = candidate
		_observed_bait_id = candidate_id
		_pre_bite_state = PreBiteState.ROAM
		_pre_bite_timer = 0.0
		_bite_ready_timer = 0.0
		_interest_cooldown = 0.0
		_inspect_target_timer = 0.0
		_inspect_offset = Vector3.ZERO

	# Ignore the lure while it is clearly still airborne.
	if candidate.global_position.y > water_surface_y + 0.12:
		return

	_interest_cooldown = maxf(_interest_cooldown - delta, 0.0)

	var horizontal := candidate.global_position - global_position
	horizontal.y = 0.0
	var distance := horizontal.length()

	match _pre_bite_state:
		PreBiteState.ROAM:
			if _interest_cooldown <= 0.0 and distance <= seek_detection_radius:
				_enter_watch_state()

		PreBiteState.WATCH:
			_target_depth_ratio = minf(_target_depth_ratio, 0.48)
			_depth_change_remaining = maxf(_depth_change_remaining, 0.6)
			_pre_bite_timer -= delta

			if distance > seek_detection_radius * 1.35:
				_return_to_roam_with_cooldown()
			elif _pre_bite_timer <= 0.0:
				if _rng.randf() <= seek_bait_chance:
					_enter_approach_state()
				else:
					_return_to_roam_with_cooldown()

		PreBiteState.APPROACH:
			_target_depth_ratio = minf(_target_depth_ratio, 0.38)
			_depth_change_remaining = maxf(_depth_change_remaining, 0.8)

			if distance <= inspect_distance:
				_enter_inspect_state()
			elif distance > seek_detection_radius * 1.65:
				_return_to_roam_with_cooldown()

		PreBiteState.INSPECT:
			# Stay visibly near the surface while deciding whether to bite.
			_target_depth_ratio = minf(_target_depth_ratio, 0.30)
			_depth_change_remaining = maxf(_depth_change_remaining, 1.0)
			_pre_bite_timer -= delta
			_bite_ready_timer = maxf(_bite_ready_timer - delta, 0.0)
			_inspect_target_timer -= delta

			if _inspect_target_timer <= 0.0:
				_inspect_target_timer = inspect_target_change_time
				_pick_inspect_offset()

			# If the player pulls the lure away, chase it again instead of snapping.
			if distance > inspect_distance * 2.8:
				_enter_approach_state()
			elif _pre_bite_timer <= 0.0:
				# No bite happened during the visible inspection window: this fish
				# loses interest and disappears. A shadow is risk, never a promise.
				abandon_bait_and_dive()


func _enter_watch_state() -> void:
	_pre_bite_state = PreBiteState.WATCH
	# Once the player has clearly reached a visible fish with the lure, keep it
	# alive long enough for the full watch -> approach -> inspect sequence.
	_life_remaining = maxf(
		_life_remaining,
		watch_time_max + inspect_duration_max + 2.0
	)
	_pre_bite_timer = _rng.randf_range(
		watch_time_min,
		maxf(watch_time_max, watch_time_min)
	)
	_pause_remaining = 0.0


func _enter_approach_state() -> void:
	_pre_bite_state = PreBiteState.APPROACH
	_pre_bite_timer = 0.0
	_inspect_offset = Vector3.ZERO
	_inspect_target_timer = 0.0


func _enter_inspect_state() -> void:
	_pre_bite_state = PreBiteState.INSPECT
	_pre_bite_timer = _rng.randf_range(
		inspect_duration_min,
		maxf(inspect_duration_max, inspect_duration_min)
	)
	_bite_ready_timer = _rng.randf_range(
		bite_ready_delay_min,
		maxf(bite_ready_delay_max, bite_ready_delay_min)
	)
	_inspect_target_timer = 0.0
	_pick_inspect_offset()


func _pick_inspect_offset() -> void:
	var angle := _rng.randf_range(-PI, PI)
	_inspect_offset = Vector3(
		cos(angle) * inspect_radius,
		0.0,
		sin(angle) * inspect_radius
	)


func _return_to_roam_with_cooldown() -> void:
	_pre_bite_state = PreBiteState.ROAM
	_pre_bite_timer = 0.0
	_bite_ready_timer = 0.0
	_inspect_target_timer = 0.0
	_inspect_offset = Vector3.ZERO
	_interest_cooldown = _rng.randf_range(
		rejected_interest_cooldown_min,
		maxf(rejected_interest_cooldown_max, rejected_interest_cooldown_min)
	)
	if not _has_target:
		_pick_new_target()


func _clear_bait_interest() -> void:
	_bait = null
	_observed_bait_id = 0
	_pre_bite_state = PreBiteState.ROAM
	_pre_bite_timer = 0.0
	_bite_ready_timer = 0.0
	_interest_cooldown = 0.0
	_inspect_target_timer = 0.0
	_inspect_offset = Vector3.ZERO


func _update_motion(delta: float) -> void:
	if _pause_remaining > 0.0 and _pre_bite_state == PreBiteState.ROAM:
		_pause_remaining = maxf(_pause_remaining - delta, 0.0)
		_current_velocity = _current_velocity.move_toward(
			Vector3.ZERO,
			move_speed * 2.0 * delta
		)
		return

	if is_instance_valid(_bait):
		if _pre_bite_state == PreBiteState.WATCH:
			# Stop and face the lure. This is the readable "did it notice me?" beat.
			_current_velocity = _current_velocity.move_toward(
				Vector3.ZERO,
				move_speed * 2.0 * delta
			)
			_face_world_position(_bait.global_position, delta, 0.75)
			return
		elif _pre_bite_state == PreBiteState.APPROACH:
			_target_world_position = swim_bounds.constrain_fish_motion(
				global_position,
				_bait.global_position
			)
			_has_target = true
		elif _pre_bite_state == PreBiteState.INSPECT:
			var bait_target := _bait.global_position + _inspect_offset
			bait_target.y = global_position.y
			_target_world_position = swim_bounds.constrain_fish_motion(
				global_position,
				bait_target
			)
			_has_target = true

	if not _has_target:
		_pick_new_target()
		return

	var to_target := _target_world_position - global_position
	to_target.y = 0.0
	var distance_to_target := to_target.length()

	if distance_to_target <= target_reach_distance and _pre_bite_state == PreBiteState.ROAM:
		_arrive_at_target()
		return

	if distance_to_target <= 0.001:
		_current_velocity = _current_velocity.move_toward(Vector3.ZERO, move_speed * delta)
		return

	var desired_direction := to_target / distance_to_target
	var speed := move_speed

	if _pre_bite_state == PreBiteState.APPROACH:
		speed *= seek_speed_multiplier
	elif _pre_bite_state == PreBiteState.INSPECT:
		speed *= inspect_speed_multiplier

	# Deeper fish feel a little more distant and unhurried.
	speed *= lerpf(1.0, 0.82, _depth_ratio)

	var desired_velocity := desired_direction * speed
	var response := clampf(1.0 - exp(-turn_response * delta), 0.0, 1.0)

	_current_velocity = _current_velocity.lerp(desired_velocity, response)

	if _current_velocity.length_squared() > 0.0001:
		_head_direction = _head_direction.slerp(
			_current_velocity.normalized(),
			response
		).normalized()

	var proposed_position := global_position + _current_velocity * delta
	proposed_position.y = _get_visual_plane_y()
	proposed_position = swim_bounds.constrain_fish_motion(global_position, proposed_position)
	proposed_position.y = _get_visual_plane_y()
	global_position = proposed_position


func _update_hooked_motion(delta: float) -> void:
	if not is_instance_valid(_fight_bait):
		release_from_hooked_bait(true)
		return

	var bait_position := _fight_bait.global_position
	var bait_delta := bait_position - _fight_last_bait_position
	bait_delta.y = 0.0
	_fight_last_bait_position = bait_position

	if bait_delta.length_squared() > 0.000001:
		var instantaneous_direction := bait_delta.normalized()
		var direction_response := clampf(1.0 - exp(-8.0 * delta), 0.0, 1.0)
		_fight_motion_direction = _fight_motion_direction.slerp(
			instantaneous_direction,
			direction_response
		).normalized()

	if _fight_motion_direction.length_squared() <= 0.0001:
		_fight_motion_direction = _head_direction

	# The bait can be several metres below the water while the shadow is rendered
	# on a shallow visibility plane. Copying only bait X/Z creates a large
	# perspective/parallax error: the bait and shadow no longer occupy the same
	# screen pixel. Project the bait through the active camera onto the shadow
	# plane instead. This keeps the fish nose visually welded to the bait at any
	# lure depth while preserving the readable surface-shadow presentation.
	global_position = _project_bait_to_visual_plane(bait_position)

	# Normal hooked motion follows the bait/retrieve direction so the fish reads
	# as physically attached to the lure. Resistance is shown mostly through body
	# wave and lateral motion. Only a genuine thrash temporarily turns the fish
	# strongly against the retrieve.
	if _fight_thrash_time_left > 0.0:
		_fight_thrash_time_left = maxf(_fight_thrash_time_left - delta, 0.0)

	var follow_alignment := _fight_follow_alignment
	var turn_multiplier := 1.10

	if _fight_thrash_time_left > 0.0:
		# Only a genuine thrash strongly turns the fish against the retrieve.
		# Weak thrashes oppose less; strong thrashes can approach a full reversal.
		follow_alignment = lerpf(0.25, 0.05, _fight_thrash_intensity)
		turn_multiplier = lerpf(1.45, 2.0, _fight_thrash_intensity)

	var motion_direction := _fight_motion_direction.normalized()
	if motion_direction.length_squared() > 0.0001:
		# Rotate from fully opposed (180 degrees) toward fully following (0 degrees).
		# Preserve the fish's current turning side so intermediate states do not
		# suddenly flip from left-leaning to right-leaning.
		var side_sign := signf(_head_direction.cross(motion_direction).y)
		if is_zero_approx(side_sign):
			side_sign = 1.0

		var offset_angle := PI * (1.0 - clampf(follow_alignment, 0.0, 1.0))
		var desired_facing := motion_direction.rotated(
			Vector3.UP,
			offset_angle * side_sign
		).normalized()

		# Close to the catch point, the lure head is visually the line-entry cue.
		# Force the fish progressively toward Ryu so the head cannot end up facing
		# away from the character or disappearing backward through the feet.
		if _fight_bait.has_method("get_reel_target_node"):
			var reel_target_node = _fight_bait.get_reel_target_node()
			if is_instance_valid(reel_target_node):
				var bait_to_target: Vector3 = (
					reel_target_node.global_position - bait_position
				)
				bait_to_target.y = 0.0

				var target_distance := bait_to_target.length()
				if (
					target_distance > 0.0001
					and target_distance < fight_close_align_start_distance
				):
					var close_blend := 1.0 - smoothstep(
						fight_close_align_full_distance,
						fight_close_align_start_distance,
						target_distance
					)
					desired_facing = desired_facing.slerp(
						bait_to_target.normalized(),
						clampf(close_blend, 0.0, 1.0)
					).normalized()
					turn_multiplier = maxf(
						turn_multiplier,
						fight_close_turn_multiplier
					)

		_head_direction = _head_direction.slerp(
			desired_facing,
			clampf(1.0 - exp(-turn_response * turn_multiplier * delta), 0.0, 1.0)
		).normalized()


func _project_bait_to_visual_plane(bait_position: Vector3) -> Vector3:
	var plane_y := _get_visual_plane_y()
	var camera := get_viewport().get_camera_3d()

	if camera == null:
		return Vector3(bait_position.x, plane_y, bait_position.z)

	# Build the camera ray that goes through the bait's exact screen position,
	# then intersect that ray with the plane on which the shadow is rendered.
	var screen_position := camera.unproject_position(bait_position)
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)

	if absf(ray_direction.y) <= 0.00001:
		return Vector3(bait_position.x, plane_y, bait_position.z)

	var distance_along_ray := (plane_y - ray_origin.y) / ray_direction.y

	# A negative intersection would place the shadow behind the camera. Fall
	# back safely rather than allowing a bad camera angle to fling it away.
	if distance_along_ray < 0.0:
		return Vector3(bait_position.x, plane_y, bait_position.z)

	var projected := ray_origin + ray_direction * distance_along_ray
	projected.y = plane_y
	return projected


func _get_head_nose_distance() -> float:
	if head_sprite != null and head_sprite.texture != null:
		return (
			float(head_sprite.texture.get_width())
			* head_sprite.pixel_size
			* 0.5
		)

	# Fallback for a temporarily missing texture/import.
	return fight_nose_anchor_distance


func _face_world_position(world_position: Vector3, delta: float, response_scale: float = 1.0) -> void:
	var direction := world_position - global_position
	direction.y = 0.0

	if direction.length_squared() <= 0.0001:
		return

	var response := clampf(
		1.0 - exp(-turn_response * response_scale * delta),
		0.0,
		1.0
	)
	_head_direction = _head_direction.slerp(direction.normalized(), response).normalized()


func _arrive_at_target() -> void:
	_has_target = false

	if _rng.randf() <= pause_chance:
		_pause_remaining = _rng.randf_range(
			pause_time_min,
			maxf(pause_time_max, pause_time_min)
		)
	else:
		_pick_new_target()


func _pick_new_target() -> void:
	if swim_bounds == null:
		_has_target = false
		return

	_target_world_position = swim_bounds.get_random_horizontal_point(
		_get_visual_plane_y(),
		_rng
	)
	_has_target = true


func _place_at_random_point() -> void:
	if swim_bounds == null:
		return

	global_position = swim_bounds.get_random_horizontal_point(
		_get_visual_plane_y(),
		_rng
	)

	var random_heading := _rng.randf_range(-PI, PI)
	_head_direction = Vector3(cos(random_heading), 0.0, sin(random_heading)).normalized()


func _place_body() -> void:
	if head_segment == null or middle_segment == null or tail_segment == null:
		return

	var visual_scale := (
		base_visual_scale
		* _fight_size_multiplier
		* lerpf(1.0, deep_scale_multiplier, _depth_ratio)
	)
	var active_wave_speed := swim_wave_speed
	var wave_activity := 1.0
	if _fight_tracking:
		active_wave_speed *= fight_wave_multiplier
		wave_activity = _fight_wave_activity
		if _fight_thrash_time_left > 0.0:
			wave_activity *= lerpf(
				1.15,
				fight_thrash_wave_boost,
				_fight_thrash_intensity
			)
	var phase := _swim_time * active_wave_speed

	var head_direction := _head_direction.rotated(
		Vector3.UP,
		deg_to_rad(sin(phase) * head_sway_degrees * wave_activity)
	).normalized()

	var middle_direction := _head_direction.rotated(
		Vector3.UP,
		deg_to_rad(sin(phase - 0.90) * middle_sway_degrees * wave_activity)
	).normalized()

	var tail_direction := _head_direction.rotated(
		Vector3.UP,
		deg_to_rad(sin(phase - 1.80) * tail_sway_degrees * wave_activity)
	).normalized()

	var spacing := segment_spacing * visual_scale
	var head_center := global_position
	if _fight_tracking:
		# global_position is now the screen-correct nose anchor. Derive the real
		# center-to-nose distance from the texture width instead of guessing an
		# offset value, then place the rest of the articulated body behind it.
		head_center -= head_direction * _get_head_nose_distance() * visual_scale
	var middle_center := head_center - head_direction * spacing
	var tail_center := middle_center - middle_direction * spacing

	_place_segment(head_segment, head_center, head_direction, visual_scale)
	_place_segment(middle_segment, middle_center, middle_direction, visual_scale)
	_place_segment(tail_segment, tail_center, tail_direction, visual_scale)


func _place_segment(
	segment: Node3D,
	world_position: Vector3,
	forward: Vector3,
	visual_scale: float
) -> void:
	segment.global_position = world_position

	# The source BOF4 texture faces LEFT, so local -X is the fish's forward.
	var yaw := atan2(-forward.z, forward.x) + PI
	segment.rotation.y = yaw
	segment.scale = Vector3.ONE * visual_scale


func _update_visuals() -> void:
	var alpha := lerpf(shallow_opacity, deep_opacity, _depth_ratio)
	alpha *= _get_lifecycle_alpha()
	alpha = clampf(alpha, 0.0, 1.0)

	var color := Color(1.0, 1.0, 1.0, alpha)

	if head_sprite != null:
		head_sprite.modulate = color
	if middle_sprite != null:
		middle_sprite.modulate = color
	if tail_sprite != null:
		tail_sprite.modulate = color


func _get_lifecycle_alpha() -> float:
	if _fight_tracking:
		return 1.0

	var in_alpha := clampf(_age / maxf(fade_in_time, 0.001), 0.0, 1.0)
	var active_fade_out := fade_out_time

	if _expire_fade_override > 0.0:
		active_fade_out = _expire_fade_override

	var out_alpha := clampf(
		_life_remaining / maxf(active_fade_out, 0.001),
		0.0,
		1.0
	)

	return minf(in_alpha, out_alpha)


func _get_visual_plane_y() -> float:
	return water_surface_y + lerpf(
		shallow_plane_height,
		deep_plane_height,
		_depth_ratio
	)
