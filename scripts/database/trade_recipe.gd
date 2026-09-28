extends Resource
class_name FishingTradeRecipe

enum RewardType {
	LURE,
	ROD,
}

@export_category("Identity")
@export var recipe_id: StringName = &""
@export var shop_id: StringName = &""
@export var shop_name: String = ""
@export var sort_order: int = 0

@export_category("Reward")
## Display name kept separate from stable reward_id so localization/UI wording
## can change without affecting transaction identity.
@export var reward_item: String = ""
@export var reward_type: RewardType = RewardType.LURE
@export var reward_id: StringName = &""
@export_range(1, 99, 1)
var reward_quantity: int = 1

## Rods are unique equipment. A unique reward cannot be traded again once owned.
@export var unique_reward: bool = false

## Most lure trades are repeatable. Unique rods are authored non-repeatable.
@export var repeatable: bool = true

@export_category("Fish Cost")
@export var required_fish_ids: PackedStringArray = PackedStringArray()
@export var required_counts: PackedInt32Array = PackedInt32Array()

@export_category("Manillo Economy")
## Reference/fallback Manillo trade-value units. 100 units = 1 stamp. Runtime
## value is normally calculated from the player's CURRENT record points for the
## fish being spent, matching BOF4. This field remains useful for old tools or
## scenes that do not provide FishingProgress to FishingTradeService.
@export_range(0, 100000, 1)
var manillo_value_units: int = 0

@export_multiline var source_note: String = ""


func is_valid_definition() -> bool:
	if (
		recipe_id == &""
		or shop_id == &""
		or reward_id == &""
		or reward_quantity <= 0
		or required_fish_ids.size() != required_counts.size()
		or required_fish_ids.is_empty()
	):
		return false

	for index in range(required_fish_ids.size()):
		var fish_id: String = str(
			required_fish_ids[index]
		).strip_edges()

		if fish_id.is_empty():
			return false

		if int(required_counts[index]) <= 0:
			return false

	return true


func is_cost_shape_valid() -> bool:
	# Compatibility alias retained for existing callers.
	return is_valid_definition()


func get_cost_dictionary() -> Dictionary:
	var result: Dictionary = {}

	for index in range(required_fish_ids.size()):
		var fish_id: String = str(
			required_fish_ids[index]
		).strip_edges().to_lower()
		var count: int = maxi(
			int(required_counts[index]),
			0
		)

		if fish_id.is_empty() or count <= 0:
			continue

		result[fish_id] = (
			int(result.get(fish_id, 0))
			+ count
		)

	return result


func get_manillo_value_display() -> float:
	return (
		float(maxi(manillo_value_units, 0))
		/ 100.0
	)


func is_unique_equipment_reward() -> bool:
	return (
		reward_type == RewardType.ROD
		and unique_reward
	)
