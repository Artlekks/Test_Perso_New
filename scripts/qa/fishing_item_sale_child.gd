extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const PlayerItems = preload("res://scripts/items/player_item_inventory.gd")
const Wallet = preload("res://scripts/fishing_inventory.gd")
const Catalog = preload("res://scripts/items/game_item_catalog_service.gd")
const Sale = preload("res://scripts/items/game_item_transaction_service.gd")
const BeachCatalog = preload("res://data/crafting/beach/beach_vertical_slice_catalog.tres")
const FishCatalog = preload("res://data/bof4/catalogs/all_content.tres")
const TackleCatalog = preload("res://data/bof4/tackle/all_tackle.tres")
const ShopCatalog = preload("res://data/bof4/shops/all_shops.tres")
const EconomyConfig = preload("res://data/economy/economy_foundation_v1.tres")
const ROOT := "user://sale_fault_qa"

func _initialize() -> void:
	if not Isolation.verify([ROOT, ROOT + "/fault.marker"]):
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var action := args[0]
	var folder := ROOT + "/" + args[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var items: PlayerItemInventory = PlayerItems.new()
	items.configure(folder + "/items.json")
	items.initialize()
	var wallet: FishingInventory = Wallet.new()
	wallet.configure_save_path(folder + "/wallet.json")
	wallet.initialize()
	var driftwood := &"player/driftwood"
	var ok := false
	match action:
		"setup":
			items.grant(driftwood, 2)
			wallet.set_zenny(10)
			ok = items.get_count(driftwood) == 2 and wallet.get_zenny() == 10
		"item_staging_crash":
			OS.set_environment("FISHING_QA_FAULT_STAGE", "temporary_open")
			items.grant(driftwood, 1)
			ok = false
		"verify_item_only_tmp":
			ok = items.get_count(driftwood) == 2 and wallet.get_zenny() == 10
		"baseline_interrupt", "sale", "fault_before_intent", "fault_after_intent", "fault_after_item_commit", "fault_after_wallet_commit", "fault_before_cleanup", "fail_item_commit", "fail_wallet_commit", "fail_cleanup", "pending_sell", "blocked_sale", "blocked_sale_insufficient", "retry_after_fail", "recover_fail_item", "recover_fail_wallet", "recover_fail_cleanup", "verify_before", "verify_completed":
			var catalog: GameItemCatalogService = Catalog.new()
			catalog.configure(BeachCatalog, FishCatalog, TackleCatalog, ShopCatalog, EconomyConfig)
			var sale: GameItemTransactionService = Sale.new()
			sale.configure_sale_journal_path(folder + "/pending.json")
			var stage := ""
			if action == "baseline_interrupt":
				stage = "after_item_commit"
			elif action.begins_with("fault_"):
				stage = action.trim_prefix("fault_")
			elif action.begins_with("recover_fail_"):
				stage = "fail_" + action.trim_prefix("recover_fail_") + "_recovery"
			elif action == "pending_sell" or action == "blocked_sale_insufficient":
				stage = "fail_wallet_recovery"
			elif action == "retry_after_fail":
				stage = "fail_wallet_commit"
			elif action.begins_with("fail_"):
				stage = action
			if action == "recover_fail_cleanup":
				stage = "fail_cleanup"
			OS.set_environment("FISHING_QA_SALE_STAGE", stage)
			sale.configure(catalog, items, null, wallet)
			if action == "verify_completed":
				ok = items.get_count(driftwood) == 1 and wallet.get_zenny() == 13 and not sale.has_pending_sale()
			elif action == "verify_before":
				ok = items.get_count(driftwood) == 2 and wallet.get_zenny() == 10 and not sale.has_pending_sale()
			elif action.begins_with("recover_fail_"):
				var recovery: Dictionary = sale.recover_pending_sale()
				ok = not bool(recovery.get("recovered", false)) and sale.has_pending_sale()
			elif action in ["pending_sell", "blocked_sale", "blocked_sale_insufficient"]:
				var requested := 2 if action == "blocked_sale_insufficient" else 1
				var result: Dictionary = sale.sell_player_item_for_zenny(driftwood, requested, 3)
				ok = not bool(result.get("success", false)) and result.get("reason", "") == "pending_sale_unresolved" and sale.has_pending_sale()
			elif action == "retry_after_fail":
				var first: Dictionary = sale.sell_player_item_for_zenny(driftwood, 1, 3)
				var pending_id: String = str(first.get("transaction_id", ""))
				OS.set_environment("FISHING_QA_SALE_STAGE", "")
				var retry: Dictionary = sale.sell_player_item_for_zenny(driftwood, 1, 3)
				ok = not bool(first.get("success", false)) and not pending_id.is_empty() and not bool(retry.get("success", false)) and retry.get("reason", "") == "pending_sale_recovered" and retry.get("pending_transaction_id", "") == pending_id and items.get_count(driftwood) == 1 and wallet.get_zenny() == 13 and not sale.has_pending_sale()
			else:
				var result: Dictionary = sale.sell_player_item_for_zenny(driftwood, 1, 3)
				if action == "sale":
					ok = bool(result.get("success", false)) and not sale.has_pending_sale()
				elif action == "fail_item_commit":
					ok = not bool(result.get("success", false)) and result.get("reason", "") == "item_save_failed" and sale.has_pending_sale()
				elif action == "fail_wallet_commit":
					ok = not bool(result.get("success", false)) and result.get("reason", "") == "wallet_save_failed" and sale.has_pending_sale()
				elif action == "fail_cleanup":
					ok = bool(result.get("success", false)) and bool(result.get("journal_cleanup_pending", false)) and sale.has_pending_sale()
				else:
					ok = false
			sale.free()
			catalog.free()
		"baseline_verify":
			ok = items.get_count(driftwood) == 1 and wallet.get_zenny() == 10
		_:
			ok = false
	var final_items := items.get_count(driftwood)
	var final_zenny := wallet.get_zenny()
	items.free()
	wallet.free()
	var marker := FileAccess.open(folder + "/result.marker", FileAccess.WRITE)
	if marker != null:
		marker.store_string("ok" if ok else "failed")
		marker.close()
	print("ITEM_SALE_CHILD %s items=%d zenny=%d ok=%s" % [action, final_items, final_zenny, ok])
	quit(0 if ok else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
