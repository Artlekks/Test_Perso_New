@tool
extends Resource
class_name WorldActorPresentationProfile
## Sheet-space feet data; it never moves a collider or actor root.
@export_enum("Character", "Critter", "Ground item", "Ground prop", "Excluded") var category: int = 0
@export var feet_from_bottom_px: float = 0.0
@export var animation_feet_from_bottom_px: Dictionary = {}
## -1 uses frame center. Explicit sheet-space stance points support uneven
## transparent padding without moving the actor or its physical shadow.
@export var feet_from_left_px: float = -1.0
@export var animation_feet_from_left_px: Dictionary = {}
## Pose -> animation prefix. Adding idle_n/idle_ne/etc. only needs frames.
@export var directional_animation_prefixes: Dictionary = {}
## Static actors can opt into newly assigned directional art entirely in data.
## Empty preserves their existing one-direction/state animation selection.
@export var default_directional_pose: String = ""
## Pose -> direction -> {animation, flip_h}; only existing authored mirrors.
@export var directional_aliases: Dictionary = {}
@export var pixel_size: float = 0.01
@export var sprite_scale: Vector3 = Vector3.ONE
@export var ground_lift: float = 0.012
@export var flat_on_ground: bool = false
@export var ground_yaw_degrees: float = 0.0
@export var shadow_enabled: bool = true
@export_storage var shadow_width: float = 0.22
@export_storage var shadow_depth: float = 0.22
@export_storage var shadow_opacity: float = 0.65
@export_storage var shadow_ground_lift: float = 0.006

## Family values are authoritative; legacy scalar fields above are retained for
## older tooling and migration, not used to size production ground shadows.
@export_enum("player", "humanoid_standard", "humanoid_large", "humanoid_small", "critter", "ground_prop", "item") var shadow_family: String = "humanoid_standard"
@export_range(0.1, 4.0, 0.05) var shadow_scale_multiplier := 1.0
@export var marker_height := 0.72

func resolved_shadow_family() -> WorldShadowFamily:
	return preload("res://scripts/world/world_shadow_families.gd").resolve(StringName(shadow_family))
