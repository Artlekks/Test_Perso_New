extends Control
## Shared reference skin and read-only state adapter. Owns no gameplay/session data.
const Layout = preload("res://scripts/ui/seaside_shell_layout.gd")
const FONT = preload("res://assets/fonts/BOF_Font_Refined.fnt")
const PAPER = preload("res://assets/ui/seaside_shell/panel.png")
const BUTTON = preload("res://assets/ui/seaside_shell/button.png")
const DESKTOP_PARCHMENT := Color("d0c19e")
const DESKTOP_INK := Color("563047")
const DESKTOP_LINE := Color("aa9274")
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
var dashboard: Control
var desktop_actions: Control
# Existing clickable controls remain implemented and QA-addressable, but are
# not a mandatory permanent desktop toolbar. Can be enabled later by Settings.
var show_desktop_shortcuts := false
static func skin(texture: Texture2D, margin := 12) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = texture
	for side in range(4): s.set_texture_margin(side,margin)
	return s
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for id in ["Menu","Inventory","Journal","Settings","Equipment","Active","Passive","Cards","Dock Left","Dock Right","Minimize","Maximize","Close","Float","Collapse","Mode","Window"]:
		var b: Button = MenuButton.new() if id == "Window" else Button.new()
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
		if id == "Window":
			var popup := (b as MenuButton).get_popup()
			for title in ["Dock Left","Dock Right","Float","Collapse"]: popup.add_item(title)
			popup.id_pressed.connect(func(index: int): _activate(["Dock Left","Dock Right","Float","Collapse"][index]))
		else: b.pressed.connect(_activate.bind(id))
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
	if host.get("window_state") != null:
		dashboard = preload("res://scripts/desktop/companion_dashboard.gd").new()
		dashboard.host = host
		add_child(dashboard)
		desktop_actions=preload("res://scripts/input/desktop_action_controls.gd").new()
		desktop_actions.host=host; add_child(desktop_actions)
		desktop_actions.hide()
func configure(next: Dictionary) -> void:
	if regions == next: return
	regions = next
	for b in utility.values(): b.hide()
	environment_strip.visible = true
	equipment_drawer.hide()
	var desktop := str(regions.variant).begins_with("desktop")
	if desktop:
		if dashboard != null:
			dashboard.position = regions.dashboard.position
			dashboard.size = regions.dashboard.size
			dashboard.visible = regions.dashboard.size.y >= 70.0
		# Three unobtrusive, icon-only native window actions at top right.
		# These preserve the existing dock/undock implementation.
		var window_width := 112.0
		var dock_area := Rect2(
			Vector2(regions.info.end.x - window_width, regions.info.position.y),
			Vector2(window_width, regions.info.size.y))
		_row(["Dock Left", "Dock Right", "Float"], dock_area)
		for id in ["Dock Left", "Dock Right", "Float"]:
			_desktop_flat_button(id, "")
		utility["Dock Left"].tooltip_text = "Dock left"
		utility["Dock Right"].tooltip_text = "Dock right"
		utility["Float"].tooltip_text = "Float / undock"
		# The second band follows the reference: Active / Passive left,
		# equipment, original J menu and settings icons right.
		var bar: Rect2 = regions.toolbar
		var action_width := 46.0 if not regions.compact else 40.0
		var mode_width := 92.0 if not regions.compact else 72.0
		_place("Active", Rect2(bar.position + Vector2(12, 1), Vector2(mode_width, bar.size.y - 2)))
		_place("Passive", Rect2(bar.position + Vector2(12 + mode_width, 1), Vector2(mode_width, bar.size.y - 2)))
		_desktop_flat_button("Active", "Active")
		_desktop_flat_button("Passive", "Passive")
		var icons := ["Equipment", "Menu", "Settings"]
		for i in range(icons.size()):
			var id: String = icons[i]
			var bx := bar.end.x - 10.0 - action_width * float(icons.size() - i)
			_place(id, Rect2(Vector2(bx, bar.position.y + 1), Vector2(action_width, bar.size.y - 2)))
			_desktop_flat_button(id, "")
		utility["Equipment"].tooltip_text = "Equipment (existing Equip menu)"
		utility["Menu"].tooltip_text = "Menu (J)"
		utility["Settings"].tooltip_text = "Settings"
		if desktop_actions != null:
			desktop_actions.position = bar.position
			desktop_actions.size = Vector2(maxf(1.0, bar.size.x - 140.0), 30)
			desktop_actions.visible = false
		environment_strip.position = regions.info.position
		environment_strip.size = Vector2(maxf(1.0, regions.info.size.x - window_width), regions.info.size.y)
		environment_strip.portrait = false
		environment_strip.desktop_compact = regions.compact
		environment_strip.desktop_mode = true
		# This transient mobile-style drawer is not used for desktop.
		# All expanded desktop panels belong to FishingMenu below gameplay.
		equipment_drawer.hide()

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
		environment_strip.desktop_mode = false
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
	b.text = {"Minimize":"-","Maximize":"[]","Close":"X","Equipment":"Gear" if str(regions.get("variant","")).begins_with("desktop") else "Select"}.get(id,id)
	var caption: Label = b.get_node("Caption")
	caption.hide()
	if box.size.x<105 and b.icon != null:
		b.text = ""
		caption.text = id
		caption.position = Vector2(0,box.size.y-20)
		caption.size = Vector2(box.size.x,18)
		caption.show()
	if id in ["Active","Passive"]:
		b.text = id
	if box.size.x<60 or box.size.y<40:
		caption.hide()
		for key in ["normal","hover","pressed"]: b.add_theme_stylebox_override(key,skin(BUTTON,6))
		b.add_theme_constant_override("icon_max_width",16)
	else:
		for key in ["normal","hover","pressed"]: b.add_theme_stylebox_override(key,skin(BUTTON))
		b.add_theme_constant_override("icon_max_width",24)
	b.size = box.size
	b.show()
