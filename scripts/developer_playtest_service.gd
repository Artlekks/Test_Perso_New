extends Node
class_name DeveloperPlaytestService
## Transient access policy. Never writes progression or inventory on toggle.
signal mode_changed(enabled: bool)
const ACCESS_KEYS := [&"travel", &"cards", &"economy", &"mastery", &"world_interactions"]
var enabled := false
var indicator: Label
var _isolated_mobile_save_authorized := false

func authorize_isolated_mobile_save(isolated: bool) -> void:
	# Only the dedicated harness opts into its existing separate save namespace.
	_isolated_mobile_save_authorized = isolated

static func current() -> DeveloperPlaytestService:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("FishingSessionServices/DeveloperPlaytestService") if tree != null else null

static func allows(key: StringName) -> bool:
	var service := current()
	return service != null and service.enabled and ACCESS_KEYS.has(key)

static func force_normal_for_qa() -> void:
	var service := current()
	if service != null: service.set_enabled(false)

func set_enabled(value: bool) -> void:
	if value and not OS.is_debug_build(): return
	if enabled == value: return
	enabled = value
	if indicator != null: indicator.visible = enabled
	mode_changed.emit(enabled)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var locations := get_node_or_null("/root/WorldLocations")
	if locations != null: locations.configure_developer_access(self)
	var layer := CanvasLayer.new()
	layer.name = "DeveloperIndicator"
	layer.layer = 125
	add_child(layer)
	indicator = Label.new()
	indicator.text = "DEV"
	indicator.position = Vector2(6, 6)
	indicator.add_theme_font_size_override("font_size", 18)
	indicator.modulate = Color(1, 0.8, 0.2)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.visible = enabled
	layer.add_child(indicator)

func can_mutate_test_save() -> bool:
	# Explicit allowlist, rather than assuming all custom userdata is disposable.
	var name := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var known_test_name := name == "FishingGame-MobilePortraitPlaytest" or name.begins_with("CodexDeveloperPlaytestQA-")
	return enabled and _isolated_mobile_save_authorized and ProjectSettings.get_setting("application/config/use_custom_user_dir", false) and known_test_name and (OS.get_name() == "Web" or OS.get_user_data_dir().get_file() == name)

func grant_loadout(kind: String) -> Dictionary:
	if not can_mutate_test_save():
		return {"success": false, "reason": "Blocked: loadouts require isolated MobilePortraitPlaytest save + DEV"}
	var session := get_parent()
	match kind:
		"fishing":
			var catalog = preload("res://data/bof4/catalogs/all_content.tres")
			for lure in catalog.tackle.lure_catalog.lures: session.inventory.grant_lure(lure, 2, true)
			for rod in catalog.tackle.rods: session.inventory.grant_rod(rod, 1, true)
		"wallet": session.inventory.set_zenny(10000, true)
		"cards":
			var scene = preload("res://scripts/gameplay_scene_root.gd").resolve(get_tree())
			var game = scene.find_child("TripleTriadGame", true, false) if scene != null else null
			if game == null:
				return {"success": false, "reason": "Card backend unavailable"}
			return game.grant_development_card_loadout()
		_:
			return {"success": false, "reason": "Unknown loadout"}
	return {"success": true, "reason": "Granted %s in isolated test save" % kind}
