extends Node
class_name TripleTriadFishingSalvageBridge

## Integration boundary between the fishing game's persistent catch transaction
## stream and Triple Triad's acquisition backend.
##
## V1 onboarding behavior:
## - A fresh card-game save begins locked and owns no cards.
## - The first committed catch at an eligible sea spot discovers the Saltworn
##   Card Case.
## - Triple Triad remains the sole authority for what the case contains,
##   one-shot persistence, card ownership, and the unlock flag.
##
## A future physical salvage/object encounter can call
## TripleTriadGame.claim_salvaged_card_case() directly and disable the temporary
## first-catch discovery rule without changing either backend.

signal repository_bound
signal starter_case_discovered(result: Dictionary)

const STARTER_BUNDLE_ID: StringName = &"salvaged_card_case"

var _triple_triad_game: Node = null
var _catch_repository: Node = null
var _last_result: Dictionary = {}
var _eligible_spot_ids: PackedStringArray = PackedStringArray(["ocean_2"])
var _auto_discovery_enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func configure(
	triple_triad_game: Node,
	eligible_spot_ids: PackedStringArray,
	auto_discovery_enabled: bool = true
) -> void:
	_triple_triad_game = triple_triad_game
	_eligible_spot_ids = eligible_spot_ids.duplicate()
	_auto_discovery_enabled = auto_discovery_enabled
	set_process(true)
	_try_bind_repository()


func _process(_delta: float) -> void:
	if is_instance_valid(_catch_repository):
		set_process(false)
		return
	_try_bind_repository()


func is_bound() -> bool:
	return is_instance_valid(_catch_repository)


func get_debug_snapshot() -> Dictionary:
	return {
		"bound": is_bound(),
		"auto_discovery_enabled": _auto_discovery_enabled,
		"eligible_spot_ids": _eligible_spot_ids.duplicate(),
		"last_result": _last_result.duplicate(true),
	}


func resolve_salvage_object(
	source_context: StringName = &"fishing_salvage"
) -> Dictionary:
	## Stable entry point for the later physical salvage-object implementation.
	## The temporary first-catch rule below calls the same Triple Triad API.
	if not is_instance_valid(_triple_triad_game):
		return {
			"success": false,
			"reason": "triple_triad_game_unavailable",
			"bundle_id": String(STARTER_BUNDLE_ID),
		}

	if not _triple_triad_game.has_method("claim_salvaged_card_case"):
		return {
			"success": false,
			"reason": "salvage_api_unavailable",
			"bundle_id": String(STARTER_BUNDLE_ID),
		}

	var raw_result = _triple_triad_game.call(
		"claim_salvaged_card_case",
		source_context
	)
	if not (raw_result is Dictionary):
		return {
			"success": false,
			"reason": "invalid_salvage_result",
			"bundle_id": String(STARTER_BUNDLE_ID),
		}

	var result: Dictionary = (raw_result as Dictionary).duplicate(true)
	_last_result = result.duplicate(true)
	if bool(result.get("success", false)):
		starter_case_discovered.emit(result.duplicate(true))
	return result


func _try_bind_repository() -> void:
	if is_instance_valid(_catch_repository):
		set_process(false)
		return

	var repository: Node = _find_catch_repository()
	if repository == null or not repository.has_signal("catch_committed"):
		return

	var callback := Callable(self, "_on_catch_committed")
	if not repository.is_connected("catch_committed", callback):
		repository.connect("catch_committed", callback)

	_catch_repository = repository
	set_process(false)
	repository_bound.emit()


func _find_catch_repository() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	# FishingSessionServices is deliberately SceneTree-root persistent, so this
	# is the preferred path once the fishing backend has initialized.
	var services_repository := tree.root.get_node_or_null(
		"FishingSessionServices/FishingCatchRepository"
	)
	if services_repository is Node:
		return services_repository as Node

	# During scene startup the root service may still be awaiting deferred
	# attachment. The live Fishing controller already owns the same repository
	# reference, so use it as a startup-safe fallback.
	var scene: Node = tree.current_scene
	if scene == null:
		return null
	var fishing_controller: Node = scene.find_child("Fishing", true, false)
	if (
		fishing_controller != null
		and fishing_controller.has_method("get_fishing_catch_repository")
	):
		var raw_repository = fishing_controller.call(
			"get_fishing_catch_repository"
		)
		if raw_repository is Node:
			return raw_repository as Node

	return null


func _on_catch_committed(result: Dictionary) -> void:
	if not _auto_discovery_enabled:
		return
	if not bool(result.get("committed", false)):
		return
	if not is_instance_valid(_triple_triad_game):
		return
	if not _triple_triad_game.has_method("get_acquisition_snapshot"):
		return

	var acquisition: Dictionary = _triple_triad_game.call(
		"get_acquisition_snapshot"
	)
	if bool(acquisition.get("card_game_unlocked", false)):
		return
	if _bundle_is_claimed(acquisition):
		return

	var catch_context: Dictionary = {}
	var raw_context = result.get("catch_context", {})
	if raw_context is Dictionary:
		catch_context = (raw_context as Dictionary).duplicate(true)

	var spot_id: String = str(
		catch_context.get("spot_id", "")
	).strip_edges()
	if not _is_eligible_spot(spot_id):
		return

	var source_context := StringName(
		"fishing_salvage:%s" % spot_id
	)
	var claim_result: Dictionary = resolve_salvage_object(
		source_context
	)

	if bool(claim_result.get("success", false)):
		print(
			"TripleTriad Onboarding: recovered %s at %s; %d cards granted and card duels unlocked."
			% [
				str(claim_result.get("display_name", "Saltworn Card Case")),
				spot_id,
				int(claim_result.get("granted_cards", 0)),
			]
		)


func _is_eligible_spot(spot_id: String) -> bool:
	if spot_id.is_empty():
		return false
	if _eligible_spot_ids.is_empty():
		return true
	return _eligible_spot_ids.has(spot_id)


func _bundle_is_claimed(acquisition: Dictionary) -> bool:
	var raw_ids = acquisition.get(
		"claimed_bundle_ids",
		PackedStringArray()
	)
	if raw_ids is PackedStringArray or raw_ids is Array:
		for raw_id in raw_ids:
			if str(raw_id) == String(STARTER_BUNDLE_ID):
				return true
	return false
