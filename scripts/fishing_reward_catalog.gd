extends Resource
class_name FishingRewardCatalog

@export var rewards: Array[FishingRewardDefinition] = []


func is_valid_catalog() -> bool:
	var seen_keys: Dictionary = {}

	for reward in rewards:
		if reward == null or not reward.is_valid_definition():
			return false

		var key: String = str(reward.reward_key).strip_edges().to_lower()
		if key.is_empty() or seen_keys.has(key):
			return false
		seen_keys[key] = true

	return true


func get_all_rewards() -> Array[FishingRewardDefinition]:
	var result: Array[FishingRewardDefinition] = []

	for reward in rewards:
		if (
			reward != null
			and reward.is_valid_definition()
		):
			result.append(reward)

	result.sort_custom(
		Callable(self, "_reward_less")
	)
	return result


func get_reward_by_key(
	reward_key: StringName
) -> FishingRewardDefinition:
	for reward in rewards:
		if (
			reward != null
			and reward.reward_key == reward_key
		):
			return reward

	return null


func get_rewards_for_source(
	source_id: StringName
) -> Array[FishingRewardDefinition]:
	var result: Array[FishingRewardDefinition] = []

	for reward in get_all_rewards():
		if reward.claim_source_id == source_id:
			result.append(reward)

	return result


func _reward_less(
	a: FishingRewardDefinition,
	b: FishingRewardDefinition
) -> bool:
	if a.sort_order == b.sort_order:
		return (
			str(a.reward_key)
			.naturalnocasecmp_to(
				str(b.reward_key)
			)
			< 0
		)

	return a.sort_order < b.sort_order
