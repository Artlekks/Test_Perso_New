extends Resource
class_name TripleTriadOpponentProfile

@export_category("Identity")
@export var opponent_id: StringName = &"opponent"
@export var display_name: String = "Card Player"
## Difficulty/content rank for this opponent. Separate from the player's Duel Rank.
@export_range(1, 10, 1) var duel_rank: int = 1
## Minimum player Duel Rank required for registry availability queries.
@export_range(1, 10, 1) var required_player_rank: int = 1
@export var enabled_by_default: bool = true
@export var encounter_tags: PackedStringArray = PackedStringArray()

@export_category("Behavior")
@export var ai_profile: Resource
@export var region_profile: Resource
@export var rule_set_override: Resource

@export_category("Cards")
@export_range(1, 10, 1) var min_card_level: int = 1
@export_range(1, 10, 1) var max_card_level: int = 3
## 0 means: use the active region's deck budget.
@export_range(0, 50, 1) var deck_budget_override: int = 0
## Authored permanent starting collection. Empty keeps deterministic prototype seeding.
@export var native_card_ids: PackedStringArray = PackedStringArray()
## Up to five preferred cards. They are tried before the rest of the owned collection.
@export var preferred_deck_ids: PackedStringArray = PackedStringArray()
@export_range(5, 100, 1) var initial_collection_size: int = 15

@export_category("Progression")
## Duel progression awarded when the player defeats this opponent.
@export_range(0, 100, 1) var progression_points_on_win: int = 3


func validate_profile(card_catalog: Resource = null) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()

	if String(opponent_id).strip_edges().is_empty():
		errors.append("opponent_id is empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is empty")
	if duel_rank < 1:
		errors.append("duel_rank must be at least 1")
	if required_player_rank < 1:
		errors.append("required_player_rank must be at least 1")
	if min_card_level < 1 or max_card_level < min_card_level:
		errors.append("card level range is invalid")
	if initial_collection_size < 5:
		errors.append("initial_collection_size must be at least 5")
	if preferred_deck_ids.size() > 5:
		errors.append("preferred_deck_ids cannot contain more than 5 cards")

	if region_profile != null and region_profile.has_method("validate_profile"):
		var region_audit: Dictionary = region_profile.call("validate_profile")
		for error_text in region_audit.get("errors", []):
			errors.append("region_profile: %s" % str(error_text))
	if rule_set_override != null and rule_set_override.has_method("validate_runtime_support"):
		var rule_audit: Dictionary = rule_set_override.call("validate_runtime_support")
		for error_text in rule_audit.get("errors", []):
			errors.append("rule_set_override: %s" % str(error_text))

	var native_seen: Dictionary = {}
	for raw_id in native_card_ids:
		var card_id: String = str(raw_id).strip_edges()
		if card_id.is_empty():
			errors.append("native_card_ids contains an empty id")
			continue
		if native_seen.has(card_id):
			errors.append("duplicate native card id: %s" % card_id)
			continue
		native_seen[card_id] = true
		if card_catalog != null and card_catalog.has_method("get_card_by_id"):
			if card_catalog.call("get_card_by_id", StringName(card_id)) == null:
				errors.append("unknown native card id: %s" % card_id)

	var preferred_seen: Dictionary = {}
	for raw_id in preferred_deck_ids:
		var card_id: String = str(raw_id).strip_edges()
		if card_id.is_empty():
			errors.append("preferred_deck_ids contains an empty id")
			continue
		if preferred_seen.has(card_id):
			errors.append("duplicate preferred card id: %s" % card_id)
			continue
		preferred_seen[card_id] = true
		if card_catalog != null and card_catalog.has_method("get_card_by_id"):
			if card_catalog.call("get_card_by_id", StringName(card_id)) == null:
				errors.append("unknown preferred card id: %s" % card_id)
		if not native_card_ids.is_empty() and not native_seen.has(card_id):
			errors.append(
				"preferred card '%s' is not in this opponent's native collection"
				% card_id
			)

	if deck_budget_override > 0 and deck_budget_override < 5:
		errors.append("deck_budget_override is below a legal five-card budget")

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}


func get_region_id() -> StringName:
	if region_profile == null:
		return &""
	var raw_id = region_profile.get("region_id")
	if raw_id == null:
		return &""
	return StringName(str(raw_id))


func has_tag(tag: StringName) -> bool:
	var wanted: String = String(tag).strip_edges().to_lower()
	if wanted.is_empty():
		return false
	for raw_tag in encounter_tags:
		if str(raw_tag).strip_edges().to_lower() == wanted:
			return true
	return false
