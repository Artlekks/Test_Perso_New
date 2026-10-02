extends Node
class_name GameItemCatalogService

signal catalog_rebuilt(snapshot: Dictionary)
signal item_registered(item_id: StringName)

const STORAGE_PLAYER: StringName = &"player"
const STORAGE_FISH: StringName = &"fish"
const STORAGE_LURE: StringName = &"lure"
const STORAGE_ROD: StringName = &"rod"

const CATEGORY_MATERIALS: StringName = &"MATERIALS"
const CATEGORY_FISH: StringName = &"FISH"
const CATEGORY_LURES: StringName = &"LURES"
const CATEGORY_RODS: StringName = &"RODS"

var _definitions: Dictionary = {}
var _domain_lookup: Dictionary = {}
var _configured: bool = false


func configure(
	beach_catalog: BeachCraftingCatalog,
	fishing_content: FishingContentCatalog,
	tackle_catalog: FishingTackleCatalog,
	shop_catalog
) -> void:
	_definitions.clear()
	_domain_lookup.clear()

	_register_beach_materials(beach_catalog)
	_register_fish(fishing_content)
	_register_tackle(tackle_catalog)
	_apply_shop_prices(shop_catalog)

	_configured = true
	catalog_rebuilt.emit(get_snapshot())


func is_configured() -> bool:
	return _configured


func make_item_id(
	storage_kind: StringName,
	domain_id: StringName
) -> StringName:
	var clean_storage: String = String(storage_kind).strip_edges().to_lower()
	var clean_domain: String = String(domain_id).strip_edges()
	if clean_storage.is_empty() or clean_domain.is_empty():
		return &""
	return StringName("%s/%s" % [clean_storage, clean_domain])


func get_definition(item_id: StringName) -> GameItemDefinition:
	return _definitions.get(String(item_id), null) as GameItemDefinition


func get_by_domain(
	storage_kind: StringName,
	domain_id: StringName
) -> GameItemDefinition:
	var lookup_key: String = _domain_key(storage_kind, domain_id)
	var item_id: String = str(_domain_lookup.get(lookup_key, ""))
	if item_id.is_empty():
		return null
	return get_definition(StringName(item_id))


func get_all_definitions() -> Array[GameItemDefinition]:
	var result: Array[GameItemDefinition] = []
	for value in _definitions.values():
		var definition := value as GameItemDefinition
		if definition != null:
			result.append(definition)
	result.sort_custom(func(a: GameItemDefinition, b: GameItemDefinition) -> bool:
		var category_compare: int = String(a.category).naturalnocasecmp_to(
			String(b.category)
		)
		if category_compare != 0:
			return category_compare < 0
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)
	return result


func get_definitions_in_category(
	category: StringName
) -> Array[GameItemDefinition]:
	var result: Array[GameItemDefinition] = []
	for definition in get_all_definitions():
		if definition.category == category:
			result.append(definition)
	return result


func register_dynamic_lure(lure: BaitData) -> StringName:
	if lure == null or lure.lure_id == &"":
		return &""
	var existing: GameItemDefinition = get_by_domain(
		STORAGE_LURE,
		lure.lure_id
	)
	if existing != null:
		# A crafted lure may be reconstructed before its display override is
		# restored, so refresh presentation without changing canonical identity.
		existing.display_name = lure.display_name
		existing.description = lure.description
		return existing.item_id

	var definition := GameItemDefinition.new()
	definition.item_id = make_item_id(STORAGE_LURE, lure.lure_id)
	definition.domain_id = lure.lure_id
	definition.display_name = lure.display_name
	definition.description = lure.description
	definition.category = CATEGORY_LURES
	definition.storage_kind = STORAGE_LURE
	definition.stackable = true
	definition.max_stack = 999
	definition.tags = PackedStringArray(["fishing", "lure", "crafted"])
	_register(definition)
	return definition.item_id


func get_snapshot() -> Dictionary:
	var entries: Array = []
	for definition in get_all_definitions():
		entries.append(definition.to_snapshot())
	return {
		"configured": _configured,
		"count": entries.size(),
		"entries": entries,
	}


