extends Resource
class_name FishingCurrentFieldDefinition

enum FieldType {
	FLOW,
	CALM,
	EDDY,
}

@export_category("Identity")
@export var field_id: StringName = &""
@export var field_type: FieldType = FieldType.FLOW

@export_category("Shape")
## Normalized position inside FishSwimBounds (0..1 on each axis).
@export var center_uv: Vector2 = Vector2(0.5, 0.5)
## Ellipse radius in normalized swim-bound coordinates.
@export var radius_uv: Vector2 = Vector2(0.20, 0.20)
## Portion of the ellipse edge used to blend back toward surrounding water.
@export_range(0.05, 0.95, 0.05)
var edge_softness: float = 0.35

@export_category("Flow")
## Used by FLOW fields. X/Y maps to world X/Z.
@export var direction: Vector2 = Vector2.RIGHT
## Target flow speed in world units/second for FLOW and EDDY fields.
@export_range(0.0, 2.0, 0.005)
var speed: float = 0.06
## Used by CALM fields. 0.2 means the local water retains 20% of incoming flow.
@export_range(0.0, 1.0, 0.05)
var calm_multiplier: float = 0.25
## Used by EDDY fields.
@export var clockwise: bool = true


func is_valid_definition() -> bool:
	return (
		field_id != &""
		and radius_uv.x > 0.001
		and radius_uv.y > 0.001
		and edge_softness > 0.0
	)


func get_weight(uv: Vector2) -> float:
	if not is_valid_definition():
		return 0.0

	var normalized := Vector2(
		(uv.x - center_uv.x) / radius_uv.x,
		(uv.y - center_uv.y) / radius_uv.y
	)
	var distance := normalized.length()
	if distance >= 1.0:
		return 0.0

	var inner_edge := clampf(1.0 - edge_softness, 0.0, 0.95)
	if distance <= inner_edge:
		return 1.0

	return 1.0 - smoothstep(inner_edge, 1.0, distance)


func apply_to_velocity(
	incoming_velocity: Vector2,
	uv: Vector2
) -> Vector2:
	var weight := get_weight(uv)
	if weight <= 0.0:
		return incoming_velocity

	var target := incoming_velocity
	match field_type:
		FieldType.FLOW:
			var flow_direction := direction
			if flow_direction.length_squared() <= 0.000001:
				flow_direction = incoming_velocity.normalized()
			if flow_direction.length_squared() > 0.000001:
				target = flow_direction.normalized() * speed
			else:
				target = Vector2.ZERO
		FieldType.CALM:
			target = incoming_velocity * calm_multiplier
		FieldType.EDDY:
			var radial := uv - center_uv
			if radial.length_squared() <= 0.000001:
				radial = Vector2.RIGHT
			var tangent := Vector2(-radial.y, radial.x).normalized()
			if clockwise:
				tangent = -tangent
			target = tangent * speed
		_:
			target = incoming_velocity

	return incoming_velocity.lerp(target, weight)
