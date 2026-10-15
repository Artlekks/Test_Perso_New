extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const SaveStorage = preload("res://scripts/fishing_save_storage.gd")
const Catalog = preload("res://data/economy/card_maker/card_maker_catalog_v1.tres")
const Content = preload("res://data/bof4/catalogs/all_content.tres")
const ROOT := "user://card_maker_journal_qa"
const INVENTORY := ROOT + "/inventory.json"
const JOURNAL := ROOT + "/pending.json"
const TEMP := ROOT + "/pending.tmp"
const CARD := ROOT + "/card.json"
const RESULT := ROOT + "/result.json"

class PersistentCardGame:
	extends Node
	var path: String
	var quantity: int = 0
	func configure(save_path: String) -> void:
		path = save_path
		if FileAccess.file_exists(path):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:
				quantity = int(data.get("quantity", 0))
	func get_card_snapshot(card_id: StringName) -> Dictionary:
		return {"card_id": String(card_id), "display_name": "QA Card", "quantity": quantity}
	func get_player_snapshot() -> Dictionary:
		return {"duel_rank": 10, "card_game_unlocked": true}
	func claim_world_source_card(_source_type: StringName, _source_id: StringName,
			_card_id: StringName, _context: StringName) -> Dictionary:
		quantity += 1
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return {"success": false}
		file.store_string(JSON.stringify({"quantity": quantity}))
		file.close()
		return {"success": true, "quantity_after": quantity}

func _initialize() -> void:
	if not Isolation.verify([ROOT, INVENTORY, JOURNAL, TEMP, CARD, RESULT, "user://card_maker_fault.marker"]):
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var action := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	var recipe: FishingCardMakerRecipe = Catalog.get_all_recipes()[0]
	SaveStorage.register_cross_store_journal("user://item_sale_pending.json", ROOT + "/items.json",
		INVENTORY, GameItemTransactionService.SALE_JOURNAL_KEYS)
	var inventory := FishingInventory.new()
	inventory.configure_save_path(INVENTORY)
	inventory.initialize()
	var game := PersistentCardGame.new()
	game.configure(CARD)
	var service := FishingCardMakerService.new()
	service.configure_pending_journal_paths(JOURNAL, TEMP)
	service.configure(Catalog, inventory, Content)
	service.bind_triple_triad_game(game)
	var result: Dictionary = {}
	match action:
		"setup":
			var specimen := inventory.add_fish_specimen(String(recipe.fish_species_id), "QA Card Fish",
				10.0, 1, false, false, false, {}, "", false)
			inventory.set_zenny(275, false)
			result = {"success": specimen != null and inventory.commit_changes()}
		"make":
			result = service.make_card(recipe.recipe_id)
		"recover":
			result = service.recover_pending_transaction()
		"inspect":
			result = {"status": service.call("_pending_state")}
		"direct_write":
			result = {"saved": inventory.save_to_disk()}
		"conflict_catch":
			var repository := FishingCatchRepository.new()
			repository.progress = FishingProgress.new()
			repository.inventory = inventory
			result = repository.commit_snapshot({"transaction_id": "qa-card-conflicting-catch"})
			repository.progress.free()
			repository.free()
	result["fish"] = inventory.get_fish_count(String(recipe.fish_species_id))
	result["zenny"] = inventory.get_zenny()
	result["card_quantity"] = game.quantity
	result["pending"] = service.has_pending_transaction()
	var output := FileAccess.open(RESULT, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(result))
		output.close()
	service.free()
	game.free()
	inventory.free()
	quit(0)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
