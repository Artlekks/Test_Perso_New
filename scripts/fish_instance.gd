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

## Cached once when hooked; hot fight code consumes plain values.
var behavior_intensity_multiplier: float = 1.0
var pull_multiplier: float = 1.0
var stamina_recovery_multiplier: float = 1.0


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

	var safe_average: float = maxf(data.average_size, 0.001)
	var size_ratio: float = size / safe_average
	var stamina_size_scale: float = pow(
		maxf(size_ratio, 0.001),
		maxf(data.stamina_size_exponent, 0.0)
	)
	var strength_size_scale: float = lerpf(
		1.0,
		size_ratio,
		clampf(data.strength_size_influence, 0.0, 1.0)
	)

	max_stamina = data.base_stamina * stamina_size_scale
	strength = data.base_strength * strength_size_scale

	behavior_intensity_multiplier = 1.0
	pull_multiplier = 1.0
	stamina_recovery_multiplier = 1.0

	if behavior_profile != null:
		behavior_intensity_multiplier = maxf(
			behavior_profile.fight_intensity_multiplier,
			0.01
		)
		pull_multiplier = maxf(
			behavior_profile.pull_multiplier,
			0.01
		)
		stamina_recovery_multiplier = maxf(
			behavior_profile.stamina_recovery_multiplier,
			0.01
		)

	if is_king:
		max_stamina *= maxf(data.king_stamina_multiplier, 1.0)
		strength *= maxf(data.king_strength_multiplier, 1.0)
		behavior_intensity_multiplier *= maxf(
			data.king_behavior_multiplier,
			1.0
		)
		pull_multiplier *= sqrt(maxf(data.king_behavior_multiplier, 1.0))

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


func get_debug_snapshot() -> Dictionary:
	var species_name: String = "NONE"
	var profile_name: String = "NONE"

	if species != null:
		species_name = species.fish_name

	if behavior_profile != null:
		profile_name = behavior_profile.get_archetype_label()

	return {
		"species": species_name,
		"size": size,
		"is_king": is_king,
		"size_band": str(size_band),
		"max_stamina": max_stamina,
		"strength": strength,
		"resistance_rounds": resistance_rounds,
		"profile": profile_name,
		"behavior_intensity": behavior_intensity_multiplier,
		"pull_multiplier": pull_multiplier,
		"stamina_recovery_multiplier": stamina_recovery_multiplier,
	}
