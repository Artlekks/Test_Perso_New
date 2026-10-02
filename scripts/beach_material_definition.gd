extends Resource
class_name BeachMaterialDefinition

@export_category("Identity")
@export var material_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_category("Crafting Traits")
@export_range(-4, 4, 1) var buoyancy_delta: int = 0
@export_range(-4, 4, 1) var handling_delta: int = 0
@export_range(-4, 4, 1) var attraction_delta: int = 0


@export_category("Economy")
@export_range(0, 9999, 1) var sell_price_zenny: int = 0

@export_category("Presentation")
@export var visual_tint: Color = Color.WHITE


func get_trait_summary() -> String:
	var pieces := PackedStringArray()
	if buoyancy_delta != 0:
		pieces.append("Buoyancy %+d" % buoyancy_delta)
	if handling_delta != 0:
		pieces.append("Handling %+d" % handling_delta)
	if attraction_delta != 0:
		pieces.append("Attraction %+d" % attraction_delta)
	if pieces.is_empty():
		return "Neutral"
	return " / ".join(pieces)
