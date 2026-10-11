extends Control
## Shared reference skin and read-only state adapter. Owns no gameplay/session data.
const Layout = preload("res://scripts/ui/seaside_shell_layout.gd")
const FONT = preload("res://assets/fonts/BOF_Font_Refined.fnt")
const PAPER = preload("res://assets/ui/seaside_shell/panel.png")
const BUTTON = preload("res://assets/ui/seaside_shell/button.png")
var host: Node
var regions: Dictionary = {}
var shortcut: Button
var utility: Dictionary = {}
var snapshot: Dictionary = {}
var _refresh := 0.0
var environment_strip: Control
var equipment_drawer: PanelContainer
var equipment_text: Label
var equipment_open := false
var equipment_pinned := false
static func skin(texture: Texture2D, margin := 12) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = texture
	for side in range(4): s.set_texture_margin(side,margin)
	return s
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for id in ["Menu","Inventory","Journal","Settings","Equipment","Active","Passive","Cards","Dock Left","Dock Right","Minimize","Maximize","Close"]:
		var b := Button.new()
		b.text = {"Minimize":"-","Maximize":"[]","Close":"X"}.get(id,id)
		if id.to_lower() in ["inventory","journal","cards","settings"]:
			b.icon = load("res://assets/ui/seaside_shell/"+id.to_lower()+".png")
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width",24)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal",skin(BUTTON))
		b.add_theme_stylebox_override("hover",skin(BUTTON))
		b.add_theme_stylebox_override("pressed",skin(BUTTON))
		b.add_theme_font_override("font",ThemeDB.fallback_font)
		b.add_theme_font_size_override("font_size",16)
		b.add_theme_color_override("font_color",Color("fff0bd"))
		var caption := Label.new()
		caption.name = "Caption"
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size",11)
		b.add_child(caption)
		b.tooltip_text = id
		b.pressed.connect(_activate.bind(id))
		utility[id] = b
		add_child(b)
	var shortcut_layer := CanvasLayer.new()
	shortcut_layer.layer = 129
	add_child(shortcut_layer)
	shortcut = Button.new()
	shortcut.name = "ContextualExistingInput"
	shortcut.focus_mode = Control.FOCUS_NONE
	shortcut.add_theme_stylebox_override("normal",skin(BUTTON))
	shortcut.add_theme_font_size_override("font_size",14)
	shortcut.pressed.connect(_shortcut_pressed)
	shortcut_layer.add_child(shortcut)
	shortcut.hide()
	environment_strip = preload("res://scripts/ui/seaside_environment_strip.gd").new()
	environment_strip.host = host
	add_child(environment_strip)
	environment_strip.hide()
	equipment_drawer = PanelContainer.new()
	equipment_drawer.name = "EquipmentDrawer"
	# Shell was added before the gameplay texture. Transient drawers must render
	# above that texture; permanent shell controls remain outside the game.
	equipment_drawer.z_index = 20
	equipment_drawer.add_theme_stylebox_override("panel",skin(PAPER))
	add_child(equipment_drawer)
	var column := VBoxContainer.new()
	equipment_drawer.add_child(column)
	equipment_text = Label.new()
	equipment_text.add_theme_font_override("font",ThemeDB.fallback_font)
	equipment_text.add_theme_font_size_override("font_size",13)
	equipment_text.add_theme_color_override("font_color",Color("35202d"))
	equipment_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(equipment_text)
	var drawer_row := HBoxContainer.new()
	column.add_child(drawer_row)
	for caption in ["Pin / unpin","Change equipment","Close"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size.y = 44
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size",12)
		button.add_theme_stylebox_override("normal",skin(BUTTON,6))
		button.pressed.connect(_equipment_action.bind(caption))
		if caption == "Change equipment": column.add_child(button)
		else:
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			drawer_row.add_child(button)
	equipment_drawer.hide()
func configure(next: Dictionary) -> void:
	if regions == next: return
	regions = next
	for b in utility.values(): b.hide()
	environment_strip.visible = str(regions.variant).begins_with("mobile")
	equipment_drawer.hide()
	var desktop := str(regions.variant).begins_with("desktop")
	if desktop:
		_row(["Active","Passive"],regions.modes)
		_row(["Dock Left","Dock Right"],regions.docks)
		var header: Rect2 = regions.header
		_row(["Minimize","Maximize","Close"],Rect2(header.end-Vector2(100,header.size.y),Vector2(100,header.size.y)))
		var menu: Rect2 = regions.menus
		if regions.variant == "desktop_wide":
			_column(["Inventory","Journal","Cards","Settings"],Rect2(menu.position+Vector2(10,28),menu.size-Vector2(20,38)))
		else: _row(["Inventory","Journal","Cards","Settings"],Rect2(menu.position+Vector2(6,24),menu.size-Vector2(12,30)))
	else:
		var geometry := Layout.landscape_controls(regions)
		utility.Settings.z_index = 21
		utility.Equipment.z_index = 21
		_place("Settings",geometry.settings)
		utility.Settings.get_node("Caption").hide()
		utility.Settings.add_theme_constant_override("icon_max_width",28)
		_place("Equipment",geometry.select)
		environment_strip.position = regions.info.position
		environment_strip.size = regions.info.size
		environment_strip.portrait = regions.variant == "mobile_portrait"
		equipment_drawer.position = regions.world.position+Vector2(10,10)
		equipment_drawer.size = Vector2(minf(240,regions.world.size.x-20),0)
		if regions.get("fallback","") == "edge_overlay":
			var free_left: float = regions.left.end.x+6
			var free_right: float = regions.right.position.x-6
			equipment_drawer.size.x = minf(240,free_right-free_left)
			equipment_drawer.position.x = (free_left+free_right-equipment_drawer.size.x)*.5
	queue_redraw()
func _row(ids: Array, box: Rect2) -> void:
	for i in range(ids.size()): _place(ids[i],Rect2(box.position+Vector2(i*box.size.x/ids.size(),0),Vector2(box.size.x/ids.size()-3,box.size.y)))
func _column(ids: Array, box: Rect2) -> void:
	for i in range(ids.size()): _place(ids[i],Rect2(box.position+Vector2(0,i*box.size.y/ids.size()),Vector2(box.size.x,box.size.y/ids.size()-4)))
func _place(id: String, box: Rect2) -> void:
	var b: Button = utility[id]
	b.position = box.position
	b.custom_minimum_size = Vector2.ZERO
	b.add_theme_font_size_override("font_size",12 if box.size.x<145 else 18)
	b.text = {"Minimize":"-","Maximize":"[]","Close":"X","Equipment":"Select"}.get(id,id)
	var caption: Label = b.get_node("Caption")
	caption.hide()
	if box.size.x<105 and b.icon != null:
		b.text = ""
		caption.text = id
		caption.position = Vector2(0,box.size.y-20)
		caption.size = Vector2(box.size.x,18)
		caption.show()
	if id in ["Active","Passive"]:
		b.text = ""
		caption.text = "Active\nPlay in real-time" if id == "Active" else "Passive\nFish while you work"
		caption.position = Vector2(3,box.size.y*.19)
		caption.size = box.size-Vector2(6,6)
		caption.add_theme_font_size_override("font_size",12 if box.size.x<145 else 16)
		caption.show()
	if box.size.x<60:
		caption.hide()
		for key in ["normal","hover","pressed"]: b.add_theme_stylebox_override(key,skin(BUTTON,6))
		b.add_theme_constant_override("icon_max_width",16)
	else:
		for key in ["normal","hover","pressed"]: b.add_theme_stylebox_override(key,skin(BUTTON))
		b.add_theme_constant_override("icon_max_width",24)
	b.size = box.size
	b.show()
func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0: return
	_refresh = .25
	snapshot = _read_state()
	if environment_strip.visible: environment_strip.refresh(snapshot)
	if str(regions.get("variant","")).begins_with("mobile") and host._has_surface_modal() and not equipment_pinned:
		equipment_open = false
	equipment_drawer.visible = str(regions.get("variant","")).begins_with("mobile") and equipment_open and not host._has_surface_modal()
	if equipment_drawer.visible:
		equipment_text.text = "Equipment%s\nRod: %s\nLure/bait: %s x%d" % [" (pinned)" if equipment_pinned else "",snapshot.rod,snapshot.bait,snapshot.count]
		# A short portrait world can be shorter than the drawer's content minimum.
		# Use its top edge instead of letting the drawer cover the shoulder controls.
		equipment_drawer.position.y = maxf(regions.world.position.y,minf(regions.world.position.y+10,regions.world.end.y-equipment_drawer.size.y))
	_update_shortcut()
	if is_instance_valid(host) and str(regions.get("variant","")).begins_with("desktop"):
		utility.Active.modulate = Color.WHITE if host.mode == host.Mode.ACTIVE else Color(.65,.65,.65)
		utility.Passive.modulate = Color.WHITE if host.mode == host.Mode.PASSIVE else Color(.65,.65,.65)
		utility["Dock Left"].disabled = not host.platform.supported()
		utility["Dock Right"].disabled = not host.platform.supported()
	queue_redraw()
func _read_state() -> Dictionary:
	var result := {"location":"No location","spot":"","rod":"No rod","bait":"No bait","count":0,"time":Time.get_time_string_from_system().left(5)}
	var locations := get_node_or_null("/root/WorldLocations")
	if locations != null and locations.current_location != null:
		var c = locations.current_location
		result.location = c.display_name
		result.preview = preload("res://assets/ui/seaside_shell/preview.png") if c.location_id == &"beach" else null
		if c.fishing_spot != null: result.spot = c.fishing_spot.spot_name
	if not is_instance_valid(host) or not is_instance_valid(host.game): return result
	var hud: Node = host.game.find_child("ExplorationHud",true,false)
	if hud != null and hud.has_method("_format_location_name"): result.spot = hud._format_location_name(str(result.spot))
	var fishing: Node = host.game.get_node_or_null("Game/Fishing")
	if fishing != null and is_instance_valid(fishing.loadout):
		var rod = fishing.loadout.get_selected_rod()
		var bait = fishing.loadout.get_selected_lure()
		if rod != null: result.rod = rod.rod_name
		if bait != null:
			result.bait = bait.display_name
			result.bait_icon = FishingMenu.LURE_GUIDE_ICONS.get(bait.lure_id)
			var inv = fishing.loadout.get_inventory()
			if inv != null: result.count = inv.get_lure_count(bait.lure_id)
	return result
func _activate(id: String) -> void:
	if not is_instance_valid(host): return
	match id:
		"Equipment": equipment_open = not equipment_open
		"Active": host.set_mode(host.Mode.ACTIVE)
		"Passive": host.set_mode(host.Mode.PASSIVE)
		"Dock Left": host.dock_from_shell(host.WindowState.DOCK_LEFT)
		"Dock Right": host.dock_from_shell(host.WindowState.DOCK_RIGHT)
		"Minimize": host.toggle_collapse()
		"Maximize": host.toggle_shell_fullscreen()
		"Close": host.get_tree().quit()
		_: host.request_shell_menu(id)

func _equipment_action(id: String) -> void:
	match id:
		"Pin / unpin": equipment_pinned = not equipment_pinned
		"Close": equipment_open = false
		"Change equipment":
			if not equipment_pinned: equipment_open = false
			host.request_shell_menu("Inventory")
func _text(value: String, rect: Rect2, font_size: int = 16, color := Color("35202d")) -> void:
	draw_string(FONT,rect.position+Vector2(6,font_size+3),value,HORIZONTAL_ALIGNMENT_LEFT,maxf(1,rect.size.x-12),font_size,color)
func _draw() -> void:
	if regions.is_empty(): return
	if str(regions.variant).begins_with("mobile"):
		# Compact control islands sit on a quiet burgundy charcoal surface.
		# Unused side space is not an oversized decorative parchment panel.
		draw_rect(regions.safe,Color("25222c"))
		if regions.variant == "mobile_portrait":
			draw_style_box(skin(PAPER),regions.controls.intersection(regions.safe))
			draw_line(regions.controls.position+Vector2(regions.controls.size.x*.5,56),regions.controls.intersection(regions.safe).end-Vector2(regions.controls.size.x*.5,54),Color("c99d69"),1)
	var paper := skin(PAPER)
	for key in ["header","info","gear","frame","controls","modes","docks","menus","left","right"]:
		if str(regions.variant).begins_with("mobile") and key in ["controls","left","right"]: continue
		if regions.has(key): draw_style_box(paper,regions[key])
	if regions.has("header"): _text("Seaside Companion",regions.header,24)
	if str(regions.variant).begins_with("mobile"): return
	var info: Rect2 = regions.info
	var preview_width := minf(info.size.y-16,info.size.x*.27)
	var preview: Texture2D = snapshot.get("preview")
	if preview != null: draw_texture_rect(preview,Rect2(info.position+Vector2(8,8),Vector2(preview_width,info.size.y-16)),false)
	var x := info.position.x+preview_width+10
	var fs := 24 if info.size.x > 500 else 12
	_text(str(snapshot.get("spot","")),Rect2(x,info.position.y+maxf(4,info.size.y*.06),info.end.x-x,28),fs)
	_text(str(snapshot.get("location","")),Rect2(x,info.position.y+info.size.y*.36,info.end.x-x,28),fs)
	_text("Local " + str(snapshot.get("time","")),Rect2(x,info.position.y+info.size.y*.67,info.end.x-x,28),12)
	var gear: Rect2 = regions.gear
	_text("ROD",gear,12)
	_text("BAIT",Rect2(gear.position+Vector2(gear.size.x*.5,0),gear.size*.5),12)
	var half := gear.size.x*.5
	var icon_size := minf(half-20,maxf(0,gear.size.y*.66-20))
	if icon_size>12:
		draw_texture_rect(preload("res://assets/ui/seaside_shell/rod.png"),Rect2(gear.position+Vector2(10,24),Vector2(icon_size,icon_size)),false)
		var bait_icon: Texture2D = snapshot.get("bait_icon")
		if bait_icon != null: draw_texture_rect(bait_icon,Rect2(gear.position+Vector2(half+10,24),Vector2(icon_size,icon_size)),false)
	_gear_caption(str(snapshot.get("rod","")),Rect2(gear.position+Vector2(0,gear.size.y*.72),Vector2(half,gear.size.y*.28)))
	_gear_caption(str(snapshot.get("bait","")),Rect2(gear.position+Vector2(half,gear.size.y*.72),Vector2(half,gear.size.y*.28)))
	var count := str(snapshot.get("count",0))
	var badge_width := ThemeDB.fallback_font.get_string_size(count,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+6
	var badge := Rect2(gear.position+Vector2(gear.size.x-badge_width-8,maxf(20,gear.size.y*.48)),Vector2(badge_width,18))
	draw_rect(badge,Color("292a32"))
	draw_string(ThemeDB.fallback_font,badge.position+Vector2(3,14),count,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("fff0bd"))
	if regions.has("menus"): _text("Menu",regions.menus,12)
	if regions.has("controls") and str(regions.variant).begins_with("desktop"):
		_text("Controls",regions.controls,12)

func _shortcut_key() -> int:
	if not is_instance_valid(host) or not is_instance_valid(host.game): return 0
	var cards: Node = host.game.find_child("TripleTriadGame",true,false)
	if cards != null and cards.deck_setup != null and cards.deck_setup.is_active(): return KEY_ENTER
	var fishing: Node = host.game.get_node_or_null("Game/Fishing")
	if fishing != null and fishing.debug_controller.debug_menu != null and fishing.debug_controller.debug_menu.is_open(): return KEY_SPACE
	return 0
func _update_shortcut() -> void:
	var key := _shortcut_key()
	shortcut.visible = key != 0
	if key == 0 or regions.is_empty(): return
	shortcut.text = "Start match" if key == KEY_ENTER else "QA / Playtest"
	shortcut.size = Vector2(124,44)
	shortcut.position = regions.world.end-Vector2(130,50)
func _shortcut_pressed() -> void:
	var key := _shortcut_key()
	if key != 0: preload("res://scripts/ui/seaside_shell_actions.gd").send_key(host,key)

func _gear_caption(value: String, rect: Rect2) -> void:
	draw_string(ThemeDB.fallback_font,rect.position+Vector2(4,13),value,HORIZONTAL_ALIGNMENT_LEFT,maxf(1,rect.size.x-8),11,Color("35202d"))
