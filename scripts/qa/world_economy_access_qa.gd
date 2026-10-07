extends SceneTree

## Real backend/menu integration with in-memory inventory and no player saves.
const AccessScript = preload("res://scripts/fishing_economy_access.gd")
const ContextScript = preload("res://scripts/economy/merchant_economy_context.gd")
const Content = preload("res://data/bof4/catalogs/all_content.tres")
const Shops = preload("res://data/bof4/shops/all_shops.tres")
const Trades = preload("res://data/bof4/trades/all_trades.tres")
const Config = preload("res://data/economy/economy_foundation_v1.tres")
const BeachContext = preload("res://data/economy/contexts/beach_merchant.tres")
const MenuScene = preload("res://actors/FishingEconomyMenu.tscn")
const MerchantScene = preload("res://actors/BeachMerchantNPC.tscn")
const Foundation = preload("res://scripts/economy/fishing_economy_foundation_qa.gd")
const Regression = preload("res://scripts/fishing_regression_harness.gd")
const Simulator = preload("res://scripts/progression/economy_progression_simulator.gd")

class MemoryInventory:
	extends FishingInventory
	func save_to_disk() -> bool:
		return true

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(label)
		push_error(label)


func _entry(entries: Array[Dictionary], id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.id == id:
			return entry
	return {}


func _only_source(entries: Array[Dictionary], source: String) -> bool:
	if entries.is_empty():
		return false
	for entry: Dictionary in entries:
		if entry.shop_id != source:
			return false
	return true


func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	current_scene = fixture
	var inventory := MemoryInventory.new()
	fixture.add_child(inventory)
	inventory.set_zenny(99999, false)
	var service := FishingEconomyService.new()
	fixture.add_child(service)
	service.configure(inventory, Content, Content.tackle, Shops, null, Config)
	var trade := FishingTradeService.new()
	fixture.add_child(trade)
	trade.configure(inventory, Content.tackle, Trades)
	var access := AccessScript.new()
	fixture.add_child(access)
	access.configure(inventory, service, trade, null, null, Content, Shops, Trades)
	_check(access.get_buy_entries().is_empty() and access.get_trade_entries().is_empty(), "default access is restricted")
	access.enable_vertical_slice_full_access()
	_check(access.get_buy_entries().size() == 16, "explicit full access exposes all 16 authored offers")
	_check(access.get_trade_entries().size() == 14, "explicit full access exposes all 14 trades")
	BeachContext.apply_to(access)
	_check(_only_source(access.get_buy_entries(), "shyde") and access.get_buy_entries().size() == 4, "Beach context exposes only its four Shyde offers")
	_check(access.get_trade_entries().is_empty(), "Beach context has no Manillo sources")
	_check(access.buy_one(&"lyp_popper").reason == "shop_not_available", "disallowed buy rejected")
	_check(access.trade_one(&"lyp_crab").reason == "shop_not_available", "disallowed trade rejected")
	var trade_context := ContextScript.new()
	trade_context.trade_shop_ids = PackedStringArray(["wyndia"])
	trade_context.apply_to(access)
	_check(_only_source(access.get_trade_entries(), "wyndia") and access.get_trade_entries().size() == 7, "restricted trade context exposes only Wyndia")
	_check(access.get_buy_entries().is_empty(), "trade context does not grant shops")
	_check(access.trade_one(&"lyp_crab").reason == "shop_not_available", "Lyp remains rejected in Wyndia context")
	var faerie := ContextScript.new()
	faerie.shop_ids = PackedStringArray(["faerie_diligent"])
	faerie.apply_to(access)
	_check(_entry(access.get_buy_entries(), "faerie_bamboo_rod").reason == "availability_locked", "allowed shop does not bypass authored availability tag")
	_check(access.buy_one(&"faerie_bamboo_rod").reason == "availability_locked", "tag-locked purchase blocked")
	faerie.availability = {"faerie_diligent_shop": true}
	faerie.apply_to(access)
	_check(bool(_entry(access.get_buy_entries(), "faerie_bamboo_rod").can_execute), "authored availability flag unlocks allowed offer")
	faerie.availability["faerie_diligent_shop"] = false
	_check(bool(_entry(access.get_buy_entries(), "faerie_bamboo_rod").can_execute), "applied availability is copied, not shared mutable data")
	access.enable_vertical_slice_full_access()
	_check(_entry(access.get_buy_entries(), "faerie_bamboo_rod").reason == "availability_locked", "full access cannot inherit prior tag grants")
	var state_before := inventory.create_transaction_snapshot()
	BeachContext.apply_to(access)
	access.clear_access_context()
	_check(inventory.create_transaction_snapshot() == state_before, "context lifecycle mutates no persistent inventory state")
	_check(not BeachContext.has_method("save_to_disk") and not BeachContext.has_method("serialize"), "context Resource owns policy, no persistence API")
	_check(BeachContext.shop_ids == PackedStringArray(["shyde"]) and not BeachContext.full_catalog_access, "authored Beach policy unchanged by interactions")

	var menu: Node = MenuScene.instantiate()
	menu.name = "FishingEconomyMenu"
	fixture.add_child(menu)
	menu.configure(null, access)
	var merchant: Node3D = MerchantScene.instantiate()
	fixture.add_child(merchant)
	var other: Node3D = MerchantScene.instantiate()
	fixture.add_child(other)
	other.economy_context = ContextScript.new()
	other.economy_context.shop_ids = PackedStringArray(["sarai"])
	merchant._player_in_range = true
	merchant._open_buy_menu()
	_check(menu.is_open() and menu._source_entries.size() == 4 and _only_source(menu._source_entries, "shyde"), "real Merchant applies context before menu builds rows")
	_check(int(menu._source_entries[0].price_zenny) == 200 and menu.row_price_labels[0].text == "200z", "menu row displays canonical Straight price instead of authored 20z")
	var purchase_entry := _entry(menu._source_entries, "shyde_straight")
	var balance := inventory.get_zenny()
	var purchase: Dictionary = access.buy_one(&"shyde_straight")
	_check(purchase.reason == "completed" and balance - inventory.get_zenny() == int(purchase_entry.price_zenny), "purchase deduction equals displayed resolved live price")
	_check(Shops.get_offer_by_id(&"shyde_straight").price_zenny == 20, "underlying historical offer price not mutated")
	menu._begin_confirmation()
	_check(menu._confirm_active, "confirmation opens on current entries")
	other.economy_context.apply_to(access)
	_check(_only_source(menu._source_entries, "sarai") and menu._source_entries.size() == 3, "changing context refreshes actual player-facing entries")
	_check(not menu._confirm_active, "context change cancels stale confirmation")
	BeachContext.apply_to(access)
	_check(not menu.open_merchant_menu(other.economy_context, other), "second merchant cannot replace an open menu")
	_check(_only_source(menu._source_entries, "shyde"), "failed open preserves active context")
	other._cached_menu = menu
	other._clear_economy_access_context()
	_check(menu.is_open() and _only_source(access.get_buy_entries(), "shyde"), "inactive merchant cannot clear active merchant's context")
	menu.close_menu()
	_check(not paused and access.get_buy_entries().is_empty() and access.get_trade_entries().is_empty(), "closing menu clears context and restores pause")
	menu.open_buy_menu()
	_check(menu.is_open() and menu._source_entries.is_empty(), "unscoped invocation cannot inherit previous merchant")
	menu.close_menu()
	other._player_in_range = true
	other._open_buy_menu()
	_check(_only_source(menu._source_entries, "sarai"), "next merchant applies its own source")
	var player := CharacterBody3D.new()
	player.name = "CharacterBody3D"
	fixture.add_child(player)
	other._on_body_exited(player)
	_check(not menu.is_open() and access.get_buy_entries().is_empty(), "leaving active merchant closes and clears owned context")
	other._open_buy_menu()
	_check(not menu.is_open(), "deferred choice cannot reopen departed merchant")
	merchant._on_dialogue_interaction_finished(merchant.ACTION_CHOOSE_SERVICE, &"cancelled")
	_check(access.get_buy_entries().is_empty(), "cancelled merchant dialogue leaves no context")
	_check(menu.open_debug_full_catalog_menu(), "debug menu requires explicit full-access entry point")
	_check(menu._source_entries.size() == 16 and access.get_trade_entries().size() == 14, "debug entry preserves full catalog compatibility")
	merchant._clear_economy_access_context()
	_check(menu.is_open() and menu._source_entries.size() == 16, "merchant exit cannot erase debug ownership")
	menu.close_menu()
	_check(access.get_access_context_snapshot().availability.is_empty(), "closing clears tag flags as well as sources")
	other._player_in_range = true
	other._open_buy_menu()
	other.queue_free()
	await process_frame
	_check(not menu.is_open() and not paused and access.get_buy_entries().is_empty(), "merchant destruction clears its owned menu/context")
	merchant._player_in_range = true
	merchant._open_buy_menu()
	var next_access := AccessScript.new()
	fixture.add_child(next_access)
	next_access.configure(inventory, service, trade, null, null, Content, Shops, Trades)
	menu.configure(null, next_access)
	_check(not menu.is_open() and access.get_buy_entries().is_empty(), "reconfiguring menu clears previous facade context")
	_check(not access.is_connected("changed", Callable(menu, "_on_access_changed")), "reconfigured menu disconnects old facade signal")
	access = next_access
	merchant._open_buy_menu()
	menu.free()
	_check(not paused and access.get_buy_entries().is_empty(), "menu destruction clears active context and pause")
	merchant._cached_menu = null

	# Existing foundation and authored-catalog freeze checks, without altering
	# their assertion counts or running unrelated persistence-writing suites.
	var catalog := GameItemCatalogService.new()
	fixture.add_child(catalog)
	catalog.configure(load("res://data/crafting/beach/beach_vertical_slice_catalog.tres"), Content, Content.tackle, Shops, Config)
	var foundation: Dictionary = Foundation.run(Config, catalog, Content, Content.tackle, Shops)
	print("Existing Economy Foundation QA: %d/%d" % [foundation.passed_count, foundation.test_count])
	_check(bool(foundation.valid), "existing foundation suite remains green")
	var orphan_before := Node.get_orphan_node_ids()
	var regression := Regression.new()
	var report := {"passed": 0, "failed": 0, "assertions": 0, "failures": PackedStringArray(), "groups": {}}
	regression._test_trades(report)
	regression._test_economy_contract(report)
	regression._test_player_economy_access_and_save_integrity(report)
	print("Existing Economy/Trade/Full-Access regression groups: %d/%d" % [report.passed, report.assertions])
	_check(int(report.failed) == 0, "existing economy freeze/full-access groups remain green")
	for id in Node.get_orphan_node_ids():
		if not orphan_before.has(id):
			var orphan = instance_from_id(id)
			if is_instance_valid(orphan):
				orphan.free()
	var simulation: Dictionary = Simulator.new().run_default_suite(false)
	print("Existing First-10h source/economy simulator: %d/%d" % [simulation.checks_passed, simulation.checks_total])
	_check(simulation.checks_passed == simulation.checks_total, "First-10h simulator remains green")
	print("World Economy Access QA: %d checks, %d failures" % [_checks, _failures.size()])
	fixture.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
