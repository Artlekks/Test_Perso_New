extends Resource
class_name FishingRewardDefinition

enum TriggerType {
	FISHING_POINTS,
	RANK_INDEX,
	TOTAL_CATCHES,
	SPECIES_CATCH_COUNT,
	KING_CAUGHT,
	UNLOCK_FLAG,
}

enum RewardType {
	LURE,
	ROD,
	UNLOCK_FLAG,
}

@export_category("Identity")
@export var reward_key: StringName = &""
@export var display_name: String = ""
@export_multiline var source_description: String = ""

@export_category("Condition")
@export var trigger_type: TriggerType = TriggerType.FISHING_POINTS
@export var threshold: int = 0
@export var species_id: String = ""
@export var required_flag: StringName = &""

@export_category("Reward")
@export var reward_type: RewardType = RewardType.LURE
@export var reward_item_id: StringName = &""
@export_range(1, 99, 1) var quantity: int = 1

## False means the condition only makes the reward claimable. A future NPC/menu
## can call FishingRewardService.claim_reward(). True grants immediately.
@export var auto_claim: bool = false


func is_valid_definition() -> bool:
	if reward_key == &"":
		return false

	match trigger_type:
		TriggerType.SPECIES_CATCH_COUNT, TriggerType.KING_CAUGHT:
			if species_id.strip_edges().is_empty():
				return false
		TriggerType.UNLOCK_FLAG:
			if required_flag == &"":
				return false

	match reward_type:
		RewardType.LURE, RewardType.ROD, RewardType.UNLOCK_FLAG:
			return reward_item_id != &"" and quantity > 0
		_:
			return false
