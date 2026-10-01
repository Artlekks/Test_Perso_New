extends Resource
class_name TripleTriadAcquisitionBundle

@export_category("Identity")
@export var bundle_id: StringName = &"bundle"
@export var display_name: String = "Card Bundle"
@export_multiline var description: String = ""
@export var source_type: StringName = &"world"

@export_category("Behavior")
@export var one_shot: bool = true
@export var unlocks_card_game: bool = false
## Compatibility bridge for saves created before the acquisition-state system.
## If the player already owns cards, this bundle is treated as previously claimed
## rather than duplicating its contents into the old save.
@export var migration_claim_if_collection_nonempty: bool = false

@export_category("Cards")
@export var card_ids: PackedStringArray = PackedStringArray()


func validate_bundle(card_catalog: Resource = null) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var clean_id: String = String(bundle_id).strip_edges()
	if clean_id.is_empty():
		errors.append("bundle_id is empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is empty")
	if String(source_type).strip_edges().is_empty():
		errors.append("source_type is empty")
	if card_ids.is_empty():
		errors.append("card_ids is empty")

	var seen: Dictionary = {}
	for raw_id in card_ids:
		var card_id: String = str(raw_id).strip_edges()
		if card_id.is_empty():
			errors.append("card_ids contains an empty id")
			continue
		if seen.has(card_id):
			errors.append("duplicate card id: %s" % card_id)
			continue
		seen[card_id] = true
		if card_catalog != null and card_catalog.has_method("get_card_by_id"):
			if card_catalog.call("get_card_by_id", StringName(card_id)) == null:
				errors.append("unknown card id: %s" % card_id)

	if unlocks_card_game and card_ids.size() < 5:
		warnings.append("unlock bundle contains fewer than five cards")

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}
