extends Resource
class_name PlayableLocationContext

@export var location_id: StringName
@export var display_name: String
@export_file("*.tscn") var scene_path: String
@export var fishing_spot: FishingSpotData
@export var economy_contexts: Array[MerchantEconomyContext] = []
@export var economy_provider_paths: PackedStringArray = []
@export var destinations: PackedStringArray = []
## Derived from existing persistent ownership; no hours or new save fields.
@export var required_lure_ids: PackedStringArray = []
@export var required_rod_ids: PackedStringArray = []
@export var unlock_hint: String = ""
## Latched in existing FishingUnlockState so losing a lure cannot strand travel.
@export var unlock_flag: StringName = &""
