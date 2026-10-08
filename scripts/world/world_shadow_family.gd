@tool
extends Resource
class_name WorldShadowFamily

## Shared world-unit footprint. Edit one family, never destination instances.
@export var family: StringName = &"humanoid_standard"
@export_range(0.01, 4.0, 0.01) var width := 0.22
@export_range(0.01, 4.0, 0.01) var depth := 0.22
@export_range(0.0, 1.0, 0.01) var opacity := 0.65
@export_range(0.001, 0.05, 0.001) var ground_offset := 0.006
