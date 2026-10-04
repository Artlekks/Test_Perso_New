extends Node
class_name FishingSessionServices

## Owns the persistent/runtime fishing services for one game session.
##
## FishingController no longer decides how Progress, Inventory, Journal,
## Rewards, Trades and UnlockState are created or wired together.

const FishingProgressScript = preload(
	"res://scripts/fishing_progress.gd"
)
const FishingInventoryScript = preload(
	"res://scripts/fishing_inventory.gd"
)
const FishingCatchRepositoryScript = preload(
	"res://scripts/fishing_catch_repository.gd"
)
const FishingTradeServiceScript = preload(
	"res://scripts/fishing_trade_service.gd"
)
const FishingEconomyServiceScript = preload(
	"res://scripts/fishing_economy_service.gd"
)
const FishingEconomyAccessScript = preload(
	"res://scripts/fishing_economy_access.gd"
)
const FishingCookingServiceScript = preload(
	"res://scripts/economy/fishing_cooking_service.gd"
)
const FishingPreparedBaitServiceScript = preload(
	"res://scripts/economy/fishing_prepared_bait_service.gd"
)
const FishingEconomyFoundationQAScript = preload(
	"res://scripts/economy/fishing_economy_foundation_qa.gd"
)
const PlayableCampaignLoopQAScript = preload(
	"res://scripts/progression/playable_campaign_loop_qa.gd"
)
const PlayableCampaignProgressionDirectorScript = preload(
	"res://scripts/progression/playable_campaign_progression_director.gd"
)
const PlayableCampaignProgressionDirectorQAScript = preload(
	"res://scripts/progression/playable_campaign_progression_director_qa.gd"
)
const PlayableCampaignQAControllerScript = preload(
	"res://scripts/progression/playable_campaign_qa_controller.gd"
)
const PlayableCampaignQAGuideQAScript = preload(
	"res://scripts/progression/playable_campaign_qa_guide_qa.gd"
)
const PlayableCampaignPresentationControllerScript = preload(
	"res://scripts/progression/playable_campaign_presentation_controller.gd"
)
const PlayableCampaignPresentationQAScript = preload(
	"res://scripts/progression/playable_campaign_presentation_qa.gd"
)
const FishingCardMakerServiceScript = preload(
	"res://scripts/economy/fishing_card_maker_service.gd"
)
const FishingCardMakerQAScript = preload(
	"res://scripts/economy/fishing_card_maker_qa.gd"
)
const FishingSaveIntegrityServiceScript = preload(
	"res://scripts/fishing_save_integrity_service.gd"
)
const FishingSessionModifierServiceScript = preload(
	"res://scripts/fishing_session_modifier_service.gd"
)
const FishingEnvironmentServiceScript = preload(
	"res://scripts/fishing_environment_service.gd"
)
const FishingCurrentServiceScript = preload(
	"res://scripts/fishing_current_service.gd"
)
const FishingTideServiceScript = preload(
	"res://scripts/fishing_tide_service.gd"
)
const FishingMasteryServiceScript = preload(
	"res://scripts/mastery/fishing_mastery_service.gd"
)
const FishingMasteryQAScript = preload(
	"res://scripts/mastery/fishing_mastery_qa.gd"
)
const FishingFightCombatQAScript = preload(
	"res://scripts/fishing_fight_combat_qa.gd"
)
const FishingPresentationQAScript = preload(
	"res://scripts/fishing_presentation_qa.gd"
)
const FishingBiteTimingQAScript = preload(
	"res://scripts/fishing_bite_timing_qa.gd"
)
const FishingPumpReelQAScript = preload(
	"res://scripts/fishing_pump_reel_qa.gd"
)
const FishingRunReadingQAScript = preload(
	"res://scripts/fishing_run_reading_qa.gd"
)
const FishingAerialControlQAScript = preload(
	"res://scripts/fishing_aerial_control_qa.gd"
)
const FishingWeatherSenseQAScript = preload(
	"res://scripts/fishing_weather_sense_qa.gd"
)
const FishingTideSenseQAScript = preload(
	"res://scripts/fishing_tide_sense_qa.gd"
)
const FishingDeepWaterControlQAScript = preload(
	"res://scripts/fishing_deep_water_control_qa.gd"
)
const FishingFishConsumableServiceScript = preload(
	"res://scripts/fishing_fish_consumable_service.gd"
)
const FishingManilloLedgerScript = preload(
	"res://scripts/fishing_manillo_ledger.gd"
)
const FishingUnlockStateScript = preload(
	"res://scripts/fishing_unlock_state.gd"
)
const FishingRewardServiceScript = preload(
	"res://scripts/fishing_reward_service.gd"
)
const FishingJournalServiceScript = preload(
	"res://scripts/fishing_journal_service.gd"
)
const FishingProgressionIntegrityScript = preload(
	"res://scripts/fishing_progression_integrity.gd"
)
const FishingEconomyIntegrityScript = preload(
	"res://scripts/fishing_economy_integrity.gd"
)
const FishingFishEffectIntegrityScript = preload(
	"res://scripts/fishing_fish_effect_integrity.gd"
)
const FishingEnvironmentIntegrityScript = preload(
	"res://scripts/fishing_environment_integrity.gd"
)
const FishingEnvironmentCatalogScript = preload(
	"res://scripts/fishing_environment_catalog.gd"
)
const GameItemCatalogServiceScript = preload(
	"res://scripts/items/game_item_catalog_service.gd"
)
const PlayerItemInventoryScript = preload(
	"res://scripts/items/player_item_inventory.gd"
)
const GameInventoryFacadeScript = preload(
	"res://scripts/items/game_inventory_facade.gd"
)
const GameItemTransactionServiceScript = preload(
	"res://scripts/items/game_item_transaction_service.gd"
)
const GameItemBackendQAScript = preload(
	"res://scripts/items/game_item_backend_qa.gd"
)
const BeachGatheringInventoryScript = preload(
	"res://scripts/beach_gathering_inventory.gd"
)
const BeachCraftingServiceScript = preload(
	"res://scripts/beach_crafting_service.gd"
)
const BeachCraftingIntegrityScript = preload(
	"res://scripts/beach_crafting_integrity.gd"
)
const BeachCraftingQAScript = preload(
	"res://scripts/beach_crafting_qa.gd"
)
const BeachGatheringFeedbackScene = preload(
	"res://actors/BeachGatheringFeedbackView.tscn"
)
const BeachCraftingFeelQAHUDScene = preload(
	"res://actors/BeachCraftingFeelQAHUD.tscn"
)

