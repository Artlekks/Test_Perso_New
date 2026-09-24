extends Node

signal movement_changed(lateral: float)
signal depth_changed(value: float)
signal pressure_changed(value: float)
signal thrash_started(intensity: float)


@export_category("Movement")
@export var min_change_time: float = 0.8
@export var max_change_time: float = 2.0



@export_category("Movement Smoothing")
@export var lateral_response_speed: float = 2.5
@export var depth_response_speed: float = 2.0
@export var pressure_response_speed: float = 2.5


@export_category("Fight Rhythm")
# These multipliers shape the cadence of each movement archetype without
# changing fish stamina, strength, or authored profile weights.
@export_range(0.25, 2.0, 0.05)
var surge_hold_multiplier: float = 0.90

@export_range(0.25, 2.0, 0.05)
var side_run_hold_multiplier: float = 1.15

@export_range(0.25, 2.0, 0.05)
var dive_hold_multiplier: float = 1.15

@export_range(0.25, 2.0, 0.05)
var rise_hold_multiplier: float = 0.90

@export_range(0.25, 2.0, 0.05)
var erratic_hold_multiplier: float = 0.55

# A selected behavior that is strongly represented in the species profile
# lasts a little longer; rare secondary behaviors are intentionally shorter.
@export_range(0.0, 0.5, 0.05)
var profile_persistence_amount: float = 0.20

# Movement response is also archetype-aware: runners react sharply sideways,
# divers/rising fish commit vertically, and erratic fish snap between targets.
@export_range(1.0, 2.0, 0.05)
var side_run_lateral_response_multiplier: float = 1.20

@export_range(1.0, 2.0, 0.05)
var vertical_response_multiplier: float = 1.20

@export_range(1.0, 2.0, 0.05)
var erratic_response_multiplier: float = 1.40

@export_range(1.0, 2.0, 0.05)
var surge_pressure_response_multiplier: float = 1.20


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

# Per-target response multipliers are reset whenever a new movement is chosen.
# They affect presentation cadence only; they do not change fight balance.
var current_lateral_response_multiplier: float = 1.0
var current_depth_response_multiplier: float = 1.0
var current_pressure_response_multiplier: float = 1.0


# Species-specific movement values.
var lateral_activity: float = 1.0
var vertical_activity: float = 1.0

