extends SceneTree

const Faults = preload("res://scripts/qa/fishing_catch_repository_fault_qa.gd")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const Catalog = preload("res://data/bof4/catalogs/all_content.tres")
const BASE := "user://fishing_catch_repository_fault_qa/process_restart"
const ID := "qa-process-restart-1"

func _initialize() -> void:
	if not Isolation.verify([BASE]):
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	for frame in range(2):
		await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var file := FileAccess.open(BASE + "/stage.txt", FileAccess.READ)
	if file == null:
		quit(1)
		return
	var stage: String = file.get_as_text().strip_edges()
	file.close()
	var blocked: bool = stage == "commit" or stage == "blocked"
	var state: Dictionary = Faults._open(BASE, false, blocked)
	var species = Catalog.fish[0]
	var species_id: String = species.get_stable_species_id()
	var passed: bool = false
	if stage == "commit":
		var result: Dictionary = state.repo.commit_snapshot(Faults._snapshot(species, ID))
		passed = bool(result.get("committed", false)) and not bool(result.get("durable", true)) and state.repo.has_pending_transaction()
	elif stage == "blocked":
		var retry: Dictionary = state.repo.recover_pending_transaction()
		passed = not bool(retry.get("recovered", false)) and state.repo.has_pending_transaction() and state.repo.get_pending_debug_snapshot().get("transaction_id", "") == ID
	elif stage == "repair" or stage == "verify":
		passed = not state.repo.has_pending_transaction() and state.progress.has_catch_transaction(ID) and state.inventory.has_catch_transaction(ID) and state.progress.get_total_catches() == 1 and state.inventory.get_fish_count(species_id) == 1
	Faults._close(state)
	print("QA_CHILD_RESULT stage=%s pass=%s" % [stage, str(passed)])
	quit(0 if passed else 1)
