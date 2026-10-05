extends RefCounted
class_name FishingMasterGyosilPolicy

const SOURCE_ID: String = "gyosil"
const SPANNER_KEY: String = "gyosil_spanner_6000"
const MASTERS_ROD_KEY: String = "gyosil_masters_rod_9500"
const EXPECTED_KEYS: Array[String] = [
	SPANNER_KEY,
	MASTERS_ROD_KEY,
]


static func filter_gyosil_statuses(statuses: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for status in statuses:
		if str(status.get("claim_source_id", "")).strip_edges().to_lower() != SOURCE_ID:
			continue
		result.append(status.duplicate(true))
	for i in range(1, result.size()):
		var candidate: Dictionary = result[i]
		var j := i - 1
		while j >= 0 and _comes_before(candidate, result[j]):
			result[j + 1] = result[j]
			j -= 1
		result[j + 1] = candidate
	return result


static func get_claimable_keys(statuses: Array[Dictionary]) -> PackedStringArray:
	var result := PackedStringArray()
	for status in filter_gyosil_statuses(statuses):
		if bool(status.get("claimed", false)):
			continue
		if bool(status.get("can_claim", false)):
			result.append(str(status.get("reward_key", "")))
	return result


static func get_next_unclaimed_status(statuses: Array[Dictionary]) -> Dictionary:
	for status in filter_gyosil_statuses(statuses):
		if not bool(status.get("claimed", false)):
			return status.duplicate(true)
	return {}


static func are_all_rewards_claimed(statuses: Array[Dictionary]) -> bool:
	var filtered := filter_gyosil_statuses(statuses)
	if filtered.is_empty():
		return false
	for status in filtered:
		if not bool(status.get("claimed", false)):
			return false
	return true


static func get_progress_text(status: Dictionary) -> String:
	var condition: Dictionary = status.get("condition", {})
	var current := int(condition.get("current", 0))
	var target := int(condition.get("target", int(status.get("threshold", 0))))
	return "%d / %d fishing points" % [current, target]


static func _comes_before(a: Dictionary, b: Dictionary) -> bool:
	var at := int(a.get("threshold", 0))
	var bt := int(b.get("threshold", 0))
	if at == bt:
		return str(a.get("reward_key", "")) < str(b.get("reward_key", ""))
	return at < bt