var behavior_profile: FishBehaviorProfile = null
var profile_response_multiplier: float = 1.0
var profile_release_reaction_multiplier: float = 1.0

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
		_reselect_fight_back_for_next_movement()
		_choose_new_movement()

	lateral = move_toward(
		lateral,
		target_lateral,
		lateral_response_speed
		* current_lateral_response_multiplier
		* profile_response_multiplier
		* delta
	)

	depth = move_toward(
		depth,
		target_depth,
		depth_response_speed
		* current_depth_response_multiplier
		* profile_response_multiplier
		* delta
	)

	pressure = move_toward(
		pressure,
		target_pressure,
		pressure_response_speed
		* current_pressure_response_multiplier
		* profile_response_multiplier
		* delta
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
	profile_response_multiplier = maxf(profile.movement_response_multiplier, 0.5)
	profile_release_reaction_multiplier = maxf(profile.release_reaction_multiplier, 0.5)


func _reset_profile_settings() -> void:
	_capture_default_profile_settings()

	behavior_profile = null

	lateral_activity = _default_lateral_activity
	vertical_activity = _default_vertical_activity

	min_change_time = _default_min_change_time
	max_change_time = _default_max_change_time

	thrash_chance_per_change = _default_thrash_chance
	thrash_multiplier = _default_thrash_multiplier
	profile_response_multiplier = 1.0
	profile_release_reaction_multiplier = 1.0


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

	current_lateral_response_multiplier = 1.0
	current_depth_response_multiplier = 1.0
	current_pressure_response_multiplier = 1.0

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

	reaction_intensity = clampf(
		reaction_intensity * profile_release_reaction_multiplier,
		0.0,
		1.0
	)

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




func _reselect_fight_back_for_next_movement() -> void:
	# A species profile describes tendencies, not a one-time dice roll.
	# Re-evaluating the weighted behavior each movement cycle lets those
	# tendencies actually emerge over the full resistance phase.
	var previous_fight_back := current_fight_back

	current_fight_back = _choose_fight_back_type()

	# Keep a continuous side run travelling in the same direction. If the
	# fish leaves SIDE_RUN and later returns to it, choose a fresh side.
	if (
		current_fight_back == FightBackType.SIDE_RUN
		and previous_fight_back != FightBackType.SIDE_RUN
	):
		side_direction = (
			-1.0
			if randf() < 0.5
			else 1.0
		)


func _choose_new_movement(
	allow_thrash: bool = true
) -> void:
	var new_lateral := 0.0
	var new_depth := 0.0
	var new_pressure := 0.0

	_apply_response_rhythm_for_current_behavior()

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

		# Presentation hook only. The splash/view layer can react to a real
		# thrash without inferring it from tension or movement values.
		thrash_started.emit(movement_intensity)

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
		var base_hold_time := randf_range(
			min_change_time,
			max_change_time
		)

		time_until_change = (
			base_hold_time
			* _get_behavior_hold_multiplier(
				current_fight_back
			)
			* _get_profile_persistence_multiplier(
				current_fight_back
			)
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


func _apply_response_rhythm_for_current_behavior() -> void:
	current_lateral_response_multiplier = 1.0
	current_depth_response_multiplier = 1.0
	current_pressure_response_multiplier = 1.0

	match current_fight_back:
		FightBackType.SURGE_AWAY:
			current_pressure_response_multiplier = (
				surge_pressure_response_multiplier
			)

		FightBackType.SIDE_RUN:
			current_lateral_response_multiplier = (
				side_run_lateral_response_multiplier
			)

		FightBackType.DIVE, FightBackType.RISE:
			current_depth_response_multiplier = (
				vertical_response_multiplier
			)

		FightBackType.ERRATIC:
			current_lateral_response_multiplier = (
				erratic_response_multiplier
			)
			current_depth_response_multiplier = (
				erratic_response_multiplier
			)
			current_pressure_response_multiplier = (
				erratic_response_multiplier
			)


func _get_behavior_hold_multiplier(
	fight_back_type: int
) -> float:
	match fight_back_type:
		FightBackType.SURGE_AWAY:
			return surge_hold_multiplier

		FightBackType.SIDE_RUN:
			return side_run_hold_multiplier

		FightBackType.DIVE:
			return dive_hold_multiplier

		FightBackType.RISE:
			return rise_hold_multiplier

		FightBackType.ERRATIC:
			return erratic_hold_multiplier

	return 1.0


func _get_profile_persistence_multiplier(
	fight_back_type: int
) -> float:
	if behavior_profile == null:
		return 1.0

	var selected_weight := _get_profile_weight_for_type(
		fight_back_type
	)

	var max_weight := maxf(
		behavior_profile.surge_weight,
		behavior_profile.side_run_weight
	)
	max_weight = maxf(
		max_weight,
		behavior_profile.dive_weight
	)
	max_weight = maxf(
		max_weight,
		behavior_profile.rise_weight
	)
	max_weight = maxf(
		max_weight,
		behavior_profile.erratic_weight
	)

	if max_weight <= 0.0:
		return 1.0

	var dominance := clampf(
		selected_weight / max_weight,
		0.0,
		1.0
	)

	return lerpf(
		1.0 - profile_persistence_amount,
		1.0 + profile_persistence_amount,
		dominance
	)


func _get_profile_weight_for_type(
	fight_back_type: int
) -> float:
	if behavior_profile == null:
		return 1.0

	match fight_back_type:
		FightBackType.SURGE_AWAY:
			return behavior_profile.surge_weight

		FightBackType.SIDE_RUN:
			return behavior_profile.side_run_weight

		FightBackType.DIVE:
			return behavior_profile.dive_weight

		FightBackType.RISE:
			return behavior_profile.rise_weight

		FightBackType.ERRATIC:
			return behavior_profile.erratic_weight

	return 1.0


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
