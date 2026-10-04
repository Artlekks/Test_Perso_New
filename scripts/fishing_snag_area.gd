class_name FishingSnagArea
extends Area3D

@export_category("Lure Snag")
@export_range(0.0, 4.0, 0.05)
var snag_risk_multiplier: float = 1.0
@export var snag_label: StringName = &"obstacle"

@export_category("Fight Structure")
## When enabled, a hooked fish can use this same authored obstacle as cover.
@export var fight_structure_enabled: bool = true
@export var structure_id: StringName = &""
@export var structure_label: String = "STRUCTURE"
@export_range(0.0, 2.0, 0.05)
var line_abrasion_rate: float = 0.30
@export_range(0.0, 1.0, 0.05)
var fish_seek_strength: float = 0.65
@export_range(0.0, 2.0, 0.05)
var pressure_abrasion_multiplier: float = 1.0


func _ready() -> void:
	add_to_group("fishing_snag")
	add_to_group("fishing_structure")


func get_snag_risk_multiplier() -> float:
	return maxf(snag_risk_multiplier, 0.0)


func get_snag_label() -> StringName:
	return snag_label


func get_fight_structure_snapshot() -> Dictionary:
	if not fight_structure_enabled:
		return {}
	var stable_id := structure_id
	if stable_id == &"":
		stable_id = StringName(name)
	return {
		"structure_id": stable_id,
		"label": structure_label,
		"world_position": global_position,
		"abrasion_rate": maxf(line_abrasion_rate, 0.0),
		"seek_strength": clampf(fish_seek_strength, 0.0, 1.0),
		"pressure_multiplier": maxf(pressure_abrasion_multiplier, 0.0),
		"snag_label": snag_label,
	}