const FishingTackleCatalogResource = preload(
	"res://data/bof4/tackle/all_tackle.tres"
)
const FishingTradeCatalogResource = preload(
	"res://data/bof4/trades/all_trades.tres"
)
const FishingShopCatalogResource = preload(
	"res://data/bof4/shops/all_shops.tres"
)
const FishingRewardCatalogResource = preload(
	"res://data/bof4/rewards/all_rewards.tres"
)
const FishingJournalCatalogResource = preload(
	"res://data/bof4/journal/all_journal_data.tres"
)
const FishingFishEffectCatalogResource = preload(
	"res://data/bof4/effects/all_fish_effects.tres"
)
const FishingEnvironmentCatalogResource: FishingEnvironmentCatalogScript = preload(
	"res://data/bof4/environment/all_environment_conditions.tres"
)
const FishingProgressionCatalogResource: FishingProgressionCatalog = preload(
	"res://data/bof4/progression/all_progression.tres"
)
const FishingMasteryTechniqueCatalogResource: FishingMasteryTechniqueCatalog = preload(
	"res://data/bof4/mastery/all_techniques.tres"
)
const FishingTideSenseTechniqueResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/tide_sense.tres"
)
const FishingDeepWaterControlTechniqueResource: FishingMasteryTechniqueDefinition = preload(
	"res://data/bof4/mastery/deep_water_control.tres"
)
const FishingMasteryQASpotResource: FishingSpotData = preload(
	"res://data/bof4/spots/ocean_2.tres"
)
const FishingContentCatalogResource: FishingContentCatalog = preload(
	"res://data/bof4/catalogs/all_content.tres"
)
const BeachCraftingCatalogResource: BeachCraftingCatalog = preload(
	"res://data/crafting/beach/beach_vertical_slice_catalog.tres"
)
const FishingEconomyConfigResource: FishingEconomyConfig = preload(
	"res://data/economy/economy_foundation_v1.tres"
)
const FishingCardMakerCatalogResource: FishingCardMakerCatalog = preload(
	"res://data/economy/card_maker/card_maker_catalog_v1.tres"
)
const TripleTriadCardCatalogResource: Resource = preload(
	"res://data/triple_triad/card_catalog.tres"
)

var progress: FishingProgress = null
var inventory: FishingInventory = null
var catch_repository: FishingCatchRepository = null
var trade_service: FishingTradeService = null
var economy_service = null
var economy_access = null
var cooking_service: FishingCookingService = null
var prepared_bait_service: FishingPreparedBaitService = null
var card_maker_service: FishingCardMakerService = null
var save_integrity_service = null
var session_modifier_service = null
var environment_service = null
var current_service: FishingCurrentService = null
var tide_service: FishingTideService = null
var mastery_service: FishingMasteryService = null
var mastery_qa_report: Dictionary = {}
var fight_combat_qa_report: Dictionary = {}
var presentation_qa_report: Dictionary = {}
var bite_timing_qa_report: Dictionary = {}
var pump_reel_qa_report: Dictionary = {}
var run_reading_qa_report: Dictionary = {}
var aerial_control_qa_report: Dictionary = {}
var weather_sense_qa_report: Dictionary = {}
var tide_sense_qa_report: Dictionary = {}
var deep_water_control_qa_report: Dictionary = {}
var fish_consumable_service = null
var manillo_ledger: FishingManilloLedger = null
var unlock_state: FishingUnlockState = null
var reward_service: FishingRewardService = null
var journal_service: FishingJournalService = null
var progression_integrity_report: Dictionary = {}
var economy_integrity_report: Dictionary = {}
var economy_foundation_qa_report: Dictionary = {}
var campaign_loop_qa_report: Dictionary = {}
var campaign_progression_director = null
var campaign_progression_director_qa_report: Dictionary = {}
var campaign_qa_controller = null
var campaign_qa_guide_qa_report: Dictionary = {}
var campaign_presentation_controller = null
var campaign_presentation_qa_report: Dictionary = {}
var card_maker_qa_report: Dictionary = {}
var fish_effect_integrity_report: Dictionary = {}
var environment_integrity_report: Dictionary = {}
var beach_crafting_integrity_report: Dictionary = {}
var beach_crafting_qa_report: Dictionary = {}
var save_integrity_report: Dictionary = {}

