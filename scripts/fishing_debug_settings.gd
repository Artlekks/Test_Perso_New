extends RefCounted

const SizeRoller = preload("res://scripts/fishing_size_roller.gd")

enum KingMode {
	DEFAULT,
	FORCE_NORMAL,
	FORCE_KING
}

enum SpecimenMode {
	DEFAULT,
	SMALL,
	AVERAGE,
	LARGE,
	NEW_RECORD,
	KING,
}

var forced_fish: FishData = null
var shadow_fish_override: FishData = null
var shadow_count_override: int = 0
var king_mode: int = KingMode.DEFAULT
var forced_tech_level: int = 0
var record_debug_catches: bool = false
var specimen_mode: int = SpecimenMode.DEFAULT
var _progress: FishingProgress = null


func configure_progress(progress: FishingProgress) -> void:
	_progress = progress


func set_specimen_mode(mode: int) -> void:
	specimen_mode = clampi(mode, SpecimenMode.DEFAULT, SpecimenMode.KING)


func get_specimen_mode() -> int:
	return specimen_mode


func get_specimen_mode_label(data: FishData = null) -> String:
	var base := "DEFAULT RNG"
	match specimen_mode:
		SpecimenMode.SMALL:
			base = "FORCE SMALL"
		SpecimenMode.AVERAGE:
			base = "FORCE AVERAGE"
		SpecimenMode.LARGE:
			base = "FORCE LARGE"
		SpecimenMode.NEW_RECORD:
			base = "FORCE NEW RECORD"
		SpecimenMode.KING:
			base = "FORCE KING SIZE"

	if data == null or specimen_mode == SpecimenMode.DEFAULT:
		return base

	var size_cm := get_forced_specimen_size(data)
	if size_cm <= 0.0:
		return base
	return "%s (%d cm)" % [base, roundi(size_cm)]


func get_forced_specimen_size(data: FishData) -> float:
	if data == null or specimen_mode == SpecimenMode.DEFAULT:
		return -1.0

	var normal_bounds: Vector2i = SizeRoller.get_normal_size_bounds(data)
	var king_bounds: Vector2i = SizeRoller.get_king_size_bounds(data)

	match specimen_mode:
		SpecimenMode.SMALL:
			return float(normal_bounds.x)
		SpecimenMode.AVERAGE:
			return float(clampi(roundi(data.average_size), normal_bounds.x, normal_bounds.y))
		SpecimenMode.LARGE:
			return float(normal_bounds.y)
		SpecimenMode.NEW_RECORD:
			var current_best := 0
			if is_instance_valid(_progress):
				var record: Dictionary = _progress.get_species_record(data)
				current_best = roundi(float(record.get("best_size", 0.0)))
			if current_best <= 0:
				return float(clampi(roundi(data.average_size), normal_bounds.x, king_bounds.y))
			return float(clampi(current_best + 1, 1, king_bounds.y))
		SpecimenMode.KING:
			return float(king_bounds.x)

	return -1.0

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
	# Broad QA-state diagnostic: true for either gameplay-affecting overrides
	# or presentation-only shadow overrides. Do NOT use this to decide whether
	# a catch is allowed to enter permanent progression.
	return (
		is_catch_outcome_override_active()
		or is_presentation_override_active()
	)


func is_catch_outcome_override_active() -> bool:
	# Only overrides capable of changing the catch itself should make a catch
	# "debug" for persistence purposes. Ambient shadow species/count are visual
	# QA controls and must never disable legitimate catch records.
	return (
		forced_fish != null
		or king_mode != KingMode.DEFAULT
		or specimen_mode != SpecimenMode.DEFAULT
		or forced_tech_level > 0
	)


func is_presentation_override_active() -> bool:
	return (
		shadow_fish_override != null
		or shadow_count_override > 0
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