func _register_beach_materials(
	beach_catalog: BeachCraftingCatalog
) -> void:
	if beach_catalog == null:
		return
	for material in beach_catalog.materials:
		if material == null or material.material_id == &"":
			continue
		var definition := GameItemDefinition.new()
		definition.item_id = make_item_id(
			STORAGE_PLAYER,
			material.material_id
		)
		# Player-storage items still use a domain id; canonical item ids prevent
		# collisions with future fish/lure/rod ids of the same spelling.
		definition.domain_id = material.material_id
		definition.display_name = material.display_name
		definition.description = material.description
		definition.category = CATEGORY_MATERIALS
		definition.storage_kind = STORAGE_PLAYER
		definition.stackable = true
		definition.max_stack = 9999
		definition.sell_price_zenny = maxi(
			0,
			material.sell_price_zenny
		)
		definition.tags = PackedStringArray(["crafting", "material", "beach"])
		_register(definition)


func _register_fish(content: FishingContentCatalog) -> void:
	if content == null:
		return
	for fish in content.fish:
		if fish == null:
			continue
		var domain_text: String = fish.get_stable_species_id()
		if domain_text.is_empty():
			continue
		var definition := GameItemDefinition.new()
		definition.item_id = make_item_id(
			STORAGE_FISH,
			StringName(domain_text)
		)
		definition.domain_id = StringName(domain_text)
		definition.display_name = fish.fish_name
		definition.category = CATEGORY_FISH
		definition.storage_kind = STORAGE_FISH
		definition.stackable = true
		definition.max_stack = 9999
		definition.sell_price_zenny = fish.get_sell_value_zenny()
		definition.tags = PackedStringArray(["fishing", "fish"])
		_register(definition)


func _register_tackle(tackle_catalog: FishingTackleCatalog) -> void:
	if tackle_catalog == null:
		return

	if tackle_catalog.lure_catalog != null:
		for lure in tackle_catalog.lure_catalog.lures:
			if lure == null or lure.lure_id == &"":
				continue
			var lure_definition := GameItemDefinition.new()
			lure_definition.item_id = make_item_id(
				STORAGE_LURE,
				lure.lure_id
			)
			lure_definition.domain_id = lure.lure_id
			lure_definition.display_name = lure.display_name
			lure_definition.description = lure.description
			lure_definition.category = CATEGORY_LURES
			lure_definition.storage_kind = STORAGE_LURE
			lure_definition.stackable = true
			lure_definition.max_stack = 999
			lure_definition.tags = PackedStringArray(["fishing", "lure"])
			_register(lure_definition)

	for rod in tackle_catalog.rods:
		if rod == null or rod.rod_id == &"":
			continue
		var rod_definition := GameItemDefinition.new()
		rod_definition.item_id = make_item_id(
			STORAGE_ROD,
			rod.rod_id
		)
		rod_definition.domain_id = rod.rod_id
		rod_definition.display_name = rod.rod_name
		rod_definition.description = rod.description
		rod_definition.category = CATEGORY_RODS
		rod_definition.storage_kind = STORAGE_ROD
		rod_definition.stackable = false
		rod_definition.max_stack = 1
		rod_definition.tags = PackedStringArray(["fishing", "rod"])
		_register(rod_definition)


func _apply_shop_prices(shop_catalog) -> void:
	if shop_catalog == null or not shop_catalog.has_method("get_all_offers"):
		return
	for raw_offer in shop_catalog.call("get_all_offers"):
		if raw_offer == null:
			continue
		var storage_kind: StringName = STORAGE_LURE
		# FishingShopOffer.ItemType.ROD == 1. Avoid coupling this generic catalog
		# to the concrete shop-offer class just to classify presentation data.
		if int(raw_offer.item_type) == 1:
			storage_kind = STORAGE_ROD
		var definition: GameItemDefinition = get_by_domain(
			storage_kind,
			raw_offer.item_id
		)
		if definition == null:
			continue
		var price: int = maxi(0, int(raw_offer.price_zenny))
		if definition.buy_price_zenny <= 0:
			definition.buy_price_zenny = price
		else:
			definition.buy_price_zenny = mini(
				definition.buy_price_zenny,
				price
			)


func _register(definition: GameItemDefinition) -> void:
	if definition == null or not definition.is_valid_definition():
		return
	var key: String = String(definition.item_id)
	_definitions[key] = definition
	_domain_lookup[_domain_key(
		definition.storage_kind,
		definition.domain_id
	)] = key
	item_registered.emit(definition.item_id)


func _domain_key(
	storage_kind: StringName,
	domain_id: StringName
) -> String:
	return "%s|%s" % [
		String(storage_kind),
		String(domain_id),
	]
