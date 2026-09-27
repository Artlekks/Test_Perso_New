extends Resource
class_name FishingTechniqueDefinition

enum IntervalKind {
	SHORT,
	PAUSE,
}

@export_category("Identity")
@export_range(1, 4, 1)
var level: int = 1
@export var technique_id: StringName = &""
@export var display_name: String = ""

@export_category("Rhythm")
## Pulse groups from the BOF4 help notation.
##
## Examples:
## Tec 1 = [1, 1, 1]
## Tec 2 = [1, 2, 1]
## Tec 3 = [1, 2, 2]
## Tec 4 = [3, 2, 1]
@export var pulse_groups: PackedInt32Array = PackedInt32Array()

@export_category("Attraction")
## Gameplay tuning layered over lure/depth/species attraction.
## Exact original-engine multipliers are not documented.
@export_range(1.0, 4.0, 0.05)
var attraction_multiplier: float = 1.0

## Duration of the successful technique's attraction boost.
## This is project tuning, not claimed canonical BOF4 timing.
@export_range(0.1, 10.0, 0.05)
var boost_duration: float = 2.5

## Source metadata. Fandom describes the fourth technique as attracting all
## fish types. We preserve that fact in data without pretending it overrides
## BOF4 lure/depth preference rules whose exact interaction is undocumented.
@export var broad_attraction: bool = false

@export_category("Documentation")
@export_multiline var source_note: String = ""
@export_multiline var tuning_note: String = ""


func is_valid_definition() -> bool:
	if (
		level < 1
		or level > 4
		or technique_id == &""
		or pulse_groups.is_empty()
	):
		return false

	for group_size in pulse_groups:
		if group_size <= 0:
			return false

	return true


func get_required_pulse_count() -> int:
	var total: int = 0

	for group_size in pulse_groups:
		total += maxi(group_size, 0)

	return total


func get_interval_pattern() -> PackedInt32Array:
	var result := PackedInt32Array()

	for group_index in range(pulse_groups.size()):
		var group_size: int = maxi(
			int(pulse_groups[group_index]),
			0
		)

		for _pulse_index in range(
			maxi(group_size - 1, 0)
		):
			result.append(
				IntervalKind.SHORT
			)

		if group_index < pulse_groups.size() - 1:
			result.append(
				IntervalKind.PAUSE
			)

	return result


func get_rhythm_label() -> String:
	if pulse_groups.is_empty():
		return ""

	var parts := PackedStringArray()

	for group_size in pulse_groups:
		parts.append(
			"x".repeat(
				maxi(group_size, 0)
			)
		)

	return " . ".join(parts)


func get_debug_summary() -> String:
	return "%s | %s | x%.2f %.2fs%s" % [
		display_name,
		get_rhythm_label(),
		attraction_multiplier,
		boost_duration,
		(" | BROAD" if broad_attraction else ""),
	]
