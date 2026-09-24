extends Resource
class_name FishingTradeRecipe

enum RewardType {
	LURE,
	ROD,
}

@export var shop_name: String = ""

# Display name kept separate from the stable reward id so future UI/localization
# can change wording without breaking save/trade logic.
@export var reward_item: String = ""
@export var reward_type: RewardType = RewardType.LURE
@export var reward_id: StringName = &""

@export var required_fish_ids: PackedStringArray = PackedStringArray()
@export var required_counts: PackedInt32Array = PackedInt32Array()


func is_cost_shape_valid() -> bool:
	return (
		reward_id != &""
		and required_fish_ids.size() == required_counts.size()
		and not required_fish_ids.is_empty()
	)
