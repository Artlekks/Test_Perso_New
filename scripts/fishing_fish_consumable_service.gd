extends Node

const ModifierDefinitionScript = preload(
	"res://scripts/database/fishing_session_modifier_definition.gd"
)

var inventory = null
var effect_catalog = null
var modifier_service = null


func configure(new_inventory, new_effect_catalog, new_modifier_service) -> void:
	inventory = new_inventory
	effect_catalog = new_effect_catalog
	modifier_service = new_modifier_service


func get_effect_for_species(species_id: String) -> ModifierDefinitionScript:
	if effect_catalog == null:
		return null
	return effect_catalog.get_effect_for_species(species_id)


func get_effect_preview(species_id: String) -> Dictionary:
	var effect := get_effect_for_species(species_id)
	if effect == null:
		return {}
	return {
		"effect_id": str(effect.effect_id),
		"display_name": effect.display_name,
		"description": effect.description,
		"duration_seconds": effect.duration_seconds,
		"legacy_bof4_effect": effect.legacy_bof4_effect,
	}


func use_fish(
	species_id: String,
	specimen_id: int = -1,
	persist: bool = true
) -> Dictionary:
	var result := {
		"success": false,
		"species_id": species_id.strip_edges().to_lower(),
		"specimen_id": specimen_id,
		"effect_id": "",
		"remaining_count": 0,
	}

	if inventory == null or effect_catalog == null or modifier_service == null:
		result["reason"] = "service_not_ready"
		return result

	var effect := get_effect_for_species(species_id)
	if effect == null:
		result["reason"] = "no_fishing_effect"
		return result

	var specimen = null
	if specimen_id > 0:
		specimen = inventory.get_fish_specimen(species_id, specimen_id)
	else:
		specimen = inventory.get_smallest_owned_specimen(species_id)

	if specimen == null:
		result["reason"] = "fish_not_owned"
		return result

	result["specimen_id"] = specimen.specimen_id
	result["effect_id"] = str(effect.effect_id)

	var inventory_snapshot: Dictionary = inventory.create_transaction_snapshot()
	var modifier_snapshot: Dictionary = modifier_service.create_runtime_snapshot()

	if not inventory.remove_fish_specimen(species_id, specimen.specimen_id, false):
		result["reason"] = "fish_remove_failed"
		return result

	var apply_result: Dictionary = modifier_service.apply_modifier(
		effect,
		&"fish_consumable",
		str(species_id).strip_edges().to_lower()
	)
	if not bool(apply_result.get("success", false)):
		inventory.restore_transaction_snapshot(inventory_snapshot)
		modifier_service.restore_runtime_snapshot(modifier_snapshot)
		result["reason"] = "effect_apply_failed"
		return result

	if persist and not inventory.commit_changes():
		inventory.restore_transaction_snapshot(inventory_snapshot)
		modifier_service.restore_runtime_snapshot(modifier_snapshot)
		result["reason"] = "inventory_save_failed"
		return result

	result["success"] = true
	result["effect"] = apply_result
	result["remaining_count"] = inventory.get_fish_count(species_id)
	return result
