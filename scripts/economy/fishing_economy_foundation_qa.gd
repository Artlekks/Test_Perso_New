extends RefCounted
class_name FishingEconomyFoundationQA

const EconomyServiceScript = preload("res://scripts/fishing_economy_service.gd")
const EconomyAccessScript = preload("res://scripts/fishing_economy_access.gd")
const CookingServiceScript = preload("res://scripts/economy/fishing_cooking_service.gd")
const PlayerInventoryScript = preload("res://scripts/items/player_item_inventory.gd")
const FishingInventoryScript = preload("res://scripts/fishing_inventory.gd")
const InventoryFacadeScript = preload("res://scripts/items/game_inventory_facade.gd")
const TransactionServiceScript = preload("res://scripts/items/game_item_transaction_service.gd")
const PreparedBaitServiceScript = preload(
	"res://scripts/economy/fishing_prepared_bait_service.gd"
)


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
	_test_world_shop_context_filtering(report, config, content, tackle, shop_catalog)
	_test_prepared_bait_cooking(report, config, catalog)
	_test_unsuitable_fish_rejected(report, config, catalog)
	_test_prepared_bait_gameplay_tuning(report, config)
	_test_prepared_bait_cast_consumption(report, config, catalog)
	_test_prepared_bait_cast_modifiers(report, config, catalog)
	_test_prepared_bait_cast_cleanup(report, config, catalog)
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


static func _test_world_shop_context_filtering(
	report: Dictionary,
	config: FishingEconomyConfig,
	content: FishingContentCatalog,
	tackle: FishingTackleCatalog,
	shop_catalog
) -> void:
	var fishing := FishingInventoryScript.new() as FishingInventory
	fishing.set_zenny(99999, false)
	var service := EconomyServiceScript.new() as FishingEconomyService
	service.configure(
		fishing,
		content,
		tackle,
		shop_catalog,
		null,
		config
	)
	var access = EconomyAccessScript.new()
	access.configure(
		fishing,
		service,
		null,
		null,
		null,
		content,
		shop_catalog,
		null
	)
	access.set_access_context(
		PackedStringArray(["shyde"]),
		PackedStringArray(),
		{},
		false
	)
	var entries: Array[Dictionary] = access.get_buy_entries()
	var only_shyde: bool = not entries.is_empty()
	var has_baby_frog: bool = false
	var has_floater: bool = false
	var leaked_lyp: bool = false
	for entry in entries:
		only_shyde = only_shyde and str(entry.get("shop_id", "")) == "shyde"
		var offer_id := str(entry.get("id", ""))
		has_baby_frog = has_baby_frog or offer_id == "shyde_baby_frog"
		has_floater = has_floater or offer_id == "shyde_floater"
		leaked_lyp = leaked_lyp or offer_id == "lyp_popper"
	access.clear_access_context()
	var closes_when_context_clears: bool = access.get_buy_entries().is_empty()
	_record(
		report,
		"World economy access filters Buy inventory to the active authored shop",
		only_shyde
		and has_baby_frog
		and has_floater
		and not leaked_lyp
		and closes_when_context_clears,
		"A world merchant must not expose remote shops once full-catalog debug access is disabled."
	)
	access.queue_free()
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


static func _test_prepared_bait_gameplay_tuning(
	report: Dictionary,
	config: FishingEconomyConfig
) -> void:
	var valid: bool = (
		config != null
		and config.prepared_bait_bite_attraction_multiplier > 1.0
		and config.prepared_bait_quality_bonus_roll_chance > 0.0
		and config.prepared_bait_quality_bonus_rolls > 0
	)
	_record(
		report,
		"Prepared bait has bounded live fishing bonuses",
		valid,
		"Prepared bait must improve bite activity and specimen quality without editing fish prices."
	)


