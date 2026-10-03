extends RefCounted
class_name PlayableCampaignLoopQA

const EconomySimulatorScript = preload(
	"res://scripts/progression/economy_progression_simulator.gd"
)
const StarterBundle = preload(
	"res://data/triple_triad/acquisition/bundles/salvaged_card_case.tres"
)

const PLAN_PATH := "res://data/progression/playable_campaign_loop_v1.json"
const EARLY_CARD_PLAN_PATH := (
	"res://data/triple_triad/acquisition/early_progression_plan_v1.json"
)
const WORLD_MAP_PATH := (
	"res://data/triple_triad/acquisition/world_acquisition_map.json"
)

const STARTER_SPARKLE_SCRIPT_PATH := (
	"res://scripts/triple_triad/triple_triad_salvage_sparkle.gd"
)
const OPPONENT_SCENE_PATH := "res://actors/TripleTriadOpponentNPC.tscn"

const REQUIRED_WORLD_SCENES := [
	"res://actors/FishingCardMakerNPC.tscn",
	"res://actors/HarborLockbox.tscn",
	"res://actors/HarborRequestBoard.tscn",
	"res://actors/RegionalChampionshipRegistrar.tscn",
]


static func run(economy_config: FishingEconomyConfig) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}
	var plan: Dictionary = _load_json(PLAN_PATH)
	var early_plan: Dictionary = _load_json(EARLY_CARD_PLAN_PATH)
	var world_map: Dictionary = _load_json(WORLD_MAP_PATH)
	var simulator = EconomySimulatorScript.new()
	var simulation: Dictionary = simulator.run_default_suite(false)

	_test_plan_shape(report, plan)
	_test_fresh_save_contract(report, plan, economy_config)
	_test_starter_case_contract(report, plan)
	_test_starter_discovery_contract(report, plan, simulation)
	_test_card_challenge_control(report)
	_test_milestone_order(report, plan)
	_test_early_card_plan_alignment(report, plan, early_plan)
	_test_authored_sources_exist(report, plan, world_map)
	_test_activity_contract_shape(report, plan)
	_test_activity_sources_exist(report, plan, world_map)
	_test_pacing_does_not_require_unspawned_opponents(report, plan)
	_test_world_vertical_slice_presence(report)
	_test_balanced_simulation(report, plan, simulation)
	_test_simulator_health(report, simulation)

	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	report["simulator_summary"] = str(simulation.get("summary", "NO RESULT"))
	return report


static func _test_plan_shape(report: Dictionary, plan: Dictionary) -> void:
	var milestones = plan.get("milestones", [])
	_record(
		report,
		"Playable campaign plan has the four canonical fresh-save milestones",
		str(plan.get("plan_id", "")) == "playable_campaign_loop_v1"
		and milestones is Array
		and milestones.size() == 4,
		"Campaign loop v1 must define 15m, 1h, 4h and 12h milestones."
	)


static func _test_fresh_save_contract(
	report: Dictionary,
	plan: Dictionary,
	economy_config: FishingEconomyConfig
) -> void:
	var fresh = plan.get("fresh_save", {})
	var valid: bool = fresh is Dictionary and economy_config != null
	if valid:
		valid = (
			int(fresh.get("starting_zenny", -1))
			== economy_config.new_game_starting_zenny
			and int(fresh.get("starting_cards", -1)) == 0
			and int(fresh.get("starting_rods", -1)) == 1
			and int(fresh.get("starting_lures", -1)) == 1
			and str(fresh.get("starter_rod_id", "")) == "wooden_rod"
			and str(fresh.get("starter_lure_id", "")) == "straight"
			and not bool(fresh.get("card_game_unlocked", true))
		)
	_record(
		report,
		"Fresh-save campaign contract matches the live economy/loadout baseline",
		valid,
		"The campaign must start at 100z, zero cards, one Wooden Rod and one Straight lure."
	)


