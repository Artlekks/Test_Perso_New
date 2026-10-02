extends RefCounted
class_name TripleTriadBackendBootstrap

const CollectionScript = preload("res://scripts/triple_triad/triple_triad_collection.gd")
const CardEconomyScript = preload("res://scripts/triple_triad/triple_triad_card_economy.gd")
const ProgressionScript = preload("res://scripts/triple_triad/triple_triad_progression.gd")
const SaveIntegrityScript = preload("res://scripts/triple_triad/triple_triad_save_integrity.gd")
const AcquisitionTrackerScript = preload("res://scripts/triple_triad/triple_triad_acquisition_tracker.gd")
const AcquisitionServiceScript = preload("res://scripts/triple_triad/triple_triad_acquisition_service.gd")
const EncounterRecordsScript = preload("res://scripts/triple_triad/triple_triad_encounter_records.gd")
const StateAPIScript = preload("res://scripts/triple_triad/triple_triad_state_api.gd")
const WorldAcquisitionCatalogScript = preload("res://scripts/triple_triad/triple_triad_world_acquisition_catalog.gd")
const WorldRewardLedgerScript = preload("res://scripts/triple_triad/triple_triad_world_reward_ledger.gd")
const CompetitionCatalogScript = preload("res://scripts/triple_triad/triple_triad_competition_catalog.gd")
const CompetitionServiceScript = preload("res://scripts/triple_triad/triple_triad_competition_service.gd")
const CompletionTrackerScript = preload("res://scripts/triple_triad/triple_triad_completion_tracker.gd")
const WorldProgressionDirectorScript = preload("res://scripts/triple_triad/triple_triad_world_progression_director.gd")
const BackendValidatorScript = preload("res://scripts/triple_triad/triple_triad_backend_validator.gd")


func bootstrap(config: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var services: Dictionary = {}

	var card_catalog = config.get("card_catalog")
	var opponent_registry = config.get("opponent_registry")
	var acquisition_policy = config.get("acquisition_policy")
	var acquisition_registry = config.get("acquisition_registry")
	var region_profile = config.get("region_profile")
	var rule_set = config.get("rule_set")
	var player_deck_budget: int = int(config.get("player_deck_budget", 30))

	var world_acquisition_catalog = WorldAcquisitionCatalogScript.new()
	world_acquisition_catalog.initialize(
		card_catalog,
		opponent_registry,
		acquisition_registry
	)
	services["world_acquisition_catalog"] = world_acquisition_catalog

	var competition_catalog = CompetitionCatalogScript.new()
	competition_catalog.initialize(
		opponent_registry,
		world_acquisition_catalog
	)
	services["competition_catalog"] = competition_catalog

	var validator = BackendValidatorScript.new()
	var validation: Dictionary = validator.validate({
		"card_catalog": card_catalog,
		"region_profile": region_profile,
		"rule_set": rule_set,
		"opponent_registry": opponent_registry,
		"acquisition_policy": acquisition_policy,
		"acquisition_registry": acquisition_registry,
		"competition_catalog": competition_catalog,
		"world_acquisition_catalog": world_acquisition_catalog,
		"player_deck_budget": player_deck_budget,
	})
	for warning in validation.get("warnings", []):
		warnings.append(str(warning))
	for error_text in validation.get("errors", []):
		errors.append(str(error_text))
	if not bool(validation.get("valid", false)):
		return _result(false, services, errors, warnings, {})

	var save_integrity = SaveIntegrityScript.new()
	services["save_integrity"] = save_integrity
	var preflight_report: Dictionary = save_integrity.preflight_restore_backups()
	if not bool(preflight_report.get("valid", true)):
		errors.append(
			"One or more Triple Triad saves are corrupt and have no valid backup: %s"
			% str(preflight_report.get("failed", []))
		)
		return _result(false, services, errors, warnings, preflight_report)

	var collection_backend = CollectionScript.new()
	collection_backend.initialize(card_catalog, acquisition_policy)
	services["collection_backend"] = collection_backend

	var acquisition_tracker = AcquisitionTrackerScript.new()
	acquisition_tracker.initialize(card_catalog)
	services["acquisition_tracker"] = acquisition_tracker

	var acquisition_service = AcquisitionServiceScript.new()
	acquisition_service.initialize(
		card_catalog,
		collection_backend,
		acquisition_tracker,
		acquisition_registry
	)
	services["acquisition_service"] = acquisition_service

	var progression = ProgressionScript.new()
	progression.initialize()
	services["progression"] = progression

	var world_reward_ledger = WorldRewardLedgerScript.new()
	world_reward_ledger.initialize()
	services["world_reward_ledger"] = world_reward_ledger

	var encounter_records = EncounterRecordsScript.new()
	encounter_records.initialize()
	services["encounter_records"] = encounter_records

	var competition_service = CompetitionServiceScript.new()
	competition_service.initialize(competition_catalog)
	services["competition_service"] = competition_service

	var completion_tracker = CompletionTrackerScript.new()
	completion_tracker.initialize(
		card_catalog,
		collection_backend,
		world_acquisition_catalog,
		encounter_records,
		progression,
		competition_service,
		opponent_registry
	)
	services["completion_tracker"] = completion_tracker

	var world_progression_director = WorldProgressionDirectorScript.new()
	services["world_progression_director"] = world_progression_director

	var card_economy = CardEconomyScript.new()
	services["card_economy"] = card_economy
	var recovery_ok: bool = card_economy.recover_pending(
		card_catalog,
		collection_backend
	)
	if (
		not recovery_ok
		and card_economy.has_method("has_pending_transfer")
		and bool(card_economy.call("has_pending_transfer"))
	):
		errors.append("A card-transfer recovery is still pending.")
		return _result(false, services, errors, warnings, preflight_report)

	var state_api = StateAPIScript.new()
	state_api.initialize(
		card_catalog,
		collection_backend,
		progression,
		opponent_registry,
		encounter_records,
		acquisition_tracker,
		acquisition_service,
		acquisition_policy,
		world_acquisition_catalog,
		player_deck_budget
	)
	services["state_api"] = state_api

	return _result(true, services, errors, warnings, preflight_report)


func _result(
	success: bool,
	services: Dictionary,
	errors: PackedStringArray,
	warnings: PackedStringArray,
	preflight_report: Dictionary
) -> Dictionary:
	return {
		"success": success,
		"services": services,
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
		"preflight_report": preflight_report.duplicate(true),
	}
