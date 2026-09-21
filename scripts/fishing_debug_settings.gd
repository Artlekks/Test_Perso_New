extends RefCounted

enum KingMode {
	DEFAULT,
	FORCE_NORMAL,
	FORCE_KING
}

var forced_fish: FishData = null
var king_mode: int = KingMode.DEFAULT


func set_forced_fish(fish: FishData) -> void:
	forced_fish = fish


func get_forced_fish() -> FishData:
	return forced_fish


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
