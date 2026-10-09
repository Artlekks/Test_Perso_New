extends Node
class_name FishingSessionQA
## Explicit QA observer/fixture layer. Never required by production startup.
const Runtime = preload("res://scripts/fishing_session_services.gd")
var _catalogs: Dictionary = {}
func _catalog(key: String, resource: Resource) -> Resource:
	if not _catalogs.has(key): _catalogs[key] = resource.duplicate(true)
	return _catalogs[key]

const DEBUG_QA_PATHS: Dictionary = {
	"FishingEconomyFoundationQAScript": "res://scripts/economy/fishing_economy_foundation_qa.gd",
	"PlayableCampaignLoopQAScript": "res://scripts/progression/playable_campaign_loop_qa.gd",
	"PlayableCampaignProgressionDirectorQAScript": "res://scripts/progression/playable_campaign_progression_director_qa.gd",
	"PlayableCampaignQAGuideQAScript": "res://scripts/progression/playable_campaign_qa_guide_qa.gd",
	"PlayableCampaignPresentationQAScript": "res://scripts/progression/playable_campaign_presentation_qa.gd",
	"FishingCardMakerQAScript": "res://scripts/economy/fishing_card_maker_qa.gd",
	"FishingMasteryQAScript": "res://scripts/mastery/fishing_mastery_qa.gd",
	"FishingMasterCurrentReaderQAScript": "res://scripts/mastery/fishing_master_current_reader_qa.gd",
	"FishingMasterDepthReaderQAScript": "res://scripts/mastery/fishing_master_depth_reader_qa.gd",
	"FishingMasterStructureHunterQAScript": "res://scripts/mastery/fishing_master_structure_hunter_qa.gd",
	"FishingMasterLineFighterQAScript": "res://scripts/mastery/fishing_master_line_fighter_qa.gd",
	"FishingMasterDeepwaterVeteranQAScript": "res://scripts/mastery/fishing_master_deepwater_veteran_qa.gd",
	"FishingMasterSurfaceAnglerQAScript": "res://scripts/mastery/fishing_master_surface_angler_qa.gd",
	"FishingMasterLandingGuideQAScript": "res://scripts/mastery/fishing_master_landing_guide_qa.gd",
	"FishingMasterWeatherWatcherQAScript": "res://scripts/mastery/fishing_master_weather_watcher_qa.gd",
	"FishingMasterTideReaderQAScript": "res://scripts/mastery/fishing_master_tide_reader_qa.gd",
	"FishingMasterSignReaderQAScript": "res://scripts/mastery/fishing_master_sign_reader_qa.gd",
	"FishingMasterNatureGuideQAScript": "res://scripts/mastery/fishing_master_nature_guide_qa.gd",
	"FishingMasterDriftAnglerQAScript": "res://scripts/mastery/fishing_master_drift_angler_qa.gd",
	"FishingCephalopodShadowQAScript": "res://scripts/fishing_cephalopod_shadow_qa.gd",
	"FishingMasterGyosilQAScript": "res://scripts/progression/fishing_master_gyosil_qa.gd",
	"FishingFightCombatQAScript": "res://scripts/fishing_fight_combat_qa.gd",
	"FishingPresentationQAScript": "res://scripts/fishing_presentation_qa.gd",
	"FishingBiteTimingQAScript": "res://scripts/fishing_bite_timing_qa.gd",
	"FishingPumpReelQAScript": "res://scripts/fishing_pump_reel_qa.gd",
	"FishingRunReadingQAScript": "res://scripts/fishing_run_reading_qa.gd",
	"FishingAerialControlQAScript": "res://scripts/fishing_aerial_control_qa.gd",
	"FishingWeatherSenseQAScript": "res://scripts/fishing_weather_sense_qa.gd",
	"FishingTideSenseQAScript": "res://scripts/fishing_tide_sense_qa.gd",
	"FishingDeepWaterControlQAScript": "res://scripts/fishing_deep_water_control_qa.gd",
	"FishingSurfaceControlQAScript": "res://scripts/fishing_surface_control_qa.gd",
	"FishingLandingTechniqueQAScript": "res://scripts/fishing_landing_technique_qa.gd",
	"FishingReadFishSignQAScript": "res://scripts/fishing_read_fish_sign_qa.gd",
	"FishingOneWithNatureQAScript": "res://scripts/fishing_one_with_nature_qa.gd",
	"GameItemBackendQAScript": "res://scripts/items/game_item_backend_qa.gd",
	"BeachCraftingQAScript": "res://scripts/beach_crafting_qa.gd",
	"FishingSystemStabilityQAScript": "res://scripts/qa/fishing_system_stability_qa.gd",
	"DialogueSystemQAScript": "res://scripts/dialogue/dialogue_system_qa.gd",
	"FishingFreshSaveRehearsalQAScript": "res://scripts/qa/fishing_fresh_save_rehearsal_qa.gd",
}
var FishingEconomyFoundationQAScript = null
var PlayableCampaignLoopQAScript = null
var PlayableCampaignProgressionDirectorQAScript = null
var PlayableCampaignQAGuideQAScript = null
var PlayableCampaignPresentationQAScript = null
var FishingCardMakerQAScript = null
var FishingMasteryQAScript = null
var FishingMasterCurrentReaderQAScript = null
var FishingMasterDepthReaderQAScript = null
var FishingMasterStructureHunterQAScript = null
var FishingMasterLineFighterQAScript = null
var FishingMasterDeepwaterVeteranQAScript = null
var FishingMasterSurfaceAnglerQAScript = null
var FishingMasterLandingGuideQAScript = null
var FishingMasterWeatherWatcherQAScript = null
var FishingMasterTideReaderQAScript = null
var FishingMasterSignReaderQAScript = null
var FishingMasterNatureGuideQAScript = null
var FishingMasterDriftAnglerQAScript = null
var FishingCephalopodShadowQAScript = null
var FishingMasterGyosilQAScript = null
var FishingFightCombatQAScript = null
var FishingPresentationQAScript = null
var FishingBiteTimingQAScript = null
var FishingPumpReelQAScript = null
var FishingRunReadingQAScript = null
var FishingAerialControlQAScript = null
var FishingWeatherSenseQAScript = null
var FishingTideSenseQAScript = null
var FishingDeepWaterControlQAScript = null
var FishingSurfaceControlQAScript = null
var FishingLandingTechniqueQAScript = null
var FishingReadFishSignQAScript = null
var FishingOneWithNatureQAScript = null
var GameItemBackendQAScript = null
var BeachCraftingQAScript = null
var FishingSystemStabilityQAScript = null
var DialogueSystemQAScript = null
var FishingFreshSaveRehearsalQAScript = null
var _debug_qa_load_attempted: bool = false
var _debug_qa_scripts_ready: bool = false
var _debug_qa_load_failures: PackedStringArray = PackedStringArray()
var system_stability_qa_report: Dictionary = {}
var dialogue_qa_report: Dictionary = {}
var fresh_save_rehearsal_qa_report: Dictionary = {}
var mastery_qa_report: Dictionary = {}
var master_current_reader_qa_report: Dictionary = {}
var master_depth_reader_qa_report: Dictionary = {}
var master_structure_hunter_qa_report: Dictionary = {}
var master_line_fighter_qa_report: Dictionary = {}
var master_deepwater_veteran_qa_report: Dictionary = {}
var master_surface_angler_qa_report: Dictionary = {}
var master_landing_guide_qa_report: Dictionary = {}
var master_weather_watcher_qa_report: Dictionary = {}
var master_tide_reader_qa_report: Dictionary = {}
var master_sign_reader_qa_report: Dictionary = {}
var master_nature_guide_qa_report: Dictionary = {}
var master_drift_angler_qa_report: Dictionary = {}
var cephalopod_shadow_qa_report: Dictionary = {}
var master_gyosil_qa_report: Dictionary = {}
var fight_combat_qa_report: Dictionary = {}
var presentation_qa_report: Dictionary = {}
var bite_timing_qa_report: Dictionary = {}
var pump_reel_qa_report: Dictionary = {}
var run_reading_qa_report: Dictionary = {}
var aerial_control_qa_report: Dictionary = {}
var weather_sense_qa_report: Dictionary = {}
var tide_sense_qa_report: Dictionary = {}
var deep_water_control_qa_report: Dictionary = {}
var surface_control_qa_report: Dictionary = {}
var landing_technique_qa_report: Dictionary = {}
var read_fish_sign_qa_report: Dictionary = {}
var one_with_nature_qa_report: Dictionary = {}
var economy_foundation_qa_report: Dictionary = {}
var campaign_loop_qa_report: Dictionary = {}
var campaign_progression_director_qa_report: Dictionary = {}
var campaign_qa_guide_qa_report: Dictionary = {}
var campaign_presentation_qa_report: Dictionary = {}
var card_maker_qa_report: Dictionary = {}
var beach_crafting_qa_report: Dictionary = {}
var item_backend_qa_report: Dictionary = {}

