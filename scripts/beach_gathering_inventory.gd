extends Node
class_name BeachGatheringInventory

signal changed(snapshot: Dictionary)
signal material_changed(material_id: StringName, count: int)

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://beach_gathering_inventory.json"

var _counts: Dictionary = {}
var _initialized: bool = false
var _item_inventory: PlayerItemInventory = null
var _item_catalog: GameItemCatalogService = null
var _transaction_service: GameItemTransactionService = null
var _legacy_save_path: String = SAVE_PATH


func configure_backbone(
	item_inventory: PlayerItemInventory,
	item_catalog: GameItemCatalogService,
	transaction_service: GameItemTransactionService,
	legacy_save_path: String = SAVE_PATH
) -> void:
	_item_inventory = item_inventory
	_item_catalog = item_catalog
	_transaction_service = transaction_service
	if not legacy_save_path.strip_edges().is_empty():
		_legacy_save_path = legacy_save_path.strip_edges()

	if (
		_item_inventory != null
		and _item_inventory.has_signal("item_count_changed")
	):
		var callback := Callable(
			self,
			"_on_backbone_item_count_changed"
		)
		if not _item_inventory.is_connected(
			"item_count_changed",
			callback
		):
			_item_inventory.connect(
				"item_count_changed",
				callback
			)


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	if _using_backbone():
		_migrate_legacy_save_once()
		return
	load_from_disk()


func get_count(material_id: StringName) -> int:
	if _using_backbone():
		return _item_inventory.get_count(_canonical_id(material_id))
	return maxi(0, int(_counts.get(String(material_id), 0)))


func has(material_id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return get_count(material_id) >= amount


func grant(
	material_id: StringName,
	amount: int = 1,
	persist: bool = true
) -> int:
	if _using_backbone():
		var canonical: StringName = _canonical_id(material_id)
		if canonical == &"":
			return 0
		return _item_inventory.grant(
			canonical,
			amount,
			persist
		)

	var clean_id: String = String(material_id).strip_edges()
	if clean_id.is_empty() or amount <= 0:
		return get_count(material_id)
	var next_count: int = get_count(material_id) + amount
	_counts[clean_id] = next_count
	material_changed.emit(StringName(clean_id), next_count)
	changed.emit(get_snapshot())
	if persist:
		save_to_disk()
	return next_count

func remove(
	material_id: StringName,
	amount: int = 1,
	persist: bool = true
) -> bool:
	if _using_backbone():
		var canonical: StringName = _canonical_id(material_id)
		if canonical == &"":
			return false
		return _item_inventory.remove(
			canonical,
			amount,
			persist
		)

	var clean_id: String = String(material_id).strip_edges()
	if clean_id.is_empty() or amount <= 0:
		return amount <= 0
	var current: int = get_count(StringName(clean_id))
	if current < amount:
		return false
	var next_count: int = current - amount
	if next_count <= 0:
		_counts.erase(clean_id)
	else:
		_counts[clean_id] = next_count
	material_changed.emit(StringName(clean_id), next_count)
	changed.emit(get_snapshot())
	if persist:
		save_to_disk()
	return true

func can_afford(costs: Dictionary) -> bool:
	for raw_id in costs.keys():
		var check_material_id := StringName(str(raw_id))
		var check_required: int = maxi(0, int(costs[raw_id]))
		if get_count(check_material_id) < check_required:
			return false
	return true


func consume_costs(
	costs: Dictionary,
	persist: bool = true
) -> Dictionary:
	if _using_backbone():
		var canonical_costs: Dictionary = {}
		for raw_id in costs.keys():
			var canonical: StringName = _canonical_id(
				StringName(str(raw_id))
			)
			if canonical == &"":
				return {
					"success": false,
					"reason": "unknown_material",
					"missing": {},
					"consumed": {},
				}
			canonical_costs[String(canonical)] = maxi(
				0,
				int(costs[raw_id])
			)
		var backbone_result: Dictionary = _transaction_service.consume_player_items(
			canonical_costs,
			persist,
			&"beach_crafting"
		)
		if bool(backbone_result.get("success", false)):
			var translated: Dictionary = {}
			for raw_canonical in backbone_result.get("consumed", {}).keys():
				var definition: GameItemDefinition = _item_catalog.get_definition(
					StringName(str(raw_canonical))
				)
				if definition != null:
					translated[String(definition.domain_id)] = int(
						backbone_result["consumed"][raw_canonical]
					)
			backbone_result["consumed"] = translated
		return backbone_result

	var result := {
		"success": false,
		"missing": {},
		"consumed": {},
	}
	var missing: Dictionary = {}
	for raw_id in costs.keys():
		var consume_material_id := StringName(str(raw_id))
		var consume_required: int = maxi(0, int(costs[raw_id]))
		var available: int = get_count(consume_material_id)
		if available < consume_required:
			missing[String(consume_material_id)] = consume_required - available
	if not missing.is_empty():
		result["missing"] = missing
		return result
	for raw_id in costs.keys():
		var consume_material_id := StringName(str(raw_id))
		var consume_required: int = maxi(0, int(costs[raw_id]))
		if consume_required <= 0:
			continue
		remove(consume_material_id, consume_required, false)
		result["consumed"][String(consume_material_id)] = consume_required
	result["success"] = true
	if persist:
		save_to_disk()
	return result

func get_snapshot() -> Dictionary:
	if _using_backbone():
		var counts: Dictionary = {}
		if _item_catalog != null:
			for definition in _item_catalog.get_definitions_in_category(
				GameItemCatalogService.CATEGORY_MATERIALS
			):
				counts[String(definition.domain_id)] = _item_inventory.get_count(
					definition.item_id
				)
		return {
			"version": SAVE_VERSION,
			"counts": counts,
			"storage": "player_item_inventory",
		}
	return {
		"version": SAVE_VERSION,
		"counts": _counts.duplicate(true),
	}

func reset_all(persist: bool = true) -> void:
	if _using_backbone():
		for definition in _item_catalog.get_definitions_in_category(
			GameItemCatalogService.CATEGORY_MATERIALS
		):
			var count: int = _item_inventory.get_count(definition.item_id)
			if count > 0:
				_item_inventory.remove(definition.item_id, count, false)
		_item_inventory.set_metadata(
			_migration_key(),
			true,
			false
		)
		if persist:
			_item_inventory.commit_changes()
		changed.emit(get_snapshot())
		return
	_counts.clear()
	changed.emit(get_snapshot())
	if persist:
		save_to_disk()

func save_to_disk() -> bool:
	if _using_backbone():
		return _item_inventory.commit_changes()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("BeachGatheringInventory: could not open save for writing.")
		return false
	file.store_string(
		JSON.stringify(
			{
				"version": SAVE_VERSION,
				"counts": _counts,
			},
			"\t"
		)
	)
	file.close()
	return true

func load_from_disk() -> bool:
	if _using_backbone():
		_migrate_legacy_save_once()
		return true
	_counts.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary):
		push_warning("BeachGatheringInventory: save is invalid; using empty inventory.")
		return false
	var data: Dictionary = parsed
	var raw_counts = data.get("counts", {})
	if raw_counts is Dictionary:
		for raw_id in raw_counts.keys():
			var clean_id: String = str(raw_id).strip_edges()
			var amount: int = maxi(0, int(raw_counts[raw_id]))
			if not clean_id.is_empty() and amount > 0:
				_counts[clean_id] = amount
	return true

