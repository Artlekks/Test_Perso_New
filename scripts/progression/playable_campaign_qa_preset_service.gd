extends RefCounted
class_name PlayableCampaignQAPresetService

const TripleTriadHarnessScript = preload(
	"res://scripts/triple_triad/triple_triad_campaign_qa_harness.gd"
)
const FishingContentCatalogResource: FishingContentCatalog = preload(
	"res://data/bof4/catalogs/all_content.tres"
)
const FishingTackleCatalogResource: FishingTackleCatalog = preload(
	"res://data/bof4/tackle/all_tackle.tres"
)
const TripleTriadCardCatalogResource: Resource = preload(
	"res://data/triple_triad/card_catalog.tres"
)

const TRANSIENT_PATHS := [
	"user://fishing_catch_pending.json",
	"user://fishing_catch_pending.tmp",
	"user://fishing_card_maker_pending.json",
	"user://fishing_card_maker_pending.tmp",
	"user://fishing_loadout.json",
	"user://beach_crafted_lures.json",
	"user://beach_crafting_recipe_selections.cfg",
]

const SPECIES_SEQUENCE := [
	"bass",
	"blue_gill",
	"sea_bass",
	"trout",
	"piranha",
	"rainbow_trout",
	"sea_bream",
	"black_bass",
	"bonito",
	"flatfish",
	"salmon",
	"black_porgy",
	"blowfish",
	"flying_fish",
	"sweetfish",
	"dorado",
	"sturgeon",
	"octopus",
]

var _services = null
var _tt_harness = TripleTriadHarnessScript.new()


func configure(session_services) -> void:
	_services = session_services


func get_presets() -> Array:
	return [
		{
			"id": "live",
			"name": "LIVE / Current Save",
			"checkpoint": "Read-only",
			"summary": "Inspect the real save. Nothing is changed.",
			"tutorial": "Use this row during normal playtests. The right panel explains the current campaign phase and the Director's next objective.",
			"checklist": [
				"Read PHASE and NEXT OBJECTIVE.",
				"Check cards / species / rods / lures against the target.",
				"Resolve any BLOCKER before judging progression flow.",
			],
			"applyable": false,
			"destructive": false,
		},
		_preset(
			"fresh_start", "Fresh Start", "0 min",
			"100z, Wooden Rod, Straight lure, 0 cards, Triple Triad locked.",
			"fresh", 0, 100, ["wooden_rod"], ["straight"], 0,
			[
				"Enter fishing with no card-system knowledge.",
				"Confirm the first useful action is obvious without debug help.",
				"Catch naturally until the Saltworn Card Case is discovered.",
			]
		),
		_preset(
			"first_fishing_trip", "After First Fishing Trip", "~15 min",
			"2 species recorded, Saltworn Card Case found, exactly 5 starter cards.",
			"starter", 2, 160, ["wooden_rod"], ["straight"], 0,
			[
				"Open the card game and confirm the five-card deck is usable.",
				"Check that fishing still feels like the primary activity.",
				"Verify the Director now points toward the Learn Loop.",
			]
		),
		_preset(
			"learn_loop", "Hour 1 / Learn Loop", "~1 h",
			"5 species, 8 reachable cards, Beach Trader cleared, light tackle growth.",
			"learn_loop", 5, 350, ["wooden_rod"], ["straight", "tail"], 0,
			[
				"Try fishing, selling, gathering and an early duel in any order.",
				"Check that card salvage and Beach Trader progression are understandable.",
				"Look for a natural reason to keep fishing after cards unlock.",
			]
		),
		_preset(
			"connected_systems", "Hour 4 / Connected Systems", "~4 h",
			"10 species, 20 reachable cards, 2 rods, 4 lures and Prepared Bait available.",
			"early", 10, 900, ["wooden_rod", "bamboo_rod"], ["straight", "tail", "crab", "baby_frog"], 3,
			[
				"Use fish for at least two competing purposes: money, bait or Card Maker.",
				"Test Harbor Request, Harbor Lockbox and Card Maker as optional goals.",
				"Check whether the next tackle upgrade feels worth pursuing.",
			]
		),
		_preset(
			"specialization", "Hour 12 / Specialization", "~12 h",
			"18 species, 35 reachable cards, 3 rods, 7 lures and Prepared Bait stock.",
			"specialization", 18, 2500, ["wooden_rod", "bamboo_rod", "deluxe_rod"], ["straight", "tail", "crab", "baby_frog", "toad", "popper", "flattop"], 6,
			[
				"Choose a fishing-heavy, card-heavy or mixed goal and see if all feel valid.",
				"Test deeper salvage and Rank-2 opponent progression.",
				"Check that the game presents several goals instead of one mandatory route.",
			]
		),
	]


