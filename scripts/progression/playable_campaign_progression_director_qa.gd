extends RefCounted
class_name PlayableCampaignProgressionDirectorQA

const DirectorScript = preload(
	"res://scripts/progression/playable_campaign_progression_director.gd"
)
const PLAN_PATH := "res://data/progression/playable_campaign_loop_v1.json"


static func run() -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}
	var plan: Dictionary = _load_json(PLAN_PATH)

	_test_fresh_start(report, plan)
	_test_locked_after_noneligible_catch(report, plan)
	_test_visible_glint_becomes_cast_objective(report, plan)
	_test_armed_glint_becomes_land_objective(report, plan)
	_test_first_trip_advances_to_learn_loop(report, plan)
	_test_quantities_alone_do_not_skip_learn_loop(report, plan)
	_test_learn_loop_surfaces_salvage_after_trader(report, plan)
	_test_learn_loop_advances_to_connected_systems(report, plan)
	_test_connected_systems_prioritizes_ready_request(report, plan)
	_test_connected_systems_advances_to_specialization(report, plan)
	_test_connected_route_choice_is_not_railroaded(report, plan)
	_test_specialization_completion(report, plan)
	_test_active_competition_priority(report, plan)
	_test_pending_reward_recovery_surfaces_blocker(report, plan)

	return report


static func _test_fresh_start(report: Dictionary, plan: Dictionary) -> void:
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(0, 0, 1, 1, _cards(false, false, 0))
	)
	_record(
		report,
		"Fresh save points at fishing without pretending cards are already unlocked",
		str(snapshot.get("phase_id", "")) == "fresh_start"
		and str(snapshot.get("target_milestone_id", "")) == "first_fishing_trip"
		and str(snapshot.get("next_objective", {}).get("code", "")) == "catch_first_fish",
		"A real new save must begin in the fishing loop with zero cards."
	)


static func _test_locked_after_noneligible_catch(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(1, 1, 1, 1, _cards(false, false, 0))
	)
	_record(
		report,
		"A catch without card discovery stays in the starter-case search phase",
		str(snapshot.get("phase_id", "")) == "starter_case_search"
		and str(snapshot.get("next_objective", {}).get("code", "")) == "discover_starter_glint",
		"The director must distinguish 'has fished' from 'has discovered cards'."
	)


static func _test_visible_glint_becomes_cast_objective(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(false, false, 0)
	cards["onboarding"] = {
		"fishing_salvage_bridge": {
			"starter_search_count": 4,
			"starter_spawn_threshold": 4,
			"starter_sparkle_active": true,
			"starter_salvage_armed": false,
		}
	}
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(4, 2, 1, 1, cards)
	)
	_record(
		report,
		"A visible starter glint becomes an intentional cast objective",
		str(snapshot.get("next_objective", {}).get("code", ""))
		== "cast_at_starter_glint",
		"Once the glint exists, guidance should stop saying 'keep fishing' and point at the visible target."
	)


static func _test_armed_glint_becomes_land_objective(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(false, false, 0)
	cards["onboarding"] = {
		"fishing_salvage_bridge": {
			"starter_search_count": 4,
			"starter_spawn_threshold": 4,
			"starter_sparkle_active": true,
			"starter_salvage_armed": true,
		}
	}
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(4, 2, 1, 1, cards)
	)
	_record(
		report,
		"A cast that lands on the glint becomes a finish-the-catch objective",
		str(snapshot.get("next_objective", {}).get("code", ""))
		== "land_starter_salvage",
		"The director should acknowledge that the player already found and targeted the salvage."
	)


static func _test_first_trip_advances_to_learn_loop(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(1, 1, 1, 1, _cards(true, true, 5))
	)
	_record(
		report,
		"Five-card case discovery completes the first-trip milestone",
		str(snapshot.get("phase_id", "")) == "learn_loop"
		and _has_completed(snapshot, "first_fishing_trip"),
		"The runtime director must advance immediately after the canonical starter case."
	)