func _on_backbone_item_count_changed(
	item_id: StringName,
	count: int
) -> void:
	if _item_catalog == null:
		return
	var definition: GameItemDefinition = _item_catalog.get_definition(
		item_id
	)
	if definition == null:
		return
	if (
		definition.storage_kind
		!= GameItemCatalogService.STORAGE_PLAYER
		or definition.category
		!= GameItemCatalogService.CATEGORY_MATERIALS
	):
		return
	material_changed.emit(
		definition.domain_id,
		maxi(0, count)
	)
	changed.emit(get_snapshot())


func _using_backbone() -> bool:
	return (
		_item_inventory != null
		and _item_catalog != null
		and _transaction_service != null
	)


func _canonical_id(material_id: StringName) -> StringName:
	if _item_catalog == null:
		return &""
	var definition: GameItemDefinition = _item_catalog.get_by_domain(
		GameItemCatalogService.STORAGE_PLAYER,
		material_id
	)
	if definition == null:
		return &""
	return definition.item_id


func _migration_key() -> String:
	return "migration/beach_gathering_inventory_v1"


func _migrate_legacy_save_once() -> void:
	if not _using_backbone():
		return
	if bool(_item_inventory.get_metadata(_migration_key(), false)):
		return

	if FileAccess.file_exists(_legacy_save_path):
		var parsed = JSON.parse_string(
			FileAccess.get_file_as_string(_legacy_save_path)
		)
		if parsed is Dictionary:
			var raw_counts = (parsed as Dictionary).get("counts", {})
			if raw_counts is Dictionary:
				for raw_id in raw_counts.keys():
					var material_id := StringName(str(raw_id))
					var canonical: StringName = _canonical_id(material_id)
					if canonical == &"":
						continue
					_item_inventory.ensure_minimum_count(
						canonical,
						maxi(0, int(raw_counts[raw_id])),
						false
					)

	_item_inventory.set_metadata(_migration_key(), true, false)
	if not _item_inventory.commit_changes():
		push_warning("BeachGatheringInventory: material migration could not be saved.")