func apply_preset(preset_id: StringName) -> Dictionary:
	if _services == null:
		return {"success": false, "reason": "session_services_unavailable"}
	var preset: Dictionary = _find_preset(preset_id)
	if preset.is_empty() or not bool(preset.get("applyable", false)):
		return {"success": false, "reason": "preset_not_applyable"}

	_reset_fishing_state()
	_seed_fishing_state(preset)

	# Apply card state last. Synthetic catch commits can legitimately wake the
	# live starter-case bridge; the authored TT QA scenario is the final durable
	# source of truth immediately before the scene reload.
	var tt_result: Dictionary = _tt_harness.apply_scenario(
		StringName(str(preset.get("tt_scenario", "fresh"))),
		TripleTriadCardCatalogResource
	)
	if not bool(tt_result.get("success", false)):
		return tt_result

	if _services.has_method("save_all_fishing_state"):
		_services.call("save_all_fishing_state")

	return {
		"success": true,
		"preset_id": String(preset_id),
		"reload_required": true,
	}


func _preset(
	id: String,
	name: String,
	checkpoint: String,
	summary: String,
	tt_scenario: String,
	species_count: int,
	zenny: int,
	rod_ids: Array,
	lure_ids: Array,
	prepared_bait_count: int,
	checklist: Array
) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"checkpoint": checkpoint,
		"summary": summary,
		"tutorial": "QA preset for %s. Applying it replaces current fishing/economy/card progression and reloads the scene." % checkpoint,
		"tt_scenario": tt_scenario,
		"species_count": species_count,
		"zenny": zenny,
		"rod_ids": rod_ids.duplicate(),
		"lure_ids": lure_ids.duplicate(),
		"prepared_bait_count": prepared_bait_count,
		"checklist": checklist.duplicate(),
		"applyable": true,
		"destructive": true,
	}


func _find_preset(preset_id: StringName) -> Dictionary:
	for raw in get_presets():
		if raw is Dictionary and str(raw.get("id", "")) == String(preset_id):
			return (raw as Dictionary).duplicate(true)
	return {}


func _reset_fishing_state() -> void:
	if _services.progress != null:
		_services.progress.reset_all_progress(true)
	if _services.inventory != null:
		_services.inventory.reset_inventory(true)
	if _services.unlock_state != null:
		_services.unlock_state.reset_unlocks(true)
	if _services.reward_service != null:
		_services.reward_service.reset_rewards(true)
	if _services.session_modifier_service != null:
		if _services.session_modifier_service.has_method("reset_persistent_state"):
			_services.session_modifier_service.reset_persistent_state(true)
		elif _services.session_modifier_service.has_method("clear_all"):
			_services.session_modifier_service.clear_all()
	if _services.player_item_inventory != null:
		_services.player_item_inventory.reset_all(true, true)
	if _services.beach_gathering_inventory != null:
		_services.beach_gathering_inventory.reset_all(true)
	for path in TRANSIENT_PATHS:
		_delete_user_path(path)


func _seed_fishing_state(preset: Dictionary) -> void:
	var inventory = _services.inventory
	var progress = _services.progress
	if inventory == null or progress == null:
		return

	for raw_rod in preset.get("rod_ids", []):
		var rod_id := StringName(str(raw_rod))
		if not inventory.owns_rod(rod_id):
			inventory.grant_rod(rod_id, 1, false)
	for raw_lure in preset.get("lure_ids", []):
		var lure_id := StringName(str(raw_lure))
		if not inventory.owns_lure(lure_id):
			inventory.grant_lure(lure_id, 1, false)

	var species_count: int = clampi(
		int(preset.get("species_count", 0)),
		0,
		SPECIES_SEQUENCE.size()
	)
	for index in range(species_count):
		var species_id := StringName(SPECIES_SEQUENCE[index])
		var fish: FishData = FishingContentCatalogResource.get_fish_by_id(species_id)
		if fish == null:
			continue
		progress.record_catch_snapshot(
			{
				"transaction_id": "qa_campaign_%s_%02d" % [str(preset.get("id", "preset")), index],
				"species_id": fish.get_stable_species_id(),
				"fish_name": fish.fish_name,
				"size": maxf(fish.average_size, 0.1),
				"points": 0,
				"max_points": fish.max_points,
				"is_king": false,
				"size_band": "normal",
				"score_tier": 1,
				"size_ratio_to_king": 0.5,
				"catch_context": {
					"spot_id": "ocean_2",
					"spot_name": "Ocean 2",
					"lure_id": "straight",
					"lure_name": "Straight",
				},
			},
			true,
			true
		)

	_seed_prepared_bait(maxi(0, int(preset.get("prepared_bait_count", 0))))
	inventory.set_zenny(maxi(0, int(preset.get("zenny", 0))), true)
	inventory.commit_changes()


func _seed_prepared_bait(amount: int) -> void:
	if amount <= 0:
		return
	if _services.item_catalog == null or _services.player_item_inventory == null:
		return
	var definition = _services.item_catalog.get_by_domain(&"player", &"prepared_bait")
	if definition == null:
		return
	_services.player_item_inventory.grant(definition.item_id, amount, true)


func _delete_user_path(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
