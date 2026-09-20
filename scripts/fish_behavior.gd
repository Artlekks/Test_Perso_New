extends Node

signal movement_changed(lateral: float)
signal depth_changed(value: float)
signal pressure_changed(value: float)


@export_category("Movement")
@export var min_change_time: float = 0.8
@export var max_change_time: float = 2.0



@export_category("Movement Smoothing")
@export var lateral_response_speed: float = 2.5
@export var depth_response_speed: float = 2.0
@export var pressure_response_speed: float = 2.5


@export_category("Thrashing")

@export_range(0.0, 1.0, 0.05)
var thrash_chance_per_change: float = 0.20

@export_range(0.0, 1.0, 0.05)
var thrash_min_intensity: float = 0.60

@export var thrash_multiplier: float = 1.35

@export var thrash_time_min: float = 0.25
@export var thrash_time_max: float = 0.55


enum FightBackType {
	SURGE_AWAY,
	SIDE_RUN,
	DIVE,
	RISE,
	ERRATIC
}


var current_fight_back: int = FightBackType.SURGE_AWAY
var side_direction: float = 1.0

var active: bool = false
var time_until_change: float = 0.0
var intensity: float = 1.0


# Current smoothed movement.
var lateral: float = 0.0
var depth: float = 0.0
var pressure: float = 0.0


# Desired movement.
var target_lateral: float = 0.0
var target_depth: float = 0.0
var target_pressure: float = 0.0


# Species-specific movement values.
var lateral_activity: float = 1.0
var vertical_activity: float = 1.0

var behavior_profile: FishBehaviorProfile = null

# Baseline values are captured before any species profile is applied.
# If a future FishData has no behavior profile, we restore these instead
# of accidentally inheriting the previously configured fish's settings.
var _defaults_captured: bool = false
var _default_min_change_time: float = 0.0
var _default_max_change_time: float = 0.0
var _default_thrash_chance: float = 0.0
var _default_thrash_multiplier: float = 0.0
var _default_lateral_activity: float = 1.0
var _default_vertical_activity: float = 1.0


func _process(delta: float) -> void:
	if not active:
		return

	time_until_change -= delta

	if time_until_change <= 0.0:
		_choose_new_movement()

	lateral = move_toward(
		lateral,
		target_lateral,
		lateral_response_speed * delta
	)

	depth = move_toward(
		depth,
		target_depth,
		depth_response_speed * delta
	)

	pressure = move_toward(
		pressure,
		target_pressure,
		pressure_response_speed * delta
	)

	movement_changed.emit(lateral)
	depth_changed.emit(depth)
	pressure_changed.emit(pressure)


func configure(fish: FishInstance) -> void:
	_reset_profile_settings()

	if fish == null:
		return

	var profile: FishBehaviorProfile = fish.behavior_profile

	if profile == null:
		var fish_name := "Unknown fish"

		if fish.species != null and not fish.species.fish_name.is_empty():
			fish_name = fish.species.fish_name

		push_warning(
			"FishBehavior: %s has no behavior profile; using safe defaults."
			% fish_name
		)
		return

	behavior_profile = profile

	lateral_activity = profile.lateral_activity
	vertical_activity = profile.vertical_activity

	min_change_time = profile.direction_change_min
	max_change_time = profile.direction_change_max

	thrash_chance_per_change = profile.thrash_chance
	thrash_multiplier = profile.thrash_multiplier


func _reset_profile_settings() -> void:
	_capture_default_profile_settings()

	behavior_profile = null

	lateral_activity = _default_lateral_activity
	vertical_activity = _default_vertical_activity

	min_change_time = _default_min_change_time
	max_change_time = _default_max_change_time

	thrash_chance_per_change = _default_thrash_chance
	thrash_multiplier = _default_thrash_multiplier


func _capture_default_profile_settings() -> void:
	if _defaults_captured:
		return

	_default_lateral_activity = lateral_activity
	_default_vertical_activity = vertical_activity

	_default_min_change_time = min_change_time
	_default_max_change_time = max_change_time

	_default_thrash_chance = thrash_chance_per_change
	_default_thrash_multiplier = thrash_multiplier

	_defaults_captured = true


func start(new_intensity: float = 1.0) -> void:
	intensity = clampf(
		new_intensity,
		0.0,
		1.0
	)

	active = true

	current_fight_back = _choose_fight_back_type()

	side_direction = (
		-1.0
		if randf() < 0.5
		else 1.0
	)



	_choose_new_movement()


