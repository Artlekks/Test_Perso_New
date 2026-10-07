extends Area3D

const FishingConcentrationFieldScript = preload(
	"res://scripts/fishing_concentration_field.gd"
)

signal fishing_spot_changed(spot: FishingSpotData)

@export var facing_tolerance_degrees: float = 60.0
@export var fishing_spot: FishingSpotData
@export var shore_boundary: Node3D

@onready var water_facing: Node3D = $WaterFacing
@onready var water_surface: Node3D = $WaterSurface
@onready var water_bottom: Node3D = $WaterBottom
@onready var swim_bounds: Node = get_node_or_null("FishSwimBounds")
@onready var shadow_presence: Node = get_node_or_null("FishShadowPresence")

var concentration_field: FishingConcentrationField = (
	FishingConcentrationFieldScript.new()
)
var debug_spot_override := false


func _ready() -> void:
	add_to_group(&"world_fishing_spots")
	_rebuild_concentration_field()


func can_player_fish(player: Node3D) -> bool:
	if not overlaps_body(player):
		return false

	var player_forward := player.global_transform.basis.z.normalized()
	var water_forward := water_facing.global_transform.basis.z.normalized()
	var angle := rad_to_deg(player_forward.angle_to(water_forward))

	return angle <= facing_tolerance_degrees


func get_water_forward() -> Vector3:
	return water_facing.global_transform.basis.z.normalized()


func get_water_y() -> float:
	return water_surface.global_position.y


func get_bottom_y() -> float:
	return water_bottom.global_position.y


func get_water_depth() -> float:
	return water_surface.global_position.y - water_bottom.global_position.y


func get_swim_bounds() -> Node:
	return swim_bounds


func get_shore_boundary() -> Node3D:
	return shore_boundary


func get_fish_population() -> Array[FishSpawnEntry]:
	var spot := get_fishing_spot()
	if spot == null:
		return []

	return spot.get_fish_population()


func get_fishing_spot() -> FishingSpotData:
	var locations := get_node_or_null("/root/WorldLocations")
	if not debug_spot_override and locations != null and locations.is_current_scene(get_tree().current_scene):
		return locations.current_location.fishing_spot
	return fishing_spot


func set_fishing_spot(new_spot: FishingSpotData) -> void:
	# Existing explicit debug selector. It cannot change normal location access.
	debug_spot_override = true
	fishing_spot = new_spot
	_rebuild_concentration_field()

	if shadow_presence != null and shadow_presence.has_method("rebuild_population"):
		shadow_presence.rebuild_population()

	fishing_spot_changed.emit(fishing_spot)


func set_environment_context(context: Dictionary) -> void:
	if concentration_field != null and concentration_field.has_method("set_environment_context"):
		concentration_field.set_environment_context(context)

	if shadow_presence == null:
		shadow_presence = get_node_or_null("FishShadowPresence")

	if (
		shadow_presence != null
		and shadow_presence.has_method("set_environment_context")
	):
		shadow_presence.set_environment_context(context)


func set_debug_shadow_overrides(fish: FishData, count: int) -> void:
	if shadow_presence == null:
		shadow_presence = get_node_or_null("FishShadowPresence")

	if shadow_presence != null and shadow_presence.has_method("set_debug_overrides"):
		shadow_presence.set_debug_overrides(fish, count)


func set_debug_shadow_fish(fish: FishData) -> void:
	if shadow_presence == null:
		shadow_presence = get_node_or_null("FishShadowPresence")

	if shadow_presence != null and shadow_presence.has_method("set_debug_forced_fish"):
		shadow_presence.set_debug_forced_fish(fish)


func set_debug_shadow_count(count: int) -> void:
	if shadow_presence == null:
		shadow_presence = get_node_or_null("FishShadowPresence")

	if (
		shadow_presence != null
		and shadow_presence.has_method("set_debug_shadow_count_override")
	):
		shadow_presence.set_debug_shadow_count_override(count)


func get_shadow_population_debug_counts() -> Vector2i:
	if shadow_presence == null:
		shadow_presence = get_node_or_null("FishShadowPresence")

	if (
		shadow_presence != null
		and shadow_presence.has_method("get_population_debug_counts")
	):
		return shadow_presence.get_population_debug_counts()

	return Vector2i.ZERO


func get_one_with_nature_snapshot() -> Dictionary:
	if shadow_presence == null:
		shadow_presence = get_node_or_null("FishShadowPresence")

	if (
		shadow_presence == null
		or not shadow_presence.has_method("get_one_with_nature_snapshot")
	):
		return {
			"available": false,
			"reason": "fish_presence_unavailable",
		}

	return shadow_presence.get_one_with_nature_snapshot()


func get_fish_sign_snapshot() -> Dictionary:
	if shadow_presence == null:
		shadow_presence = get_node_or_null("FishShadowPresence")

	if (
		shadow_presence == null
		or not shadow_presence.has_method("get_fish_sign_snapshot")
	):
		return {
			"available": false,
			"reason": "fish_presence_unavailable",
		}

	return shadow_presence.get_fish_sign_snapshot()


func get_concentration_snapshot(
	world_position: Vector3,
	current_depth: float,
	total_depth: float
) -> Dictionary:
	if concentration_field == null:
		return {}

	return concentration_field.sample(
		world_position,
		current_depth,
		total_depth
	)


func get_fish_radar_snapshot(
	world_position: Vector3
) -> Dictionary:
	if concentration_field == null:
		return {
			"dot_count": 0,
			"dots": [],
		}

	return concentration_field.build_radar_snapshot(
		world_position
	)


func _rebuild_concentration_field() -> void:
	if concentration_field == null:
		concentration_field = (
			FishingConcentrationFieldScript.new()
		)

	concentration_field.configure(
		fishing_spot,
		swim_bounds as FishSwimBounds
	)


func get_spot_debug_snapshot() -> Dictionary:
	if fishing_spot == null:
		return {
			"spot": "NONE",
			"summary": "NO SPOT",
			"water_depth_m": get_water_depth(),
			"species": PackedStringArray(),
		}

	return {
		"spot": fishing_spot.spot_name,
		"summary": fishing_spot.get_debug_summary(),
		"water_depth_m": get_water_depth(),
		"species": fishing_spot.get_population_species_names(),
		"hotspot_count": fishing_spot.get_hotspot_count(),
		"baseline_concentration": fishing_spot.baseline_concentration,
	}
