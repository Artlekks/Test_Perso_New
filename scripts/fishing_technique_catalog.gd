extends Resource
class_name FishingTechniqueCatalog

@export_category("Timing")
## Authored feel windows for the clone. Source material confirms rhythm
## structure, not the original-engine millisecond tolerances.
@export_range(0.01, 0.30, 0.01)
var minimum_input_interval: float = 0.06

@export_range(0.02, 0.50, 0.01)
var short_interval_min: float = 0.08

@export_range(0.05, 0.70, 0.01)
var short_interval_max: float = 0.30

@export_range(0.10, 1.00, 0.01)
var pause_interval_min: float = 0.34

@export_range(0.15, 1.50, 0.01)
var pause_interval_max: float = 0.75

@export_range(0.20, 2.00, 0.01)
var sequence_reset_gap: float = 0.95

@export_category("Definitions")
@export var techniques: Array[FishingTechniqueDefinition] = []


func is_valid_catalog() -> bool:
	if techniques.is_empty():
		return false

	var seen_levels: Dictionary = {}

	for technique in techniques:
		if (
			technique == null
			or not technique.is_valid_definition()
		):
			return false

		if seen_levels.has(technique.level):
			return false

		seen_levels[technique.level] = true

	return true


func get_technique(
	level: int
) -> FishingTechniqueDefinition:
	for technique in techniques:
		if (
			technique != null
			and technique.level == level
		):
			return technique

	return null


func get_techniques_descending() -> Array[FishingTechniqueDefinition]:
	var result: Array[FishingTechniqueDefinition] = []

	for technique in techniques:
		if (
			technique != null
			and technique.is_valid_definition()
		):
			result.append(technique)

	result.sort_custom(
		Callable(self, "_level_descending")
	)
	return result


func get_max_level() -> int:
	var result: int = 0

	for technique in techniques:
		if technique != null:
			result = maxi(
				result,
				technique.level
			)

	return result


func get_max_required_pulses() -> int:
	var result: int = 0

	for technique in techniques:
		if technique == null:
			continue

		result = maxi(
			result,
			technique.get_required_pulse_count()
		)

	return result


func interval_matches(
	interval: float,
	kind: int
) -> bool:
	match kind:
		FishingTechniqueDefinition.IntervalKind.SHORT:
			return (
				interval >= short_interval_min
				and interval <= short_interval_max
			)

		FishingTechniqueDefinition.IntervalKind.PAUSE:
			return (
				interval >= pause_interval_min
				and interval <= pause_interval_max
			)

		_:
			return false


func get_interval_max(
	kind: int
) -> float:
	match kind:
		FishingTechniqueDefinition.IntervalKind.SHORT:
			return short_interval_max

		FishingTechniqueDefinition.IntervalKind.PAUSE:
			return pause_interval_max

		_:
			return 0.0


func get_extension_wait_seconds(
	completed: FishingTechniqueDefinition
) -> float:
	if completed == null:
		return 0.0

	var completed_pattern: PackedInt32Array = (
		completed.get_interval_pattern()
	)
	var best_wait: float = 0.0

	for candidate in techniques:
		if (
			candidate == null
			or candidate.level <= completed.level
		):
			continue

		var candidate_pattern: PackedInt32Array = (
			candidate.get_interval_pattern()
		)

		if (
			candidate_pattern.size()
			<= completed_pattern.size()
		):
			continue

		if not _is_pattern_prefix(
			completed_pattern,
			candidate_pattern
		):
			continue

		var next_kind: int = int(
			candidate_pattern[
				completed_pattern.size()
			]
		)

		best_wait = maxf(
			best_wait,
			get_interval_max(next_kind)
		)

	return best_wait


func get_debug_summary() -> String:
	return "%d techs | short %.2f-%.2f | pause %.2f-%.2f" % [
		techniques.size(),
		short_interval_min,
		short_interval_max,
		pause_interval_min,
		pause_interval_max,
	]


func _is_pattern_prefix(
	prefix: PackedInt32Array,
	full_pattern: PackedInt32Array
) -> bool:
	if prefix.size() >= full_pattern.size():
		return false

	for index in range(prefix.size()):
		if prefix[index] != full_pattern[index]:
			return false

	return true


func _level_descending(
	a: FishingTechniqueDefinition,
	b: FishingTechniqueDefinition
) -> bool:
	return a.level > b.level
