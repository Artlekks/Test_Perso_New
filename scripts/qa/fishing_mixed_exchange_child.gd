extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const PlayerItems = preload("res://scripts/items/player_item_inventory.gd")
const FishInventory = preload("res://scripts/fishing_inventory.gd")
const Catalog = preload("res://scripts/items/game_item_catalog_service.gd")
const Exchange = preload("res://scripts/items/game_item_transaction_service.gd")
const CatchRepository = preload("res://scripts/fishing_catch_repository.gd")
const Progress = preload("res://scripts/fishing_progress.gd")
const SaveStorage = preload("res://scripts/fishing_save_storage.gd")
const Cooking = preload("res://scripts/economy/fishing_cooking_service.gd")
const BeachCatalog = preload("res://data/crafting/beach/beach_vertical_slice_catalog.tres")
const FishCatalog = preload("res://data/bof4/catalogs/all_content.tres")
const TackleCatalog = preload("res://data/bof4/tackle/all_tackle.tres")
const ShopCatalog = preload("res://data/bof4/shops/all_shops.tres")
const EconomyConfig = preload("res://data/economy/economy_foundation_v1.tres")
const ROOT := "user://mixed_exchange_qa"

func _initialize() -> void:
	if not Isolation.verify([ROOT, ROOT + "/fault.marker"]):
		quit(1)
		return
	call_deferred("run")

