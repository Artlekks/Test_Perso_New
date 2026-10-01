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
const FishingSaveIntegrityServiceScript = preload(
	"res://scripts/fishing_save_integrity_service.gd"
)
const FishingSessionModifierServiceScript = preload(
	"res://scripts/fishing_session_modifier_service.gd"
)
const FishingEnvironmentServiceScript = preload(
	"res://scripts/fishing_environment_service.gd"
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
const BeachGatheringInventoryScript = preload(
	"res://scripts/beach_gathering_inventory.gd"
)
const BeachCraftingServiceScript = preload(
	"res://scripts/beach_crafting_service.gd"
)
const BeachCraftingIntegrityScript = preload(
	"res://scripts/beach_crafting_integrity.gd"
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
const FishingContentCatalogResource: FishingContentCatalog = preload(
	"res://data/bof4/catalogs/all_content.tres"
)
const BeachCraftingCatalogResource: BeachCraftingCatalog = preload(
	"res://data/crafting/beach/beach_vertical_slice_catalog.tres"
)

var progress: FishingProgress = null
var inventory: FishingInventory = null
var catch_repository: FishingCatchRepository = null
var trade_service: FishingTradeService = null
var economy_service = null
var economy_access = null
var save_integrity_service = null
var session_modifier_service = null
var environment_service = null
var fish_consumable_service = null
var manillo_ledger: FishingManilloLedger = null
var unlock_state: FishingUnlockState = null
var reward_service: FishingRewardService = null
var journal_service: FishingJournalService = null
var progression_integrity_report: Dictionary = {}
var economy_integrity_report: Dictionary = {}
var fish_effect_integrity_report: Dictionary = {}
var environment_integrity_report: Dictionary = {}
var beach_crafting_integrity_report: Dictionary = {}
var save_integrity_report: Dictionary = {}

var beach_gathering_inventory: BeachGatheringInventory = null
var beach_crafting_service: BeachCraftingService = null

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

	# Run the existing migration/enrichment path, but normal new catches are
	# committed explicitly by FishingCatchRepository.
	inventory.bind_progress(
		progress,
		false
	)

	beach_gathering_inventory = (
		BeachGatheringInventoryScript.new()
		as BeachGatheringInventory
	)
	beach_gathering_inventory.name = "BeachGatheringInventory"
	add_child(beach_gathering_inventory)
	beach_gathering_inventory.initialize()

	beach_crafting_service = (
		BeachCraftingServiceScript.new()
		as BeachCraftingService
	)
	beach_crafting_service.name = "BeachCraftingService"
	add_child(beach_crafting_service)
	beach_crafting_service.configure(
		beach_gathering_inventory,
		inventory,
		FishingTackleCatalogResource,
		BeachCraftingCatalogResource
	)

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
		trade_service
	)

	session_modifier_service = FishingSessionModifierServiceScript.new()
	session_modifier_service.name = "FishingSessionModifierService"
	add_child(session_modifier_service)
	session_modifier_service.configure(FishingFishEffectCatalogResource)

	environment_service = FishingEnvironmentServiceScript.new()
	environment_service.name = "FishingEnvironmentService"
	add_child(environment_service)
	environment_service.configure(FishingEnvironmentCatalogResource)

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
		FishingTradeCatalogResource
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


func get_beach_gathering_inventory() -> BeachGatheringInventory:
	return beach_gathering_inventory


func get_beach_crafting_service() -> BeachCraftingService:
	return beach_crafting_service


func bind_loadout(loadout) -> Dictionary:
	if loadout == null:
		return {}
	loadout.configure_persistence(
		inventory,
		FishingTackleCatalogResource
	)
	if save_integrity_service == null:
		return {}
	save_integrity_report = save_integrity_service.bind_loadout(loadout)
	return save_integrity_report.duplicate(true)


func save_all_fishing_state() -> Dictionary:
	if save_integrity_service == null:
		return {"durable": false, "reason": "integrity_service_unavailable"}
	return save_integrity_service.save_all()


func is_ready() -> bool:
	return (
		_initialized
		and progress != null
		and inventory != null
		and catch_repository != null
		and trade_service != null
		and economy_service != null
		and economy_access != null
		and save_integrity_service != null
		and session_modifier_service != null
		and environment_service != null
		and fish_consumable_service != null
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
