extends RefCounted
class_name PlayableCampaignQAGuideQA

const PresetServiceScript = preload(
	"res://scripts/progression/playable_campaign_qa_preset_service.gd"
)
const FishingContentCatalogResource: FishingContentCatalog = preload(
	"res://data/bof4/catalogs/all_content.tres"
)
const FishingTackleCatalogResource: FishingTackleCatalog = preload(
	"res://data/bof4/tackle/all_tackle.tres"
)


static func run() -> Dictionary:
	var failures := PackedStringArray()
	var passed: int = 0
	var service = PresetServiceScript.new()
	var presets: Array = service.get_presets()

	passed += _check(presets.size() == 6, "Guide exposes LIVE plus five campaign presets.", failures)
	passed += _check(_ids(presets) == ["live", "fresh_start", "first_fishing_trip", "learn_loop", "connected_systems", "specialization"], "Preset order matches the campaign spine.", failures)
	passed += _check(_tt_scenarios(presets) == ["fresh", "starter", "learn_loop", "early", "specialization"], "Applied presets reuse canonical Triple Triad QA scenarios.", failures)
	passed += _check(_species_targets(presets) == [0, 2, 5, 10, 18], "Species targets increase across campaign checkpoints.", failures)
	passed += _check(_zenny_targets(presets) == [100, 160, 350, 900, 2500], "Zenny targets are monotonic and preserve the 100z fresh start.", failures)
	passed += _check(_all_species_exist(presets), "Every synthetic catch species exists in the fishing catalog.", failures)
	passed += _check(_all_tackle_exists(presets), "Every preset rod/lure exists in the tackle catalog.", failures)
	passed += _check(FileAccess.file_exists("res://actors/PlayableCampaignQAGuide.tscn"), "Campaign QA guide scene is present.", failures)

	return {
		"passed_count": passed,
		"test_count": 8,
		"failures": failures,
	}


static func _check(ok: bool, label: String, failures: PackedStringArray) -> int:
	if ok:
		return 1
	failures.append(label)
	return 0


static func _ids(presets: Array) -> Array:
	var result: Array = []
	for row in presets:
		result.append(str(row.get("id", "")))
	return result


static func _tt_scenarios(presets: Array) -> Array:
	var result: Array = []
	for row in presets:
		if bool(row.get("applyable", false)):
			result.append(str(row.get("tt_scenario", "")))
	return result


static func _species_targets(presets: Array) -> Array:
	var result: Array = []
	for row in presets:
		if bool(row.get("applyable", false)):
			result.append(int(row.get("species_count", 0)))
	return result


static func _zenny_targets(presets: Array) -> Array:
	var result: Array = []
	for row in presets:
		if bool(row.get("applyable", false)):
			result.append(int(row.get("zenny", 0)))
	return result


static func _all_species_exist(presets: Array) -> bool:
	var max_species: int = 0
	for row in presets:
		max_species = maxi(max_species, int(row.get("species_count", 0)))
	for index in range(max_species):
		var species_id := StringName(PresetServiceScript.SPECIES_SEQUENCE[index])
		if FishingContentCatalogResource.get_fish_by_id(species_id) == null:
			return false
	return true


static func _all_tackle_exists(presets: Array) -> bool:
	for row in presets:
		for raw_rod in row.get("rod_ids", []):
			if not FishingTackleCatalogResource.has_rod(StringName(str(raw_rod))):
				return false
		for raw_lure in row.get("lure_ids", []):
			if not FishingTackleCatalogResource.has_lure(StringName(str(raw_lure))):
				return false
	return true
