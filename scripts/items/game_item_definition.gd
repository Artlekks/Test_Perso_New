extends Resource
class_name GameItemDefinition

@export_category("Identity")
@export var item_id: StringName = &""
@export var domain_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_category("Classification")
@export var category: StringName = &"MISC"
@export var storage_kind: StringName = &"player"
@export var stackable: bool = true
@export_range(1, 99999, 1) var max_stack: int = 9999
@export var tags: PackedStringArray = PackedStringArray()

@export_category("Economy")
@export_range(0, 999999, 1) var buy_price_zenny: int = 0
@export_range(0, 999999, 1) var sell_price_zenny: int = 0


func is_valid_definition() -> bool:
	return (
		item_id != &""
		and domain_id != &""
		and not display_name.strip_edges().is_empty()
		and category != &""
		and storage_kind != &""
		and max_stack > 0
	)


func to_snapshot() -> Dictionary:
	return {
		"item_id": String(item_id),
		"domain_id": String(domain_id),
		"display_name": display_name,
		"description": description,
		"category": String(category),
		"storage_kind": String(storage_kind),
		"stackable": stackable,
		"max_stack": max_stack,
		"buy_price_zenny": buy_price_zenny,
		"sell_price_zenny": sell_price_zenny,
		"tags": tags.duplicate(),
	}
