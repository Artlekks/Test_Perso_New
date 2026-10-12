extends Control
## Minimal, clickable desktop summary rows. Expanded pages remain owned by
## FishingMenu and are never duplicated by this presentation layer.
const INK := Color("563047")
const SEPARATOR := Color("aa9274")
var host: Node
var _equipment: Button
var _records: Button
var _equipment_summary: Label
var _records_summary: Label
var _elapsed := 0.0
var _equipment_expanded := false
var _records_expanded := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	_equipment = _make_banner("Equipment", "Inventory")
	_records = _make_banner("Fishing records", "Journal")
	_equipment_summary = _make_summary(_equipment)
	_records_summary = _make_summary(_records)
	resized.connect(_arrange)
	_arrange()

func _make_banner(caption: String, target: String) -> Button:
	var button := Button.new()
	button.name = target + "Banner"
	button.text = "      " + caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", ThemeDB.fallback_font)
	button.add_theme_font_size_override("font_size", 17)
	for kind in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(kind, INK)
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color.TRANSPARENT
	clear.set_content_margin_all(0.0)
	var hovered := clear.duplicate() as StyleBoxFlat
	hovered.bg_color = Color(0.34, 0.19, 0.28, 0.06)
	for kind in ["normal", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(kind, clear)
	button.add_theme_stylebox_override("hover", hovered)
	button.pressed.connect(_open.bind(target))
	add_child(button)
	return button

func _make_summary(parent: Button) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", ThemeDB.fallback_font)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", INK)
	label.clip_text = true
	parent.add_child(label)
	return label

func _arrange() -> void:
	if _equipment == null or _records == null: return
	var half := maxf(1.0, size.y * 0.5)
	for i in range(2):
		var button: Button = _equipment if i == 0 else _records
		var summary: Label = _equipment_summary if i == 0 else _records_summary
		button.position = Vector2(0.0, float(i) * half)
		button.size = Vector2(size.x, half)
		var compact := size.x < 570.0
		button.text = ("     " if compact else "      ") + ("Equipment" if i == 0 else "Fishing records")
		button.add_theme_font_size_override("font_size", 15 if compact else 17)
		if compact:
			summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			summary.position = Vector2(30.0, half * 0.49)
			summary.size = Vector2(maxf(1.0, size.x - 36.0), half * 0.45)
			summary.add_theme_font_size_override("font_size", 12)
		else:
			summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			summary.position = Vector2(size.x * 0.40, 1.0)
			summary.size = Vector2(maxf(1.0, size.x * 0.58 - 16.0), half - 2.0)
			summary.add_theme_font_size_override("font_size", 14)
	queue_redraw()

func _draw() -> void:
	# Exactly one understated divider between the two parchment rows.
	draw_line(Vector2(14.0, size.y * 0.5), Vector2(size.x - 14.0, size.y * 0.5), SEPARATOR, 1.0)
	for i in range(2):
		var y := size.y * (float(i) + 0.5) * 0.5
		var expanded: bool = _equipment_expanded if i == 0 else _records_expanded
		var points := PackedVector2Array([
			Vector2(14, y - 2), Vector2(19, y - 2), Vector2(16.5, y + 3)
		]) if expanded else PackedVector2Array([
			Vector2(14, y - 4), Vector2(19, y), Vector2(14, y + 4)
		])
		draw_colored_polygon(points, INK)

func _open(target: String) -> void:
	if not is_instance_valid(host): return
	var menu: FishingMenu = host._fishing_menu()
	if menu == null: return
	menu.open_desktop_page(FishingMenu.Page.EQUIP if target == "Inventory" else FishingMenu.Page.DATA)

func _process(delta: float) -> void:
	_elapsed -= delta
	if _elapsed > 0.0 or not visible or not is_instance_valid(host): return
	_elapsed = 0.35
	var menu: FishingMenu = host._fishing_menu()
	var page := menu._page if menu != null and menu.is_open() else -1
	_equipment_expanded = page == FishingMenu.Page.EQUIP
	_records_expanded = page == FishingMenu.Page.DATA
	queue_redraw()
	var state: Dictionary = host.shell.snapshot
	_equipment_summary.text = "%s  ·  %s x%d" % [str(state.get("rod", "Unavailable")), str(state.get("bait", "Unavailable")), int(state.get("count", 0))]
	var services := get_node_or_null("/root/FishingSessionServices")
	if services == null or services.journal_service == null:
		_records_summary.text = "Fishing records unavailable"
		return
	var summary: Dictionary = services.journal_service.get_summary()
	if size.x < 570.0:
		_records_summary.text = "%d catches  ·  %d/%d species  ·  %d pts" % [int(summary.total_catches), int(summary.discovered_species), int(summary.total_species), int(summary.fishing_points)]
	else:
		_records_summary.text = "%d catches  ·  %d/%d species  ·  %d pts  ·  %s" % [int(summary.total_catches), int(summary.discovered_species), int(summary.total_species), int(summary.fishing_points), str(summary.rank_name)]
