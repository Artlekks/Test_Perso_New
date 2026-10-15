extends RefCounted

## QA-only process contract. The launcher sets the namespace before Godot loads autoloads.
const DEFAULT_PATHS := [
	"user://input_bindings.json",
	"user://game_clock_v1.json",
	"user://game_clock_v1.json.tmp",
	"user://game_clock_v1.json.bak",
	"user://fishing_progress.json",
	"user://fishing_inventory.json",
	"user://fishing_rewards.json",
	"user://fishing_loadout.json",
	"user://fishing_unlocks.json",
	"user://fishing_session_modifiers.json",
	"user://fishing_catch_pending.json",
	"user://fishing_catch_pending.tmp",
	"user://player_item_inventory.json",
	"user://beach_crafted_lures.json",
	"user://beach_gathering_inventory.json"
]

static func verify(extra_paths: Array = []) -> bool:
	var run_id := OS.get_environment("FISHING_QA_RUN_ID")
	var expected := OS.get_environment("FISHING_QA_USER_DIR").replace("\\", "/").trim_suffix("/")
	var sandbox := OS.get_environment("FISHING_QA_SANDBOX").replace("\\", "/").trim_suffix("/")
	var roaming := OS.get_environment("APPDATA").replace("\\", "/").trim_suffix("/")
	var local := OS.get_environment("LOCALAPPDATA").replace("\\", "/").trim_suffix("/")
	var actual := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	var os_dir := OS.get_user_data_dir().replace("\\", "/").trim_suffix("/")
	var name := str(ProjectSettings.get_setting("application/config/name", ""))
	var custom := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var enabled := bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	if run_id.is_empty() or expected.is_empty() or sandbox.is_empty():
		push_error("QA_ISOLATION_REJECT: missing launcher contract")
		return false
	if not enabled or name != run_id or custom != run_id:
		push_error("QA_ISOLATION_REJECT: project namespace mismatch")
		return false
	if not _inside(expected, sandbox) or not _inside(roaming, sandbox) or not _inside(local, sandbox):
		push_error("QA_ISOLATION_REJECT: environment outside sandbox")
		return false
	if actual != expected or os_dir != expected or not actual.begins_with(roaming + "/"):
		push_error("QA_ISOLATION_REJECT: user directory mismatch; actual=%s expected=%s" % [actual, expected])
		return false
	if not DirAccess.dir_exists_absolute(actual):
		push_error("QA_ISOLATION_REJECT: user directory missing")
		return false
	var paths: Array = DEFAULT_PATHS.duplicate()
	paths.append_array(extra_paths)
	var supplied := OS.get_environment("FISHING_QA_PERSISTENCE_PATHS")
	if not supplied.is_empty():
		paths.append_array(Array(supplied.split("|", false)))
	for path_value in paths:
		var path := str(path_value).replace("\\", "/")
		if path.is_empty() or path.contains("/../") or path.ends_with("/..") or path.contains("/./"):
			push_error("QA_ISOLATION_REJECT: invalid persistence path: %s" % path)
			return false
		var resolved := ProjectSettings.globalize_path(path).replace("\\", "/")
		if not _inside(resolved, actual):
			push_error("QA_ISOLATION_REJECT: persistence path outside user directory: %s -> %s" % [path, resolved])
			return false
		print("QA_SAVE_PATH: %s -> %s" % [path, resolved])
	print("QA_ISOLATION_PASS run_id=%s sandbox=%s APPDATA=%s LOCALAPPDATA=%s user=%s clock=%s" % [run_id, sandbox, roaming, local, actual, ProjectSettings.globalize_path("user://game_clock_v1.json")])
	return true

static func verify_root_clock(tree: SceneTree) -> bool:
	var clock := tree.root.get_node_or_null("GameClock")
	if clock == null:
		push_error("QA_ISOLATION_REJECT: root GameClock missing")
		return false
	var clock_path := str(clock.get("_save_path"))
	if not verify([clock_path, clock_path + ".tmp", clock_path + ".bak"]):
		return false
	print("QA_ROOT_CLOCK_PATH: %s -> %s" % [clock_path, ProjectSettings.globalize_path(clock_path)])
	return true

static func _inside(path: String, root: String) -> bool:
	return path.to_lower().begins_with(root.to_lower() + "/")

static func emit_result(suite: String, passed: int, total: int, failed: int, orphans: int) -> void:
	print("QA_SUITE_RESULT " + JSON.stringify({"suite": suite, "passed": passed,
		"total": total, "failed": failed, "orphans": orphans}))