func _desktop_flat_button(id: String, label_text: String) -> void:
	var button: Button = utility[id]
	button.icon = null
	button.text = label_text
	button.get_node("Caption").hide()
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_override("font", ThemeDB.fallback_font)
	button.add_theme_font_size_override("font_size", 16)
	for color_name in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, DESKTOP_INK)
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color.TRANSPARENT
	clear.set_content_margin_all(0.0)
	var hover := clear.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.34, 0.19, 0.28, 0.07)
	for name in ["normal", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(name, clear)
	button.add_theme_stylebox_override("hover", hover)
	button.show()

func _desktop_symbol(id: String) -> void:
	if not utility.has(id): return
	var button: Button = utility[id]
	if not button.visible: return
	var c: Vector2 = button.position + button.size * 0.5
	var ink := DESKTOP_INK
	match id:
		"Dock Left", "Dock Right":
			draw_rect(Rect2(c - Vector2(9, 7), Vector2(18, 14)), ink, false, 1.5)
			var line_x := c.x - 3.5 if id == "Dock Left" else c.x + 3.5
			draw_line(Vector2(line_x, c.y - 7), Vector2(line_x, c.y + 7), ink, 1.5)
		"Float":
			draw_rect(Rect2(c - Vector2(9, 7), Vector2(18, 14)), ink, false, 1.5)
			draw_line(c - Vector2(9, 2), c + Vector2(9, -2), ink, 1.5)
			draw_rect(Rect2(c + Vector2(0, 1), Vector2(9, 6)), ink, false, 1.0)
		"Equipment":
			draw_rect(Rect2(c - Vector2(7, 4), Vector2(14, 12)), ink, false, 1.7)
			draw_arc(c - Vector2(0, 4), 4.0, PI, TAU, 13, ink, 1.6)
			draw_line(c - Vector2(4, 2), c + Vector2(4, -2), ink, 1.2)
			for dx in [-3.0, 3.0]:
				draw_line(c + Vector2(dx, 3), c + Vector2(dx, 7), ink, 1.3)
		"Menu":
			draw_polyline(PackedVector2Array([c + Vector2(-9, -6), c + Vector2(-2, -5), c + Vector2(0, -3), c + Vector2(0, 8), c + Vector2(-3, 6), c + Vector2(-9, 5), c + Vector2(-9, -6)]), ink, 1.6)
			draw_polyline(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3, -5), c + Vector2(9, -6), c + Vector2(9, 5), c + Vector2(3, 6), c + Vector2(0, 8)]), ink, 1.6)
		"Settings":
			draw_arc(c, 6.0, 0, TAU, 24, ink, 1.5)
			draw_arc(c, 2.0, 0, TAU, 16, ink, 1.5)
			for n in range(8):
				var ray := Vector2.from_angle(float(n) * TAU / 8.0)
				draw_line(c + ray * 7, c + ray * 10, ink, 1.6)

