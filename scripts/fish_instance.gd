extends RefCounted
class_name FishInstance


var species: FishData

var size: float = 0.0
var max_stamina: float = 0.0
var strength: float = 0.0
var points: int = 0
var resistance_rounds: int = 1
var recovery_time_min: float = 0.8
var recovery_time_max: float = 1.5
var behavior_profile: FishBehaviorProfile

func setup(data: FishData) -> void:
	species = data

	size = _roll_size(data)
	behavior_profile = data.behavior_profile
	resistance_rounds = data.resistance_rounds
	recovery_time_min = data.recovery_time_min
	recovery_time_max = data.recovery_time_max
	
	var size_ratio := size / data.average_size

	max_stamina = data.base_stamina * size_ratio
	strength = data.base_strength * lerpf(1.0, size_ratio, 0.5)

	points = int(round(
		data.max_points
		* clampf(size / data.king_size, 0.1, 1.0)
	))

func _roll_size(data: FishData) -> float:
	var minimum_size := data.average_size * 0.7

	var roll := randf()

	# Bias the result toward more common/smaller fish.
	roll *= roll

	return lerpf(
		minimum_size,
		data.king_size,
		roll
	)
