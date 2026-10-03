extends RefCounted
class_name FishingEconomyFoundationQA

const EconomyServiceScript = preload("res://scripts/fishing_economy_service.gd")
const CookingServiceScript = preload("res://scripts/economy/fishing_cooking_service.gd")
const PlayerInventoryScript = preload("res://scripts/items/player_item_inventory.gd")
const FishingInventoryScript = preload("res://scripts/fishing_inventory.gd")
const InventoryFacadeScript = preload("res://scripts/items/game_inventory_facade.gd")
const TransactionServiceScript = preload("res://scripts/items/game_item_transaction_service.gd")


static func run(
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService,
	content: FishingContentCatalog,
	tackle: FishingTackleCatalog,
	shop_catalog
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}
	_test_config_shape(report, config)
	_test_fish_price_coverage(report, config, content)
	_test_shop_price_coverage(report, config, shop_catalog)
	_test_prepared_bait_registration(report, config, catalog)
	_test_herb_registration(report, config, catalog)
	_test_runtime_price_resolution(report, config, content, tackle, shop_catalog)
	_test_prepared_bait_cooking(report, config, catalog)
	_test_unsuitable_fish_rejected(report, config, catalog)
	report["valid"] = int(report["passed_count"]) == int(report["test_count"])
	return report


static func _test_config_shape(
	report: Dictionary,
	config: FishingEconomyConfig
) -> void:
	var snapshot: Dictionary = (
		config.validate_shape()
		if config != null
		else {"valid": false}
	)
	_record(
		report,
		"Canonical economy config has a valid shape",
		config != null and bool(snapshot.get("valid", false)),
		"Price arrays and prepared-bait recipe fields must be internally consistent."
	)


static func _test_fish_price_coverage(
	report: Dictionary,
	config: FishingEconomyConfig,
	content: FishingContentCatalog
) -> void:
	var valid: bool = config != null and content != null
	if valid:
		for fish in content.fish:
			if fish == null:
				valid = false
				break
			var species_id := StringName(fish.get_stable_species_id())
			if config.get_fish_sell_price(species_id, 0) <= 0:
				valid = false
				break
	_record(
		report,
		"Every current fish has a canonical sell price",
		valid,
		"Economy v1 must not silently fall back to zero-value fish."
	)


static func _test_shop_price_coverage(
	report: Dictionary,
	config: FishingEconomyConfig,
	shop_catalog
) -> void:
	var valid: bool = config != null and shop_catalog != null
	if valid:
		for offer in shop_catalog.get_all_offers():
			if config.get_offer_buy_price(
				int(offer.item_type),
				offer.item_id,
				0
			) <= 0:
				valid = false
				break
	_record(
		report,
		"Every current shop offer resolves to a canonical base price",
		valid,
		"Live tackle prices must come from the economy config, not scattered offer values."
	)


static func _test_prepared_bait_registration(
	report: Dictionary,
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService
) -> void:
	var definition: GameItemDefinition = null
	if config != null and catalog != null:
		definition = catalog.get_by_domain(
			GameItemCatalogService.STORAGE_PLAYER,
			config.prepared_bait_item_domain_id
		)
	_record(
		report,
		"Prepared bait is a canonical stackable inventory item",
		definition != null
		and definition.category == GameItemCatalogService.CATEGORY_BAIT
		and definition.stackable,
		"Cooking output must live in the unified item catalog."
	)


static func _test_herb_registration(
	report: Dictionary,
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService
) -> void:
	var definition: GameItemDefinition = null
	if config != null and catalog != null:
		definition = catalog.get_by_domain(
			GameItemCatalogService.STORAGE_PLAYER,
			config.bait_herb_material_id
		)
	_record(
		report,
		"Coastal herb is registered as a gathering/crafting material",
		definition != null
		and definition.category == GameItemCatalogService.CATEGORY_MATERIALS,
		"Gathered herbs must share the authoritative item backbone."
	)


