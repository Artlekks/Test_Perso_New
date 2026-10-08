@tool
extends WorldActorPresentationProfile
class_name NPCVisualProfile
## Grounding is inherited from the production profile, never a second anchor.
enum DirectionalMode { ONE_VIEW, TWO_VIEW, FOUR_DIR, FOUR_DIR_WITH_MIRROR, EIGHT_DIR, SPECIAL }
@export var npc_id: StringName
@export var development_name: String
@export var sprite_frames: SpriteFrames
@export var directional_mode: DirectionalMode = DirectionalMode.ONE_VIEW
@export var available_directions: PackedStringArray = []
@export var default_animation: StringName
@export_range(0.1, 4.0, 0.1) var animation_speed: float = 1.0
@export var collider_profile: NPCColliderProfile
@export var movement_capability: bool = false
@export var role_tags: PackedStringArray = []

