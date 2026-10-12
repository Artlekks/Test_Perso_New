extends ScrollContainer
## Read-only companion projection of the existing equipment and journal services.
var host: Node
var equipment: Label
var records: Label
var _refresh := 0.0
func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(column)
	equipment = _section(column,"Equipment","Inventory")
	records = _section(column,"Fishing records","Journal")
func _section(column: VBoxContainer, title: String, page: String) -> Label:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",host.shell.skin(preload("res://assets/ui/seaside_shell/panel.png")))
	column.add_child(panel)
	var content := VBoxContainer.new(); panel.add_child(content)
	var toggle := Button.new(); toggle.text=title+"  -"; toggle.focus_mode=Control.FOCUS_NONE
	content.add_child(toggle)
	var body := Label.new()
	body.add_theme_color_override("font_color",Color("35202d"))
	body.add_theme_font_size_override("font_size",16)
	body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(body)
	var entry := Button.new(); entry.text="Open Equip" if page == "Inventory" else "Open Data"
	entry.focus_mode=Control.FOCUS_NONE; content.add_child(entry)
	for button in [toggle,entry]:
		for style in ["normal","hover","pressed"]: button.add_theme_stylebox_override(style,host.shell.skin(preload("res://assets/ui/seaside_shell/button.png"),6))
		button.add_theme_color_override("font_color",Color("fff0bd"))
		button.add_theme_font_size_override("font_size",14)
		button.custom_minimum_size.y=32
	entry.pressed.connect(func(): host.request_shell_menu(page))
	toggle.pressed.connect(func():
		body.visible=not body.visible; entry.visible=body.visible
		toggle.text=title+("  -" if body.visible else "  +"))
	return body
func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0 or not visible: return
	_refresh=0.5
	var state: Dictionary = host.shell.snapshot
	equipment.text="Rod: %s\nLure / bait: %s x%d\nOther equipment: see Equip" % [state.get("rod","Unavailable"),state.get("bait","Unavailable"),state.get("count",0)]
	var service := get_node_or_null("/root/FishingSessionServices")
	if service == null or service.journal_service == null:
		records.text="Records unavailable"; return
	var summary: Dictionary = service.journal_service.get_summary()
	records.text="%s\nLifetime catches: %d\nDiscovered species: %d / %d\nFishing points: %d\nRank: %s\nLocal species / best catches: open Data" % [state.get("spot",""),summary.total_catches,summary.discovered_species,summary.total_species,summary.fishing_points,summary.rank_name]


	var entries: Array[Dictionary] = service.journal_service.get_entries(false)
	if entries.is_empty(): records.text += "\nNo recorded catches yet."
	else:
		records.text += "\nRecorded species:"
		for entry in entries:
			records.text += "\n%s: %d caught, best size %.1f / %d points" % [entry.display_name,entry.caught_count,entry.best_size,entry.best_points]

