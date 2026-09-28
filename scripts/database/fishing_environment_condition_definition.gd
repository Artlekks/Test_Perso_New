extends Resource

## Data-only world/environment condition used by the fishing runtime.
##
## Conditions are grouped (weather, time, event, etc.). Only one condition per
## stacking_group can be active at once, while different groups compose. The
## definition never reaches into Encounter or fish state directly.

@export_category("Identity")
@export var condition_id: StringName = &""
@export var display_name: String = ""
@export var stacking_group: StringName = &"weather"
@export var tags: PackedStringArray = PackedStringArray()
@export_multiline var description: String = ""

@export_category("Bite Activity / Water Column")
@export_range(0.25, 3.0, 0.01)
var bite_activity_multiplier: float = 1.0
@export_range(0.25, 3.0, 0.01)
var surface_activity_multiplier: float = 1.0
@export_range(0.25, 3.0, 0.01)
var mid_activity_multiplier: float = 1.0
@export_range(0.25, 3.0, 0.01)
var deep_activity_multiplier: float = 1.0

@export_category("Specimen Quality")
## Chance for each extra natural specimen roll. Largest candidate wins.
## This does not directly change king_chance or guarantee a record.
@export_range(0.0, 0.75, 0.01)
var quality_bonus_roll_chance: float = 0.0
@export_range(0, 2, 1)
var quality_bonus_rolls: int = 0

@export_category("Species Activity")
## Selection multipliers by authored fish difficulty tier (Tier 1..5).
## This changes encounter frequency, not fish combat stats.
@export var tier_selection_multipliers: PackedFloat32Array = PackedFloat32Array([
	1.0, 1.0, 1.0, 1.0, 1.0
])

## Optional exact-species overrides. IDs use FishData.species_id / stable ID.
@export var species_ids: PackedStringArray = PackedStringArray()
@export var species_selection_multipliers: PackedFloat32Array = PackedFloat32Array()

## Exact species blocked while this condition is active. This is useful for
## event/weather-specific encounter tables without deleting spot entries.
@export var blocked_species_ids: PackedStringArray = PackedStringArray()

@export_category("Fight Conditions")
## These compose after fish identity + tackle. They never rewrite FishData.
@export_range(0.50, 1.75, 0.01)
var stamina_drain_multiplier: float = 1.0
@export_range(0.50, 2.0, 0.01)
var hook_off_delay_multiplier: float = 1.0
@export_range(0.50, 2.0, 0.01)
var line_tolerance_multiplier: float = 1.0
@export_range(0.50, 2.0, 0.01)
var counter_steer_multiplier: float = 1.0
@export_range(0.50, 1.75, 0.01)
var fish_pressure_multiplier: float = 1.0


func is_valid_definition() -> bool:
	if condition_id == &"" or stacking_group == &"":
		return false
	if tier_selection_multipliers.size() != 5:
		return false
	if species_ids.size() != species_selection_multipliers.size():
		return false
	if quality_bonus_rolls < 0 or quality_bonus_rolls > 2:
		return false
	if quality_bonus_roll_chance < 0.0 or quality_bonus_roll_chance > 0.75:
		return false
	for multiplier in tier_selection_multipliers:
		if multiplier < 0.0:
			return false
	for multiplier in species_selection_multipliers:
		if multiplier < 0.0:
			return false
	return true


func get_tier_selection_multiplier(tier: int) -> float:
	if tier_selection_multipliers.size() != 5:
		return 1.0
	var index: int = clampi(tier, 1, 5) - 1
	return maxf(float(tier_selection_multipliers[index]), 0.0)


func get_species_selection_multiplier(species_id: String) -> float:
	var key: String = species_id.strip_edges().to_lower()
	if key.is_empty():
		return 1.0
	for index in range(mini(species_ids.size(), species_selection_multipliers.size())):
		if str(species_ids[index]).strip_edges().to_lower() == key:
			return maxf(float(species_selection_multipliers[index]), 0.0)
	return 1.0


func is_species_blocked(species_id: String) -> bool:
	var key: String = species_id.strip_edges().to_lower()
	if key.is_empty():
		return false
	for raw_id in blocked_species_ids:
		if str(raw_id).strip_edges().to_lower() == key:
			return true
	return false


func get_depth_activity_multiplier(depth_ratio: float) -> float:
	var ratio: float = clampf(depth_ratio, 0.0, 1.0)
	if ratio <= 0.33:
		return maxf(surface_activity_multiplier, 0.0)
	if ratio >= 0.67:
		return maxf(deep_activity_multiplier, 0.0)
	return maxf(mid_activity_multiplier, 0.0)
