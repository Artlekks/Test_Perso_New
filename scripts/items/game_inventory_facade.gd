extends Node
class_name GameInventoryFacade

signal changed
signal inventory_event(event: Dictionary)

var item_catalog: GameItemCatalogService = null
var player_inventory: PlayerItemInventory = null
var fishing_inventory: FishingInventory = null


func configure(
	new_catalog: GameItemCatalogService,
	new_player_inventory: PlayerItemInventory,
	new_fishing_inventory: FishingInventory
) -> void:
	item_catalog = new_catalog
	player_inventory = new_player_inventory
	fishing_inventory = new_fishing_inventory

	if player_inventory != null:
		if player_inventory.has_signal("changed"):
			var player_callback := Callable(
				self,
				"_on_player_inventory_changed"
			)
			if not player_inventory.is_connected(
				"changed",
				player_callback
			):
				player_inventory.connect(
					"changed",
					player_callback
				)
		if player_inventory.has_signal("item_count_changed"):
			var player_count_callback := Callable(
				self,
				"_on_player_item_count_changed"
			)
			if not player_inventory.is_connected(
				"item_count_changed",
				player_count_callback
			):
				player_inventory.connect(
					"item_count_changed",
					player_count_callback
				)

	if fishing_inventory != null:
		_connect_fishing_signal(
			"changed",
			"_on_fishing_inventory_changed"
		)
		_connect_fishing_signal(
			"fish_count_changed",
			"_on_fish_count_changed"
		)
		_connect_fishing_signal(
			"lure_count_changed",
			"_on_lure_count_changed"
		)
		_connect_fishing_signal(
			"rod_count_changed",
			"_on_rod_count_changed"
		)
		_connect_fishing_signal(
			"zenny_changed",
			"_on_zenny_changed"
		)
		_connect_fishing_signal(
			"manillo_balance_changed",
			"_on_manillo_balance_changed"
		)


func get_count(item_id: StringName) -> int:
	if item_catalog == null:
		return 0
	var definition: GameItemDefinition = item_catalog.get_definition(item_id)
	if definition == null:
		return 0
	match definition.storage_kind:
		GameItemCatalogService.STORAGE_PLAYER:
			if player_inventory == null:
				return 0
			return player_inventory.get_count(definition.item_id)
		GameItemCatalogService.STORAGE_FISH:
			if fishing_inventory == null:
				return 0
			return fishing_inventory.get_fish_count(
				String(definition.domain_id)
			)
		GameItemCatalogService.STORAGE_LURE:
			if fishing_inventory == null:
				return 0
			return fishing_inventory.get_lure_count(
				definition.domain_id
			)
		GameItemCatalogService.STORAGE_ROD:
			if fishing_inventory == null:
				return 0
			return fishing_inventory.get_rod_count(
				definition.domain_id
			)
	return 0


func has(item_id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return get_count(item_id) >= amount


func get_item_snapshot(item_id: StringName) -> Dictionary:
	if item_catalog == null:
		return {}
	var definition: GameItemDefinition = item_catalog.get_definition(item_id)
	if definition == null:
		return {}
	var result: Dictionary = definition.to_snapshot()
	result["owned_count"] = get_count(item_id)
	return result


func get_owned_items(
	category: StringName = &""
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if item_catalog == null:
		return result
	for definition in item_catalog.get_all_definitions():
		if category != &"" and definition.category != category:
			continue
		var count: int = get_count(definition.item_id)
		if count <= 0:
			continue
		var snapshot: Dictionary = definition.to_snapshot()
		snapshot["owned_count"] = count
		result.append(snapshot)
	return result


func publish_transaction(result: Dictionary) -> void:
	var event: Dictionary = {
		"kind": "transaction",
		"context": str(result.get("context", "")),
		"result": result.duplicate(true),
	}
	inventory_event.emit(event)
	changed.emit()


func _connect_fishing_signal(
	signal_name: String,
	method_name: String
) -> void:
	if fishing_inventory == null:
		return
	if not fishing_inventory.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if fishing_inventory.is_connected(signal_name, callback):
		return
	fishing_inventory.connect(signal_name, callback)


func _on_player_inventory_changed(
	_snapshot: Dictionary
) -> void:
	changed.emit()


func _on_fishing_inventory_changed() -> void:
	changed.emit()


func _on_player_item_count_changed(
	item_id: StringName,
	count: int
) -> void:
	_emit_item_event(item_id, count, &"player")


func _on_fish_count_changed(
	species_id: String,
	count: int
) -> void:
	_emit_domain_item_event(
		GameItemCatalogService.STORAGE_FISH,
		StringName(species_id),
		count
	)


func _on_lure_count_changed(
	lure_id: StringName,
	count: int
) -> void:
	_emit_domain_item_event(
		GameItemCatalogService.STORAGE_LURE,
		lure_id,
		count
	)


func _on_rod_count_changed(
	rod_id: StringName,
	count: int
) -> void:
	_emit_domain_item_event(
		GameItemCatalogService.STORAGE_ROD,
		rod_id,
		count
	)


func _on_zenny_changed(balance: int) -> void:
	inventory_event.emit({
		"kind": "currency",
		"currency_id": "zenny",
		"balance": maxi(0, balance),
	})


func _on_manillo_balance_changed(
	point_units: int,
	stamps: int,
	stamp_cards: int
) -> void:
	inventory_event.emit({
		"kind": "currency",
		"currency_id": "manillo",
		"point_units": maxi(0, point_units),
		"stamps": maxi(0, stamps),
		"stamp_cards": maxi(0, stamp_cards),
	})


func _emit_domain_item_event(
	storage_kind: StringName,
	domain_id: StringName,
	count: int
) -> void:
	if item_catalog == null:
		return
	var definition: GameItemDefinition = item_catalog.get_by_domain(
		storage_kind,
		domain_id
	)
	if definition == null:
		return
	_emit_item_event(
		definition.item_id,
		count,
		storage_kind
	)


func _emit_item_event(
	item_id: StringName,
	count: int,
	storage_kind: StringName
) -> void:
	var event: Dictionary = {
		"kind": "item_count",
		"item_id": String(item_id),
		"storage_kind": String(storage_kind),
		"count": maxi(0, count),
	}
	if item_catalog != null:
		var definition: GameItemDefinition = item_catalog.get_definition(
			item_id
		)
		if definition != null:
			event["domain_id"] = String(definition.domain_id)
			event["category"] = String(definition.category)
			event["display_name"] = definition.display_name
	inventory_event.emit(event)
