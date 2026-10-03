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
	_test_milestone_order(report, plan)
	_test_early_card_plan_alignment(report, plan, early_plan)
	_test_authored_sources_exist(report, plan, world_map)
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
