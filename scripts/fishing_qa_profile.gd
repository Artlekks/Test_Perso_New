extends Resource
class_name FishingQAProfile

enum KingMode {
	DEFAULT_RNG,
	FORCE_NORMAL,
	FORCE_KING,
}

@export var profile_name: String = "QA Profile"
@export var sort_order: int = 100
@export_multiline var purpose: String = ""

@export_category("Environment")
@export var fishing_spot: FishingSpotData

@export_category("Fish Overrides")
## Null keeps normal encounter selection for this profile.
@export var forced_fish: FishData
## Optional ambient/pre-bite shadow override. This is deliberately separate so
## a QA profile can force a visible species without bypassing pre-bite RNG.
@export var shadow_fish_override: FishData

@export_category("Gear / Technique")
@export var lure: BaitData
@export var rod: RodData
@export_range(0, 4, 1) var forced_tech_level: int = 0
@export_enum("Default RNG", "Force Normal", "Force King")
var king_mode: int = KingMode.DEFAULT_RNG

@export_category("Debug Save")
@export var record_debug_catches: bool = false