var session: Node
var _ran := false
static func reports(owner: Node) -> Node:
	var adapter := owner.get_node_or_null("SessionQA")
	if adapter == null:
		adapter = load("res://scripts/qa/fishing_session_qa.gd").new()
		adapter.name = "SessionQA"
		adapter.session = owner
		owner.add_child(adapter)
	adapter.run_all()
	return adapter

func run_all() -> void:
	if _ran: return
	_ran = true
	_load_debug_qa_dependencies()
	if not _debug_qa_scripts_ready: return
	var provider := RuntimeAccessPolicy.current()
	var previous := bool(provider.enabled) if provider != null else false
	if provider != null: provider.set_enabled(false)
	dialogue_qa_report = DialogueSystemQAScript.run(
		_catalog("DialogueCatalogResource", Runtime.DialogueCatalogResource)
	)
	print(
		"Dialogue System QA: %d/%d tests passed."
		% [
			int(dialogue_qa_report.get("passed_count", 0)),
			int(dialogue_qa_report.get("test_count", 0)),
		]
	)
	for failure in dialogue_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Dialogue System QA: %s" % str(failure))

	item_backend_qa_report = GameItemBackendQAScript.run(session.item_catalog)
	print(
		"Item Backend QA: %d/%d tests passed."
		% [
			int(item_backend_qa_report.get("passed_count", 0)),
			int(item_backend_qa_report.get("test_count", 0)),
		]
	)
	for failure in item_backend_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Item Backend QA: %s" % str(failure))

	beach_crafting_qa_report = BeachCraftingQAScript.run(
		_catalog("BeachCraftingCatalogResource", Runtime.BeachCraftingCatalogResource),
		session.beach_crafting_service,
		_catalog("FishingTackleCatalogResource", Runtime.FishingTackleCatalogResource)
	)
	print(
		"Beach Crafting QA: %d/%d tests passed (%d recipe combinations)."
		% [
			int(beach_crafting_qa_report.get("passed_count", 0)),
			int(beach_crafting_qa_report.get("test_count", 0)),
			int(beach_crafting_qa_report.get("matrix_combination_count", 0)),
		]
	)
	for failure in beach_crafting_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Beach Crafting QA: %s" % str(failure))

	economy_foundation_qa_report = FishingEconomyFoundationQAScript.run(
		_catalog("FishingEconomyConfigResource", Runtime.FishingEconomyConfigResource),
		session.item_catalog,
		_catalog("FishingContentCatalogResource", Runtime.FishingContentCatalogResource),
		_catalog("FishingTackleCatalogResource", Runtime.FishingTackleCatalogResource),
		_catalog("FishingShopCatalogResource", Runtime.FishingShopCatalogResource)
	)
	print(
		"Economy Foundation QA: %d/%d tests passed."
		% [
			int(economy_foundation_qa_report.get("passed_count", 0)),
			int(economy_foundation_qa_report.get("test_count", 0)),
		]
	)
	for failure in economy_foundation_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Economy Foundation QA: %s" % str(failure))

	campaign_loop_qa_report = PlayableCampaignLoopQAScript.run(
		_catalog("FishingEconomyConfigResource", Runtime.FishingEconomyConfigResource)
	)
	print(
		"Campaign Loop QA: %d/%d tests passed. Simulator: %s"
		% [
			int(campaign_loop_qa_report.get("passed_count", 0)),
			int(campaign_loop_qa_report.get("test_count", 0)),
			str(campaign_loop_qa_report.get("simulator_summary", "NO RESULT")),
		]
	)
	for failure in campaign_loop_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Campaign Loop QA: %s" % str(failure))
	var economy_health: Dictionary = campaign_loop_qa_report.get("simulator_structural_health", {})
	print("Structural economy health: %s; %d provisional balance alerts" % ["PASS" if economy_health.get("structural_passed", false) else "FAIL", economy_health.get("balance_alerts", []).size()])
	for alert in campaign_loop_qa_report.get("balance_alerts", []):
		push_warning("Economy balance [%s]: %s | value %s | target %s" % [alert.check_id, alert.label, alert.value, alert.target])

	campaign_progression_director_qa_report = (
		PlayableCampaignProgressionDirectorQAScript.run()
	)
	print(
		"Campaign Director QA: %d/%d tests passed."
		% [
			int(campaign_progression_director_qa_report.get("passed_count", 0)),
			int(campaign_progression_director_qa_report.get("test_count", 0)),
		]
	)
	for failure in campaign_progression_director_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Campaign Director QA: %s" % str(failure))

	campaign_qa_guide_qa_report = PlayableCampaignQAGuideQAScript.run()
	print(
		"Campaign Guide QA: %d/%d tests passed."
		% [
			int(campaign_qa_guide_qa_report.get("passed_count", 0)),
			int(campaign_qa_guide_qa_report.get("test_count", 0)),
		]
	)
	for failure in campaign_qa_guide_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Campaign Guide QA: %s" % str(failure))

	campaign_presentation_qa_report = (
		PlayableCampaignPresentationQAScript.run()
	)
	print(
		"Campaign Presentation QA: %d/%d tests passed."
		% [
			int(campaign_presentation_qa_report.get("passed_count", 0)),
			int(campaign_presentation_qa_report.get("test_count", 0)),
		]
	)
	for failure in campaign_presentation_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Campaign Presentation QA: %s" % str(failure))

	card_maker_qa_report = FishingCardMakerQAScript.run(
		_catalog("FishingCardMakerCatalogResource", Runtime.FishingCardMakerCatalogResource),
		_catalog("FishingContentCatalogResource", Runtime.FishingContentCatalogResource),
		_catalog("TripleTriadCardCatalogResource", Runtime.TripleTriadCardCatalogResource)
	)
	print(
		"Card Maker QA: %d/%d tests passed."
		% [
			int(card_maker_qa_report.get("passed_count", 0)),
			int(card_maker_qa_report.get("test_count", 0)),
		]
	)
	for failure in card_maker_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Card Maker QA: %s" % str(failure))

	mastery_qa_report = FishingMasteryQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource),
		_catalog("FishingMasteryQASpotResource", Runtime.FishingMasteryQASpotResource)
	)
	print(
		"Fishing Mastery QA: %d/%d tests passed."
		% [
			int(mastery_qa_report.get("passed_count", 0)),
			int(mastery_qa_report.get("test_count", 0)),
		]
	)
	for failure in mastery_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Mastery QA: %s" % str(failure))

	master_current_reader_qa_report = FishingMasterCurrentReaderQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Current Reader QA: %d/%d tests passed."
		% [
			int(master_current_reader_qa_report.get("passed_count", 0)),
			int(master_current_reader_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_current_reader_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Current Reader QA: %s" % str(failure))

	master_depth_reader_qa_report = FishingMasterDepthReaderQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Depth Reader QA: %d/%d tests passed."
		% [
			int(master_depth_reader_qa_report.get("passed_count", 0)),
			int(master_depth_reader_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_depth_reader_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Depth Reader QA: %s" % str(failure))

	master_structure_hunter_qa_report = FishingMasterStructureHunterQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Structure Hunter QA: %d/%d tests passed."
		% [
			int(master_structure_hunter_qa_report.get("passed_count", 0)),
			int(master_structure_hunter_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_structure_hunter_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Structure Hunter QA: %s" % str(failure))

	master_line_fighter_qa_report = FishingMasterLineFighterQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Line Fighter QA: %d/%d tests passed."
		% [
			int(master_line_fighter_qa_report.get("passed_count", 0)),
			int(master_line_fighter_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_line_fighter_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Line Fighter QA: %s" % str(failure))

	master_deepwater_veteran_qa_report = FishingMasterDeepwaterVeteranQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Deepwater Veteran QA: %d/%d tests passed."
		% [
			int(master_deepwater_veteran_qa_report.get("passed_count", 0)),
			int(master_deepwater_veteran_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_deepwater_veteran_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Deepwater Veteran QA: %s" % str(failure))

	master_surface_angler_qa_report = FishingMasterSurfaceAnglerQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Surface Angler QA: %d/%d tests passed."
		% [
			int(master_surface_angler_qa_report.get("passed_count", 0)),
			int(master_surface_angler_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_surface_angler_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Surface Angler QA: %s" % str(failure))

	master_landing_guide_qa_report = FishingMasterLandingGuideQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Landing Guide QA: %d/%d tests passed."
		% [
			int(master_landing_guide_qa_report.get("passed_count", 0)),
			int(master_landing_guide_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_landing_guide_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Landing Guide QA: %s" % str(failure))

	master_weather_watcher_qa_report = FishingMasterWeatherWatcherQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Weather Watcher QA: %d/%d tests passed."
		% [
			int(master_weather_watcher_qa_report.get("passed_count", 0)),
			int(master_weather_watcher_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_weather_watcher_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Weather Watcher QA: %s" % str(failure))

	master_tide_reader_qa_report = FishingMasterTideReaderQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Tide Reader QA: %d/%d tests passed."
		% [
			int(master_tide_reader_qa_report.get("passed_count", 0)),
			int(master_tide_reader_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_tide_reader_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Tide Reader QA: %s" % str(failure))

	master_sign_reader_qa_report = FishingMasterSignReaderQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Sign Reader QA: %d/%d tests passed."
		% [
			int(master_sign_reader_qa_report.get("passed_count", 0)),
			int(master_sign_reader_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_sign_reader_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Sign Reader QA: %s" % str(failure))

	master_nature_guide_qa_report = FishingMasterNatureGuideQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Nature Guide QA: %d/%d tests passed."
		% [
			int(master_nature_guide_qa_report.get("passed_count", 0)),
			int(master_nature_guide_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_nature_guide_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Nature Guide QA: %s" % str(failure))

	master_drift_angler_qa_report = FishingMasterDriftAnglerQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Master Drift Angler QA: %d/%d tests passed."
		% [
			int(master_drift_angler_qa_report.get("passed_count", 0)),
			int(master_drift_angler_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_drift_angler_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Drift Angler QA: %s" % str(failure))

	cephalopod_shadow_qa_report = FishingCephalopodShadowQAScript.run()
	print(
		"Fishing Cephalopod Shadow QA: %d/%d tests passed."
		% [
			int(cephalopod_shadow_qa_report.get("passed_count", 0)),
			int(cephalopod_shadow_qa_report.get("test_count", 0)),
		]
	)
	for failure in cephalopod_shadow_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Cephalopod Shadow QA: %s" % str(failure))

	master_gyosil_qa_report = FishingMasterGyosilQAScript.run(
		_catalog("FishingRewardCatalogResource", Runtime.FishingRewardCatalogResource)
	)
	print(
		"Fishing Master Gyosil QA: %d/%d tests passed."
		% [
			int(master_gyosil_qa_report.get("passed_count", 0)),
			int(master_gyosil_qa_report.get("test_count", 0)),
		]
	)
	for failure in master_gyosil_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Master Gyosil QA: %s" % str(failure))

	fight_combat_qa_report = FishingFightCombatQAScript.run()
	print(
		"Fishing Fight QA: %d/%d tests passed."
		% [
			int(fight_combat_qa_report.get("passed_count", 0)),
			int(fight_combat_qa_report.get("test_count", 0)),
		]
	)
	for failure in fight_combat_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Fight QA: %s" % str(failure))

	presentation_qa_report = FishingPresentationQAScript.run()
	print(
		"Fishing Presentation QA: %d/%d tests passed."
		% [
			int(presentation_qa_report.get("passed_count", 0)),
			int(presentation_qa_report.get("test_count", 0)),
		]
	)
	for failure in presentation_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Presentation QA: %s" % str(failure))

	bite_timing_qa_report = FishingBiteTimingQAScript.run()
	print(
		"Fishing Bite Timing QA: %d/%d tests passed."
		% [
			int(bite_timing_qa_report.get("passed_count", 0)),
			int(bite_timing_qa_report.get("test_count", 0)),
		]
	)
	for failure in bite_timing_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Bite Timing QA: %s" % str(failure))

	pump_reel_qa_report = FishingPumpReelQAScript.run()
	print(
		"Fishing Pump & Reel QA: %d/%d tests passed."
		% [
			int(pump_reel_qa_report.get("passed_count", 0)),
			int(pump_reel_qa_report.get("test_count", 0)),
		]
	)
	for failure in pump_reel_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Pump & Reel QA: %s" % str(failure))

	run_reading_qa_report = FishingRunReadingQAScript.run()
	print(
		"Fishing Reading the Run QA: %d/%d tests passed."
		% [
			int(run_reading_qa_report.get("passed_count", 0)),
			int(run_reading_qa_report.get("test_count", 0)),
		]
	)
	for failure in run_reading_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Reading the Run QA: %s" % str(failure))

	aerial_control_qa_report = FishingAerialControlQAScript.run()
	print(
		"Fishing Aerial Control QA: %d/%d tests passed."
		% [
			int(aerial_control_qa_report.get("passed_count", 0)),
			int(aerial_control_qa_report.get("test_count", 0)),
		]
	)
	for failure in aerial_control_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Aerial Control QA: %s" % str(failure))

	weather_sense_qa_report = FishingWeatherSenseQAScript.run(
		_catalog("FishingEnvironmentCatalogResource", Runtime.FishingEnvironmentCatalogResource),
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Weather Sense QA: %d/%d tests passed."
		% [
			int(weather_sense_qa_report.get("passed_count", 0)),
			int(weather_sense_qa_report.get("test_count", 0)),
		]
	)
	for failure in weather_sense_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Weather Sense QA: %s" % str(failure))

	tide_sense_qa_report = FishingTideSenseQAScript.run(
		_catalog("FishingEnvironmentCatalogResource", Runtime.FishingEnvironmentCatalogResource),
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource),
		_catalog("FishingMasteryQASpotResource", Runtime.FishingMasteryQASpotResource)
	)
	print(
		"Fishing Tide Sense QA: %d/%d tests passed."
		% [
			int(tide_sense_qa_report.get("passed_count", 0)),
			int(tide_sense_qa_report.get("test_count", 0)),
		]
	)
	for failure in tide_sense_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Tide Sense QA: %s" % str(failure))

	deep_water_control_qa_report = FishingDeepWaterControlQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Deep-Water Control QA: %d/%d tests passed."
		% [
			int(deep_water_control_qa_report.get("passed_count", 0)),
			int(deep_water_control_qa_report.get("test_count", 0)),
		]
	)
	for failure in deep_water_control_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Deep-Water Control QA: %s" % str(failure))

	surface_control_qa_report = FishingSurfaceControlQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Surface Control QA: %d/%d tests passed."
		% [
			int(surface_control_qa_report.get("passed_count", 0)),
			int(surface_control_qa_report.get("test_count", 0)),
		]
	)
	for failure in surface_control_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Surface Control QA: %s" % str(failure))

	landing_technique_qa_report = FishingLandingTechniqueQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Landing Technique QA: %d/%d tests passed."
		% [
			int(landing_technique_qa_report.get("passed_count", 0)),
			int(landing_technique_qa_report.get("test_count", 0)),
		]
	)
	for failure in landing_technique_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Landing Technique QA: %s" % str(failure))

	read_fish_sign_qa_report = FishingReadFishSignQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing Read Fish Sign QA: %d/%d tests passed."
		% [
			int(read_fish_sign_qa_report.get("passed_count", 0)),
			int(read_fish_sign_qa_report.get("test_count", 0)),
		]
	)
	for failure in read_fish_sign_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Read Fish Sign QA: %s" % str(failure))

	one_with_nature_qa_report = FishingOneWithNatureQAScript.run(
		_catalog("FishingMasteryTechniqueCatalogResource", Runtime.FishingMasteryTechniqueCatalogResource)
	)
	print(
		"Fishing One With Nature QA: %d/%d tests passed."
		% [
			int(one_with_nature_qa_report.get("passed_count", 0)),
			int(one_with_nature_qa_report.get("test_count", 0)),
		]
	)
	for failure in one_with_nature_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing One With Nature QA: %s" % str(failure))


	system_stability_qa_report = FishingSystemStabilityQAScript.run(session, self)
	print(
		"Fishing System Stability QA: %d/%d tests passed."
		% [
			int(system_stability_qa_report.get("passed_count", 0)),
			int(system_stability_qa_report.get("test_count", 0)),
		]
	)
	for failure in system_stability_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing System Stability QA: %s" % str(failure))

	fresh_save_rehearsal_qa_report = FishingFreshSaveRehearsalQAScript.run(session, self)
	print(
		"Fishing Fresh Save Rehearsal QA: %d/%d tests passed."
		% [
			int(fresh_save_rehearsal_qa_report.get("passed_count", 0)),
			int(fresh_save_rehearsal_qa_report.get("test_count", 0)),
		]
	)
	var rehearsal_path = fresh_save_rehearsal_qa_report.get(
		"rehearsal_path",
		PackedStringArray()
	)
	if rehearsal_path is PackedStringArray or rehearsal_path is Array:
		print(
			"Fresh Save Path: %s"
			% " -> ".join(rehearsal_path)
		)
	for failure in fresh_save_rehearsal_qa_report.get(
		"failures",
		PackedStringArray()
	):
		push_error("Fishing Fresh Save Rehearsal QA: %s" % str(failure))


	if provider != null: provider.set_enabled(previous)

func _load_debug_qa_dependencies() -> bool:
	if _debug_qa_load_attempted:
		return _debug_qa_scripts_ready
	_debug_qa_load_attempted = true
	_debug_qa_load_failures = PackedStringArray()

	var loaded: Dictionary = {}
	for dependency_name in DEBUG_QA_PATHS.keys():
		var path := str(DEBUG_QA_PATHS[dependency_name])
		var resource = ResourceLoader.load(path)
		if resource == null:
			_debug_qa_load_failures.append(
				"%s -> %s" % [str(dependency_name), path]
			)
			continue
		loaded[dependency_name] = resource

	FishingEconomyFoundationQAScript = loaded.get("FishingEconomyFoundationQAScript", null)
	PlayableCampaignLoopQAScript = loaded.get("PlayableCampaignLoopQAScript", null)
	PlayableCampaignProgressionDirectorQAScript = loaded.get("PlayableCampaignProgressionDirectorQAScript", null)
	PlayableCampaignQAGuideQAScript = loaded.get("PlayableCampaignQAGuideQAScript", null)
	PlayableCampaignPresentationQAScript = loaded.get("PlayableCampaignPresentationQAScript", null)
	FishingCardMakerQAScript = loaded.get("FishingCardMakerQAScript", null)
	FishingMasteryQAScript = loaded.get("FishingMasteryQAScript", null)
	FishingMasterCurrentReaderQAScript = loaded.get("FishingMasterCurrentReaderQAScript", null)
	FishingMasterDepthReaderQAScript = loaded.get("FishingMasterDepthReaderQAScript", null)
	FishingMasterStructureHunterQAScript = loaded.get("FishingMasterStructureHunterQAScript", null)
	FishingMasterLineFighterQAScript = loaded.get("FishingMasterLineFighterQAScript", null)
	FishingMasterDeepwaterVeteranQAScript = loaded.get("FishingMasterDeepwaterVeteranQAScript", null)
	FishingMasterSurfaceAnglerQAScript = loaded.get("FishingMasterSurfaceAnglerQAScript", null)
	FishingMasterLandingGuideQAScript = loaded.get("FishingMasterLandingGuideQAScript", null)
	FishingMasterWeatherWatcherQAScript = loaded.get("FishingMasterWeatherWatcherQAScript", null)
	FishingMasterTideReaderQAScript = loaded.get("FishingMasterTideReaderQAScript", null)
	FishingMasterSignReaderQAScript = loaded.get("FishingMasterSignReaderQAScript", null)
	FishingMasterNatureGuideQAScript = loaded.get("FishingMasterNatureGuideQAScript", null)
	FishingMasterDriftAnglerQAScript = loaded.get("FishingMasterDriftAnglerQAScript", null)
	FishingCephalopodShadowQAScript = loaded.get("FishingCephalopodShadowQAScript", null)
	FishingMasterGyosilQAScript = loaded.get("FishingMasterGyosilQAScript", null)
	FishingFightCombatQAScript = loaded.get("FishingFightCombatQAScript", null)
	FishingPresentationQAScript = loaded.get("FishingPresentationQAScript", null)
	FishingBiteTimingQAScript = loaded.get("FishingBiteTimingQAScript", null)
	FishingPumpReelQAScript = loaded.get("FishingPumpReelQAScript", null)
	FishingRunReadingQAScript = loaded.get("FishingRunReadingQAScript", null)
	FishingAerialControlQAScript = loaded.get("FishingAerialControlQAScript", null)
	FishingWeatherSenseQAScript = loaded.get("FishingWeatherSenseQAScript", null)
	FishingTideSenseQAScript = loaded.get("FishingTideSenseQAScript", null)
	FishingDeepWaterControlQAScript = loaded.get("FishingDeepWaterControlQAScript", null)
	FishingSurfaceControlQAScript = loaded.get("FishingSurfaceControlQAScript", null)
	FishingLandingTechniqueQAScript = loaded.get("FishingLandingTechniqueQAScript", null)
	FishingReadFishSignQAScript = loaded.get("FishingReadFishSignQAScript", null)
	FishingOneWithNatureQAScript = loaded.get("FishingOneWithNatureQAScript", null)
	GameItemBackendQAScript = loaded.get("GameItemBackendQAScript", null)
	BeachCraftingQAScript = loaded.get("BeachCraftingQAScript", null)
	FishingSystemStabilityQAScript = loaded.get("FishingSystemStabilityQAScript", null)
	DialogueSystemQAScript = loaded.get("DialogueSystemQAScript", null)
	FishingFreshSaveRehearsalQAScript = loaded.get("FishingFreshSaveRehearsalQAScript", null)

	_debug_qa_scripts_ready = _debug_qa_load_failures.is_empty()
	if not _debug_qa_scripts_ready:
		push_warning(
			"Fishing debug QA was isolated and skipped for this run because "
			+ "%d QA dependencies failed to load. Gameplay services will continue."
			% _debug_qa_load_failures.size()
		)
		for failure in _debug_qa_load_failures:
			push_warning("Fishing QA dependency: %s" % str(failure))
	return _debug_qa_scripts_ready


func get_debug_qa_dependency_health() -> Dictionary:
	return {
		"attempted": _debug_qa_load_attempted,
		"ready": _debug_qa_scripts_ready,
		"failure_count": _debug_qa_load_failures.size(),
		"failures": _debug_qa_load_failures.duplicate(),
	}


func get_fishing_system_stability_qa_report() -> Dictionary:
	return system_stability_qa_report.duplicate(true)


func get_dialogue_system_qa_report() -> Dictionary:
	return dialogue_qa_report.duplicate(true)


func run_dialogue_system_qa() -> Dictionary:
	if OS.is_debug_build() and not _debug_qa_scripts_ready:
		_load_debug_qa_dependencies()
	if not _debug_qa_scripts_ready:
		return {
			"available": false,
			"reason": "debug_qa_unavailable",
			"failures": _debug_qa_load_failures.duplicate(),
		}
	dialogue_qa_report = DialogueSystemQAScript.run(_catalog("DialogueCatalogResource", Runtime.DialogueCatalogResource))
	return dialogue_qa_report.duplicate(true)


func get_fishing_fresh_save_rehearsal_qa_report() -> Dictionary:
	return fresh_save_rehearsal_qa_report.duplicate(true)


func get_beach_crafting_qa_report() -> Dictionary:
	return beach_crafting_qa_report.duplicate(true)


func run_beach_crafting_qa() -> Dictionary:
	if OS.is_debug_build() and not _debug_qa_scripts_ready:
		_load_debug_qa_dependencies()
	if not _debug_qa_scripts_ready:
		return {"available": false, "reason": "debug_qa_unavailable", "failures": _debug_qa_load_failures.duplicate()}
	beach_crafting_qa_report = BeachCraftingQAScript.run(
		_catalog("BeachCraftingCatalogResource", Runtime.BeachCraftingCatalogResource),
		session.beach_crafting_service,
		_catalog("FishingTackleCatalogResource", Runtime.FishingTackleCatalogResource)
	)
	return beach_crafting_qa_report.duplicate(true)


func get_item_backend_qa_report() -> Dictionary:
	return item_backend_qa_report.duplicate(true)


func run_item_backend_qa() -> Dictionary:
	if OS.is_debug_build() and not _debug_qa_scripts_ready:
		_load_debug_qa_dependencies()
	if not _debug_qa_scripts_ready:
		return {"available": false, "reason": "debug_qa_unavailable", "failures": _debug_qa_load_failures.duplicate()}
	item_backend_qa_report = GameItemBackendQAScript.run(session.item_catalog)
	return item_backend_qa_report.duplicate(true)


func get_campaign_presentation_qa_report() -> Dictionary:
	return campaign_presentation_qa_report.duplicate(true)


func get_card_maker_qa_report() -> Dictionary:
	return card_maker_qa_report.duplicate(true)


func run_card_maker_qa() -> Dictionary:
	if OS.is_debug_build() and not _debug_qa_scripts_ready:
		_load_debug_qa_dependencies()
	if not _debug_qa_scripts_ready:
		return {"available": false, "reason": "debug_qa_unavailable", "failures": _debug_qa_load_failures.duplicate()}
	card_maker_qa_report = FishingCardMakerQAScript.run(
		_catalog("FishingCardMakerCatalogResource", Runtime.FishingCardMakerCatalogResource),
		_catalog("FishingContentCatalogResource", Runtime.FishingContentCatalogResource),
		_catalog("TripleTriadCardCatalogResource", Runtime.TripleTriadCardCatalogResource)
	)
	return card_maker_qa_report.duplicate(true)


func get_economy_foundation_qa_report() -> Dictionary:
	return economy_foundation_qa_report.duplicate(true)


func run_economy_foundation_qa() -> Dictionary:
	if OS.is_debug_build() and not _debug_qa_scripts_ready:
		_load_debug_qa_dependencies()
	if not _debug_qa_scripts_ready:
		return {"available": false, "reason": "debug_qa_unavailable", "failures": _debug_qa_load_failures.duplicate()}
	economy_foundation_qa_report = FishingEconomyFoundationQAScript.run(
		_catalog("FishingEconomyConfigResource", Runtime.FishingEconomyConfigResource),
		session.item_catalog,
		_catalog("FishingContentCatalogResource", Runtime.FishingContentCatalogResource),
		_catalog("FishingTackleCatalogResource", Runtime.FishingTackleCatalogResource),
		_catalog("FishingShopCatalogResource", Runtime.FishingShopCatalogResource)
	)
	return economy_foundation_qa_report.duplicate(true)


func get_fishing_mastery_qa_report() -> Dictionary:
	return mastery_qa_report.duplicate(true)


func get_fishing_master_gyosil_qa_report() -> Dictionary:
	return master_gyosil_qa_report.duplicate(true)


func get_fishing_cephalopod_shadow_qa_report() -> Dictionary:
	return cephalopod_shadow_qa_report.duplicate(true)


func get_fishing_master_current_reader_qa_report() -> Dictionary:
	return master_current_reader_qa_report.duplicate(true)


func get_fishing_master_depth_reader_qa_report() -> Dictionary:
	return master_depth_reader_qa_report.duplicate(true)


func get_fishing_master_structure_hunter_qa_report() -> Dictionary:
	return master_structure_hunter_qa_report.duplicate(true)


func get_fishing_master_line_fighter_qa_report() -> Dictionary:
	return master_line_fighter_qa_report.duplicate(true)


func get_fishing_master_deepwater_veteran_qa_report() -> Dictionary:
	return master_deepwater_veteran_qa_report.duplicate(true)


func get_fishing_master_surface_angler_qa_report() -> Dictionary:
	return master_surface_angler_qa_report.duplicate(true)

func get_fishing_master_landing_guide_qa_report() -> Dictionary:
	return master_landing_guide_qa_report.duplicate(true)


func get_fishing_master_weather_watcher_qa_report() -> Dictionary:
	return master_weather_watcher_qa_report.duplicate(true)


func get_fishing_master_tide_reader_qa_report() -> Dictionary:
	return master_tide_reader_qa_report.duplicate(true)


func get_fishing_master_sign_reader_qa_report() -> Dictionary:
	return master_sign_reader_qa_report.duplicate(true)

func get_fishing_master_nature_guide_qa_report() -> Dictionary:
	return master_nature_guide_qa_report.duplicate(true)


func get_fishing_master_drift_angler_qa_report() -> Dictionary:
	return master_drift_angler_qa_report.duplicate(true)


func get_fishing_fight_qa_report() -> Dictionary:
	return fight_combat_qa_report.duplicate(true)


func get_fishing_presentation_qa_report() -> Dictionary:
	return presentation_qa_report.duplicate(true)


func get_fishing_bite_timing_qa_report() -> Dictionary:
	return bite_timing_qa_report.duplicate(true)


func get_fishing_pump_reel_qa_report() -> Dictionary:
	return pump_reel_qa_report.duplicate(true)


func get_fishing_run_reading_qa_report() -> Dictionary:
	return run_reading_qa_report.duplicate(true)


func get_fishing_aerial_control_qa_report() -> Dictionary:
	return aerial_control_qa_report.duplicate(true)


func get_fishing_weather_sense_qa_report() -> Dictionary:
	return weather_sense_qa_report.duplicate(true)


func get_fishing_tide_sense_qa_report() -> Dictionary:
	return tide_sense_qa_report.duplicate(true)


func get_fishing_deep_water_control_qa_report() -> Dictionary:
	return deep_water_control_qa_report.duplicate(true)


func get_fishing_surface_control_qa_report() -> Dictionary:
	return surface_control_qa_report.duplicate(true)


func get_fishing_landing_technique_qa_report() -> Dictionary:
	return landing_technique_qa_report.duplicate(true)


func get_fishing_read_fish_sign_qa_report() -> Dictionary:
	return read_fish_sign_qa_report.duplicate(true)


func get_fishing_one_with_nature_qa_report() -> Dictionary:
	return one_with_nature_qa_report.duplicate(true)


func get_campaign_progression_director_qa_report() -> Dictionary:
	return campaign_progression_director_qa_report.duplicate(true)


func run_campaign_progression_director_qa() -> Dictionary:
	if OS.is_debug_build() and not _debug_qa_scripts_ready:
		_load_debug_qa_dependencies()
	if not _debug_qa_scripts_ready:
		return {"available": false, "reason": "debug_qa_unavailable", "failures": _debug_qa_load_failures.duplicate()}
	campaign_progression_director_qa_report = (
		PlayableCampaignProgressionDirectorQAScript.run()
	)
	return campaign_progression_director_qa_report.duplicate(true)


func get_campaign_qa_guide_qa_report() -> Dictionary:
	return campaign_qa_guide_qa_report.duplicate(true)


func run_campaign_qa_guide_qa() -> Dictionary:
	if OS.is_debug_build() and not _debug_qa_scripts_ready:
		_load_debug_qa_dependencies()
	if not _debug_qa_scripts_ready:
		return {"available": false, "reason": "debug_qa_unavailable", "failures": _debug_qa_load_failures.duplicate()}
	campaign_qa_guide_qa_report = PlayableCampaignQAGuideQAScript.run()
	return campaign_qa_guide_qa_report.duplicate(true)



func _get(property: StringName):
	return session.get(property) if session != null else null
