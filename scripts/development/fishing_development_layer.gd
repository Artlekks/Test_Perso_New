extends Node
class_name FishingDevelopmentLayer
## Optional consumers; canonical gameplay services remain owned by the session.
var session: Node
var telemetry: Node
var crafting_hud: CanvasLayer
var campaign_guide: Node
var _controllers: Array[WeakRef] = []
var _card_hosts: Array[WeakRef] = []

static func ensure(owner: Node) -> Node:
	var layer := owner.get_node_or_null("DevelopmentLayer")
	if layer == null:
		layer = load("res://scripts/development/fishing_development_layer.gd").new()
		layer.name = "DevelopmentLayer"
		layer.session = owner
		owner.add_child(layer)
		var developer = load("res://scripts/developer_playtest_service.gd").new()
		developer.name = "DeveloperPlaytestService"
		developer.session = owner
		layer.add_child(developer)
		RuntimeAccessPolicy.bind(developer)
	return layer

func mount_game(game: Node) -> void:
	# Weak handles do not retain actors, but the handle list itself must stay bounded.
	_controllers = _controllers.filter(func(binding): return binding.get_ref() != null)
	_card_hosts = _card_hosts.filter(func(binding): return binding.get_ref() != null)
	var fishing := game.get_node("Game/Fishing")
	if fishing.debug_controller == null:
		var debug = load("res://scripts/fishing_debug_controller.gd").new()
		debug.name = "FishingDebugController"
		fishing.add_child(debug)
		debug.configure(fishing.game_mode, fishing.encounter, fishing.aim, fishing.loadout, session.progress, session.journal_service, session.unlock_state, session.reward_service, session.session_modifier_service)
		fishing.debug_controller = debug
		_controllers.append(weakref(fishing))
		debug.debug_menu.configure_economy_telemetry_provider(get_economy_playtest_telemetry)
	if campaign_guide == null:
		campaign_guide = load("res://scripts/progression/playable_campaign_qa_controller.gd").new()
		campaign_guide.name = "PlayableCampaignQAController"
		add_child(campaign_guide)
		campaign_guide.configure(session, session.campaign_progression_director)
	if crafting_hud == null:
		crafting_hud = load("res://actors/BeachCraftingFeelQAHUD.tscn").instantiate()
		add_child(crafting_hud)
		crafting_hud.configure(session.beach_crafting_service, session.active_loadout)
		session.loadout_bound.connect(crafting_hud.set_loadout)
	else:
		crafting_hud.set_loadout(session.active_loadout)
	var cards := game.get_node_or_null("UI/TripleTriadGame")
	if cards != null:
		_card_hosts.append(weakref(cards))
		if cards.debug_menu == null:
			cards.debug_menu = load("res://actors/TripleTriadDebugMenu.tscn").instantiate()
			cards.add_child(cards.debug_menu)
			cards.debug_menu.apply_requested.connect(cards._on_qa_profile_apply_requested)
			cards._ui_flow.bind_optional_overlay(cards.debug_menu)
		cards._developer_tools.enable_development()
		var provider := RuntimeAccessPolicy.current()
		if provider != null and not provider.mode_changed.is_connected(cards._on_developer_mode_changed):
			provider.mode_changed.connect(cards._on_developer_mode_changed)

func get_economy_playtest_telemetry() -> Node:
	if not is_instance_valid(telemetry):
		telemetry = load("res://scripts/telemetry/runtime_economy_telemetry.gd").new()
		telemetry.name = "RuntimeEconomyTelemetry"
		add_child(telemetry)
		telemetry.configure(session)
	var game := preload("res://scripts/gameplay_scene_root.gd").resolve(get_tree())
	if game != null: telemetry.bind_runtime(game.get_node("Game/Fishing"))
	return telemetry

func _exit_tree() -> void:
	if is_instance_valid(crafting_hud): crafting_hud.queue_free()
	for binding in _card_hosts:
		var cards = binding.get_ref()
		if cards != null:
			cards._developer_tools.disable_development()
			if is_instance_valid(cards.debug_menu):
				cards.debug_menu.close_menu()
				cards.debug_menu.queue_free()
			cards.debug_menu = null
			cards._ui_flow.bind_optional_overlay(null)
	_card_hosts.clear()
	for binding in _controllers:
		var fishing = binding.get_ref()
		if fishing != null and is_instance_valid(fishing.debug_controller):
			fishing.debug_controller.close(false)
			fishing.debug_controller.queue_free()
			fishing.debug_controller = null
	_controllers.clear()
