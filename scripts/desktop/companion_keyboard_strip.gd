extends Label
## Read-only input hints; action keys come from the live InputMap. Raw-key menu
## bindings remain explicit until those existing controllers support actions.
var host: Node

func _ready() -> void:
	clip_contents = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 12)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_font_override("font",preload("res://assets/fonts/BOF_Font_Refined.fnt"))
	add_theme_font_size_override("font_size",16)
	add_theme_color_override("font_color",Color.TRANSPARENT)
	add_theme_constant_override("outline_size",0)
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

static func key_name(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key: int = event.physical_keycode if event.physical_keycode else event.keycode
			return OS.get_keycode_string(key)
	return "Unbound"

func _process(_delta: float) -> void:
	queue_redraw()
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

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var ink := Color("35202d")
	if host == null: return
	if get_tree().paused or host.mode == host.Mode.PASSIVE or (size.x < 500 and size.y < 280):
		draw_multiline_string(font,Vector2(0,16),text.replace("    ","\n"),HORIZONTAL_ALIGNMENT_LEFT,size.x,14,-1,ink)
		return
	var wide := size.x > 500
	var move_origin := Vector2.ZERO
	_cap(key_name(&"move_forward"),move_origin+Vector2(28,0))
	_cap(key_name(&"move_left"),move_origin+Vector2(0,28))
	_cap(key_name(&"move_back"),move_origin+Vector2(28,28))
	_cap(key_name(&"move_right"),move_origin+Vector2(56,28))
	draw_string(font,Vector2(90,16),"Move",HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
	draw_multiline_string(font,Vector2(90,34),"Walk around\nthe beach.",HORIZONTAL_ALIGNMENT_LEFT,-1,12,-1,ink)
	var x := size.x*.26 if wide else 0.0
	var y := 0.0 if wide else 80.0
	draw_style_box(preload("res://scripts/ui/seaside_shell_view.gd").skin(preload("res://assets/ui/seaside_shell/button.png")),Rect2(x+5,y+5,28,42))
	draw_line(Vector2(x+19,y+5),Vector2(x+19,y+25),Color("f8da9a"),1)
	draw_string(font,Vector2(x+42,y+16),"Mouse control",HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
	draw_multiline_string(font,Vector2(x+42,y+34),"Use existing game\nmouse controls.",HORIZONTAL_ALIGNMENT_LEFT,-1,12,-1,ink)
	x = size.x*.52 if wide else 0.0
	y = 0.0 if wide else 156.0
	_hint(key_name(&"enter_fishing"),"Interact / Reel",Vector2(x,y))
	_hint("J","Open Menu",Vector2(x,y+40))
	x = size.x*.77 if wide else 0.0
	y = 0.0 if wide else 240.0
	_hint(key_name(&"world_card_challenge"),"Open Cards",Vector2(x,y))
	_hint(key_name(&"cam_left")+"/"+key_name(&"cam_right"),"Rotate View",Vector2(x,y+40))
func _cap(key: String, point: Vector2) -> void:
	draw_style_box(preload("res://scripts/ui/seaside_shell_view.gd").skin(preload("res://assets/ui/seaside_shell/keycap.png"),4),Rect2(point,Vector2(maxf(24,key.length()*8+12),26)))
	draw_string(ThemeDB.fallback_font,point+Vector2(7,18),key,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("fff0bd"))
func _hint(key: String, title: String, point: Vector2) -> void:
	_cap(key,point)
	draw_string(ThemeDB.fallback_font,point+Vector2(44,18),title,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("35202d"))
