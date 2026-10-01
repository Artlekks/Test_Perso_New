extends Resource
class_name BeachCraftingRecipe

@export_category("Identity")
@export var recipe_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var template_lure_id: StringName = &""

@export_category("Recipe Baseline")
@export_range(-4, 4, 1) var base_buoyancy: int = 0
@export_range(-4, 4, 1) var base_handling: int = 0
@export_range(-4, 4, 1) var base_attraction: int = 0

@export_category("Component Slots")
@export var body_material_ids: PackedStringArray = PackedStringArray()
@export var core_material_ids: PackedStringArray = PackedStringArray()
@export var accent_material_ids: PackedStringArray = PackedStringArray()
@export var accent_optional: bool = true


func get_allowed_material_ids(slot_id: StringName) -> PackedStringArray:
	match slot_id:
		&"body":
			return body_material_ids
		&"core":
			return core_material_ids
		&"accent":
			return accent_material_ids
		_:
			return PackedStringArray()


func allows_material(slot_id: StringName, material_id: StringName) -> bool:
	if slot_id == &"accent" and material_id == &"" and accent_optional:
		return true
	return get_allowed_material_ids(slot_id).has(String(material_id))
