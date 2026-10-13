extends SceneTree
## Environment species profiles v2. Run with Godot 4.7.2 in a full project:
## godot --headless --path . --script res://scripts/qa/environment_species_profiles_qa.gd
## Read-only: no scene loads, saves, world mutations, random values or camera changes.

const Policy = preload("res://scripts/fishing_ecology_policy.gd")
const FISH_DIRECTORY := "res://data/bof4/fish/"
const PROFILES := {
	"blue_gill": [2, 1, 0],
	"rainbow_trout": [0, 2, 0],
	"black_bass": [0, 0, 1],
	"bonito": [1, 0, 1],
}

var successes: int = 0
var failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if ok:
		successes += 1
	else:
		failures.append(message)
		push_error("Species ecology QA: " + message)

func _snapshot(minute: int, flow: float = 0.25, tags: PackedStringArray = PackedStringArray()) -> Dictionary:
	var snapshot: Dictionary = Policy.build_snapshot(
		{"total_minutes": minute},
		{"available": true, "speed_mps": 3.0, "velocity_xz": Vector2(1, 0)},
		{"active": true, "water_level_ratio": 0.5, "phase_id": &"incoming"},
		Vector2(flow, 0.0), tags, "ocean_2"
	)
	snapshot["current_available"] = true
	return snapshot

func _run() -> void:
	var fish_by_id: Dictionary = {}
	var files := DirAccess.get_files_at(FISH_DIRECTORY)
	for filename in files:
		if not filename.ends_with(".tres"):
			continue
		var fish := load(FISH_DIRECTORY + filename) as FishData
		_check(fish != null, "Load fish resource: " + filename)
		if fish == null:
			continue
		var id: String = fish.get_stable_species_id()
		_check(not fish_by_id.has(id), "Unique species ID: " + id)
		fish_by_id[id] = fish
		if PROFILES.has(id):
			var preference: Array = PROFILES[id]
			_check(int(fish.ecological_activity_cycle) == int(preference[0]), id + " activity profile")
			_check(int(fish.ecological_flow_niche) == int(preference[1]), id + " current profile")
			_check(int(fish.ecological_visibility_niche) == int(preference[2]), id + " visibility profile")
			_check(fish.has_meta("ecology_reference"), id + " evidence source recorded")
		else:
			_check(fish.ecological_activity_cycle == 0 and fish.ecological_flow_niche == 0 and fish.ecological_visibility_niche == 0, id + " legacy profile neutral")
	_check(fish_by_id.size() == 30, "30 canonical BOF4 fish remain registered")
	for id in PROFILES:
		_check(fish_by_id.has(id), "Configured species present: " + id)

	var dawn := _snapshot(390, 0.12)
	var noon := _snapshot(720, 0.12)
	var night := _snapshot(0, 0.12)
	var fast_flow := _snapshot(720, 0.95)
	var mid_flow := _snapshot(720, 0.52)
	var rainy := _snapshot(720, 0.12, PackedStringArray(["rain"]))
	_check(float(noon.visual_detection_0_1) > float(rainy.visual_detection_0_1), "rain reduces estimated visual detection, not a guaranteed fish response")
	_check(noon == _snapshot(720, 0.12), "snapshot deterministic for repeated conditions")

	if fish_by_id.has("blue_gill"):
		var fish: FishData = fish_by_id["blue_gill"]
		_check(Policy.species_activity_multiplier(fish, dawn) > Policy.species_activity_multiplier(fish, noon), "bluegill twilight vs midday")
		_check(Policy.species_activity_multiplier(fish, noon) > Policy.species_activity_multiplier(fish, fast_flow), "bluegill low flow vs fast flow")
	if fish_by_id.has("rainbow_trout"):
		var fish: FishData = fish_by_id["rainbow_trout"]
		_check(Policy.species_activity_multiplier(fish, mid_flow) > Policy.species_activity_multiplier(fish, fast_flow), "rainbow trout intermediate vs strong flow")
		_check(Policy.species_activity_multiplier(fish, mid_flow) > Policy.species_activity_multiplier(fish, _snapshot(720, 0.0)), "rainbow trout intermediate vs stagnant water")
	if fish_by_id.has("black_bass"):
		var fish: FishData = fish_by_id["black_bass"]
		_check(Policy.species_activity_multiplier(fish, noon) > Policy.species_activity_multiplier(fish, night), "black bass visual detection, day vs very low light")
		_check(Policy.species_activity_multiplier(fish, noon) >= Policy.species_activity_multiplier(fish, rainy), "black bass simulated visibility effect under rain")
	if fish_by_id.has("bonito"):
		var fish: FishData = fish_by_id["bonito"]
		_check(Policy.species_activity_multiplier(fish, noon) > Policy.species_activity_multiplier(fish, night), "bonito daylight and visual response")
		_check(Policy.species_activity_multiplier(fish, noon) >= Policy.species_activity_multiplier(fish, rainy), "bonito visibility and rain")

	var missing_clock := _snapshot(720)
	missing_clock["clock_available"] = false
	var missing_current := _snapshot(720)
	missing_current["current_available"] = false
	for id in fish_by_id:
		var fish: FishData = fish_by_id[id]
		for environment in [dawn, noon, night, fast_flow, mid_flow, rainy]:
			var result: float = Policy.species_activity_multiplier(fish, environment)
			_check(result >= Policy.MIN_SPECIES_MULTIPLIER and result <= Policy.MAX_SPECIES_MULTIPLIER, id + " ecology bounded")
		if not PROFILES.has(id):
			_check(is_equal_approx(Policy.species_activity_multiplier(fish, noon), 1.0), id + " neutral at noon")
			_check(is_equal_approx(Policy.species_activity_multiplier(fish, rainy), 1.0), id + " neutral under rain")
	_check(is_equal_approx(Policy.species_activity_multiplier(fish_by_id["bonito"], missing_clock), 1.0), "unknown clock never invents bonito preference")
	_check(is_equal_approx(Policy.species_activity_multiplier(fish_by_id["black_bass"], missing_clock), 1.0), "unknown clock never invents visual preference")
	_check(is_equal_approx(Policy.species_activity_multiplier(fish_by_id["rainbow_trout"], missing_current), 1.0), "unknown current never invents trout preference")

	print("Species ecology QA: %d/%d passed" % [successes, successes + failures.size()])
	for label in failures:
		print("FAIL: " + label)
	quit(0 if failures.is_empty() else 1)
