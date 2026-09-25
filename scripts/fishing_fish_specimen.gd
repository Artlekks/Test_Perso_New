extends RefCounted
class_name FishingFishSpecimen

var specimen_id: int = 0
var species_id: String = ""
var fish_name: String = ""
var size: float = 0.0
var points: int = 0
var is_king: bool = false
var spot_id: String = ""
var spot_name: String = ""
var lure_id: String = ""
var lure_name: String = ""
var legacy: bool = false


func to_dictionary() -> Dictionary:
	return {
		"specimen_id": specimen_id,
		"species_id": species_id,
		"fish_name": fish_name,
		"size": size,
		"points": points,
		"is_king": is_king,
		"spot_id": spot_id,
		"spot_name": spot_name,
		"lure_id": lure_id,
		"lure_name": lure_name,
		"legacy": legacy,
	}


func duplicate_specimen() -> FishingFishSpecimen:
	return from_dictionary(to_dictionary())


static func from_dictionary(data: Dictionary) -> FishingFishSpecimen:
	var specimen := FishingFishSpecimen.new()
	specimen.specimen_id = maxi(int(data.get("specimen_id", 0)), 0)
	specimen.species_id = _normalize_id_static(str(data.get("species_id", "")))
	specimen.fish_name = str(data.get("fish_name", ""))
	specimen.size = float(maxi(roundi(float(data.get("size", 0.0))), 0))
	specimen.points = maxi(int(data.get("points", 0)), 0)
	specimen.is_king = bool(data.get("is_king", false))
	specimen.spot_id = str(data.get("spot_id", ""))
	specimen.spot_name = str(data.get("spot_name", ""))
	specimen.lure_id = str(data.get("lure_id", ""))
	specimen.lure_name = str(data.get("lure_name", ""))
	specimen.legacy = bool(data.get("legacy", false))
	return specimen


static func _normalize_id_static(value: String) -> String:
	return value.strip_edges().to_lower().replace(" ", "_").replace("-", "_").replace("'", "")
