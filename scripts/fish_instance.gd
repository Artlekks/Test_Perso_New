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


func setup(data: FishData, king_override: int = -1) -> void:
	species = data

	if data == null:
		return

	_roll_size_and_king(data, king_override)

	behavior_profile = data.behavior_profile
	resistance_rounds = data.resistance_rounds

	var recovery_multiplier := 1.0
	if behavior_profile != null:
		recovery_multiplier = maxf(
			behavior_profile.recovery_time_multiplier,
			0.5
		)

	recovery_time_min = data.recovery_time_min * recovery_multiplier
	recovery_time_max = data.recovery_time_max * recovery_multiplier

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


func _roll_size_and_king(data: FishData, king_override: int) -> void:
	var safe_average: float = maxf(data.average_size, 1.0)
	var king_threshold: float = maxf(
		data.king_size,
		safe_average
	)

	var roll_king_band: bool = false
	match king_override:
		0:
			roll_king_band = false
		1:
			roll_king_band = true
		_:
			roll_king_band = randf() < clampf(
				data.king_chance,
				0.0,
				1.0
			)

	if roll_king_band:
		var king_min_cm: int = maxi(ceili(king_threshold), 1)
		var king_max_cm: int = maxi(
			king_min_cm,
			roundi(
				king_threshold
				* maxf(data.king_max_size_multiplier, 1.0)
			)
		)

		size = float(randi_range(king_min_cm, king_max_cm))
		is_king = size >= king_threshold
		return

	# Normal fish are kept below the crown threshold. The two-roll average
	# makes middle-sized specimens common and record-near fish progressively
	# rarer, while still centering the population close to average_size.
	var minimum_cm: int = maxi(roundi(safe_average * 0.60), 1)
	var normal_max_cm: int = maxi(
		ceili(king_threshold) - 1,
		minimum_cm
	)

	var normal_roll: float = (randf() + randf()) * 0.5
	var rolled_cm: int = roundi(
		lerpf(
			float(minimum_cm),
			float(normal_max_cm),
			normal_roll
		)
	)

	size = float(clampi(rolled_cm, minimum_cm, normal_max_cm))
	is_king = size >= king_threshold

