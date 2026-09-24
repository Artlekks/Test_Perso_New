extends RefCounted

enum KingMode {
	DEFAULT,
	FORCE_NORMAL,
	FORCE_KING
}

var forced_fish: FishData = null
var shadow_fish_override: FishData = null
var shadow_count_override: int = 0
var king_mode: int = KingMode.DEFAULT
var forced_tech_level: int = 0
var record_debug_catches: bool = false


func set_forced_fish(fish: FishData) -> void:
	forced_fish = fish


func get_forced_fish() -> FishData:
	return forced_fish


func set_shadow_fish_override(fish: FishData) -> void:
	shadow_fish_override = fish


func get_shadow_fish_override() -> FishData:
	return shadow_fish_override


func set_shadow_count_override(count: int) -> void:
	shadow_count_override = clampi(count, 0, 32)


func get_shadow_count_override() -> int:
	return shadow_count_override


func get_shadow_count_label() -> String:
	if shadow_count_override <= 0:
		return "SPOT PROFILE"
	return str(shadow_count_override)


func set_king_mode(mode: int) -> void:
	king_mode = clampi(
		mode,
		KingMode.DEFAULT,
		KingMode.FORCE_KING
	)


func get_king_mode() -> int:
	return king_mode


func get_king_override() -> int:
	match king_mode:
		KingMode.FORCE_NORMAL:
			return 0
		KingMode.FORCE_KING:
			return 1
		_:
			return -1


func get_king_mode_label() -> String:
	match king_mode:
		KingMode.FORCE_NORMAL:
			return "FORCE NORMAL"
		KingMode.FORCE_KING:
			return "FORCE KING"
		_:
			return "DEFAULT RNG"


func set_forced_tech_level(level: int) -> void:
	forced_tech_level = clampi(level, 0, 4)


func get_forced_tech_level() -> int:
	return forced_tech_level


func get_forced_tech_label() -> String:
	if forced_tech_level <= 0:
		return "NORMAL RHYTHM"

	return "FORCE TEC %d" % forced_tech_level


func is_encounter_override_active() -> bool:
	return (
		forced_fish != null
		or shadow_fish_override != null
		or shadow_count_override > 0
		or king_mode != KingMode.DEFAULT
		or forced_tech_level > 0
	)


func set_record_debug_catches(enabled: bool) -> void:
	record_debug_catches = enabled


func should_record_debug_catches() -> bool:
	return record_debug_catches


func get_record_debug_label() -> String:
	return (
		"ON"
		if record_debug_catches
		else "OFF"
	)