func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0: return
	_refresh = .25
	snapshot = _read_state()
	if environment_strip.visible: environment_strip.refresh(snapshot)
	if host._has_surface_modal() and not equipment_pinned:
		equipment_open = false
	equipment_drawer.visible = equipment_open and not host._has_surface_modal()
	if equipment_drawer.visible:
		equipment_text.text = "Equipment%s\nRod: %s\nLure/bait: %s x%d" % [" (pinned)" if equipment_pinned else "",snapshot.rod,snapshot.bait,snapshot.count]
		# A short portrait world can be shorter than the drawer's content minimum.
		# Use its top edge instead of letting the drawer cover the shoulder controls.
		equipment_drawer.position.y = maxf(regions.world.position.y,minf(regions.world.position.y+10,regions.world.end.y-equipment_drawer.size.y))
	_update_shortcut()
	if is_instance_valid(host) and str(regions.get("variant","")).begins_with("desktop"):
		utility.Mode.text = "Active" if host.mode == host.Mode.ACTIVE else "Passive"
		utility.Active.modulate = Color.WHITE if host.mode == host.Mode.ACTIVE else Color(.65,.65,.65)
		utility.Passive.modulate = Color.WHITE if host.mode == host.Mode.PASSIVE else Color(.65,.65,.65)
		utility["Dock Left"].disabled = not host.platform.supported()
		utility["Dock Right"].disabled = not host.platform.supported()
	queue_redraw()
func _read_state() -> Dictionary:
	var result := {"location":"No location","spot":"","rod":"No rod","bait":"No bait","count":0,"time":"N/A"}
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
		"Float": host.set_window_state(host.WindowState.FLOATING)
		"Collapse": host.toggle_collapse()
		"Equipment":
			if str(regions.get("variant","")).begins_with("desktop"):
				var menu: FishingMenu = host._fishing_menu()
				if menu != null: menu.open_desktop_page(FishingMenu.Page.EQUIP)
			else:
				equipment_open = not equipment_open
				equipment_drawer.visible = equipment_open and not host._has_surface_modal()
		"Mode": host.cycle_mode()
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
func _desktop_paper(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0: return
	# Deliberately flat, unframed parchment like the approved desktop mockup.
	# Stretching the old 64px ornamented texture enlarged its pixels/borders.
	draw_rect(rect, DESKTOP_PARCHMENT)

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
	if str(regions.variant).begins_with("desktop"):
		# A single uninterrupted beige field. The thin dividers are the
		# ONLY lines; no ornate frames, extra bars or default Control borders.
		_desktop_paper(Rect2(Vector2.ZERO, regions.safe.size))
		draw_line(Vector2(12, regions.info.end.y), Vector2(regions.safe.size.x - 12, regions.info.end.y), DESKTOP_LINE, 1.0)
		for id in ["Dock Left", "Dock Right", "Float", "Equipment", "Menu", "Settings"]:
			_desktop_symbol(id)
		return
	for key in ["header","info","gear","frame","controls","modes","docks","menus","left","right","toolbar"]:
		if key in ["controls","left","right"]: continue
		if regions.has(key): draw_style_box(paper,regions[key])
	if regions.has("header"): _text("Seaside Companion",regions.header,24)
	if str(regions.variant).begins_with("mobile"): return

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