func _ids(fish: FishingInventory) -> Array:
	var result := []
	for specimen in fish.get_fish_specimens("sea_bass"):
		result.append(specimen.specimen_id)
	result.sort()
	return result

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var action: String = args[0]
	var folder: String = ROOT + "/" + args[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var items: PlayerItemInventory = PlayerItems.new()
	items.configure(folder + "/items.json")
	items.initialize()
	var fish: FishingInventory = FishInventory.new()
	fish.configure_save_path(folder + "/fish.json")
	fish.initialize()
	var herb := &"player/coastal_herb"
	var bait := &"player/prepared_bait"
	var ok := false
	if action == "setup":
		items.grant(herb, 2)
		fish.add_fish_specimen("sea_bass", "Sea Bass", 31, 100, false)
		fish.add_fish_specimen("sea_bass", "Sea Bass", 52, 200, false)
		ok = items.get_count(herb) == 2 and _ids(fish) == [1, 2]
	else:
		var catalog: GameItemCatalogService = Catalog.new()
		catalog.configure(BeachCatalog, FishCatalog, TackleCatalog, ShopCatalog, EconomyConfig)
		var service: GameItemTransactionService = Exchange.new()
		service.configure_sale_journal_path(folder + "/pending.json")
		var stage := ""
		if action == "baseline_crash":
			stage = "after_item_commit"
		elif action.begins_with("fault_"):
			stage = action.trim_prefix("fault_")
		elif action == "pending_exchange" or action == "blocked_sale" or action == "catch_conflict" or action == "direct_write_blocked" or action == "cook_pending" or action == "recover_fail_fish":
			stage = "fail_fish_recovery"
		elif action.begins_with("fail_"):
			stage = action
		OS.set_environment("FISHING_QA_MIXED_STAGE", stage)
		var early_write_blocked := false
		if action == "early_guard":
			SaveStorage.register_cross_store_journal(folder + "/pending.json",
				items.get_save_path(), fish.get_save_path(), Exchange.SALE_JOURNAL_KEYS)
			fish.add_fish_specimen("sea_bass", "Sea Bass", 75, 300, false, false)
			early_write_blocked = not fish.commit_changes()
		service.configure(catalog, items, null, fish)
		if action == "verify_completed":
			ok = items.get_count(herb) == 0 and items.get_count(bait) == 3 and _ids(fish) == [2] and not service.has_pending_sale()
		elif action == "verify_before":
			ok = items.get_count(herb) == 2 and items.get_count(bait) == 0 and _ids(fish) == [1, 2] and not service.has_pending_sale()
		elif action == "verify_sale_only":
			ok = items.get_count(herb) == 1 and items.get_count(bait) == 0 and _ids(fish) == [1, 2] and fish.get_zenny() == 3 and not service.has_pending_sale()
		elif action == "early_guard":
			ok = early_write_blocked and items.get_count(herb) == 0 and items.get_count(bait) == 3 and _ids(fish) == [2] and not service.has_pending_sale()
		elif action == "recover_fail_fish":
			var recovered := service.recover_pending_sale()
			ok = not bool(recovered.get("recovered", false)) and service.has_pending_sale()
		elif action == "pending_exchange" or action == "ambiguous_exchange":
			var pending := service.exchange_fish_and_player_items({"sea_bass": 1}, {String(herb): 2}, {String(bait): 3})
			ok = not bool(pending.get("success", false)) and pending.get("reason") == "pending_transaction_unresolved" and service.has_pending_sale()
		elif action == "blocked_sale":
			var sale := service.sell_player_item_for_zenny(herb, 1, 3)
			ok = not bool(sale.get("success", false)) and sale.get("reason") == "pending_sale_unresolved" and service.has_pending_sale()
		elif action == "catch_conflict":
			var progress: FishingProgress = Progress.new()
			progress.configure_save_path(folder + "/progress.json")
			var catch_repo: FishingCatchRepository = CatchRepository.new()
			catch_repo.configure_pending_journal_paths(folder + "/catch.json", folder + "/catch.tmp")
			catch_repo.configure(progress, fish)
			var catch_result := catch_repo.commit_snapshot({"qa": true})
			ok = not bool(catch_result.get("committed", false)) and catch_result.get("reason") == "pending_cross_store_transaction"
			catch_repo.free()
			progress.free()
		elif action == "direct_write_blocked":
			items.grant(herb, 1, false)
			ok = not items.commit_changes() and service.has_pending_sale()
		elif action == "cook_pending":
			var cooking: FishingCookingService = Cooking.new()
			cooking.configure(EconomyConfig, catalog, items, fish, service)
			var cooked := cooking.cook_prepared_bait(&"sea_bass", 1, true)
			ok = not bool(cooked.get("success", false)) and cooked.get("reason") == "pending_transaction_unresolved" and service.has_pending_sale()
			cooking.free()
		elif action == "pending_catch_blocks":
			var catch_path := "user://fishing_catch_pending.json"
			var pending_file := FileAccess.open(catch_path, FileAccess.WRITE)
			if pending_file != null:
				pending_file.store_string("synthetic pending catch")
				pending_file.close()
			var blocked := service.exchange_fish_and_player_items({"sea_bass": 1}, {String(herb): 2}, {String(bait): 3})
			ok = not bool(blocked.get("success", false)) and blocked.get("reason") == "pending_catch_unresolved" and items.get_count(herb) == 2 and _ids(fish) == [1, 2]
			DirAccess.remove_absolute(ProjectSettings.globalize_path(catch_path))
		elif action == "pending_sale_then_exchange":
			var player_before := items.create_transaction_snapshot()
			var fish_before := fish.create_transaction_snapshot()
			var player_after := player_before.duplicate(true)
			player_after.counts[String(herb)] = 1
			var fish_after := fish_before.duplicate(true)
			fish_after.zenny_balance = int(fish_before.zenny_balance) + 3
			var sale_intent := {"version": 1, "transaction_id": "qa-sale-prior-1",
				"item_id": String(herb), "amount": 1, "unit_value_zenny": 3,
				"total_value_zenny": 3, "item_save_path": items.get_save_path(),
				"wallet_save_path": fish.get_save_path(), "player_before": player_before,
				"player_after": player_after, "wallet_before": fish_before,
				"wallet_after": fish_after}
			var journal_saved := SaveStorage.write(folder + "/pending.json", sale_intent,
				1, Exchange.SALE_JOURNAL_KEYS)
			var blocked := service.exchange_fish_and_player_items({"sea_bass": 1}, {String(herb): 2}, {String(bait): 3})
			ok = journal_saved and not bool(blocked.get("success", false)) and blocked.get("reason") == "pending_transaction_recovered" and blocked.get("pending_transaction_id") == "qa-sale-prior-1" and items.get_count(herb) == 1 and items.get_count(bait) == 0 and fish.get_zenny() == 3 and _ids(fish) == [1, 2] and not service.has_pending_sale()
		elif action == "retry_after_fail":
			OS.set_environment("FISHING_QA_MIXED_STAGE", "fail_fish_commit")
			var first := service.exchange_fish_and_player_items({"sea_bass": 1}, {String(herb): 2}, {String(bait): 3})
			var first_id := str(first.get("transaction_id", ""))
			OS.set_environment("FISHING_QA_MIXED_STAGE", "")
			var retry := service.exchange_fish_and_player_items({"sea_bass": 1}, {String(herb): 2}, {String(bait): 3})
			ok = not bool(first.get("success", false)) and not first_id.is_empty() and not bool(retry.get("success", false)) and retry.get("reason") == "pending_transaction_recovered" and retry.get("pending_transaction_id") == first_id and items.get_count(bait) == 3 and _ids(fish) == [2] and not service.has_pending_sale()
		elif action == "fail_intent_promotion":
			OS.set_environment("FISHING_QA_FAULT_STAGE", "promotion_failure")
			var pending := service.exchange_fish_and_player_items({"sea_bass": 1}, {String(herb): 2}, {String(bait): 3})
			ok = not bool(pending.get("success", false)) and pending.get("reason") == "pending_transaction_unresolved" and not str(pending.get("pending_transaction_id", "")).is_empty() and service.has_pending_sale()
		else:
			var result: Dictionary = service.exchange_fish_and_player_items(
				{"sea_bass": 1}, {String(herb): 2}, {String(bait): 3}, true,
				&"prepared_bait_cooking")
			if action == "sale":
				ok = bool(result.get("success", false)) and not service.has_pending_sale()
			elif action == "fail_item_commit":
				ok = not bool(result.get("success", false)) and result.get("reason") == "item_save_failed" and service.has_pending_sale()
			elif action == "fail_fish_commit":
				ok = not bool(result.get("success", false)) and result.get("reason") == "fish_save_failed" and service.has_pending_sale()
			elif action == "fail_cleanup":
				ok = bool(result.get("success", false)) and bool(result.get("journal_cleanup_pending", false)) and service.has_pending_sale()
		service.free()
		catalog.free()
	var marker := FileAccess.open(folder + "/result.marker", FileAccess.WRITE)
	if marker != null:
		marker.store_string("ok" if ok else "failed")
		marker.close()
	items.free()
	fish.free()
	quit(0 if ok else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
