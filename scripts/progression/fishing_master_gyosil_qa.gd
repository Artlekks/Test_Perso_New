extends RefCounted
class_name FishingMasterGyosilQA

const Policy = preload("res://scripts/progression/fishing_master_gyosil_policy.gd")


static func run(reward_catalog: FishingRewardCatalog) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	var spanner: FishingRewardDefinition = null
	var master_rod: FishingRewardDefinition = null
	if reward_catalog != null:
		spanner = reward_catalog.get_reward_by_key(&"gyosil_spanner_6000")
		master_rod = reward_catalog.get_reward_by_key(&"gyosil_masters_rod_9500")

	_record(report, "Spanner reward exists", spanner != null, "The authored 6000-point reward must remain in the catalog.")
	_record(report, "Master's Rod reward exists", master_rod != null, "The authored 9500-point reward must remain in the catalog.")
	_record(report, "Spanner threshold is 6000", spanner != null and spanner.threshold == 6000, "Master Gyosil must preserve the authored 6000-point threshold.")
	_record(report, "Master's Rod threshold is 9500", master_rod != null and master_rod.threshold == 9500, "Master Gyosil must preserve the authored 9500-point threshold.")
	_record(report, "Spanner source is Gyosil", spanner != null and spanner.claim_source_id == &"gyosil", "The world NPC must claim the canonical Gyosil reward.")
	_record(report, "Master's Rod source is Gyosil", master_rod != null and master_rod.claim_source_id == &"gyosil", "The world NPC must claim the canonical Gyosil reward.")
	_record(report, "Spanner remains manual claim", spanner != null and not spanner.auto_claim, "Talking to Gyosil must matter; the rod cannot auto-grant silently.")
	_record(report, "Master's Rod remains manual claim", master_rod != null and not master_rod.auto_claim, "Talking to Gyosil must matter; the rod cannot auto-grant silently.")
	_record(report, "Spanner item id is preserved", spanner != null and spanner.reward_item_id == &"spanner", "Do not substitute a new tackle item.")
	_record(report, "Master's Rod item id is preserved", master_rod != null and master_rod.reward_item_id == &"masters_rod", "Do not substitute a new tackle item.")
	_record(report, "Gyosil owns exactly two authored point rewards", Policy.EXPECTED_KEYS.size() == 2, "This pass must not invent extra Gyosil rewards.")

	var statuses: Array[Dictionary] = [
		_make_status("other_reward", "someone_else", 100, false, true, 100, 100),
		_make_status(Policy.MASTERS_ROD_KEY, Policy.SOURCE_ID, 9500, false, false, 6200, 9500),
		_make_status(Policy.SPANNER_KEY, Policy.SOURCE_ID, 6000, false, true, 6200, 6000),
	]
	var filtered := Policy.filter_gyosil_statuses(statuses)
	_record(report, "Policy filters unrelated rewards", filtered.size() == 2, "Gyosil must not claim other NPCs' rewards.")
	_record(report, "Gyosil rewards sort by threshold", filtered.size() == 2 and str(filtered[0].get("reward_key")) == Policy.SPANNER_KEY, "Lower point reward must resolve first.")
	var claimable := Policy.get_claimable_keys(statuses)
	_record(report, "Only available Gyosil reward is claimable", claimable.size() == 1 and claimable[0] == Policy.SPANNER_KEY, "Locked high-tier rewards must remain locked.")
	var next_status := Policy.get_next_unclaimed_status(statuses)
	_record(report, "Next unclaimed reward is Spanner", str(next_status.get("reward_key", "")) == Policy.SPANNER_KEY, "The NPC should guide the player to the nearest reward milestone.")
	_record(report, "Not all rewards claimed initially", not Policy.are_all_rewards_claimed(statuses), "Completion must wait for both rewards.")
	_record(report, "Progress text uses live condition", Policy.get_progress_text(next_status) == "6200 / 6000 fishing points", "The NPC should report actual point progress, not a hardcoded guess.")

	var completed: Array[Dictionary] = [
		_make_status(Policy.SPANNER_KEY, Policy.SOURCE_ID, 6000, true, false, 9600, 6000),
		_make_status(Policy.MASTERS_ROD_KEY, Policy.SOURCE_ID, 9500, true, false, 9600, 9500),
	]
	_record(report, "All-claimed state resolves", Policy.are_all_rewards_claimed(completed), "The NPC needs a stable completion state after both rewards are taken.")
	_record(report, "No claimable rewards after completion", Policy.get_claimable_keys(completed).is_empty(), "Claimed rewards must never be offered twice.")
	_record(report, "No next reward after completion", Policy.get_next_unclaimed_status(completed).is_empty(), "Completion should not point to a phantom milestone.")

	return report


static func _make_status(
	reward_key: String,
	source_id: String,
	threshold: int,
	claimed: bool,
	can_claim: bool,
	current: int,
	target: int
) -> Dictionary:
	return {
		"reward_key": reward_key,
		"claim_source_id": source_id,
		"threshold": threshold,
		"claimed": claimed,
		"can_claim": can_claim,
		"condition": {
			"current": current,
			"target": target,
		},
	}


static func _record(report: Dictionary, label: String, passed: bool, failure: String) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [label, failure])
	report["failures"] = failures