static func _test_prepared_bait_cast_consumption(
	report: Dictionary,
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService
) -> void:
	var setup: Dictionary = _make_prepared_bait_gameplay_setup(config, catalog)
	var service := setup.get("prepared_bait", null) as FishingPreparedBaitService
	var items := setup.get("items", null) as PlayerItemInventory
	var bait_id := catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		config.prepared_bait_item_domain_id
	)
	items.grant(bait_id, 2, false)
	var use_result: Dictionary = service.try_begin_cast(false)
	var valid: bool = (
		bool(use_result.get("used", false))
		and service.is_cast_baited()
		and items.get_count(bait_id) == 1
	)
	_record(
		report,
		"A committed baited cast consumes exactly one prepared-bait portion",
		valid,
		"Prepared bait must behave as a real consumable, one portion per successfully-created cast."
	)
	_free_prepared_bait_gameplay_setup(setup)


static func _test_prepared_bait_cast_modifiers(
	report: Dictionary,
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService
) -> void:
	var setup: Dictionary = _make_prepared_bait_gameplay_setup(config, catalog)
	var service := setup.get("prepared_bait", null) as FishingPreparedBaitService
	var items := setup.get("items", null) as PlayerItemInventory
	var bait_id := catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		config.prepared_bait_item_domain_id
	)
	items.grant(bait_id, 1, false)
	service.try_begin_cast(false)
	var generation: Dictionary = service.get_specimen_generation_context()
	var valid: bool = (
		service.get_bite_attraction_multiplier() > 1.0
		and bool(generation.get("prepared_bait_quality_active", false))
		and float(generation.get("prepared_bait_quality_bonus_chance", 0.0)) > 0.0
		and int(generation.get("prepared_bait_quality_bonus_rolls", 0)) > 0
	)
	_record(
		report,
		"Prepared bait exposes per-cast attraction and natural quality-roll bonuses",
		valid,
		"The live bonus must improve fishing opportunity/quality rather than directly inflating fish sell prices."
	)
	_free_prepared_bait_gameplay_setup(setup)


static func _test_prepared_bait_cast_cleanup(
	report: Dictionary,
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService
) -> void:
	var setup: Dictionary = _make_prepared_bait_gameplay_setup(config, catalog)
	var service := setup.get("prepared_bait", null) as FishingPreparedBaitService
	var items := setup.get("items", null) as PlayerItemInventory
	var bait_id := catalog.make_item_id(
		GameItemCatalogService.STORAGE_PLAYER,
		config.prepared_bait_item_domain_id
	)
	items.grant(bait_id, 2, false)
	service.try_begin_cast(false)
	service.clear_cast(&"qa_cleanup")
	var valid: bool = (
		not service.is_cast_baited()
		and absf(service.get_bite_attraction_multiplier() - 1.0) < 0.0001
		and items.get_count(bait_id) == 1
	)
	_record(
		report,
		"Prepared-bait bonuses end with the cast and never consume twice on cleanup",
		valid,
		"Per-cast bait state must not leak into the next throw or delete another portion."
	)
	_free_prepared_bait_gameplay_setup(setup)


static func _make_prepared_bait_gameplay_setup(
	config: FishingEconomyConfig,
	catalog: GameItemCatalogService
) -> Dictionary:
	var items := PlayerInventoryScript.new() as PlayerItemInventory
	var fishing := FishingInventoryScript.new() as FishingInventory
	var facade := InventoryFacadeScript.new() as GameInventoryFacade
	facade.configure(catalog, items, fishing)
	var transaction := TransactionServiceScript.new() as GameItemTransactionService
	transaction.configure(catalog, items, facade, fishing)
	var prepared_bait := PreparedBaitServiceScript.new() as FishingPreparedBaitService
	prepared_bait.configure(config, catalog, items, transaction)
	return {
		"items": items,
		"fishing": fishing,
		"facade": facade,
		"transaction": transaction,
		"prepared_bait": prepared_bait,
	}


static func _free_prepared_bait_gameplay_setup(setup: Dictionary) -> void:
	for key in ["prepared_bait", "transaction", "facade", "fishing", "items"]:
		var node = setup.get(key, null)
		if node is Node:
			(node as Node).queue_free()


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
