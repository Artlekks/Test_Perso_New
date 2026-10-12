extends Control
## Two persistent bottom banners, drawing their summaries from existing services.
## The original FishingMenu owns all expanded Equip/Data content and selection.
const FONT = preload("res://assets/fonts/BOF_Font_Refined.fnt")
const SKIN = preload("res://assets/ui/seaside_shell/panel.png")
const BUTTON = preload("res://assets/ui/seaside_shell/button.png")
const INK := Color("563047")
var host: Node
var _equipment: Button
var _records: Button
var _equipment_summary: Label
var _records_summary: Label
var _elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_equipment = _make_banner("Equipment", "Inventory")
	_records = _make_banner("Fishing records", "Journal")
	_equipment_summary = _label(_equipment)
	_records_summary = _label(_records)
	resized.connect(_arrange)
	_arrange()

func _make_banner(caption: String, target: String) -> Button:
	var button := Button.new()
	button.name = target+"Banner"
	button.text = ">  "+caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font",FONT)
	button.add_theme_font_size_override("font_size",16)
	button.add_theme_color_override("font_color",INK)
	for key in ["normal","hover","pressed","disabled"]:
		button.add_theme_stylebox_override(key,host.shell.skin(SKIN,12))
	button.pressed.connect(_open.bind(target))
	add_child(button)
	return button

func _label(parent: Button) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",14)
	label.add_theme_color_override("font_color",INK)
	label.clip_text = true
	parent.add_child(label)
	return label

func _arrange() -> void:
	if _equipment == null: return
	var half := maxf(1.0,size.y*0.5)
	for i in range(2):
		var b: Button = _equipment if i == 0 else _records
		b.position = Vector2(0,i*half)
		b.size = Vector2(size.x,maxf(1,half-2))
		var detail: Label = _equipment_summary if i == 0 else _records_summary
		if detail == null: continue
		var narrow := size.x < 540.0
		detail.position = Vector2(18,28 if narrow else 7)
		detail.size = Vector2(maxf(0.0,b.size.x-(24 if narrow else b.size.x*.42)),24 if narrow else 42)
		if not narrow:
			detail.position.x = b.size.x*.42
			detail.position.y = 10
			detail.size.x = b.size.x*.56-10

func _open(target: String) -> void:
	if not is_instance_valid(host): return
	var menu: FishingMenu = host._fishing_menu()
	if menu != null and menu.is_open():
		var wanted := FishingMenu.Page.EQUIP if target == "Inventory" else FishingMenu.Page.DATA
		if menu._page == wanted:
			menu.close_menu()
			return
		menu.close_menu()
	host.request_shell_menu(target)

func _process(delta: float) -> void:
	_elapsed -= delta
	if _elapsed > 0.0 or not visible: return
	_elapsed = 0.35
	var menu: FishingMenu = host._fishing_menu()
	var page := menu._page if menu != null and menu.is_open() else -1
	_equipment.text = ("v" if page == FishingMenu.Page.EQUIP else ">")+"  Equipment"
	_records.text = ("v" if page == FishingMenu.Page.DATA else ">")+"  Fishing records"
	var state: Dictionary = host.shell.snapshot
	_equipment_summary.text = "%s  |  %s x%d" % [str(state.get("rod","Unavailable")),str(state.get("bait","Unavailable")),int(state.get("count",0))]
	var session := get_node_or_null("/root/FishingSessionServices")
	if session == null or session.journal_service == null:
		_records_summary.text = "Fishing records unavailable"
		return
	var summary: Dictionary = session.journal_service.get_summary()
	_records_summary.text = "%d catches  |  %d/%d species  |  %d pts  |  %s" % [int(summary.total_catches),int(summary.discovered_species),int(summary.total_species),int(summary.fishing_points),str(summary.rank_name)]
