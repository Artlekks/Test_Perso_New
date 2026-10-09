extends Node
class_name TripleTriadFishingSalvageBridge
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

## Integration boundary between the fishing game's persistent catch transaction
## stream and Triple Triad's acquisition backend.
##
## Card-discovery onboarding behavior:
## - A fresh card-game save begins locked and owns no cards.
## - After 3-5 eligible coastal catches, a visible glint appears in the water.
## - The player must land a cast close to that glint and then complete the catch.
## - That successful salvage catch recovers the Saltworn Card Case.
## - Triple Triad remains the sole authority for bundle contents, one-shot
##   persistence, card ownership, and the unlock flag.

signal repository_bound
signal starter_sparkle_spawned(snapshot: Dictionary)
signal starter_salvage_armed
signal starter_case_discovered(result: Dictionary)
signal salvage_card_recovered(result: Dictionary)

const SalvageSparkleScript = preload(
	"res://scripts/triple_triad/triple_triad_salvage_sparkle.gd"
)

const STARTER_BUNDLE_ID: StringName = &"salvaged_card_case"
const STARTER_SEARCH_COUNTER_ID: StringName = &"fishing_salvage:starter_case_search"
const STARTER_SEARCH_MIN_CATCHES := 3
const STARTER_SEARCH_MAX_CATCHES := 5
const STARTER_SPARKLE_TRIGGER_RADIUS := 0.95
# Authored coastal water offsets, within the Wooden Rod cast envelope.
const STARTER_SPARKLE_OFFSETS: Array[Vector3] = [
	Vector3(-0.65, 0.08, -1.50),
	Vector3(0.15, 0.08, -1.70),
	Vector3(0.65, 0.08, -1.50),
]

const COAST_SALVAGE_SOURCE_ID: StringName = &"coast_shallows"
const COAST_ADVANCED_SALVAGE_SOURCE_ID: StringName = &"coast_deeper"
const COAST_SALVAGE_INTERVAL := 4

var _triple_triad_game: Node = null
var _catch_repository: Node = null
var _caster: Node = null
var _starter_sparkle: Node3D = null
var _last_result: Dictionary = {}
var _eligible_spot_ids: PackedStringArray = PackedStringArray(["ocean_2"])
var _auto_discovery_enabled: bool = true
var _starter_spawn_threshold: int = STARTER_SEARCH_MAX_CATCHES
var _starter_search_count: int = 0
var _starter_salvage_armed: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_starter_spawn_threshold = _rng.randi_range(
		STARTER_SEARCH_MIN_CATCHES,
		STARTER_SEARCH_MAX_CATCHES
	)
	set_process(true)


func configure(
	triple_triad_game: Node,
	eligible_spot_ids: PackedStringArray,
	auto_discovery_enabled: bool = true
) -> void:
	_triple_triad_game = triple_triad_game
	_eligible_spot_ids = eligible_spot_ids.duplicate()
	_auto_discovery_enabled = auto_discovery_enabled
	_starter_search_count = _read_world_counter(STARTER_SEARCH_COUNTER_ID)
	set_process(true)
	_try_bind_repository()
	_try_bind_caster()
	_refresh_starter_search_state()


func _process(_delta: float) -> void:
	_try_bind_repository()
	_try_bind_caster()
	_refresh_starter_search_state()
	if is_instance_valid(_catch_repository) and is_instance_valid(_caster):
		set_process(false)


func is_bound() -> bool:
	return is_instance_valid(_catch_repository)


func get_debug_snapshot() -> Dictionary:
	var sparkle_snapshot: Dictionary = {}
	if (
		is_instance_valid(_starter_sparkle)
		and _starter_sparkle.has_method("get_debug_snapshot")
	):
		var raw_snapshot = _starter_sparkle.call("get_debug_snapshot")
		if raw_snapshot is Dictionary:
			sparkle_snapshot = (raw_snapshot as Dictionary).duplicate(true)
	return {
		"bound": is_bound(),
		"caster_bound": is_instance_valid(_caster),
		"auto_discovery_enabled": _auto_discovery_enabled,
		"eligible_spot_ids": _eligible_spot_ids.duplicate(),
		"last_result": _last_result.duplicate(true),
		"starter_search_min_catches": STARTER_SEARCH_MIN_CATCHES,
		"starter_search_max_catches": STARTER_SEARCH_MAX_CATCHES,
		"starter_spawn_threshold": _starter_spawn_threshold,
		"starter_search_count": _starter_search_count,
		"starter_sparkle_active": is_instance_valid(_starter_sparkle),
		"starter_salvage_armed": _starter_salvage_armed,
		"starter_sparkle": sparkle_snapshot,
		"post_starter_salvage_interval": COAST_SALVAGE_INTERVAL,
		"coast_salvage_source_id": String(COAST_SALVAGE_SOURCE_ID),
		"coast_advanced_salvage_source_id": String(COAST_ADVANCED_SALVAGE_SOURCE_ID),
	}


