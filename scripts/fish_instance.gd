extends RefCounted
class_name FishInstance


const CatchScoring = preload(
	"res://scripts/fishing_catch_scoring.gd"
)
const SizeRoller = preload(
	"res://scripts/fishing_size_roller.gd"
)


var species: FishData

var size: float = 0.0
var is_king: bool = false
var size_band: StringName = &"normal"

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
	var result: Dictionary = SizeRoller.roll(data, king_override)

	size = float(result.get("size", 0.0))
	is_king = bool(result.get("is_king", false))
	size_band = StringName(result.get("band", &"normal"))
