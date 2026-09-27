extends Resource
class_name FishingHotspotDefinition

@export_category("Identity")
@export var hotspot_id: StringName = &""
@export var display_name: String = ""
@export var hotspot_tag: StringName = &""

@export_category("Horizontal Placement")
## Normalized coordinates inside FishSwimBounds:
## x = left -> right, y = near shore -> far water.
##
## These coordinates are PROJECT SCENE AUTHORING, not original BOF4 map data.
@export var center_uv: Vector2 = Vector2(0.5, 0.5)

## Elliptical influence radius in normalized swim-bounds space.
@export var radius_uv: Vector2 = Vector2(0.25, 0.25)

@export_range(0.25, 4.0, 0.05)
var horizontal_falloff_power: float = 1.5

@export_category("Depth Band")
## 0 = surface, 1 = bottom.
@export_range(0.0, 1.0, 0.01)
var depth_min_ratio: float = 0.0

@export_range(0.0, 1.0, 0.01)
var depth_max_ratio: float = 1.0

## Soft feather outside the preferred depth band so hotspot behavior does not
## become an invisible binary gate.
@export_range(0.01, 0.50, 0.01)
var depth_feather: float = 0.15

@export_category("Concentration")
## Local bite-frequency multiplier at the hotspot center.
@export_range(0.25, 3.0, 0.05)
var density_multiplier: float = 1.35

## Species listed below receive this extra local selection weighting.
@export_range(0.25, 6.0, 0.05)
var species_weight_multiplier: float = 2.0

## Empty = concentration hotspot applies to all species.
@export var species_ids: PackedStringArray = PackedStringArray()

@export_category("Source Metadata")
## Optional distance printed by guides. It is metadata only; center_uv is what
## maps that landmark into the current Godot scene.
@export_range(0.0, 100.0, 0.5)
var source_distance_m: float = 0.0

@export_multiline var source_note: String = ""

## Records the approximate scene-mapping decision separately from source fact.
@export_multiline var placement_note: String = ""


func is_valid_definition() -> bool:
	return (
		hotspot_id != &""
		and radius_uv.x > 0.0
		and radius_uv.y > 0.0
		and density_multiplier > 0.0
		and species_weight_multiplier > 0.0
	)


func applies_to_species(
	species_id: StringName
) -> bool:
	if species_ids.is_empty():
		return true

	var key: String = (
		str(species_id)
		.strip_edges()
		.to_lower()
	)

	for authored_id in species_ids:
		if (
			str(authored_id)
			.strip_edges()
			.to_lower()
			== key
		):
			return true

	return false


func get_horizontal_strength(
	uv: Vector2
) -> float:
	var safe_radius := Vector2(
		maxf(radius_uv.x, 0.001),
		maxf(radius_uv.y, 0.001)
	)
	var offset := Vector2(
		(uv.x - center_uv.x) / safe_radius.x,
		(uv.y - center_uv.y) / safe_radius.y
	)
	var distance: float = offset.length()

	if distance >= 1.0:
		return 0.0

	var normalized: float = 1.0 - distance

	return pow(
		clampf(normalized, 0.0, 1.0),
		maxf(horizontal_falloff_power, 0.01)
	)


func get_depth_strength(
	depth_ratio: float
) -> float:
	var value: float = clampf(
		depth_ratio,
		0.0,
		1.0
	)
	var band_min: float = clampf(
		minf(
			depth_min_ratio,
			depth_max_ratio
		),
		0.0,
		1.0
	)
	var band_max: float = clampf(
		maxf(
			depth_min_ratio,
			depth_max_ratio
		),
		0.0,
		1.0
	)

	if value >= band_min and value <= band_max:
		return 1.0

	var distance_from_band: float = (
		band_min - value
		if value < band_min
		else value - band_max
	)

	return clampf(
		1.0
		- distance_from_band
		/ maxf(depth_feather, 0.01),
		0.0,
		1.0
	)


func get_combined_strength(
	uv: Vector2,
	depth_ratio: float
) -> float:
	return (
		get_horizontal_strength(uv)
		* get_depth_strength(depth_ratio)
	)


func get_debug_summary() -> String:
	return "%s @ %.2f,%.2f r%.2f/%.2f d%.2f-%.2f x%.2f" % [
		display_name,
		center_uv.x,
		center_uv.y,
		radius_uv.x,
		radius_uv.y,
		depth_min_ratio,
		depth_max_ratio,
		density_multiplier,
	]