func resolve_salvage_object(
	source_context: StringName = &"fishing_salvage"
) -> Dictionary:
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
		return

	var repository: Node = _find_catch_repository()
	if repository == null or not repository.has_signal("catch_committed"):
		return

	var callback := Callable(self, "_on_catch_committed")
	if not repository.is_connected("catch_committed", callback):
		repository.connect("catch_committed", callback)

	_catch_repository = repository
	repository_bound.emit()


func _try_bind_caster() -> void:
	if is_instance_valid(_caster):
		return
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return
	var candidate: Node = GameplaySceneRoot.resolve(tree).find_child("Caster", true, false)
	if candidate == null or not candidate.has_signal("bait_landed"):
		return
	var callback := Callable(self, "_on_bait_landed")
	if not candidate.is_connected("bait_landed", callback):
		candidate.connect("bait_landed", callback)
	_caster = candidate


func _find_catch_repository() -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	var services_repository := tree.root.get_node_or_null(
		"FishingSessionServices/FishingCatchRepository"
	)
	if services_repository is Node:
		return services_repository as Node

	var scene: Node = GameplaySceneRoot.resolve(tree)
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


func _on_bait_landed(point: Vector3) -> void:
	if not is_instance_valid(_starter_sparkle):
		_starter_salvage_armed = false
		return
	if not _starter_sparkle.has_method("is_cast_near"):
		_starter_salvage_armed = false
		return
	_starter_salvage_armed = bool(
		_starter_sparkle.call("is_cast_near", point)
	)
	if _starter_salvage_armed:
		starter_salvage_armed.emit()


func _on_catch_committed(result: Dictionary) -> void:
	if not bool(result.get("committed", false)):
		return
	if not is_instance_valid(_triple_triad_game):
		return
	if not _triple_triad_game.has_method("get_acquisition_snapshot"):
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

	var acquisition: Dictionary = _triple_triad_game.call(
		"get_acquisition_snapshot"
	)
	var unlocked: bool = bool(
		acquisition.get("card_game_unlocked", false)
	)

	if not unlocked:
		_handle_locked_onboarding_catch(spot_id, acquisition)
		return

	_remove_starter_sparkle()
	_starter_salvage_armed = false
	_try_post_starter_salvage(spot_id)


func _handle_locked_onboarding_catch(
	spot_id: String,
	acquisition: Dictionary
) -> void:
	if not _auto_discovery_enabled:
		return
	if _bundle_is_claimed(acquisition):
		_remove_starter_sparkle()
		return

	if _starter_salvage_armed:
		var starter_context := StringName(
			"fishing_salvage:%s:glint" % spot_id
		)
		var starter_result: Dictionary = resolve_salvage_object(
			starter_context
		)
		if bool(starter_result.get("success", false)):
			_remove_starter_sparkle()
			_starter_salvage_armed = false
			print(
				"TripleTriad Onboarding: recovered %s from the water glint at %s; %d cards granted and card duels unlocked."
				% [
					str(
						starter_result.get(
							"display_name",
							"Saltworn Card Case"
						)
					),
					spot_id,
					int(starter_result.get("granted_cards", 0)),
				]
			)
			# The bundle claim changes the authoritative unlock state immediately.
			# Stop here so this same catch cannot advance the locked-search counter
			# and accidentally respawn the onboarding sparkle from stale input.
			return
		else:
			_starter_salvage_armed = false
			_refresh_starter_search_state()
		return

	_starter_search_count = _advance_world_counter(
		STARTER_SEARCH_COUNTER_ID
	)
	if _starter_search_count >= _starter_spawn_threshold:
		_spawn_starter_sparkle()


func _refresh_starter_search_state() -> void:
	if not _auto_discovery_enabled or not is_instance_valid(_triple_triad_game):
		return
	if not _triple_triad_game.has_method("get_acquisition_snapshot"):
		return
	var raw_acquisition = _triple_triad_game.call("get_acquisition_snapshot")
	if not (raw_acquisition is Dictionary):
		return
	var acquisition: Dictionary = raw_acquisition as Dictionary
	if (
		bool(acquisition.get("card_game_unlocked", false))
		or _bundle_is_claimed(acquisition)
	):
		_remove_starter_sparkle()
		_starter_salvage_armed = false
		return
	_starter_search_count = maxi(
		_starter_search_count,
		_read_world_counter(STARTER_SEARCH_COUNTER_ID)
	)
	if _starter_search_count >= _starter_spawn_threshold:
		_spawn_starter_sparkle()


