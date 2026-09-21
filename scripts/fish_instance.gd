extends RefCounted
class_name FishInstance


const CatchScoring = preload(
	"res://scripts/fishing_catch_scoring.gd"
)


var species: FishData

var size: float = 0.0
var is_king: bool = false

var max_stamina: float = 0.0
var strength: float = 0.0
var points: int = 0

var resistance_rounds: int = 1
var recovery_time_min: float = 0.8
var recovery_time_max: float = 1.5
var behavior_profile: FishBehaviorProfile


func setup(data: FishData) -> void:
	species = data

	if data == null:
		return

	_roll_size_and_king(data)

	behavior_profile = data.behavior_profile
	resistance_rounds = data.resistance_rounds
	recovery_time_min = data.recovery_time_min
	recovery_time_max = data.recovery_time_max

	var safe_average := maxf(data.average_size, 0.001)
	var size_ratio := size / safe_average

	max_stamina = data.base_stamina * size_ratio
	strength = data.base_strength * lerpf(
		1.0,
		size_ratio,
		0.5
	)

	points = CatchScoring.calculate_points(
		data,
		size,
		is_king
	)


func _roll_size_and_king(data: FishData) -> void:
	var safe_average := maxf(data.average_size, 0.01)
	var king_threshold := maxf(
		data.king_size,
		safe_average
	)

	is_king = randf() < clampf(
		data.king_chance,
		0.0,
		1.0
	)

	if is_king:
		var king_max := king_threshold * maxf(
			data.king_max_size_multiplier,
			1.0
		)

		size = randf_range(
			king_threshold,
			king_max
		)
		return

	# The normal band is centered roughly around average_size.
	# Averaging two random values makes extreme sizes less common without
	# requiring a separate probability table.
	var minimum_size := safe_average * 0.6
	var normal_max := maxf(
		king_threshold - 0.01,
		minimum_size
	)

	var normal_roll := (
		randf()
		+ randf()
	) * 0.5

	size = lerpf(
		minimum_size,
		normal_max,
		normal_roll
	)