static func _test_quantities_alone_do_not_skip_learn_loop(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(8, 4, 1, 1, _cards(true, true, 8))
	)
	var target: Dictionary = snapshot.get("target_milestone", {})
	_record(
		report,
		"Milestone quantities alone do not skip the intended Learn Loop activities",
		str(snapshot.get("phase_id", "")) == "learn_loop"
		and not bool(target.get("complete", true)),
		"Eight cards and four species must not bypass the Beach Trader and shallow-salvage pacing evidence."
	)


static func _test_learn_loop_surfaces_salvage_after_trader(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(true, true, 8)
	cards["opponents"] = {
		"beach_trader": {"beaten_before": true},
	}
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(8, 4, 1, 1, cards)
	)
	_record(
		report,
		"After the Beach Trader, Learn Loop guidance points at coastal salvage",
		str(snapshot.get("phase_id", "")) == "learn_loop"
		and str(snapshot.get("next_objective", {}).get("code", ""))
		== "recover_coast_shallows_salvage",
		"The first-hour sequence should teach duel play, then return the player to fishing for salvage."
	)


static func _test_learn_loop_advances_to_connected_systems(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(true, true, 8)
	cards["opponents"] = {
		"beach_trader": {"beaten_before": true},
	}
	_set_source_count(cards, "fishing_salvage:coast_shallows", 1)
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(8, 4, 1, 1, cards)
	)
	_record(
		report,
		"Learn-loop minima advance to the connected-systems target",
		str(snapshot.get("phase_id", "")) == "connected_systems"
		and _has_completed(snapshot, "learn_loop"),
		"Runtime phase selection must follow the same minima as the campaign contract."
	)


static func _test_connected_systems_prioritizes_ready_request(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(true, true, 10)
	cards["opponents"] = {
		"beach_trader": {"beaten_before": true},
	}
	_set_source_count(cards, "fishing_salvage:coast_shallows", 1)
	cards["claimed_world_event_ids"] = PackedStringArray()
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(10, 5, 1, 2, cards)
	)
	_record(
		report,
		"A completed Harbor request becomes the most relevant connected-system objective",
		str(snapshot.get("next_objective", {}).get("code", "")) == "turn_in_harbor_request",
		"Ready one-shot rewards should be surfaced before generic grind guidance."
	)


static func _test_connected_systems_advances_to_specialization(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(true, true, 18)
	cards["opponents"] = {
		"beach_trader": {"beaten_before": true},
	}
	_set_source_count(cards, "fishing_salvage:coast_shallows", 1)
	cards["claimed_world_event_ids"] = PackedStringArray([
		"beach_demo_harbor_errand_01",
		"beach_demo_harbor_lockbox_01",
	])
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(24, 10, 2, 4, cards)
	)
	_record(
		report,
		"Connected-system minima advance to specialization",
		str(snapshot.get("phase_id", "")) == "specialization"
		and _has_completed(snapshot, "connected_systems"),
		"The director must not hold the player in hour-four guidance after its minima are met."
	)


static func _test_connected_route_choice_is_not_railroaded(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(true, true, 18)
	cards["opponents"] = {
		"beach_trader": {"beaten_before": true},
	}
	_set_source_count(cards, "fishing_salvage:coast_shallows", 1)
	_set_source_count(cards, "card_maker:*", 1)
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(24, 10, 2, 4, cards)
	)
	_record(
		report,
		"Any one connected card route can satisfy the hour-four activity choice",
		str(snapshot.get("phase_id", "")) == "specialization"
		and _has_completed(snapshot, "connected_systems"),
		"Card Maker alone must be sufficient; Harbor Request and Lockbox are alternatives, not mandatory rails."
	)