func _spawn_starter_sparkle() -> void:
	if is_instance_valid(_starter_sparkle):
		return
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return
	var scene: Node = GameplaySceneRoot.resolve(tree)
	var world_parent: Node = scene.find_child("World", true, false)
	var zone: Node = scene.find_child("FishZone_V2", true, false)
	if (
		world_parent == null
		or not (world_parent is Node3D)
		or zone == null
		or not (zone is Node3D)
	):
		return
	var anchor: Node3D = zone as Node3D
	var water_surface: Node = zone.get_node_or_null("WaterSurface")
	if water_surface is Node3D:
		anchor = water_surface as Node3D

	var offset_index: int = _rng.randi_range(0, STARTER_SPARKLE_OFFSETS.size() - 1)
	var sparkle = SalvageSparkleScript.new()
	sparkle.name = "StarterCardSalvageSparkle"
	(world_parent as Node3D).add_child(sparkle)
	if sparkle.has_method("configure"):
		sparkle.call(
			"configure",
			anchor.global_position + STARTER_SPARKLE_OFFSETS[offset_index],
			STARTER_SPARKLE_TRIGGER_RADIUS
		)
	_starter_sparkle = sparkle as Node3D
	starter_sparkle_spawned.emit(get_debug_snapshot())


func _remove_starter_sparkle() -> void:
	if not is_instance_valid(_starter_sparkle):
		_starter_sparkle = null
		return
	_starter_sparkle.queue_free()
	_starter_sparkle = null


func _try_post_starter_salvage(spot_id: String) -> void:
	if spot_id != "ocean_2":
		return
	if (
		not _triple_triad_game.has_method(
			"advance_world_reward_counter"
		)
		or not _triple_triad_game.has_method(
			"claim_fishing_salvage_reward"
		)
	):
		return

	var counter_id := StringName(
		"fishing_salvage:%s"
		% String(COAST_SALVAGE_SOURCE_ID)
	)
	var catch_count: int = _advance_world_counter(counter_id)
	if catch_count <= 0:
		return
	if catch_count % COAST_SALVAGE_INTERVAL != 0:
		return

	var context := StringName(
		"fishing_salvage:%s:catch_%d"
		% [spot_id, catch_count]
	)
	var reward_result: Dictionary = _claim_salvage_pool(
		COAST_SALVAGE_SOURCE_ID,
		context
	)
	if (
		not bool(reward_result.get("success", false))
		and str(reward_result.get("reason", "")) == "source_complete"
		and _current_duel_rank() >= 2
	):
		reward_result = _claim_salvage_pool(
			COAST_ADVANCED_SALVAGE_SOURCE_ID,
			context
		)

	_last_result = reward_result.duplicate(true)
	if bool(reward_result.get("success", false)):
		salvage_card_recovered.emit(reward_result.duplicate(true))
		print(
			"TripleTriad Salvage: recovered %s from %s."
			% [
				str(reward_result.get("display_name", "card")),
				spot_id,
			]
		)


func _advance_world_counter(counter_id: StringName) -> int:
	if (
		not is_instance_valid(_triple_triad_game)
		or not _triple_triad_game.has_method("advance_world_reward_counter")
	):
		return 0
	return int(
		_triple_triad_game.call(
			"advance_world_reward_counter",
			counter_id
		)
	)


func _read_world_counter(counter_id: StringName) -> int:
	if (
		not is_instance_valid(_triple_triad_game)
		or not _triple_triad_game.has_method("get_world_reward_delivery_snapshot")
	):
		return 0
	var raw_snapshot = _triple_triad_game.call(
		"get_world_reward_delivery_snapshot"
	)
	if not (raw_snapshot is Dictionary):
		return 0
	var raw_counters = (raw_snapshot as Dictionary).get("counters", {})
	if not (raw_counters is Dictionary):
		return 0
	return maxi(
		0,
		int((raw_counters as Dictionary).get(String(counter_id), 0))
	)


func _claim_salvage_pool(
	source_id: StringName,
	context: StringName
) -> Dictionary:
	var raw_result = _triple_triad_game.call(
		"claim_fishing_salvage_reward",
		source_id,
		context
	)
	if raw_result is Dictionary:
		return (raw_result as Dictionary).duplicate(true)
	return {"success": false, "reason": "invalid_salvage_result"}


func _current_duel_rank() -> int:
	if (
		is_instance_valid(_triple_triad_game)
		and _triple_triad_game.has_method("get_player_snapshot")
	):
		var raw_snapshot = _triple_triad_game.call("get_player_snapshot")
		if raw_snapshot is Dictionary:
			return maxi(1, int(raw_snapshot.get("duel_rank", 1)))
	return 1


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
