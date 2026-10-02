extends RefCounted
class_name GameItemBackendQA

const PlayerInventoryScript = preload("res://scripts/items/player_item_inventory.gd")
const TransactionServiceScript = preload("res://scripts/items/game_item_transaction_service.gd")
const InventoryFacadeScript = preload("res://scripts/items/game_inventory_facade.gd")
const BeachInventoryScript = preload("res://scripts/beach_gathering_inventory.gd")
const FishingInventoryScript = preload("res://scripts/fishing_inventory.gd")

const QA_ITEM_SAVE := "user://player_item_inventory_qa.json"
const QA_LEGACY_SAVE := "user://beach_gathering_inventory_qa.json"


class FailingPlayerInventory:
	extends PlayerItemInventory

	func commit_changes() -> bool:
		return false


static func run(catalog: GameItemCatalogService) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}
	_test_catalog(report, catalog)
	_test_atomic_costs(report, catalog)
	_test_exchange(report, catalog)
	_test_beach_facade(report, catalog)
	_test_legacy_migration(report, catalog)
	_test_unknown_item_rejected(report, catalog)
	_test_material_sell_values(report, catalog)
	_test_shared_event_stream(report, catalog)
	_test_material_sale_transaction(report, catalog)
	_test_cross_store_notifications_are_atomic(report, catalog)
	_test_failed_save_emits_no_item_events(report, catalog)
	_test_native_adapter_coherence(report, catalog)
	_cleanup()
	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


static func _test_catalog(report: Dictionary, catalog: GameItemCatalogService) -> void:
	var material = catalog.get_by_domain(&"player", &"driftwood")
	var lure = catalog.get_by_domain(&"lure", &"straight")
	var rod = catalog.get_by_domain(&"rod", &"wooden_rod")
	var fish_defs = catalog.get_definitions_in_category(&"FISH")
	_record(
		report,
		"Unified catalog bridges materials/fish/lures/rods",
		material != null and lure != null and rod != null and not fish_defs.is_empty(),
		"Expected canonical definitions for all currently active inventory domains."
	)


static func _test_atomic_costs(report: Dictionary, catalog: GameItemCatalogService) -> void:
	var inventory := _new_inventory()
	var transaction := _new_transaction(catalog, inventory)
	var driftwood := catalog.make_item_id(&"player", &"driftwood")
	var shell := catalog.make_item_id(&"player", &"shell")
	inventory.grant(driftwood, 1, false)
	var failed: Dictionary = transaction.consume_player_items(
		{String(driftwood): 2, String(shell): 1},
		false,
		&"qa"
	)
	var preserved: bool = (
		not bool(failed.get("can_afford", false))
		and inventory.get_count(driftwood) == 1
		and inventory.get_count(shell) == 0
	)
	inventory.grant(driftwood, 1, false)
	inventory.grant(shell, 1, false)
	var success: Dictionary = transaction.consume_player_items(
		{String(driftwood): 2, String(shell): 1},
		false,
		&"qa"
	)
	var consumed: bool = (
		bool(success.get("success", false))
		and inventory.get_count(driftwood) == 0
		and inventory.get_count(shell) == 0
	)
	_record(report, "Item costs are atomic", preserved and consumed, "Failed costs must consume nothing.")
	inventory.queue_free()
	transaction.queue_free()


static func _test_exchange(report: Dictionary, catalog: GameItemCatalogService) -> void:
	var inventory := _new_inventory()
	var transaction := _new_transaction(catalog, inventory)
	var wood := catalog.make_item_id(&"player", &"driftwood")
	var shell := catalog.make_item_id(&"player", &"shell")
	inventory.grant(wood, 2, false)
	var result: Dictionary = transaction.exchange_player_items(
		{String(wood): 2},
		{String(shell): 3},
		false,
		&"qa_exchange"
	)
	_record(
		report,
		"Stackable item exchange commits once",
		bool(result.get("success", false)) and inventory.get_count(wood) == 0 and inventory.get_count(shell) == 3,
		"Cost/reward exchange should be one reversible transaction."
	)
	inventory.queue_free()
	transaction.queue_free()


static func _test_beach_facade(report: Dictionary, catalog: GameItemCatalogService) -> void:
	var inventory := _new_inventory()
	var transaction := _new_transaction(catalog, inventory)
	var beach := BeachInventoryScript.new() as BeachGatheringInventory
	beach.configure_backbone(inventory, catalog, transaction, QA_LEGACY_SAVE)
	beach.initialize()
	beach.reset_all(false)
	beach.grant(&"sea_glass", 4, false)
	var consumed: Dictionary = beach.consume_costs({"sea_glass": 3}, false)
	var canonical := catalog.make_item_id(&"player", &"sea_glass")
	_record(
		report,
		"Beach inventory facade delegates to unified storage",
		bool(consumed.get("success", false)) and beach.get_count(&"sea_glass") == 1 and inventory.get_count(canonical) == 1,
		"Legacy beach API and unified storage must report the same count."
	)
	beach.queue_free()
	inventory.queue_free()
	transaction.queue_free()


