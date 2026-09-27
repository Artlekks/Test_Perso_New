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

const FishingTackleCatalogResource = preload(
	"res://data/bof4/tackle/all_tackle.tres"
)
const FishingTradeCatalogResource = preload(
	"res://data/bof4/trades/all_trades.tres"
)
const FishingRewardCatalogResource = preload(
	"res://data/bof4/rewards/all_rewards.tres"
)
const FishingJournalCatalogResource = preload(
	"res://data/bof4/journal/all_journal_data.tres"
)
const FishingProgressionCatalogResource: FishingProgressionCatalog = preload(
	"res://data/bof4/progression/all_progression.tres"
)

var progress: FishingProgress = null
var inventory: FishingInventory = null
var catch_repository: FishingCatchRepository = null
var trade_service: FishingTradeService = null
var manillo_ledger: FishingManilloLedger = null
var unlock_state: FishingUnlockState = null
var reward_service: FishingRewardService = null
var journal_service: FishingJournalService = null

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
		manillo_ledger
	)

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


func is_ready() -> bool:
	return (
		_initialized
		and progress != null
		and inventory != null
		and catch_repository != null
		and trade_service != null
		and manillo_ledger != null
		and unlock_state != null
		and reward_service != null
		and journal_service != null
	)
