extends RefCounted
class_name FishInstance


const CatchScoring = preload(
	"res://scripts/fishing_catch_scoring.gd"
)
const SizeRoller = preload(
	"res://scripts/fishing_size_roller.gd"
)
const FightResolver = preload(
	"res://scripts/fishing_fight_resolver.gd"
)


var species: FishData

var size: float = 0.0
var is_king: bool = false
var size_band: StringName = &"normal"

var max_stamina: float = 0.0
var strength: float = 0.0

## Immutable specimen score metadata calculated once when the fish is created.
var points: int = 0
var score_tier: int = 0
var size_ratio_to_king: float = 0.0
var score_completion_ratio: float = 0.0

## Runtime fight values are resolved once by FishingFightResolver and cached as
## plain values. Encounter and FishBehavior consume these instead of each
## reinterpreting FishData independently.
var size_ratio_to_average: float = 1.0
var resistance_rounds: int = 1
var recovery_time_min: float = 0.8
var recovery_time_max: float = 1.5
var behavior_profile: FishBehaviorProfile
var archetype_label: String = "UNPROFILED"
var dominant_action: String = "UNPROFILED"
var behavior_intensity_multiplier: float = 1.0
var pressure_multiplier: float = 1.0
var pull_multiplier: float = 1.0
var stamina_recovery_multiplier: float = 1.0
var _fight_stats: Dictionary = {}


func setup(
	data: FishData,
	king_override: int = -1,
	size_override_cm: float = -1.0
) -> void:
	species = data

	if data == null:
		_fight_stats.clear()
		return

	_roll_size_and_king(data, king_override, size_override_cm)
	_apply_resolved_fight_stats(
		FightResolver.resolve_specimen(
			data,
			size,
			is_king
		)
	)


func _apply_resolved_fight_stats(stats: Dictionary) -> void:
	_fight_stats = stats.duplicate(true)

	if not FightResolver.is_valid_specimen_stats(stats):
		push_warning(
			"FishInstance: invalid resolved fight stats for %s; using safe defaults."
			% (species.fish_name if species != null else "UNKNOWN")
		)
		max_stamina = 1.0
		strength = 1.0
		resistance_rounds = 1
		recovery_time_min = 0.8
		recovery_time_max = 1.5
		behavior_profile = species.behavior_profile if species != null else null
		archetype_label = "UNPROFILED"
		dominant_action = "UNPROFILED"
		behavior_intensity_multiplier = 1.0
		pressure_multiplier = 1.0
		pull_multiplier = 1.0
		stamina_recovery_multiplier = 1.0
		size_ratio_to_average = 1.0
		return

	max_stamina = float(stats.get("max_stamina", 1.0))
	strength = float(stats.get("strength", 1.0))
	resistance_rounds = maxi(int(stats.get("resistance_rounds", 1)), 1)
	recovery_time_min = maxf(float(stats.get("recovery_time_min", 0.8)), 0.0)
	recovery_time_max = maxf(
		float(stats.get("recovery_time_max", recovery_time_min)),
		recovery_time_min
	)
	behavior_profile = stats.get("behavior_profile", null) as FishBehaviorProfile
	archetype_label = str(stats.get("archetype", "UNPROFILED"))
	dominant_action = str(stats.get("dominant_action", "UNPROFILED"))
	behavior_intensity_multiplier = maxf(
		float(stats.get("behavior_intensity_multiplier", 1.0)),
		0.01
	)
	pressure_multiplier = maxf(
		float(stats.get("pressure_multiplier", 1.0)),
		0.01
	)
	pull_multiplier = maxf(
		float(stats.get("pull_multiplier", 1.0)),
		0.01
	)
	stamina_recovery_multiplier = maxf(
		float(stats.get("stamina_recovery_multiplier", 1.0)),
		0.01
	)
	size_ratio_to_average = maxf(
		float(stats.get("size_ratio_to_average", 1.0)),
		0.0
	)


func get_fight_stats() -> Dictionary:
	return _fight_stats.duplicate(true)


func _roll_size_and_king(
	data: FishData,
	king_override: int,
	size_override_cm: float = -1.0
) -> void:
	if size_override_cm >= 0.0:
		size = CatchScoring.normalize_size_cm(size_override_cm)
	else:
		var result: Dictionary = SizeRoller.roll(
			data,
			king_override
		)
		size = float(result.get("size", 0.0))

	var score: Dictionary = CatchScoring.evaluate(
		data,
		size
	)

	is_king = bool(score.get("is_king", false))
	size_band = StringName(
		score.get("size_band", &"normal")
	)
	points = int(score.get("points", 0))
	score_tier = int(score.get("score_tier", 0))
	size_ratio_to_king = float(
		score.get("size_ratio_to_king", 0.0)
	)
	score_completion_ratio = float(
		score.get("score_completion_ratio", 0.0)
	)


func get_debug_snapshot() -> Dictionary:
	var species_name: String = "NONE"

	if species != null:
		species_name = species.fish_name

	return {
		"species": species_name,
		"size": size,
		"is_king": is_king,
		"size_band": str(size_band),
		"points": points,
		"score_tier": score_tier,
		"size_ratio_to_average": size_ratio_to_average,
		"size_ratio_to_king": size_ratio_to_king,
		"score_completion_ratio": score_completion_ratio,
		"king_size": (
			species.king_size
			if species != null
			else 0.0
		),
		"max_points": (
			species.max_points
			if species != null
			else 0
		),
		"max_stamina": max_stamina,
		"strength": strength,
		"resistance_rounds": resistance_rounds,
		"profile": archetype_label,
		"dominant_action": dominant_action,
		"behavior_intensity": behavior_intensity_multiplier,
		"pressure_multiplier": pressure_multiplier,
		"pull_multiplier": pull_multiplier,
		"stamina_recovery_multiplier": stamina_recovery_multiplier,
	}