var item_catalog: GameItemCatalogService = null
var player_item_inventory: PlayerItemInventory = null
var item_inventory_facade: GameInventoryFacade = null
var item_transaction_service: GameItemTransactionService = null
var item_backend_qa_report: Dictionary = {}

var beach_gathering_inventory: BeachGatheringInventory = null
var beach_crafting_service: BeachCraftingService = null
var beach_gathering_feedback_view: CanvasLayer = null
var beach_crafting_feel_qa_hud: CanvasLayer = null
var active_loadout = null
var _beach_circuit_progress: Dictionary = {}

var _initialized: bool = false


func _ready() -> void:
	initialize()


func initialize() -> void:
	if _initialized:
		# Services have idempotent configure/initialize paths, but avoid doing
		# unnecessary save loads and signal checks on every scene handoff.
		return

	_initialized = true

	progress = FishingProgressScript.new()
	progress.name = "FishingProgress"
	progress.configure_progression_catalog(
		FishingProgressionCatalogResource
	)
	add_child(progress)
	progress.initialize()

	inventory = FishingInventoryScript.new()
	inventory.name = "FishingInventory"
	add_child(inventory)
	inventory.initialize()
	inventory.ensure_new_game_starting_zenny(
		FishingEconomyConfigResource.new_game_starting_zenny,
		true
	)

	# Run the existing migration/enrichment path, but normal new catches are
	# committed explicitly by FishingCatchRepository.
	inventory.bind_progress(
		progress,
		false
	)

	item_catalog = GameItemCatalogServiceScript.new() as GameItemCatalogService
	item_catalog.name = "GameItemCatalog"
	add_child(item_catalog)
	item_catalog.configure(
		BeachCraftingCatalogResource,
		FishingContentCatalogResource,
		FishingTackleCatalogResource,
		FishingShopCatalogResource,
		FishingEconomyConfigResource
	)

	player_item_inventory = PlayerItemInventoryScript.new() as PlayerItemInventory
	player_item_inventory.name = "PlayerItemInventory"
	add_child(player_item_inventory)
	player_item_inventory.initialize()

	item_inventory_facade = GameInventoryFacadeScript.new() as GameInventoryFacade
	item_inventory_facade.name = "GameInventoryFacade"
	add_child(item_inventory_facade)
	item_inventory_facade.configure(
		item_catalog,
		player_item_inventory,
		inventory
	)

	item_transaction_service = (
		GameItemTransactionServiceScript.new()
		as GameItemTransactionService
	)
	item_transaction_service.name = "GameItemTransactionService"
	add_child(item_transaction_service)
	item_transaction_service.configure(
		item_catalog,
		player_item_inventory,
		item_inventory_facade,
		inventory
	)

	cooking_service = (
		FishingCookingServiceScript.new()
		as FishingCookingService
	)
	cooking_service.name = "FishingCookingService"
	add_child(cooking_service)
	cooking_service.configure(
		FishingEconomyConfigResource,
		item_catalog,
		player_item_inventory,
		inventory,
		item_transaction_service
	)

	prepared_bait_service = (
		FishingPreparedBaitServiceScript.new()
		as FishingPreparedBaitService
	)
	prepared_bait_service.name = "FishingPreparedBaitService"
	add_child(prepared_bait_service)
	prepared_bait_service.configure(
		FishingEconomyConfigResource,
		item_catalog,
		player_item_inventory,
		item_transaction_service
	)

	card_maker_service = (
		FishingCardMakerServiceScript.new()
		as FishingCardMakerService
	)
	card_maker_service.name = "FishingCardMakerService"
	add_child(card_maker_service)
	card_maker_service.configure(
		FishingCardMakerCatalogResource,
		inventory,
		FishingContentCatalogResource
	)

	card_maker_service.call_deferred("recover_pending_transaction")

	beach_gathering_inventory = (
		BeachGatheringInventoryScript.new()
		as BeachGatheringInventory
	)
	beach_gathering_inventory.name = "BeachGatheringInventory"
	add_child(beach_gathering_inventory)
	beach_gathering_inventory.configure_backbone(
		player_item_inventory,
		item_catalog,
		item_transaction_service
	)
	beach_gathering_inventory.initialize()

	beach_crafting_service = (
		BeachCraftingServiceScript.new()
		as BeachCraftingService
	)
	beach_crafting_service.name = "BeachCraftingService"
	add_child(beach_crafting_service)
	beach_crafting_service.configure_item_backbone(
		item_catalog,
		player_item_inventory,
		item_transaction_service
	)
	beach_crafting_service.configure(
		beach_gathering_inventory,
		inventory,
		FishingTackleCatalogResource,
		BeachCraftingCatalogResource
	)
	_ensure_beach_gathering_feedback_view()

	beach_crafting_integrity_report = (
		BeachCraftingIntegrityScript.audit(
			BeachCraftingCatalogResource,
			FishingTackleCatalogResource
		)
	)
	for warning in beach_crafting_integrity_report.get(
		"warnings",
		PackedStringArray()
	):
		push_warning(
			"Beach crafting audit: %s" % str(warning)
		)
	for error in beach_crafting_integrity_report.get(
		"errors",
		PackedStringArray()
	):
		push_error(
			"Beach crafting audit: %s" % str(error)
		)

	if OS.is_debug_build():
		item_backend_qa_report = GameItemBackendQAScript.run(item_catalog)
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
			BeachCraftingCatalogResource,
			beach_crafting_service,
			FishingTackleCatalogResource
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
			FishingEconomyConfigResource,
			item_catalog,
			FishingContentCatalogResource,
			FishingTackleCatalogResource,
			FishingShopCatalogResource
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
			FishingEconomyConfigResource
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
			FishingCardMakerCatalogResource,
			FishingContentCatalogResource,
			TripleTriadCardCatalogResource
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

	catch_repository = FishingCatchRepositoryScript.new()
	catch_repository.name = "FishingCatchRepository"
	add_child(catch_repository)
	catch_repository.configure(
		progress,
		inventory
	)

	unlock_state = FishingUnlockStateScript.new()
	unlock_state.name = "FishingUnlockState"
	add_child(unlock_state)
	unlock_state.initialize()

	if FishingMasteryTechniqueCatalogResource.has_method("ensure_technique"):
		FishingMasteryTechniqueCatalogResource.ensure_technique(
			FishingTideSenseTechniqueResource
		)
		FishingMasteryTechniqueCatalogResource.ensure_technique(
			FishingDeepWaterControlTechniqueResource
		)

	mastery_service = FishingMasteryServiceScript.new() as FishingMasteryService
	mastery_service.name = "FishingMasteryService"
	add_child(mastery_service)
	mastery_service.configure(
		FishingMasteryTechniqueCatalogResource,
		unlock_state
	)

	current_service = FishingCurrentServiceScript.new() as FishingCurrentService
	current_service.name = "FishingCurrentService"
	add_child(current_service)

	tide_service = FishingTideServiceScript.new() as FishingTideService
	tide_service.name = "FishingTideService"
	add_child(tide_service)
	current_service.set_tide_service(tide_service)

	if OS.is_debug_build():
		mastery_qa_report = FishingMasteryQAScript.run(
			FishingMasteryTechniqueCatalogResource,
			FishingMasteryQASpotResource
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

	manillo_ledger = FishingManilloLedgerScript.new()
	manillo_ledger.name = "FishingManilloLedger"
	add_child(manillo_ledger)
	manillo_ledger.configure(
		inventory
	)

	trade_service = FishingTradeServiceScript.new()
	trade_service.name = "FishingTradeService"
	add_child(trade_service)
	trade_service.configure(
		inventory,
		FishingTackleCatalogResource,
		FishingTradeCatalogResource,
		manillo_ledger,
		progress
	)

	economy_service = FishingEconomyServiceScript.new()
	economy_service.name = "FishingEconomyService"
	add_child(economy_service)
	economy_service.configure(
		inventory,
		FishingContentCatalogResource,
		FishingTackleCatalogResource,
		FishingShopCatalogResource,
		trade_service,
		FishingEconomyConfigResource
	)

	session_modifier_service = FishingSessionModifierServiceScript.new()
	session_modifier_service.name = "FishingSessionModifierService"
	add_child(session_modifier_service)
	session_modifier_service.configure(FishingFishEffectCatalogResource)

	environment_service = FishingEnvironmentServiceScript.new()
	environment_service.name = "FishingEnvironmentService"
	add_child(environment_service)
	environment_service.configure(FishingEnvironmentCatalogResource)
	if environment_service.has_method("set_mastery_service"):
		environment_service.set_mastery_service(mastery_service)
	if environment_service.has_method("set_tide_service"):
		environment_service.set_tide_service(tide_service)

	if OS.is_debug_build():
		weather_sense_qa_report = FishingWeatherSenseQAScript.run(
			FishingEnvironmentCatalogResource,
			FishingMasteryTechniqueCatalogResource
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
			FishingEnvironmentCatalogResource,
			FishingMasteryTechniqueCatalogResource,
			FishingMasteryQASpotResource
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
			FishingMasteryTechniqueCatalogResource
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

	fish_consumable_service = FishingFishConsumableServiceScript.new()
	fish_consumable_service.name = "FishingFishConsumableService"
	add_child(fish_consumable_service)
	fish_consumable_service.configure(
		inventory,
		FishingFishEffectCatalogResource,
		session_modifier_service
	)

	economy_access = FishingEconomyAccessScript.new()
	economy_access.name = "FishingEconomyAccess"
	add_child(economy_access)
	economy_access.configure(
		inventory,
		economy_service,
		trade_service,
		fish_consumable_service,
		session_modifier_service,
		FishingContentCatalogResource,
		FishingShopCatalogResource,
		FishingTradeCatalogResource
	)
	economy_access.configure_item_backbone(
		item_catalog,
		item_inventory_facade,
		item_transaction_service
	)
	# Until world NPC/shop entry points are authored, expose the complete catalog
	# through the basic vertical-slice economy menu. The access façade already
	# supports narrowing this to real shop contexts later.
	economy_access.enable_vertical_slice_full_access()

	reward_service = FishingRewardServiceScript.new()
	reward_service.name = "FishingRewardService"
	add_child(reward_service)
	reward_service.configure(
		progress,
		inventory,
		FishingTackleCatalogResource,
		unlock_state,
		FishingRewardCatalogResource
	)

	journal_service = FishingJournalServiceScript.new()
	journal_service.name = "FishingJournalService"
	add_child(journal_service)
	journal_service.configure(
		progress,
		inventory,
		FishingJournalCatalogResource
	)

	save_integrity_service = FishingSaveIntegrityServiceScript.new()
	save_integrity_service.name = "FishingSaveIntegrityService"
	add_child(save_integrity_service)
	save_integrity_service.configure(
		progress,
		inventory,
		catch_repository,
		reward_service,
		unlock_state,
		session_modifier_service,
		FishingContentCatalogResource,
		FishingTackleCatalogResource
	)
	save_integrity_report = save_integrity_service.get_last_report()
	for warning in save_integrity_report.get("warnings", PackedStringArray()):
		push_warning("Fishing save integrity: %s" % str(warning))
	for error in save_integrity_report.get("errors", PackedStringArray()):
		push_error("Fishing save integrity: %s" % str(error))

	campaign_progression_director = (
		PlayableCampaignProgressionDirectorScript.new()
	)
	campaign_progression_director.name = "PlayableCampaignProgressionDirector"
	add_child(campaign_progression_director)
	campaign_progression_director.configure(
		progress,
		inventory,
		unlock_state,
		prepared_bait_service,
		card_maker_service
	)

	campaign_presentation_controller = (
		PlayableCampaignPresentationControllerScript.new()
	)
	campaign_presentation_controller.name = (
		"PlayableCampaignPresentationController"
	)
	add_child(campaign_presentation_controller)
	campaign_presentation_controller.configure(
		campaign_progression_director
	)

	if OS.is_debug_build():
		campaign_qa_controller = PlayableCampaignQAControllerScript.new()
		campaign_qa_controller.name = "PlayableCampaignQAController"
		add_child(campaign_qa_controller)
		campaign_qa_controller.configure(
			self,
			campaign_progression_director
		)

	_run_progression_integrity_audit()
	_run_economy_integrity_audit()
	_run_fish_effect_integrity_audit()
	_run_environment_integrity_audit()


func _run_progression_integrity_audit() -> void:
	progression_integrity_report = FishingProgressionIntegrityScript.audit(
		FishingProgressionCatalogResource,
		FishingRewardCatalogResource,
		FishingContentCatalogResource
	)

	for warning in progression_integrity_report.get("warnings", PackedStringArray()):
		push_warning("Fishing progression audit: %s" % str(warning))

	for error in progression_integrity_report.get("errors", PackedStringArray()):
		push_error("Fishing progression audit: %s" % str(error))


func _run_economy_integrity_audit() -> void:
	economy_integrity_report = FishingEconomyIntegrityScript.audit(
		FishingContentCatalogResource,
		FishingShopCatalogResource,
		FishingTradeCatalogResource,
		FishingEconomyConfigResource
	)
	for warning in economy_integrity_report.get("warnings", PackedStringArray()):
		push_warning("Fishing economy audit: %s" % str(warning))
	for error in economy_integrity_report.get("errors", PackedStringArray()):
		push_error("Fishing economy audit: %s" % str(error))


func _run_fish_effect_integrity_audit() -> void:
	fish_effect_integrity_report = FishingFishEffectIntegrityScript.audit(
		FishingContentCatalogResource,
		FishingFishEffectCatalogResource
	)
	for warning in fish_effect_integrity_report.get("warnings", PackedStringArray()):
		push_warning("Fishing fish-effect audit: %s" % str(warning))
	for error in fish_effect_integrity_report.get("errors", PackedStringArray()):
		push_error("Fishing fish-effect audit: %s" % str(error))


func get_fish_effect_integrity_report() -> Dictionary:
	return fish_effect_integrity_report.duplicate(true)


func get_environment_integrity_report() -> Dictionary:
	return environment_integrity_report.duplicate(true)


func get_economy_integrity_report() -> Dictionary:
	return economy_integrity_report.duplicate(true)


func get_progression_integrity_report() -> Dictionary:
	return progression_integrity_report.duplicate(true)


func get_save_integrity_report() -> Dictionary:
	return save_integrity_report.duplicate(true)


func get_beach_crafting_integrity_report() -> Dictionary:
	return beach_crafting_integrity_report.duplicate(true)


func get_beach_crafting_qa_report() -> Dictionary:
	return beach_crafting_qa_report.duplicate(true)


func run_beach_crafting_qa() -> Dictionary:
	beach_crafting_qa_report = BeachCraftingQAScript.run(
		BeachCraftingCatalogResource,
		beach_crafting_service,
		FishingTackleCatalogResource
	)
	return beach_crafting_qa_report.duplicate(true)


func grant_beach_material(
	material_id: StringName,
	amount: int = 1
) -> Dictionary:
	var clean_amount: int = maxi(1, amount)
	if (
		item_catalog == null
		or player_item_inventory == null
		or item_transaction_service == null
	):
		return {
			"success": false,
			"reason": "item_backend_unavailable",
		}

	var definition: GameItemDefinition = item_catalog.get_by_domain(
		GameItemCatalogService.STORAGE_PLAYER,
		material_id
	)
	if (
		definition == null
		or definition.category
		!= GameItemCatalogService.CATEGORY_MATERIALS
	):
		return {
			"success": false,
			"reason": "unknown_material",
			"material_id": String(material_id),
		}

	var result: Dictionary = (
		item_transaction_service.grant_player_items(
			{
				String(definition.item_id): clean_amount,
			},
			true,
			&"beach_gathering"
		)
	)
	result["material_id"] = String(material_id)
	result["amount"] = clean_amount
	result["new_count"] = player_item_inventory.get_count(
		definition.item_id
	)
	return result


func get_item_catalog() -> GameItemCatalogService:
	return item_catalog


func get_player_item_inventory() -> PlayerItemInventory:
	return player_item_inventory


func get_item_inventory_facade() -> GameInventoryFacade:
	return item_inventory_facade


func get_item_transaction_service() -> GameItemTransactionService:
	return item_transaction_service


func get_item_backend_qa_report() -> Dictionary:
	return item_backend_qa_report.duplicate(true)


func run_item_backend_qa() -> Dictionary:
	item_backend_qa_report = GameItemBackendQAScript.run(item_catalog)
	return item_backend_qa_report.duplicate(true)


func get_economy_config() -> FishingEconomyConfig:
	return FishingEconomyConfigResource


func get_cooking_service() -> FishingCookingService:
	return cooking_service


func get_prepared_bait_service() -> FishingPreparedBaitService:
	return prepared_bait_service


func get_campaign_presentation_snapshot() -> Dictionary:
	if campaign_presentation_controller == null:
		return {}
	return campaign_presentation_controller.get_debug_snapshot()


func get_campaign_presentation_qa_report() -> Dictionary:
	return campaign_presentation_qa_report.duplicate(true)


func get_card_maker_service() -> FishingCardMakerService:
	return card_maker_service


func get_card_maker_recipe_statuses() -> Array[Dictionary]:
	if card_maker_service == null:
		return []
	return card_maker_service.get_all_recipe_snapshots()


func evaluate_card_maker_recipe(recipe_id: StringName) -> Dictionary:
	if card_maker_service == null:
		return {"can_make": false, "reason": "card_maker_unavailable"}
	return card_maker_service.evaluate_recipe(recipe_id)


func make_card_from_fish(recipe_id: StringName) -> Dictionary:
	if card_maker_service == null:
		return {"success": false, "reason": "card_maker_unavailable"}
	return card_maker_service.make_card(recipe_id, &"fishing_card_maker")


func get_card_maker_qa_report() -> Dictionary:
	return card_maker_qa_report.duplicate(true)


func run_card_maker_qa() -> Dictionary:
	card_maker_qa_report = FishingCardMakerQAScript.run(
		FishingCardMakerCatalogResource,
		FishingContentCatalogResource,
		TripleTriadCardCatalogResource
	)
	return card_maker_qa_report.duplicate(true)


func get_prepared_bait_snapshot() -> Dictionary:
	if prepared_bait_service == null:
		return {}
	return prepared_bait_service.get_runtime_snapshot()


func set_prepared_bait_auto_use(enabled: bool) -> void:
	if prepared_bait_service != null:
		prepared_bait_service.set_auto_use_enabled(enabled)


func get_economy_foundation_qa_report() -> Dictionary:
	return economy_foundation_qa_report.duplicate(true)


func run_economy_foundation_qa() -> Dictionary:
	economy_foundation_qa_report = FishingEconomyFoundationQAScript.run(
		FishingEconomyConfigResource,
		item_catalog,
		FishingContentCatalogResource,
		FishingTackleCatalogResource,
		FishingShopCatalogResource
	)
	return economy_foundation_qa_report.duplicate(true)


func get_fishing_mastery_service() -> FishingMasteryService:
	return mastery_service


func get_fishing_mastery_snapshot() -> Dictionary:
	if mastery_service == null:
		return {}
	return mastery_service.get_snapshot()


func can_learn_fishing_technique(
	technique_id: StringName,
	teacher_id: StringName
) -> Dictionary:
	if mastery_service == null:
		return {"can_learn": false, "reason": "mastery_unavailable"}
	return mastery_service.can_learn(technique_id, teacher_id)


func learn_fishing_technique(
	technique_id: StringName,
	teacher_id: StringName
) -> Dictionary:
	if mastery_service == null:
		return {"success": false, "reason": "mastery_unavailable"}
	return mastery_service.learn_technique(technique_id, teacher_id, true)


func get_fishing_mastery_qa_report() -> Dictionary:
	return mastery_qa_report.duplicate(true)


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


func get_fishing_weather_sense_snapshot(
	current_depth: float = 0.0,
	total_depth: float = 1.0
) -> Dictionary:
	if (
		environment_service == null
		or not environment_service.has_method("get_weather_sense_snapshot")
	):
		return {}
	return environment_service.get_weather_sense_snapshot(
		current_depth,
		total_depth
	)


func get_fishing_tide_sense_qa_report() -> Dictionary:
	return tide_sense_qa_report.duplicate(true)


func get_fishing_tide_sense_snapshot() -> Dictionary:
	if (
		environment_service == null
		or not environment_service.has_method("get_tide_sense_snapshot")
	):
		return {}
	return environment_service.get_tide_sense_snapshot()


func get_fishing_deep_water_control_qa_report() -> Dictionary:
	return deep_water_control_qa_report.duplicate(true)


func get_fishing_tide_service() -> FishingTideService:
	return tide_service


func get_fishing_tide_snapshot() -> Dictionary:
	if tide_service == null:
		return {}
	return tide_service.get_snapshot()


func set_fishing_tide_cycle_position(normalized_position: float) -> Dictionary:
	if tide_service == null:
		return {"success": false, "reason": "tide_service_unavailable"}
	tide_service.set_cycle_position(normalized_position)
	return {
		"success": true,
		"snapshot": tide_service.get_snapshot(),
	}


func get_fishing_current_service() -> FishingCurrentService:
	return current_service


func get_fishing_current_snapshot() -> Dictionary:
	if current_service == null:
		return {}
	return current_service.get_snapshot()


func get_campaign_progression_director():
	return campaign_progression_director


func get_campaign_progression_snapshot() -> Dictionary:
	if campaign_progression_director == null:
		return {}
	return campaign_progression_director.get_snapshot()


func get_campaign_progression_director_qa_report() -> Dictionary:
	return campaign_progression_director_qa_report.duplicate(true)


func run_campaign_progression_director_qa() -> Dictionary:
	campaign_progression_director_qa_report = (
		PlayableCampaignProgressionDirectorQAScript.run()
	)
	return campaign_progression_director_qa_report.duplicate(true)


func get_campaign_qa_guide_qa_report() -> Dictionary:
	return campaign_qa_guide_qa_report.duplicate(true)


func run_campaign_qa_guide_qa() -> Dictionary:
	campaign_qa_guide_qa_report = PlayableCampaignQAGuideQAScript.run()
	return campaign_qa_guide_qa_report.duplicate(true)


func cook_prepared_bait(
	fish_species_id: StringName,
	batch_count: int = 1
) -> Dictionary:
	if cooking_service == null:
		return {
			"success": false,
			"reason": "cooking_backend_unavailable",
		}
	return cooking_service.cook_prepared_bait(
		fish_species_id,
		batch_count,
		true
	)


func get_beach_gathering_inventory() -> BeachGatheringInventory:
	return beach_gathering_inventory


func get_beach_crafting_service() -> BeachCraftingService:
	return beach_crafting_service


func bind_loadout(loadout) -> Dictionary:
	if loadout == null:
		return {}
	active_loadout = loadout
	if beach_crafting_service != null:
		beach_crafting_service.bind_loadout(loadout)
	_ensure_beach_crafting_feel_qa_hud()
	if (
		beach_crafting_feel_qa_hud != null
		and beach_crafting_feel_qa_hud.has_method("set_loadout")
	):
		beach_crafting_feel_qa_hud.call(
			"set_loadout",
			loadout
		)
	loadout.configure_persistence(
		inventory,
		FishingTackleCatalogResource
	)
	if save_integrity_service == null:
		return {}
	save_integrity_report = save_integrity_service.bind_loadout(loadout)
	return save_integrity_report.duplicate(true)


func register_beach_gathering_circuit(
	circuit_id: StringName,
	node_count: int
) -> void:
	var clean_id: String = String(circuit_id)
	if clean_id.is_empty():
		return
	# A circuit's _ready() means a new scene visit. Nodes replenish on scene
	# reload/re-entry in this vertical slice, so progress intentionally resets.
	_beach_circuit_progress[clean_id] = {
		"node_count": maxi(0, node_count),
		"gathered_keys": {},
	}


func reset_beach_gathering_circuit_progress(
	circuit_id: StringName
) -> void:
	var clean_id: String = String(circuit_id)
	if not _beach_circuit_progress.has(clean_id):
		return
	var state: Dictionary = _beach_circuit_progress[clean_id]
	state["gathered_keys"] = {}
	_beach_circuit_progress[clean_id] = state


func notify_beach_material_gathered(
	material_id: StringName,
	amount: int,
	total_owned: int,
	circuit_id: StringName = &"",
	node_key: StringName = &""
) -> void:
	var gathered_count: int = 0
	var circuit_total: int = 0
	var clean_circuit: String = String(circuit_id)

	if (
		not clean_circuit.is_empty()
		and _beach_circuit_progress.has(clean_circuit)
	):
		var state: Dictionary = _beach_circuit_progress[clean_circuit]
		var gathered_keys = state.get("gathered_keys", {})
		if gathered_keys is Dictionary:
			var key: String = String(node_key)
			if not key.is_empty():
				gathered_keys[key] = true
			state["gathered_keys"] = gathered_keys
			gathered_count = gathered_keys.size()
		circuit_total = int(state.get("node_count", 0))
		_beach_circuit_progress[clean_circuit] = state

	var display_name: String = String(material_id)
	if beach_crafting_service != null:
		var definition: BeachMaterialDefinition = (
			beach_crafting_service.get_material_definition(
				material_id
			)
		)
		if definition != null:
			display_name = definition.display_name

	_ensure_beach_gathering_feedback_view()
	if (
		beach_gathering_feedback_view != null
		and beach_gathering_feedback_view.has_method("enqueue_gathered")
	):
		beach_gathering_feedback_view.call(
			"enqueue_gathered",
			display_name,
			amount,
			total_owned,
			gathered_count,
			circuit_total
		)


func get_beach_gathering_visit_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for raw_id in _beach_circuit_progress.keys():
		var state: Dictionary = _beach_circuit_progress[raw_id]
		var gathered_keys = state.get("gathered_keys", {})
		var gathered_count: int = 0
		if gathered_keys is Dictionary:
			gathered_count = gathered_keys.size()
		result[str(raw_id)] = {
			"node_count": int(state.get("node_count", 0)),
			"gathered_count": gathered_count,
		}
	return result


func _ensure_beach_gathering_feedback_view() -> void:
	if is_instance_valid(beach_gathering_feedback_view):
		return
	var instance = BeachGatheringFeedbackScene.instantiate()
	if instance is CanvasLayer:
		beach_gathering_feedback_view = instance as CanvasLayer
		add_child(beach_gathering_feedback_view)


func _ensure_beach_crafting_feel_qa_hud() -> void:
	if not OS.is_debug_build():
		return
	if is_instance_valid(beach_crafting_feel_qa_hud):
		return

	var instance = BeachCraftingFeelQAHUDScene.instantiate()
	if not (instance is CanvasLayer):
		return

	beach_crafting_feel_qa_hud = instance as CanvasLayer
	add_child(beach_crafting_feel_qa_hud)
	if beach_crafting_feel_qa_hud.has_method("configure"):
		beach_crafting_feel_qa_hud.call(
			"configure",
			beach_crafting_service,
			active_loadout
		)


func get_active_loadout():
	return active_loadout


func save_all_fishing_state() -> Dictionary:
	if save_integrity_service == null:
		return {"durable": false, "reason": "integrity_service_unavailable"}
	var result: Dictionary = save_integrity_service.save_all()
	var item_saved: bool = (
		player_item_inventory != null
		and player_item_inventory.commit_changes()
	)
	result["player_items"] = item_saved
	result["durable"] = bool(result.get("durable", false)) and item_saved
	return result


func is_ready() -> bool:
	return (
		_initialized
		and progress != null
		and inventory != null
		and catch_repository != null
		and trade_service != null
		and economy_service != null
		and economy_access != null
		and cooking_service != null
		and prepared_bait_service != null
		and card_maker_service != null
		and save_integrity_service != null
		and session_modifier_service != null
		and environment_service != null
		and current_service != null
		and tide_service != null
		and mastery_service != null
		and fish_consumable_service != null
		and item_catalog != null
		and player_item_inventory != null
		and item_inventory_facade != null
		and item_transaction_service != null
		and beach_gathering_inventory != null
		and beach_crafting_service != null
		and manillo_ledger != null
		and unlock_state != null
		and reward_service != null
		and journal_service != null
	)


func _run_environment_integrity_audit() -> void:
	environment_integrity_report = FishingEnvironmentIntegrityScript.audit(
		FishingEnvironmentCatalogResource,
		FishingContentCatalogResource
	)

	for warning in environment_integrity_report.get("warnings", PackedStringArray()):
		push_warning("Fishing environment audit: %s" % str(warning))

	for error in environment_integrity_report.get("errors", PackedStringArray()):
		push_error("Fishing environment audit: %s" % str(error))
