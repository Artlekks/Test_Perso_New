extends RefCounted
class_name TripleTriadMatchContextController

const OpponentEvolutionScript = preload(
	"res://scripts/triple_triad/triple_triad_opponent_evolution.gd"
)

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

var active_opponent_profile: Resource = null
var active_region_profile: Resource = null
var active_ai_profile: Resource = null
var active_rule_set: Resource = null
var active_deck_budget: int = 30
var active_min_level: int = 1
var active_max_level: int = 3
var active_opponent_evolution: Dictionary = {}

var qa_profile_override: Resource = null
var qa_forced_starting_owner: int = OWNER_NONE
var qa_hand_seed: int = 0
var qa_base_summary: Dictionary = {}

var _card_catalog = null
var _rng: RandomNumberGenerator = null
var _encounter_records = null
var _opponent_evolution = OpponentEvolutionScript.new()
var _default_region_profile: Resource = null
var _default_ai_profile: Resource = null
var _default_rule_set: Resource = null
var _default_deck_budget: int = 30
var _default_min_level: int = 1
var _default_max_level: int = 3


func initialize(
	card_catalog,
	rng: RandomNumberGenerator,
	encounter_records,
	defaults: Dictionary
) -> void:
	_card_catalog = card_catalog
	_rng = rng
	_encounter_records = encounter_records
	_default_region_profile = defaults.get("region_profile")
	_default_ai_profile = defaults.get("ai_profile")
	_default_rule_set = defaults.get("rule_set")
	_default_deck_budget = maxi(5, int(defaults.get("deck_budget", 30)))
	_default_min_level = clampi(int(defaults.get("min_level", 1)), 1, 10)
	_default_max_level = clampi(
		int(defaults.get("max_level", 3)),
		_default_min_level,
		10
	)
	reset_active_context()


func reset_active_context() -> void:
	active_opponent_profile = null
	active_region_profile = _default_region_profile
	active_ai_profile = _default_ai_profile
	active_rule_set = _default_rule_set
	active_deck_budget = _default_deck_budget
	active_min_level = _default_min_level
	active_max_level = _default_max_level
	active_opponent_evolution = {}
	qa_forced_starting_owner = OWNER_NONE
	qa_hand_seed = 0
	qa_base_summary = {}


func resolve(opponent_profile_override: Resource) -> Dictionary:
	active_opponent_profile = opponent_profile_override
	active_region_profile = _default_region_profile
	active_ai_profile = _default_ai_profile
	active_rule_set = _default_rule_set
	active_deck_budget = _default_deck_budget
	active_min_level = _default_min_level
	active_max_level = _default_max_level

	_apply_opponent_defaults()
	_apply_region_defaults()
	_apply_opponent_overrides()
	_apply_opponent_evolution()

	# The debug menu's CURRENT/NPC column intentionally captures the fully evolved
	# gameplay context before a temporary QA profile is layered on top.
	qa_base_summary = configuration_summary()
	_apply_qa_profile_override()
	return context_snapshot()


func set_qa_profile(profile: Resource) -> Dictionary:
	qa_profile_override = profile
	if qa_profile_override == null and _rng != null:
		_rng.randomize()
	return resolve(active_opponent_profile)


func has_qa_override() -> bool:
	return qa_profile_override != null


func active_opponent_id() -> StringName:
	if active_opponent_profile != null:
		var raw_id = active_opponent_profile.get("opponent_id")
		if raw_id != null and not str(raw_id).is_empty():
			return StringName(str(raw_id))
	return &"default_opponent"


func active_opponent_display_name() -> String:
	return _resource_display_name(active_opponent_profile, "Default Opponent")


func get_active_evolution_snapshot() -> Dictionary:
	return active_opponent_evolution.duplicate(true)


func build_opponent_evolution_snapshot(profile: Resource) -> Dictionary:
	if profile == null:
		return {}
	var encounter_snapshot: Dictionary = {}
	if _encounter_records != null:
		var raw_id = profile.get("opponent_id")
		if raw_id != null and not str(raw_id).is_empty():
			encounter_snapshot = _encounter_records.get_snapshot(
				StringName(str(raw_id))
			)
	return _opponent_evolution.build_snapshot(profile, encounter_snapshot)


func build_budgeted_hand() -> Array:
	if _card_catalog == null or _rng == null:
		return []
	if _card_catalog.has_method("build_budgeted_hand"):
		return _card_catalog.build_budgeted_hand(
			_rng,
			active_min_level,
			active_max_level,
			5,
			active_deck_budget
		)
	if _card_catalog.has_method("build_random_hand"):
		return _card_catalog.build_random_hand(
			_rng,
			active_min_level,
			active_max_level,
			5
		)
	return []


func region_trait_text() -> String:
	if active_region_profile == null:
		return ""
	var description = active_region_profile.get("board_trait_description")
	if description == null:
		return ""
	return str(description)


