extends Control
class_name ResponsiveMenuSurface
## Read-only view of existing controller outputs. Selection, quotes, transactions
## and saves belong to the original menu. One tiled skin composes all sections.
const FONT = preload("res://assets/fonts/BOF_Font_Refined.fnt")
const MIN_FONT := 18
const ATLAS = preload("res://assets/ui/Panel.png")
const Portrait = preload("res://scripts/ui/portrait_ui.gd")
var controller: Node
var authored: Control
var kind: String
var scroll: ScrollContainer
var stack: VBoxContainer
var bindings: Array[Dictionary] = []
var originals: Dictionary = {}
var last_focus := ""
var drag_index := -1
var drag_y := 0.0
var _was_visible := false
var previews: Array[Dictionary] = []

static func attach(menu: Node, root_control: Control, menu_kind: String) -> ResponsiveMenuSurface:
	var existing := root_control.get_node_or_null("ResponsiveMenuSurface") as ResponsiveMenuSurface
	if existing != null: return existing
	var view := ResponsiveMenuSurface.new()
	view.name = "ResponsiveMenuSurface"
	view.controller = menu
	view.authored = root_control
	view.kind = menu_kind
	root_control.add_child(view)
	view._build()
	return view

func _build() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 500
	# Stay owned/visibility-bound to the menu without inheriting its obsolete
	# animated 640x480 root scale. New geometry is always canvas-local pixels.
	set_as_top_level(true)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 3500
	_mask_authored()
	scroll = ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack = VBoxContainer.new()
	stack.name = "Sections"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	scroll.add_child(stack)
	match kind:
		"economy": _economy()
		"crafting": _crafting()
		"card_maker": _card_maker()
		"inventory": _inventory()
	_sync()

func _mask_authored() -> void:
	# Some existing menus create feedback/transfer artwork lazily on first open.
	# Keep those outputs available to their controller, but never draw a second UI.
	for child in authored.get_children():
		if child == self or not child is CanvasItem: continue
		if not originals.has(child): originals[child] = child.modulate
		child.modulate = Color(1, 1, 1, 0)

func _section(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Portrait.panel_style())
	stack.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	if not title.is_empty(): _line(body, [], title)
	return body

func _line(parent: Node, paths: Array, fallback := "", selection := -1, group := "") -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", MIN_FONT)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("line_spacing", 3)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 28 if selection < 0 else 54
	parent.add_child(label)
	bindings.append({"label": label, "paths": paths, "fallback": fallback, "index": selection, "group": group})
	return label

func _preview(parent: Node, path: String, footprint := Vector2(116,132)) -> void:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = footprint
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(image)
	previews.append({"image":image, "path":path})

func _economy() -> void:
	var header := _section("MERCHANT / FISH TRADE")
	_line(header, [], "", -1, "mode")
	_line(header, ["WalletLabel", "CategoryLabel", "PageLabel"])
	var list := _section("ITEMS")
	for i in range(1, 6): _line(list, ["Rows/Row%dName" % i, "Rows/Row%dOwned" % i, "Rows/Row%dPrice" % i], "", i-1, "rows")
	var detail := _section("SELECTED ITEM / OWNED")
	_line(detail, ["InfoLabel", "MessageLabel"])
	_line(detail, ["TradeRequirementsPanel/Requirements"])
	_line(_section("ACTION"), [], "K: Buy / Sell / Trade    I: Back\nJ: Buy / Sell\nQ/E: Category    Left/Right: Page")
	_line(_section("CONFIRM"), ["ConfirmPanel/Prompt", "ConfirmPanel/Choice"], "", -1, "confirm")

func _crafting() -> void:
	_line(_section("LURE CRAFTING"), ["LiveRecipeNameLabel", "RecipeCounterLabel"])
	var detail := _section("RECIPE / MATERIALS")
	for path in ["Panel/RecipeLabel", "Panel/SlotsLabel", "Panel/CostLabel"]: _line(detail, [path])
	var preview := _section("RESULT / INVENTORY")
	for path in ["Panel/PreviewLabel", "Panel/ComparisonLabel", "Panel/InventoryLabel", "Panel/StatusLabel"]: _line(preview, [path])
	_line(_section("ACTION"), [], "K: Craft    I: Back    J: Customize\nUp/Down: Recipe or material\nLeft/Right: Material slot")

func _card_maker() -> void:
	_line(_section("CARD CRAFTING"), ["Panel/ZennyLabel"])
	var list := _section("CARDS")
	for i in range(1,6): _line(list, ["Panel/Rows/Row%dName" % i, "Panel/Rows/Row%dOwned" % i, "Panel/Rows/Row%dCost" % i], "", i-1, "rows")
	var detail := _section("SELECTED CARD")
	_preview(detail, "Panel/SelectedPreview")
	for path in ["SelectedNameLabel", "SelectedDescriptionLabel", "ModeLabel", "OwnedLabel", "RequirementLabel", "FeeValueLabel", "StatusLabel"]: _line(detail, ["Panel/" + path])
	_line(_section("ACTION"), [], "K: Create card    I: Back")
	_line(_section("CONFIRM"), ["ConfirmPanel/PromptLabel", "ConfirmPanel/ChoiceLabel"], "", -1, "confirm")

