extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const Catalog = preload("res://scripts/items/game_item_catalog_service.gd")
const ItemQA = preload("res://scripts/items/game_item_backend_qa.gd")
const EconomyQA = preload("res://scripts/economy/fishing_economy_foundation_qa.gd")
const BeachCatalog = preload("res://data/crafting/beach/beach_vertical_slice_catalog.tres")
const FishCatalog = preload("res://data/bof4/catalogs/all_content.tres")
const TackleCatalog = preload("res://data/bof4/tackle/all_tackle.tres")
const ShopCatalog = preload("res://data/bof4/shops/all_shops.tres")
const EconomyConfig = preload("res://data/economy/economy_foundation_v1.tres")

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var catalog: GameItemCatalogService = Catalog.new()
	catalog.configure(BeachCatalog, FishCatalog, TackleCatalog, ShopCatalog, EconomyConfig)
	var item_report: Dictionary = ItemQA.run(catalog)
	var economy_report: Dictionary = EconomyQA.run(EconomyConfig, catalog,
		FishCatalog, TackleCatalog, ShopCatalog)
	for failure in item_report.get("failures", []):
		print("ITEM_BACKEND_FAILURE ", failure)
	for failure in economy_report.get("failures", []):
		print("ECONOMY_FOUNDATION_FAILURE ", failure)
	var passed := int(item_report.passed_count) + int(economy_report.passed_count)
	var total := int(item_report.test_count) + int(economy_report.test_count)
	catalog.free()
	Isolation.emit_result("fishing_item_economy_runner", passed, total, total - passed, 0)
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
