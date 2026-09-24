extends Resource
class_name AmbientFishProfile

## Presentation-only tuning for the visible fish-shadow population at a spot.
## Index 0 in count_weights controls 1 visible shadow, index 1 controls 2, etc.
## Extend the array to support larger populations without changing runtime code.
@export_range(1, 32, 1)
var min_visible_shadows: int = 1

@export_range(1, 32, 1)
var max_visible_shadows: int = 3

@export var count_weights: PackedFloat32Array = PackedFloat32Array([
	0.55,
	0.32,
	0.13,
])

## Added to the species-preferred normalized depth chosen for an ambient shadow.
## Negative = generally shallower; positive = generally deeper.
@export_range(-0.35, 0.35, 0.01)
var depth_bias: float = 0.0

@export_range(0.5, 1.5, 0.05)
var speed_multiplier: float = 1.0

@export_range(0.5, 2.0, 0.05)
var lifetime_multiplier: float = 1.0


func get_min_count() -> int:
	return maxi(min_visible_shadows, 1)


func get_max_count() -> int:
	return maxi(max_visible_shadows, get_min_count())


func get_weight_for_count(count: int) -> float:
	var index := count - 1
	if index < 0:
		return 0.0
	# New counts become eligible automatically when max_visible_shadows grows.
	# Add/extend count_weights only when a specific count needs custom weighting.
	if index >= count_weights.size():
		return 1.0
	return maxf(count_weights[index], 0.0)