func _inventory() -> void:
	_line(_section("INVENTORY / FISHING"), [], "", -1, "inventory_header")
	var list := _section("ENTRIES")
	for i in range(12): _line(list, [], "", i, "inventory_rows")
	var detail := _section("SELECTED ENTRY")
	_preview(detail, "Root/EquipPage/GuidePanel/GuideIcon", Vector2(64,64))
	_line(detail, [], "", -1, "inventory_detail")
	_line(_section("ACTION"), [], "K: Confirm    I: Back\nWASD: Select    Q/E: Page")

func _inventory_outputs() -> Dictionary:
	var lists: Array = [controller.command_list, controller.equip_slot_list, controller.data_species_list, controller.help_list, controller.hints_list]
	var page: int = controller._page
	var source: ItemList = lists[mini(page, 4)]
	if page == 1 and controller._equip_focus == 1: source = controller.equip_accessory_list
	if controller.exit_confirm.visible: source = controller.exit_list
	var detail: String = ""
	match page:
		0: detail = controller.main_rod_label.text + "\n" + controller.main_lure_label.text + "\nRank: " + controller.rank_label.text + "\nPoints: " + controller.points_label.text + "\nTime: " + controller.time_label.text
		1: detail = controller.equip_guide_title_label.text + "\n" + controller.equip_guide_description_label.text
		2: detail = controller.data_detail_name_label.text + "\n" + controller.data_detail_effect_label.text + "\n" + controller.data_detail_guide_label.text + "\nAverage size: " + controller.data_detail_avg_label.text + "\nBest size: " + controller.data_size_label.text + "\nBest points: " + controller.data_points_label.text + "\nLocation: " + controller.data_point_label.text + "\nOwned: " + controller.data_caught_count_label.text
		3: detail = controller.help_text_label.text
		4: detail = controller.hints_text_label.text
		_: detail = controller.info_label.text
	var selected := source.get_selected_items()
	return {"list": source, "index": int(selected[0]) if not selected.is_empty() else 0, "detail": detail, "page": page}

func _process(_delta: float) -> void:
	if authored == null: return
	_mask_authored()
	if kind == "inventory": controller.selector_layer.modulate = Color(1, 1, 1, 0)
	position = Vector2(16,12)
	size = get_viewport().get_visible_rect().size - Vector2(32,24)
	_sync()

func _sync() -> void:
	if not authored.is_visible_in_tree():
		_was_visible = false
		return
	if not _was_visible:
		scroll.scroll_vertical = 0
		last_focus = ""
	_was_visible = true
	for preview in previews:
		var source := authored.get_node_or_null(preview.path) as TextureRect
		if kind == "inventory":
			source = controller.data_portrait if controller._page == 2 else controller.equip_guide_icon
		preview.image.texture = source.texture if source != null else null
		preview.image.visible = preview.image.texture != null
	var focus := ""
	var focused: Control
	var confirmation := authored.get_node_or_null("ConfirmPanel") as Control
	var confirming := confirmation != null and confirmation.visible
	for binding in bindings:
		var parts: PackedStringArray = []
		for path in binding.paths:
			var source := authored.get_node_or_null(path) as Label
			if source != null and not source.text.is_empty(): parts.append(source.text)
		var text := "\n".join(parts) if not parts.is_empty() else String(binding.fallback)
		var selected := false
		var index: int = binding.index
		match binding.group:
			"mode": text = ["BUY", "SELL", "FISH TRADE"][controller._mode]
			"rows":
				selected = index == int(controller.get("_row_index") if kind == "economy" else controller.get("_index"))
				text = "   ".join(parts)
			"confirm":
				binding.label.get_parent().get_parent().get_parent().visible = confirming
				selected = confirming
			"inventory_header": text = ["STATUS", "EQUIPMENT", "FISH DATA", "HELP", "HINTS", "OPTIONS"][controller._page]
			"inventory_rows":
				var output := _inventory_outputs()
				var start := maxi(0, int(output.index) - 5)
				var item := start + index
				text = output.list.get_item_text(item) if item < output.list.item_count else ""
				selected = item == output.index
			"inventory_detail": text = _inventory_outputs().detail
		# Bitmap atlas has no Unicode punctuation glyphs; only presentation changes.
		text = text.replace("\u2014", "-").replace("\u00d7", "x").replace("\u2192", "->")
		binding.label.text = ("> " if selected else "") + Portrait.hints(self, text)
		binding.label.visible = not text.is_empty()
		if selected and (not confirming or binding.group == "confirm"):
			focus = binding.group + str(index) + str(text)
			focused = binding.label
	if focus != last_focus and focused != null:
		last_focus = focus
		scroll.ensure_control_visible.call_deferred(focused)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x >= get_viewport().get_visible_rect().size.x - 64:
			drag_index = event.index
			drag_y = event.position.y
		elif not event.pressed and event.index == drag_index: drag_index = -1
	if event is InputEventScreenDrag and event.index == drag_index:
		scroll.scroll_vertical += roundi(drag_y-event.position.y)
		drag_y = event.position.y
		get_viewport().set_input_as_handled()

func restore_authored() -> void:
	for original in originals:
		if is_instance_valid(original): original.modulate = originals[original]
