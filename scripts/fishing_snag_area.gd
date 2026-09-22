class_name FishingSnagArea
extends Area3D

@export_range(0.0, 4.0, 0.05)
var snag_risk_multiplier: float = 1.0

@export var snag_label: StringName = &"obstacle"


func get_snag_risk_multiplier() -> float:
	return maxf(snag_risk_multiplier, 0.0)


func get_snag_label() -> StringName:
	return snag_label