func configuration_summary() -> Dictionary:
	return {
		"opponent_id": String(active_opponent_id()),
		"opponent": active_opponent_display_name(),
		"opponent_rank": (
			int(active_opponent_profile.get("duel_rank"))
			if active_opponent_profile != null
			else 1
		),
		"region": _resource_display_name(active_region_profile, "Default"),
		"ai": _resource_display_name(active_ai_profile, "Default"),
		"budget": active_deck_budget,
		"min_level": active_min_level,
		"max_level": active_max_level,
		"rules": rules_summary(active_rule_set, active_region_profile),
		"rematch_stage": int(active_opponent_evolution.get("stage", 0)),
		"rematch_stage_label": str(
			active_opponent_evolution.get("stage_label", "Baseline")
		),
		"rematch_evolution": active_opponent_evolution.duplicate(true),
	}


func context_snapshot() -> Dictionary:
	return {
		"opponent_id": String(active_opponent_id()),
		"deck_budget": active_deck_budget,
		"min_level": active_min_level,
		"max_level": active_max_level,
		"qa_active": has_qa_override(),
		"qa_forced_starting_owner": qa_forced_starting_owner,
		"qa_hand_seed": qa_hand_seed,
		"evolution": active_opponent_evolution.duplicate(true),
	}


func rules_summary(active_rules: Resource, active_region: Resource) -> String:
	var labels: PackedStringArray = PackedStringArray()
	if active_rules != null:
		if bool(active_rules.get("same_rule")):
			labels.append("Same")
		if bool(active_rules.get("plus_rule")):
			labels.append("Plus")
		if bool(active_rules.get("combo_rule")):
			labels.append("Combo")
		if bool(active_rules.get("influence_rule")):
			labels.append("Influence")
	if active_region != null and bool(active_region.get("allow_rotate")):
		labels.append("Rotate x1")
	if labels.is_empty():
		return "Normal capture"
	return " + ".join(labels)


func _apply_opponent_defaults() -> void:
	if active_opponent_profile == null:
		return
	var profile_region = active_opponent_profile.get("region_profile")
	if profile_region != null:
		active_region_profile = profile_region
	var profile_ai = active_opponent_profile.get("ai_profile")
	if profile_ai != null:
		active_ai_profile = profile_ai
	var min_level_value = active_opponent_profile.get("min_card_level")
	var max_level_value = active_opponent_profile.get("max_card_level")
	if min_level_value != null:
		active_min_level = clampi(int(min_level_value), 1, 10)
	if max_level_value != null:
		active_max_level = clampi(int(max_level_value), active_min_level, 10)


func _apply_region_defaults() -> void:
	if active_region_profile == null:
		return
	var region_rules = active_region_profile.get("rule_set")
	if region_rules != null:
		active_rule_set = region_rules
	var region_budget = active_region_profile.get("deck_budget")
	if region_budget != null:
		active_deck_budget = maxi(5, int(region_budget))


func _apply_opponent_overrides() -> void:
	if active_opponent_profile == null:
		return
	var profile_rules = active_opponent_profile.get("rule_set_override")
	if profile_rules != null:
		active_rule_set = profile_rules
	var budget_override = active_opponent_profile.get("deck_budget_override")
	if budget_override != null and int(budget_override) > 0:
		active_deck_budget = int(budget_override)


func _apply_opponent_evolution() -> void:
	active_opponent_evolution = {}
	if qa_profile_override != null or active_opponent_profile == null:
		return
	active_opponent_evolution = build_opponent_evolution_snapshot(
		active_opponent_profile
	)
	active_deck_budget += maxi(
		0,
		int(active_opponent_evolution.get("budget_bonus", 0))
	)
	active_ai_profile = _opponent_evolution.build_adapted_ai(
		active_ai_profile,
		active_opponent_evolution
	)


func _apply_qa_profile_override() -> void:
	qa_forced_starting_owner = OWNER_NONE
	qa_hand_seed = 0
	if qa_profile_override == null:
		return

	# QA profiles are controlled experiments. They intentionally bypass persistent
	# rematch evolution so a selected debug profile remains reproducible.
	active_opponent_evolution = {}

	var qa_region: Resource = qa_profile_override.get("region_profile")
	if qa_region != null:
		active_region_profile = qa_region
		var region_rules = qa_region.get("rule_set")
		if region_rules != null:
			active_rule_set = region_rules
		var region_budget = qa_region.get("deck_budget")
		if region_budget != null:
			active_deck_budget = maxi(5, int(region_budget))

	var qa_ai: Resource = qa_profile_override.get("ai_profile")
	if qa_ai != null:
		active_ai_profile = qa_ai

	var qa_rules: Resource = qa_profile_override.get("rule_set_override")
	if qa_rules != null:
		active_rule_set = qa_rules

	var qa_budget: int = int(qa_profile_override.get("deck_budget_override"))
	if qa_budget > 0:
		active_deck_budget = qa_budget

	active_min_level = clampi(
		int(qa_profile_override.get("min_card_level")),
		1,
		10
	)
	active_max_level = clampi(
		int(qa_profile_override.get("max_card_level")),
		active_min_level,
		10
	)
	qa_forced_starting_owner = clampi(
		int(qa_profile_override.get("starting_owner")),
		OWNER_NONE,
		OWNER_OPPONENT
	)
	qa_hand_seed = maxi(0, int(qa_profile_override.get("hand_seed")))


func _resource_display_name(resource: Resource, fallback: String) -> String:
	if resource == null:
		return fallback
	var display_name = resource.get("display_name")
	if display_name != null and not str(display_name).is_empty():
		return str(display_name)
	return resource.resource_path.get_file().get_basename()
