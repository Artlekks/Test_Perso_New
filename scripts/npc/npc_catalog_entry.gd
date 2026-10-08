extends Resource
class_name NPCCatalogEntry
@export var id: StringName
@export var scene: PackedScene
@export var profile: NPCVisualProfile
@export_multiline var development_note: String
## Provisional casting metadata; never selects or installs a gameplay provider.
@export var placeholder_roles: PackedStringArray = []
@export_enum("A", "B", "C") var importance_tier: String = "C"
@export_enum("stationary", "patrol_capable", "ambient") var movement_type: String = "stationary"
@export var suggested_locations: PackedStringArray = []
@export var art_status: String = "NEEDS_REVIEW"

