extends Control
class_name ResponsiveMenuSurface
## Read-only view of existing controller outputs. Selection, quotes, transactions
## and saves belong to the original menu. One tiled skin composes all sections.
const FONT = preload("res://assets/fonts/BOF_Font_Refined.fnt")
const MIN_FONT := 18
const ATLAS = preload("res://assets/ui/Panel.png")
const PanelStyle = preload("res://scripts/dialogue/dialogue_panel_style.gd")
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
		"deck": _deck()
	_sync()

func _mask_authored() -> void:
	# Some existing menus create feedback/transfer artwork lazily on first open.
	# Keep those outputs available to their controller, but never draw a second UI.
	for child in authored.get_children():
		if child == self or not child is CanvasItem or originals.has(child): continue
		originals[child] = child.modulate
		child.modulate = Color(1, 1, 1, 0)

func _section(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PanelStyle.create(ATLAS))
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

func _economy() -> void:
	var header := _section("MERCHANT / FISH TRADE")
	_line(header, [], "", -1, "mode")
	_line(header, ["WalletLabel", "CategoryLabel", "PageLabel"])
	var list := _section("ITEMS")
	for i in range(1, 6): _line(list, ["Rows/Row%dName" % i, "Rows/Row%dOwned" % i, "Rows/Row%dPrice" % i], "", i-1, "rows")
	var detail := _section("SELECTED ITEM / OWNED")
	_line(detail, ["InfoLabel", "MessageLabel"])
	_line(detail, ["TradeRequirementsPanel/Requirements"])
	_line(_section("ACTION"), [], "A: Buy / Sell / Trade    B: Back\nMENU: Buy / Sell\nL/R: Category    Left/Right: Page")
	_line(_section("CONFIRM"), ["ConfirmPanel/Prompt", "ConfirmPanel/Choice"], "", -1, "confirm")

func _crafting() -> void:
	_line(_section("LURE CRAFTING"), ["LiveRecipeNameLabel", "RecipeCounterLabel"])
	var detail := _section("RECIPE / MATERIALS")
	for path in ["Panel/RecipeLabel", "Panel/SlotsLabel", "Panel/CostLabel"]: _line(detail, [path])
	var preview := _section("RESULT / INVENTORY")
	for path in ["Panel/PreviewLabel", "Panel/ComparisonLabel", "Panel/InventoryLabel", "Panel/StatusLabel"]: _line(preview, [path])
	_line(_section("ACTION"), [], "A: Craft    B: Back    MENU: Customize\nUp/Down: Recipe or material\nLeft/Right: Material slot")

func _card_maker() -> void:
	_line(_section("CARD CRAFTING"), ["Panel/ZennyLabel"])
	var list := _section("CARDS")
	for i in range(1,6): _line(list, ["Panel/Rows/Row%dName" % i, "Panel/Rows/Row%dOwned" % i, "Panel/Rows/Row%dCost" % i], "", i-1, "rows")
	var detail := _section("SELECTED CARD")
	for path in ["SelectedNameLabel", "SelectedDescriptionLabel", "ModeLabel", "OwnedLabel", "RequirementLabel", "FeeValueLabel", "StatusLabel"]: _line(detail, ["Panel/" + path])
	_line(_section("ACTION"), [], "A: Create card    B: Back")
	_line(_section("CONFIRM"), ["ConfirmPanel/PromptLabel", "ConfirmPanel/ChoiceLabel"], "", -1, "confirm")

func _deck() -> void:
	controller.mobile_start_enabled = true
	_line(_section("TRIPLE TRIAD / DECK"), ["CurrentDeckLabel", "CurrentDeckCount", "BudgetLabel", "CardsOwnedLabel"])
	_line(_section("PLAY"), [], "", -1, "start")
	var profiles := _section("SAVED DECKS")
	_line(profiles, [], "New Deck", -1, "new_profile")
	for i in range(1,6): _line(profiles, ["DeckList/Deck%dName" % i, "DeckList/Deck%dCount" % i], "", i-1, "profiles")
	var deck := _section("SELECTED FIVE")
	for i in range(5): _line(deck, [], "", i, "deck")
	_line(_section("SORT / PAGE"), ["PageIndicator"], "", -1, "sort")
	var collection := _section("COLLECTION")
	for i in range(20): _line(collection, [], "", i, "collection")
	var detail := _section("SELECTED CARD")
	for path in ["DetailName", "DetailNumber", "DetailRarity", "DetailDescription", "DetailEffect", "StatusLabel"]: _line(detail, [path])
	_line(_section("ACTION"), [], "A: Add / Remove    B: Back\nSTART: Play valid deck    MENU: Sort\nL: Save deck    R: Delete deck")

func _process(_delta: float) -> void:
	if authored == null: return
	_mask_authored()
	position = Vector2(16,12) - authored.get_global_transform_with_canvas().origin
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
			"start":
				var ready: bool = controller._deck.size() == 5 and controller._deck_cost() <= controller._budget_limit
				text = "START : PLAY" if ready else "Choose 5 cards within the point budget"
			"new_profile": selected = controller._nav_zone == controller.NAV_PROFILES and controller._profile_nav_index < 0
			"profiles": selected = controller._nav_zone == controller.NAV_PROFILES and controller._profile_nav_index % 5 == index and controller._profile_nav_index >= 0
			"deck":
				text = "%d. Empty" % (index+1)
				if index < controller._deck.size(): text = "%d. %s" % [index+1, controller._deck[index].display_name]
				selected = controller._nav_zone == controller.NAV_DECK and controller._deck_cursor_index == index
			"collection":
				var card_index: int = controller._page_index * 20 + index
				text = ""
				if card_index < controller._cards.size():
					var card = controller._cards[card_index]
					text = "%s  (Cost %d)%s" % [card.display_name, card.deck_cost, "  [in deck]" if controller._deck_has_card(card) else ""]
				selected = controller._nav_zone == controller.NAV_COLLECTION and controller._cursor_index == card_index
			"sort":
				text = "Sort: %s   Page %s" % [controller._sort_cursor_label(), text]
				selected = controller._nav_zone == controller.NAV_SORT
		# Bitmap atlas has no Unicode punctuation glyphs; only presentation changes.
		text = text.replace("\u2014", "-").replace("\u00d7", "x").replace("\u2192", "->")
		binding.label.text = ("> " if selected else "") + text
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
	if kind == "deck" and is_instance_valid(controller): controller.mobile_start_enabled = false