static func _test_legacy_migration(report: Dictionary, catalog: GameItemCatalogService) -> void:
	_cleanup()
	var file := FileAccess.open(QA_LEGACY_SAVE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version": 1, "counts": {"driftwood": 3, "shell": 2}}))
		file.close()
	var inventory := _new_inventory()
	var transaction := _new_transaction(catalog, inventory)
	var beach := BeachInventoryScript.new() as BeachGatheringInventory
	beach.configure_backbone(inventory, catalog, transaction, QA_LEGACY_SAVE)
	beach.initialize()
	var first_ok: bool = beach.get_count(&"driftwood") == 3 and beach.get_count(&"shell") == 2
	# Re-running migration must not duplicate old counts.
	beach.initialize()
	var second_ok: bool = beach.get_count(&"driftwood") == 3 and beach.get_count(&"shell") == 2
	_record(report, "Legacy beach-material save migrates exactly once", first_ok and second_ok, "Migration must preserve old material counts without duplication.")
	beach.queue_free()
	inventory.queue_free()
	transaction.queue_free()


static func _test_unknown_item_rejected(report: Dictionary, catalog: GameItemCatalogService) -> void:
	var inventory := _new_inventory()
	var transaction := _new_transaction(catalog, inventory)
	var result: Dictionary = transaction.grant_player_items({"player/not_real": 1}, false, &"qa")
	_record(report, "Unknown item ids are rejected", not bool(result.get("success", false)) and str(result.get("reason", "")) == "unknown_item", "Transactions must never create undeclared ids.")
	inventory.queue_free()
	transaction.queue_free()


static func _test_material_sell_values(
	report: Dictionary,
	catalog: GameItemCatalogService
) -> void:
	var definitions = catalog.get_definitions_in_category(
		GameItemCatalogService.CATEGORY_MATERIALS
	)
	var valid: bool = definitions.size() == 5
	for definition in definitions:
		if definition.sell_price_zenny <= 0:
			valid = false
			break
	_record(
		report,
		"Beach materials expose sell values through canonical definitions",
		valid,
		"All five current beach materials must have a positive provisional sell value."
	)


static func _test_shared_event_stream(
	report: Dictionary,
	catalog: GameItemCatalogService
) -> void:
	var inventory := _new_inventory()
	var facade := InventoryFacadeScript.new() as GameInventoryFacade
	facade.configure(catalog, inventory, null)
	var events: Array[Dictionary] = []
	facade.inventory_event.connect(
		func(event: Dictionary) -> void:
			events.append(event.duplicate(true))
	)
	var driftwood := catalog.make_item_id(
		&"player",
		&"driftwood"
	)
	inventory.grant(driftwood, 1, false)
	var valid: bool = false
	for event in events:
		if (
			str(event.get("kind", "")) == "item_count"
			and str(event.get("item_id", "")) == String(driftwood)
			and int(event.get("count", 0)) == 1
		):
			valid = true
			break
	_record(
		report,
		"Unified inventory event stream reports canonical item changes",
		valid,
		"Player item changes must surface through GameInventoryFacade.inventory_event."
	)
	facade.queue_free()
	inventory.queue_free()


static func _test_material_sale_transaction(
	report: Dictionary,
	catalog: GameItemCatalogService
) -> void:
	var inventory := _new_inventory()
	var wallet := FishingInventoryScript.new() as FishingInventory
	var facade := InventoryFacadeScript.new() as GameInventoryFacade
	facade.configure(catalog, inventory, wallet)
	var transaction := TransactionServiceScript.new() as GameItemTransactionService
	transaction.configure(
		catalog,
		inventory,
		facade,
		wallet
	)
	var driftwood := catalog.make_item_id(
		&"player",
		&"driftwood"
	)
	inventory.grant(driftwood, 2, false)
	wallet.set_zenny(10, false)
	var result: Dictionary = (
		transaction.sell_player_item_for_zenny(
			driftwood,
			1,
			3,
			false,
			&"qa_sale"
		)
	)
	_record(
		report,
		"Stackable material sale updates item count and wallet together",
		bool(result.get("success", false))
		and inventory.get_count(driftwood) == 1
		and wallet.get_zenny() == 13,
		"One material sale must remove exactly one item and add exactly its Zenny value."
	)
	transaction.queue_free()
	facade.queue_free()
	wallet.queue_free()
	inventory.queue_free()


static func _test_cross_store_notifications_are_atomic(
	report: Dictionary,
	catalog: GameItemCatalogService
) -> void:
	var inventory := _new_inventory()
	var wallet := FishingInventoryScript.new() as FishingInventory
	var facade := InventoryFacadeScript.new() as GameInventoryFacade
	facade.configure(catalog, inventory, wallet)
	var transaction := TransactionServiceScript.new() as GameItemTransactionService
	transaction.configure(
		catalog,
		inventory,
		facade,
		wallet
	)
	var driftwood := catalog.make_item_id(
		&"player",
		&"driftwood"
	)
	inventory.grant(driftwood, 1, false)
	wallet.set_zenny(10, false)

	var zenny_seen_by_item_listener: Array[int] = []
	var item_count_seen_by_wallet_listener: Array[int] = []
	inventory.item_count_changed.connect(
		func(changed_id: StringName, _count: int) -> void:
			if changed_id == driftwood:
				zenny_seen_by_item_listener.append(wallet.get_zenny())
	)
	wallet.zenny_changed.connect(
		func(_balance: int) -> void:
			item_count_seen_by_wallet_listener.append(
				inventory.get_count(driftwood)
			)
	)

	var result: Dictionary = transaction.sell_player_item_for_zenny(
		driftwood,
		1,
		3,
		false,
		&"qa_atomic_notifications"
	)
	var valid: bool = (
		bool(result.get("success", false))
		and zenny_seen_by_item_listener.size() == 1
		and zenny_seen_by_item_listener[0] == 13
		and item_count_seen_by_wallet_listener.size() == 1
		and item_count_seen_by_wallet_listener[0] == 0
	)
	_record(
		report,
		"Cross-store listeners only observe the final committed state",
		valid,
		"Item and wallet notifications must be deferred until both stores have been mutated successfully."
	)
	transaction.queue_free()
	facade.queue_free()
	wallet.queue_free()
	inventory.queue_free()


static func _test_failed_save_emits_no_item_events(
	report: Dictionary,
	catalog: GameItemCatalogService
) -> void:
	var inventory := FailingPlayerInventory.new()
	inventory.configure(QA_ITEM_SAVE)
	inventory.initialize()
	inventory.reset_all(false, false)
	var transaction := _new_transaction(catalog, inventory)
	var driftwood := catalog.make_item_id(
		&"player",
		&"driftwood"
	)
	inventory.grant(driftwood, 1, false)

	var count_events: Array[int] = []
	var completed_events: Array[Dictionary] = []
	inventory.item_count_changed.connect(
		func(changed_id: StringName, count: int) -> void:
			if changed_id == driftwood:
				count_events.append(count)
	)
	transaction.transaction_completed.connect(
		func(result: Dictionary) -> void:
			completed_events.append(result.duplicate(true))
	)

	var result: Dictionary = transaction.consume_player_items(
		{String(driftwood): 1},
		true,
		&"qa_forced_save_failure"
	)
	var valid: bool = (
		not bool(result.get("success", false))
		and str(result.get("reason", "")) == "save_failed"
		and inventory.get_count(driftwood) == 1
		and count_events.is_empty()
		and completed_events.is_empty()
	)
	_record(
		report,
		"Rolled-back item transactions publish no item events",
		valid,
		"A failed durable commit must restore state silently and emit no completed transaction."
	)
	inventory.queue_free()
	transaction.queue_free()


static func _test_native_adapter_coherence(
	report: Dictionary,
	catalog: GameItemCatalogService
) -> void:
	var inventory := _new_inventory()
	var transaction := _new_transaction(catalog, inventory)
	var beach := BeachInventoryScript.new() as BeachGatheringInventory
	beach.configure_backbone(
		inventory,
		catalog,
		transaction,
		QA_LEGACY_SAVE
	)
	beach.initialize()
	beach.reset_all(false)
	var sea_glass := catalog.make_item_id(
		&"player",
		&"sea_glass"
	)
	var grant_result: Dictionary = transaction.grant_player_items(
		{String(sea_glass): 3},
		false,
		&"qa_native_gather"
	)
	_record(
		report,
		"Native transactions and legacy beach adapter share one authoritative count",
		bool(grant_result.get("success", false))
		and inventory.get_count(sea_glass) == 3
		and beach.get_count(&"sea_glass") == 3,
		"Direct item-backbone changes must be immediately visible through the compatibility adapter."
	)
	beach.queue_free()
	inventory.queue_free()
	transaction.queue_free()


static func _new_inventory() -> PlayerItemInventory:
	var inventory := PlayerInventoryScript.new() as PlayerItemInventory
	inventory.configure(QA_ITEM_SAVE)
	inventory.initialize()
	inventory.reset_all(false, false)
	return inventory


static func _new_transaction(
	catalog: GameItemCatalogService,
	inventory: PlayerItemInventory
) -> GameItemTransactionService:
	var facade := InventoryFacadeScript.new() as GameInventoryFacade
	facade.configure(catalog, inventory, null)
	var transaction := TransactionServiceScript.new() as GameItemTransactionService
	transaction.configure(catalog, inventory, facade)
	# Keep the facade alive for the transaction's lifetime in this QA scope.
	transaction.add_child(facade)
	return transaction


static func _cleanup() -> void:
	for path in [QA_ITEM_SAVE, QA_LEGACY_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _record(
	report: Dictionary,
	name: String,
	passed: bool,
	detail: String
) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return

	var failures: PackedStringArray = report.get(
		"failures",
		PackedStringArray()
	)
	var failure_text: String = "%s — %s" % [
		name,
		detail,
	]
	failures.append(failure_text)
	report["failures"] = failures

	# Print immediately as well as returning it in the report. This keeps QA
	# diagnostics visible even if a caller only prints the summary.
	print("Item Backend QA FAIL: %s" % failure_text)