static func _test_starter_case_contract(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var first: Dictionary = _milestone_by_id(plan, "first_fishing_trip")
	var valid: bool = (
		StarterBundle != null
		and bool(StarterBundle.unlocks_card_game)
		and StarterBundle.card_ids.size() == 5
		and int(first.get("card_owned_min", -1)) == 5
		and int(first.get("card_owned_max", -1)) == 5
		and _source_list_has(
			first.get("required_sources", []),
			"starter_bundle",
			"salvaged_card_case"
		)
	)
	_record(
		report,
		"First fishing trip points at the real five-card Saltworn Card Case",
		valid,
		"Onboarding must not drift back to an already-unlocked or ten-card start."
	)


static func _test_starter_discovery_contract(
	report: Dictionary,
	plan: Dictionary,
	simulation: Dictionary
) -> void:
	var first: Dictionary = _milestone_by_id(plan, "first_fishing_trip")
	var assumptions: Dictionary = {}
	var raw_assumptions = simulation.get("assumptions", {})
	if raw_assumptions is Dictionary:
		assumptions = raw_assumptions as Dictionary
	var target_catches: int = int(
		assumptions.get("starter_case_target_catches", 0)
	)
	var valid: bool = (
		str(first.get("player_goal", "")).to_lower().contains("glint")
		and target_catches >= 4
		and target_catches <= 6
		and ResourceLoader.exists(STARTER_SPARKLE_SCRIPT_PATH)
	)
	_record(
		report,
		"Starter-card discovery is a visible early fishing event, not a first-catch auto grant",
		valid,
		"Campaign onboarding should surface a water glint after only a few catches and require an intentional cast."
	)


static func _test_card_challenge_control(report: Dictionary) -> void:
	var valid: bool = false
	if ResourceLoader.exists(OPPONENT_SCENE_PATH):
		var packed = load(OPPONENT_SCENE_PATH)
		if packed is PackedScene:
			var node = (packed as PackedScene).instantiate()
			if node != null:
				valid = (
					str(node.get("interaction_prompt")) == "C : Cards"
					and str(node.get("rematch_prompt")) == "C : Rematch"
				)
				node.free()
	_record(
		report,
		"Card-player interaction advertises the same C key the runtime actually uses",
		valid,
		"The first card tutorial must not teach C while the world prompt still says K."
	)


static func _test_milestone_order(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var expected_ids := [
		"first_fishing_trip",
		"learn_loop",
		"connected_systems",
		"specialization",
	]
	var expected_hours := [0.25, 1.0, 4.0, 12.0]
	var milestones = plan.get("milestones", [])
	var valid: bool = milestones is Array and milestones.size() == expected_ids.size()
	if valid:
		for index in range(expected_ids.size()):
			var milestone = milestones[index]
			if not (milestone is Dictionary):
				valid = false
				break
			if str(milestone.get("milestone_id", "")) != expected_ids[index]:
				valid = false
				break
			if not is_equal_approx(
				float(milestone.get("checkpoint_hour", -1.0)),
				float(expected_hours[index])
			):
				valid = false
				break
	_record(
		report,
		"Campaign milestones preserve the 15m / 1h / 4h / 12h spine",
		valid,
		"The progression contract must remain ordered and deterministic for QA."
	)


static func _test_early_card_plan_alignment(
	report: Dictionary,
	plan: Dictionary,
	early_plan: Dictionary
) -> void:
	var mappings := [
		["learn_loop", "learn_loop"],
		["connected_systems", "connected_systems"],
		["specialization", "specialization"],
	]
	var valid: bool = not early_plan.is_empty()
	for pair in mappings:
		if not valid:
			break
		var campaign_stage: Dictionary = _milestone_by_id(plan, str(pair[0]))
		var card_stage: Dictionary = _stage_by_id(early_plan, str(pair[1]))
		if campaign_stage.is_empty() or card_stage.is_empty():
			valid = false
			break
		if (
			int(campaign_stage.get("card_owned_min", -1))
			!= int(card_stage.get("target_owned_min", -2))
			or int(campaign_stage.get("card_owned_max", -1))
			!= int(card_stage.get("target_owned_max", -2))
		):
			valid = false
			break
	_record(
		report,
		"Campaign card targets mirror the canonical 5 / 13 / 24 / 40 acquisition spine",
		valid,
		"Whole-game progression must not invent different early card ownership targets."
	)


static func _test_authored_sources_exist(
	report: Dictionary,
	plan: Dictionary,
	world_map: Dictionary
) -> void:
	var sources = world_map.get("sources", [])
	var valid: bool = sources is Array and not sources.is_empty()
	for milestone in plan.get("milestones", []):
		if not valid:
			break
		if not (milestone is Dictionary):
			valid = false
			break
		for requirement in milestone.get("required_sources", []):
			if not (requirement is Dictionary):
				valid = false
				break
			var source_type: String = str(requirement.get("source_type", ""))
			var source_id: String = str(requirement.get("source_id", ""))
			# The starter bundle is intentionally represented by its own bundle
			# resource; every other campaign source must live in the world map.
			if source_type == "starter_bundle":
				continue
			if not _world_source_exists(sources, source_type, source_id):
				valid = false
				break
	_record(
		report,
		"Every campaign milestone references an authored acquisition source",
		valid,
		"Progression guidance must never point players toward a source that cannot exist."
	)


static func _test_activity_contract_shape(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var learn: Dictionary = _milestone_by_id(plan, "learn_loop")
	var connected: Dictionary = _milestone_by_id(plan, "connected_systems")
	var specialization: Dictionary = _milestone_by_id(plan, "specialization")
	var learn_activities = learn.get("activity_requirements", [])
	var groups = connected.get("activity_choice_groups", [])
	var specialization_activities = specialization.get("activity_requirements", [])
	var valid: bool = (
		int(plan.get("activity_evidence_version", 0)) == 1
		and learn_activities is Array
		and learn_activities.size() == 2
		and _activity_list_has(learn_activities, "beat_beach_trader")
		and _activity_list_has(learn_activities, "recover_coast_shallows_salvage")
		and groups is Array
		and groups.size() == 1
		and _choice_group_has_three_routes(groups)
		and specialization_activities is Array
		and _activity_list_has(specialization_activities, "reach_duel_rank_2")
		and _activity_list_has(specialization_activities, "recover_deeper_coast_salvage")
	)
	_record(
		report,
		"Campaign milestones include explicit activity evidence instead of quantity-only gates",
		valid,
		"H1 must prove duel + shallow salvage, H4 one connected route, and H12 Rank 2 + deeper salvage."
	)


static func _test_activity_sources_exist(
	report: Dictionary,
	plan: Dictionary,
	world_map: Dictionary
) -> void:
	var sources = world_map.get("sources", [])
	var valid: bool = sources is Array and not sources.is_empty()
	for raw_milestone in plan.get("milestones", []):
		if not valid or not (raw_milestone is Dictionary):
			valid = false
			break
		var milestone: Dictionary = raw_milestone
		var activities: Array = []
		for raw_activity in milestone.get("activity_requirements", []):
			if raw_activity is Dictionary:
				activities.append(raw_activity)
		for raw_group in milestone.get("activity_choice_groups", []):
			if not (raw_group is Dictionary):
				continue
			for raw_option in (raw_group as Dictionary).get("options", []):
				if raw_option is Dictionary:
					activities.append(raw_option)
		for raw_activity in activities:
			var activity: Dictionary = raw_activity
			var kind: String = str(activity.get("kind", ""))
			match kind:
				"source_acquired":
					if not _world_source_exists(
						sources,
						str(activity.get("source_type", "")),
						str(activity.get("source_id", ""))
					):
						valid = false
				"source_type_acquired":
					if not _world_source_type_exists(
						sources,
						str(activity.get("source_type", ""))
					):
						valid = false
				"opponent_beaten":
					if not _world_source_exists(
						sources,
						"opponent_win",
						str(activity.get("opponent_id", ""))
					):
						valid = false
				"world_event_claimed":
					if str(activity.get("event_id", "")).strip_edges().is_empty():
						valid = false
				"duel_rank_at_least":
					if int(activity.get("minimum_rank", 0)) < 1:
						valid = false
				_:
					valid = false
			if not valid:
				break
		if not valid:
			break
	_record(
		report,
		"Every pacing activity resolves to a real authored source or durable world fact",
		valid,
		"Campaign evidence must never depend on a source identifier the runtime cannot resolve."
	)


static func _test_pacing_does_not_require_unspawned_opponents(
	report: Dictionary,
	plan: Dictionary
) -> void:
	var unavailable := {
		"pier_apprentice": true,
		"gearwright": true,
		"dock_bruiser": true,
		"marsh_keeper": true,
	}
	var valid: bool = true
	for raw_milestone in plan.get("milestones", []):
		if not (raw_milestone is Dictionary):
			continue
		var milestone: Dictionary = raw_milestone
		var activities: Array = []
		activities.append_array(milestone.get("activity_requirements", []))
		for raw_group in milestone.get("activity_choice_groups", []):
			if raw_group is Dictionary:
				activities.append_array((raw_group as Dictionary).get("options", []))
		for raw_activity in activities:
			if not (raw_activity is Dictionary):
				continue
			var activity: Dictionary = raw_activity
			if (
				str(activity.get("kind", "")) == "opponent_beaten"
				and unavailable.has(str(activity.get("opponent_id", "")))
			):
				valid = false
				break
		if not valid:
			break
	_record(
		report,
		"Current beach pacing never hard-gates progress behind opponents that are not spawned yet",
		valid,
		"Pier Apprentice, Gearwright, Dock Bruiser and Marsh Keeper may define future card pools but cannot be runtime milestone requirements yet."
	)


static func _test_world_vertical_slice_presence(report: Dictionary) -> void:
	var valid: bool = true
	for scene_path in REQUIRED_WORLD_SCENES:
		if not ResourceLoader.exists(str(scene_path)):
			valid = false
			break
	_record(
		report,
		"Connected-system world interactions are physically represented on the beach",
		valid,
		"Card Maker, Harbor Lockbox, Harbor Request Board and Championship Registrar scenes must remain available."
	)


static func _test_balanced_simulation(
	report: Dictionary,
	plan: Dictionary,
	simulation: Dictionary
) -> void:
	var profiles = simulation.get("profiles", {})
	var balanced = profiles.get("BALANCED", {}) if profiles is Dictionary else {}
	var checkpoints = balanced.get("checkpoints", {}) if balanced is Dictionary else {}
	var checkpoint_keys := {
		"first_fishing_trip": "M15",
		"learn_loop": "H1",
		"connected_systems": "H4",
		"specialization": "H12",
	}
	var valid: bool = checkpoints is Dictionary and not checkpoints.is_empty()
	for milestone in plan.get("milestones", []):
		if not valid or not (milestone is Dictionary):
			valid = false
			break
		var milestone_id: String = str(milestone.get("milestone_id", ""))
		var snapshot = checkpoints.get(str(checkpoint_keys.get(milestone_id, "")), {})
		if not (snapshot is Dictionary) or snapshot.is_empty():
			valid = false
			break
		if not _snapshot_in_range(snapshot, milestone, "unique_cards", "card_owned_min", "card_owned_max"):
			valid = false
			break
		if not _snapshot_in_range(snapshot, milestone, "species_discovered", "species_discovered_min", "species_discovered_max"):
			valid = false
			break
		if int(snapshot.get("rods_owned", 0)) < int(milestone.get("rod_owned_min", 0)):
			valid = false
			break
		if int(snapshot.get("lures_owned", 0)) < int(milestone.get("lure_owned_min", 0)):
			valid = false
			break
	_record(
		report,
		"Balanced 0-12h simulation lands inside every campaign milestone envelope",
		valid,
		"The campaign contract and deterministic economy simulation must agree before human playtesting."
	)


static func _test_simulator_health(
	report: Dictionary,
	simulation: Dictionary
) -> void:
	_record(
		report,
		"Economy/progression simulator remains fully healthy after fresh-save onboarding",
		int(simulation.get("checks_passed", 0))
		== int(simulation.get("checks_total", -1))
		and int(simulation.get("checks_total", 0)) > 0,
		"Fresh-save modelling must not make the existing 0-12h economy checks fail."
	)


static func _milestone_by_id(plan: Dictionary, milestone_id: String) -> Dictionary:
	for raw in plan.get("milestones", []):
		if raw is Dictionary and str(raw.get("milestone_id", "")) == milestone_id:
			return raw
	return {}


static func _stage_by_id(plan: Dictionary, stage_id: String) -> Dictionary:
	for raw in plan.get("stages", []):
		if raw is Dictionary and str(raw.get("stage_id", "")) == stage_id:
			return raw
	return {}


static func _source_list_has(raw_sources, source_type: String, source_id: String) -> bool:
	if not (raw_sources is Array):
		return false
	for raw in raw_sources:
		if not (raw is Dictionary):
			continue
		if (
			str(raw.get("source_type", "")) == source_type
			and str(raw.get("source_id", "")) == source_id
		):
			return true
	return false


static func _world_source_exists(raw_sources, source_type: String, source_id: String) -> bool:
	if not (raw_sources is Array):
		return false
	for raw in raw_sources:
		if not (raw is Dictionary):
			continue
		if (
			str(raw.get("source_type", "")) == source_type
			and str(raw.get("source_id", "")) == source_id
		):
			return true
	return false


static func _activity_list_has(raw_activities, activity_id: String) -> bool:
	if not (raw_activities is Array):
		return false
	for raw_activity in raw_activities:
		if (
			raw_activity is Dictionary
			and str((raw_activity as Dictionary).get("activity_id", "")) == activity_id
		):
			return true
	return false


static func _choice_group_has_three_routes(raw_groups) -> bool:
	if not (raw_groups is Array) or raw_groups.size() != 1:
		return false
	var raw_group = raw_groups[0]
	if not (raw_group is Dictionary):
		return false
	var group: Dictionary = raw_group
	var options = group.get("options", [])
	return (
		str(group.get("group_id", "")) == "use_one_connected_card_route"
		and int(group.get("minimum_complete", 0)) == 1
		and options is Array
		and options.size() == 3
		and _activity_list_has(options, "use_card_maker")
		and _activity_list_has(options, "turn_in_harbor_request")
		and _activity_list_has(options, "open_harbor_lockbox")
	)


static func _world_source_type_exists(raw_sources, source_type: String) -> bool:
	if not (raw_sources is Array):
		return false
	for raw in raw_sources:
		if raw is Dictionary and str(raw.get("source_type", "")) == source_type:
			return true
	return false


static func _snapshot_in_range(
	snapshot: Dictionary,
	milestone: Dictionary,
	snapshot_field: String,
	minimum_field: String,
	maximum_field: String
) -> bool:
	var value: int = int(snapshot.get(snapshot_field, -1))
	var minimum: int = int(milestone.get(minimum_field, -1))
	var maximum: int = int(milestone.get(maximum_field, -1))
	return value >= minimum and value <= maximum


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


static func _record(
	report: Dictionary,
	label: String,
	passed: bool,
	failure: String
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [label, failure])
	report["failures"] = failures