static func _test_specialization_completion(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(true, true, 35)
	cards["duel_rank"] = 2
	cards["opponents"] = {
		"beach_trader": {"beaten_before": true},
	}
	_set_source_count(cards, "fishing_salvage:coast_shallows", 1)
	_set_source_count(cards, "card_maker:*", 1)
	_set_source_count(cards, "fishing_salvage:coast_deeper", 1)
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(60, 18, 2, 6, cards)
	)
	_record(
		report,
		"Specialization minima finish the current 0-12h campaign foundation",
		str(snapshot.get("phase_id", "")) == "campaign_foundation_complete"
		and str(snapshot.get("next_objective", {}).get("code", "")) == "choose_free_play_goal"
		and _has_completed(snapshot, "specialization"),
		"Finishing the current campaign contract should transition into free-play guidance."
	)


static func _test_active_competition_priority(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(true, true, 20)
	cards["active_competition"] = {
		"active": true,
		"display_name": "Regional Card Championship",
	}
	cards["claimed_world_event_ids"] = PackedStringArray([
		"beach_demo_harbor_errand_01",
		"beach_demo_harbor_lockbox_01",
	])
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(30, 10, 2, 4, cards)
	)
	_record(
		report,
		"An active tournament overrides ordinary campaign suggestions",
		str(snapshot.get("next_objective", {}).get("code", "")) == "continue_active_competition",
		"The director must never suggest unrelated errands while a locked tournament run is active."
	)


static func _test_pending_reward_recovery_surfaces_blocker(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var cards := _cards(true, true, 8)
	cards["pending_world_reward_count"] = 1
	var snapshot: Dictionary = DirectorScript.build_snapshot_from_state(
		plan,
		_state(8, 4, 1, 1, cards)
	)
	var blocker_found: bool = false
	for raw_blocker in snapshot.get("blockers", []):
		if (
			raw_blocker is Dictionary
			and str((raw_blocker as Dictionary).get("code", ""))
			== "world_reward_recovery_pending"
		):
			blocker_found = true
			break
	_record(
		report,
		"Pending crash-safe reward recovery is visible in the campaign read model",
		blocker_found,
		"Campaign QA must surface pending delivery state instead of hiding it behind a milestone label."
	)


static func _state(
	total_catches: int,
	species_discovered: int,
	rods_owned: int,
	lures_owned: int,
	card_state: Dictionary
) -> Dictionary:
	return {
		"zenny": 100,
		"total_catches": total_catches,
		"species_discovered": species_discovered,
		"rods_owned": rods_owned,
		"lures_owned": lures_owned,
		"prepared_bait": {},
		"card_maker_recipe_statuses": [],
		"card_state": card_state,
	}


static func _cards(
	unlocked: bool,
	starter_case_discovered: bool,
	owned_unique: int
) -> Dictionary:
	return {
		"backend_available": true,
		"card_game_unlocked": unlocked,
		"starter_case_discovered": starter_case_discovered,
		"cards_owned_unique": owned_unique,
		"cards_owned_total": owned_unique,
		"duel_rank": 1,
		"duel_points": 0,
		"matches": 0,
		"wins": 0,
		"beaten_opponent_ids": PackedStringArray(),
		"opponents": {},
		"claimed_world_event_ids": PackedStringArray(),
		"pending_world_reward_count": 0,
		"active_competition": {},
		"regional_championship": {},
		"world_progression": {},
		"source_acquisition_counts": {},
		"onboarding": {},
	}


static func _set_source_count(
	cards: Dictionary,
	source_key: String,
	count: int
) -> void:
	var counts: Dictionary = cards.get("source_acquisition_counts", {})
	counts[source_key] = maxi(0, count)
	cards["source_acquisition_counts"] = counts


static func _has_completed(snapshot: Dictionary, milestone_id: String) -> bool:
	var raw_ids = snapshot.get("completed_milestone_ids", [])
	if not (raw_ids is PackedStringArray or raw_ids is Array):
		return false
	for raw_id in raw_ids:
		if str(raw_id) == milestone_id:
			return true
	return false


static func _record(
	report: Dictionary,
	label: String,
	passed: bool,
	failure_detail: String
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get(
		"failures",
		PackedStringArray()
	)
	failures.append("%s — %s" % [label, failure_detail])
	report["failures"] = failures


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).duplicate(true)
