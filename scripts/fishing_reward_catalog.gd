extends Resource
class_name FishingRewardCatalog

@export var rewards: Array[FishingRewardDefinition] = []


func get_all_rewards() -> Array[FishingRewardDefinition]:
	var result: Array[FishingRewardDefinition] = []
	for reward in rewards:
		if reward != null and reward.is_valid_definition():
			result.append(reward)
	return result


func get_reward_by_key(reward_key: StringName) -> FishingRewardDefinition:
	for reward in rewards:
		if reward != null and reward.reward_key == reward_key:
			return reward
	return null