static func _test_runtime_price_resolution(
	report: Dictionary,
	config: FishingEconomyConfig,
	content: FishingContentCatalog,
	tackle: FishingTackleCatalog,
	shop_catalog
) -> void:
	var fishing := FishingInventoryScript.new() as FishingInventory
	fishing.add_fish("sea_bass", 1, false)
	fishing.set_zenny(5000, false)
	var service := EconomyServiceScript.new() as FishingEconomyService
	service.configure(
		fishing,
		content,
		tackle,
		shop_catalog,
		null,
		config
	)
	var sale: Dictionary = service.evaluate_fish_sale(&"sea_bass", 1)
	var bamboo_offer = shop_catalog.get_offer_by_id(&"faerie_bamboo_rod")
	var purchase: Dictionary = service.evaluate_purchase(bamboo_offer, 1, {})
	var valid: bool = (
		int(sale.get("unit_value_zenny", 0)) == 40
		and int(purchase.get("unit_price_zenny", 0)) == 1000
	)
	_record(
		report,
		"Runtime fish/shop prices resolve through economy v1",
		valid,
		"Sea Bass should resolve to 40z and Bamboo Rod to 1000z in the current baseline."
	)
	service.queue_free()
	fishing.queue_free()


static func _test_prepared_bait_cooking(
	report: Dictionary,
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService
) -> void:
	var setup: Dictionary = _make_cooking_setup(config, catalog)
	var cooking := setup.get("cooking", null) as FishingCookingService
	var inventory := setup.get("items", null) as PlayerItemInventory
	var fishing := setup.get("fishing", null) as FishingInventory
	var herb_id := catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		config.bait_herb_material_id
	)
	var bait_id := catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		config.prepared_bait_item_domain_id
	)
	inventory.grant(herb_id, 2, false)
	fishing.add_fish("sea_bass", 1, false)
	var cooked: Dictionary = cooking.cook_prepared_bait(
		&"sea_bass",
		1,
		false
	)
	var valid: bool = (
		bool(cooked.get("success", false))
		and fishing.get_fish_count("sea_bass") == 0
		and inventory.get_count(herb_id) == 0
		and inventory.get_count(bait_id) == 3
	)
	_record(
		report,
		"Prepared bait cooks 1 common fish + 2 herbs into 3 portions",
		valid,
		"The first live fishing/crafting bridge must match the simulator recipe exactly."
	)
	_free_cooking_setup(setup)


static func _test_unsuitable_fish_rejected(
	report: Dictionary,
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService
) -> void:
	var setup: Dictionary = _make_cooking_setup(config, catalog)
	var cooking := setup.get("cooking", null) as FishingCookingService
	var inventory := setup.get("items", null) as PlayerItemInventory
	var fishing := setup.get("fishing", null) as FishingInventory
	var herb_id := catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		config.bait_herb_material_id
	)
	inventory.grant(herb_id, 2, false)
	fishing.add_fish("whale", 1, false)
	var evaluation: Dictionary = cooking.evaluate_prepared_bait(&"whale", 1)
	var valid: bool = (
		not bool(evaluation.get("can_cook", false))
		and str(evaluation.get("reason", ""))
		== "fish_not_suitable_for_prepared_bait"
		and fishing.get_fish_count("whale") == 1
		and inventory.get_count(herb_id) == 2
	)
	_record(
		report,
		"Prepared bait rejects fish outside the authored common-fish pool",
		valid,
		"High-value or special fish must never be auto-treated as cheap bait ingredients."
	)
	_free_cooking_setup(setup)


static func _make_cooking_setup(
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService
) -> Dictionary:
	var items := PlayerInventoryScript.new() as PlayerItemInventory
	var fishing := FishingInventoryScript.new() as FishingInventory
	var facade := InventoryFacadeScript.new() as GameInventoryFacade
	facade.configure(catalog, items, fishing)
	var transaction := TransactionServiceScript.new() as GameItemTransactionService
	transaction.configure(catalog, items, facade, fishing)
	var cooking := CookingServiceScript.new() as FishingCookingService
	cooking.configure(config, catalog, items, fishing, transaction)
	return {
		"items": items,
		"fishing": fishing,
		"facade": facade,
		"transaction": transaction,
		"cooking": cooking,
	}


static func _free_cooking_setup(setup: Dictionary) -> void:
	for key in ["cooking", "transaction", "facade", "fishing", "items"]:
		var node = setup.get(key, null)
		if node is Node:
			(node as Node).queue_free()


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
	failures.append("%s — %s" % [name, detail])
	report["failures"] = failures
