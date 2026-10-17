extends Node
class_name DeveloperPlaytestService
## Transient access policy. Never writes progression or inventory on toggle.
signal mode_changed(enabled: bool)
const ACCESS_KEYS := [&"travel", &"cards", &"economy", &"mastery", &"world_interactions"]
var session: Node
var enabled := false
var indicator: Label
var _isolated_mobile_save_authorized := false

func authorize_isolated_mobile_save(isolated: bool) -> void:
	# Only the dedicated harness opts into its existing separate save namespace.
	_isolated_mobile_save_authorized = isolated

static func current() -> DeveloperPlaytestService:
	var tree := Engine.get_main_loop() as SceneTree
	return RuntimeAccessPolicy.current() as DeveloperPlaytestService if tree != null else null

static func allows(key: StringName) -> bool:
	var service := current()
	return service != null and service.enabled and ACCESS_KEYS.has(key)

static func force_normal_for_qa() -> void:
	var service := current()
	if service != null: service.set_enabled(false)

static func card_test_deck(catalog: Resource, owned: Array, policy: Resource, rank: int, budget: int) -> Array:
	if not allows(&"cards") or catalog == null or policy == null: return []
	var legal: Array = []
	for card in owned:
		if policy.can_use_card(card, rank): legal.append(card)
	legal.sort_custom(func(a, b): return int(a.deck_cost) < int(b.deck_cost))
	if legal.size() >= 5:
		var existing_cost := 0
		for index in range(5): existing_cost += int(legal[index].deck_cost)
		if existing_cost <= budget: return [] # Preserve the real collection/deck workflow.
	var candidates: Array = policy.build_starting_collection(catalog)
	candidates = candidates.filter(func(card): return policy.can_use_card(card, rank))
	if candidates.size() < 5: return []
	candidates.resize(5)
	var cost := 0
	for card in candidates: cost += int(card.deck_cost)
	return candidates if cost <= budget else []

func set_enabled(value: bool) -> void:
	if value and not OS.is_debug_build(): return
	if enabled == value: return
	enabled = value
	if indicator != null: indicator.visible = enabled
	mode_changed.emit(enabled)

func _ready() -> void:
	RuntimeAccessPolicy.bind(self)
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
	# F5 is its own persistent developer namespace. Existing mobile/harness
	# authorization remains required for mobile; ordinary saves stay read-only.
	if not enabled or not OS.is_debug_build():
		return false
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		return false
	var user_dir_name := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var project_name := str(ProjectSettings.get_setting("application/config/name", ""))
	var dedicated_f5 := (
		user_dir_name == "FishingGame_DEV_F5"
		and project_name == "FishingGame_DEV_F5"
	)
	var authorized_mobile := (
		_isolated_mobile_save_authorized
		and (user_dir_name == "FishingGame-MobilePortraitPlaytest"
		or user_dir_name.begins_with("CodexDeveloperPlaytestQA-"))
	)
	if not dedicated_f5 and not authorized_mobile:
		return false
	return OS.get_name() == "Web" or OS.get_user_data_dir().get_file() == user_dir_name

func grant_loadout(kind: String) -> Dictionary:
	if not can_mutate_test_save():
		return {"success": false, "reason": "Blocked: loadouts require authorized isolated F5/mobile save + DEV"}
	var active_session = self.session if self.session != null else get_parent()
	match kind:
		"fishing":
			var catalog = preload("res://data/bof4/catalogs/all_content.tres")
			for lure in catalog.tackle.lure_catalog.lures: active_session.inventory.grant_lure(lure, 2, true)
			for rod in catalog.tackle.rods: active_session.inventory.grant_rod(rod, 1, true)
		"wallet": active_session.inventory.set_zenny(10000, true)
		"cards":
			var scene = preload("res://scripts/gameplay_scene_root.gd").resolve(get_tree())
			var game = scene.find_child("TripleTriadGame", true, false) if scene != null else null
			if game == null:
				return {"success": false, "reason": "Card backend unavailable"}
			return game.grant_development_card_loadout()
		_:
			return {"success": false, "reason": "Unknown loadout"}
	return {"success": true, "reason": "Granted %s in isolated test save" % kind}

func allows_access(key: StringName) -> bool:
	return enabled and ACCESS_KEYS.has(key)

func build_practice_deck(catalog: Resource, owned: Array, policy: Resource, rank: int, budget: int) -> Array:
	return card_test_deck(catalog, owned, policy, rank, budget)

func _exit_tree() -> void:
	set_enabled(false)
	RuntimeAccessPolicy.unbind(self)
