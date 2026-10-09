extends Label
## Read-only input hints; action keys come from the live InputMap. Raw-key menu
## bindings remain explicit until those existing controllers support actions.
var host: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 12)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_font_override("font",preload("res://assets/fonts/BOF_Font_Refined.fnt"))
	add_theme_font_size_override("font_size",16)
	add_theme_color_override("font_color",Color.WHITE)
	add_theme_constant_override("outline_size",0)
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

static func key_name(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key: int = event.physical_keycode if event.physical_keycode else event.keycode
			return OS.get_keycode_string(key)
	return "Unbound"

func _process(_delta: float) -> void:
	if host == null or not is_instance_valid(host.game): return
	if host.passive != null and host.passive.state != host.passive.State.IDLE:
		if host.passive.is_ready(): text = "! FISH READY\nActive + K to hook   I to cancel"
		else: text = "FOCUS  %02d:%02d\n%s" % [int(host.passive.elapsed)/60,int(host.passive.elapsed)%60,host.passive.reason]
		return
	var service := get_node_or_null("/root/FishingSessionServices")
	var dialogue = service.get("dialogue_service") if service != null else null
	var confirm := key_name(&"enter_fishing")
	var back := key_name(&"cancel_fishing")
	if dialogue != null and dialogue.is_active():
		# DialogueController currently consumes these physical keys, not InputMap.
		text = "K / Enter  Next     I / Esc  Back     W/S  Choices"
		return
	if get_tree().paused:
		text = "K / Enter  Confirm     I / Esc  Back     W/S  Select"
		return
	var fishing: Node = host.game.get_node_or_null("Game/Fishing")
	if fishing != null and fishing.game_mode.is_fishing():
		text = "%s  Cast / Reel    %s  Back\n%s/%s  Steer    %s  Lure" % [confirm,back,key_name(&"ds_left"),key_name(&"ds_right"),key_name(&"lure_menu")]
	else:
		text = "%s  Interact    %s  Cards    J  Menu\n%s/%s/%s/%s  Move    %s/%s  Rotate" % [confirm,key_name(&"world_card_challenge"),key_name(&"move_forward"),key_name(&"move_left"),key_name(&"move_back"),key_name(&"move_right"),key_name(&"cam_left"),key_name(&"cam_right")]
