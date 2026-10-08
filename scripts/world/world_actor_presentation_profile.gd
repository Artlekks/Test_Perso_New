@tool
extends Resource
class_name WorldActorPresentationProfile
## Sheet-space feet data; it never moves a collider or actor root.
@export_enum("Character", "Critter", "Ground item", "Ground prop", "Excluded") var category: int = 0
@export var feet_from_bottom_px: float = 0.0
@export var animation_feet_from_bottom_px: Dictionary = {}
@export var pixel_size: float = 0.01
@export var sprite_scale: Vector3 = Vector3.ONE
@export var ground_lift: float = 0.012
@export var flat_on_ground: bool = false
@export var ground_yaw_degrees: float = 0.0
@export var shadow_enabled: bool = true
@export var shadow_width: float = 0.30
@export var shadow_depth: float = 0.30
@export_range(0.0, 1.0) var shadow_opacity: float = 0.65
@export var shadow_ground_lift: float = 0.006