func stop() -> void:
	active = false
	time_until_change = 0.0

	target_lateral = 0.0
	target_depth = 0.0
	target_pressure = 0.0

	lateral = 0.0
	depth = 0.0
	pressure = 0.0

	movement_changed.emit(0.0)
	depth_changed.emit(0.0)
	pressure_changed.emit(0.0)


func react_to_release(
	reaction_intensity: float = 0.40
) -> void:
	if not active:
		return

	# Releasing K gives the fish freedom to move,
	# but does not automatically cause a full surge away.
	current_fight_back = _choose_fight_back_type(
		false
	)

	side_direction = (
		-1.0
		if randf() < 0.5
		else 1.0
	)

	var previous_intensity := intensity

	intensity = clampf(
		reaction_intensity,
		0.0,
		1.0
	)


	# Release reactions cannot randomly become
	# full thrashing events.
	_choose_new_movement(false)

	# The generated movement target already contains
	# the release intensity, so restore the normal
	# fight-state intensity afterward.
	intensity = previous_intensity




func _choose_new_movement(
	allow_thrash: bool = true
) -> void:
	var new_lateral := 0.0
	var new_depth := 0.0
	var new_pressure := 0.0

	match current_fight_back:

		FightBackType.SURGE_AWAY:
			new_lateral = (
				randf_range(-0.15, 0.15)
				* lateral_activity
			)

			new_depth = (
				randf_range(-0.1, 0.1)
				* vertical_activity
			)

			new_pressure = 1.0


		FightBackType.SIDE_RUN:
			new_lateral = (
				side_direction
				* lateral_activity
			)

			new_depth = (
				randf_range(-0.2, 0.2)
				* vertical_activity
			)

			new_pressure = 0.6


		FightBackType.DIVE:
			new_lateral = (
				randf_range(-0.3, 0.3)
				* lateral_activity
			)

			new_depth = (
				-1.0
				* vertical_activity
			)

			new_pressure = 0.8


		FightBackType.RISE:
			new_lateral = (
				randf_range(-0.3, 0.3)
				* lateral_activity
			)

			new_depth = (
				1.0
				* vertical_activity
			)

			new_pressure = 0.4


		FightBackType.ERRATIC:
			new_lateral = (
				randf_range(-1.0, 1.0)
				* lateral_activity
			)

			new_depth = (
				randf_range(-1.0, 1.0)
				* vertical_activity
			)

			new_pressure = 0.75


	var movement_intensity := intensity

	var is_thrashing := (
		allow_thrash
		and intensity >= thrash_min_intensity
		and randf() < thrash_chance_per_change
	)


	if is_thrashing:
		movement_intensity = minf(
			intensity * thrash_multiplier,
			1.0
		)

		new_lateral = clampf(
			new_lateral * thrash_multiplier,
			-1.0,
			1.0
		)

		new_depth = clampf(
			new_depth * thrash_multiplier,
			-1.0,
			1.0
		)

		new_pressure = maxf(
			new_pressure,
			0.95
		)

		time_until_change = randf_range(
			thrash_time_min,
			thrash_time_max
		)


	else:
		time_until_change = randf_range(
			min_change_time,
			max_change_time
		)


	target_lateral = (
		new_lateral
		* movement_intensity
	)

	target_depth = (
		new_depth
		* movement_intensity
	)

	target_pressure = (
		new_pressure
		* movement_intensity
	)


func _choose_fight_back_type(
	allow_surge: bool = true
) -> int:
	# No profile assigned:
	# fall back to equal random behavior.
	if behavior_profile == null:
		if allow_surge:
			return randi_range(
				FightBackType.SURGE_AWAY,
				FightBackType.ERRATIC
			)

		return randi_range(
			FightBackType.SIDE_RUN,
			FightBackType.ERRATIC
		)


	var surge_weight := (
		behavior_profile.surge_weight
		if allow_surge
		else 0.0
	)

	var total_weight := (
		surge_weight
		+ behavior_profile.side_run_weight
		+ behavior_profile.dive_weight
		+ behavior_profile.rise_weight
		+ behavior_profile.erratic_weight
	)


	if total_weight <= 0.0:
		return FightBackType.ERRATIC


	var roll := randf() * total_weight


	if roll < surge_weight:
		return FightBackType.SURGE_AWAY

	roll -= surge_weight


	if roll < behavior_profile.side_run_weight:
		return FightBackType.SIDE_RUN

	roll -= behavior_profile.side_run_weight


	if roll < behavior_profile.dive_weight:
		return FightBackType.DIVE

	roll -= behavior_profile.dive_weight


	if roll < behavior_profile.rise_weight:
		return FightBackType.RISE


	return FightBackType.ERRATIC
