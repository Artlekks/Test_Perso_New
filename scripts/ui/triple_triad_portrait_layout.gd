extends RefCounted
## Geometry shared by native and Web. Card values/portraits retain native pixels.
const UI = preload("res://scripts/ui/portrait_ui.gd")

static func place(root: Node, path: String, x: float, y: float, w: float, h: float) -> void:
	UI.rect(root.get_node(path), Rect2(x, y, w, h))

static func battle(root: Control) -> void:
	UI.typography(root)
	place(root, "OpponentHand", 12, 100, 116, 692)
	place(root, "PlayerHand", 512, 100, 116, 692)
	place(root, "Board", 142, 225, 356, 404)
	root.get_node("Board").add_theme_constant_override("h_separation", 4)
	root.get_node("Board").add_theme_constant_override("v_separation", 4)
	place(root, "ResultLabel", 16, 350, 608, 100)
	UI.panel(root, "PortraitBackdrop", Rect2(0, 0, 640, 864))
	# CardView deliberately draws nothing for empty slots. The board structure
	# is independent of card artwork and remains readable before placement.
	for i in range(9):
		var cell := UI.panel(root, "BoardSlot%d" % i, Rect2(142 + (i % 3) * 120, 225 + floori(i / 3.0) * 136, 116, 132))
		cell.z_index = 1
	root.get_node("Board").z_index = 2

static func hud(root: Control) -> void:
	UI.typography(root)
	UI.panel(root, "HeaderPanel", Rect2(8, 8, 624, 80))
	UI.panel(root, "ContextPanel", Rect2(138, 640, 364, 152))
	UI.panel(root, "ActionsPanel", Rect2(8, 804, 624, 52))
	place(root, "OpponentName", 16, 16, 116, 28)
	place(root, "PlayerName", 508, 16, 116, 28)
	place(root, "RoundStatus", 200, 14, 240, 28)
	place(root, "TurnStatus", 164, 46, 312, 30)
	place(root, "TopInfo", 148, 100, 344, 100)
	root.get_node("TopInfo").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	place(root, "OpponentScoreAnchor", 54, 48, 32, 32)
	place(root, "PlayerScoreAnchor", 550, 48, 32, 32)
	for path in ["OpponentScoreAnchor/Digits", "PlayerScoreAnchor/Digits"]:
		root.get_node(path).scale = Vector2(2, 2)
	place(root, "CardName", 148, 650, 344, 30)
	place(root, "CardDescription", 148, 686, 290, 98)
	place(root, "InfluencePattern", 448, 728, 43, 43)
	root.get_node("InfoCard").hide()
	for i in range(5):
		var path := "Hotkey%d" % (i + 1)
		place(root, path, 18 + i * 122, 810, 116, 40)
		place(root, path + "/Key", 0, 0, 116, 20)
		place(root, path + "/Action", 0, 20, 116, 20)

static func deck(root: Control) -> void:
	UI.typography(root)
	root.get_node("Backdrop").hide()
	root.get_node("FooterHints").hide()
	UI.panel(root, "PortraitBackdrop", Rect2(0, 0, 640, 864))
	place(root, "CurrentDeckLabel", 14, 12, 260, 28)
	place(root, "CurrentDeckCount", 276, 12, 70, 28)
	root.get_node("CurrentDeckLabel").show()
	root.get_node("CurrentDeckCount").show()
	place(root, "CardsOwnedLabel", 354, 12, 272, 28)
	place(root, "BudgetLabel", 14, 46, 612, 30)
	place(root, "DeckRoot", 14, 96, 604, 132)
	place(root, "DeckList", 14, 250, 612, 62)
	for i in range(5):
		place(root, "DeckList/Deck%dName" % (i + 1), i * 108 + 12, 0, 92, 28)
		place(root, "DeckList/Deck%dCount" % (i + 1), i * 108 + 12, 28, 92, 28)
		place(root, "DeckList/Deck%dButton" % (i + 1), i * 108, 0, 106, 60)
	place(root, "DeckList/NewDeckLabel", 552, 0, 60, 60)
	root.get_node("DeckList/NewDeckLabel").text = "New\nDeck"
	place(root, "DeckList/NewDeckButton", 540, 0, 72, 60)
	place(root, "SortBar", 14, 322, 360, 32)
	for i in range(3):
		place(root, "SortBar/" + ["Rank", "Number", "Name"][i], i * 122, 0, 108, 32)
		root.get_node("SortBar/" + ["RankArrow", "NumberArrow", "NameArrow"][i]).position = Vector2(i * 122 + 100, 16)
	place(root, "PageIndicator", 392, 322, 234, 32)
	place(root, "CollectionRoot", 14, 370, 604, 272)
	place(root, "DetailCard", 14, 662, 116, 132)
	# Context is scrollable instead of shrinking lengthy card descriptions.
	var scroll := ScrollContainer.new()
	scroll.name = "PortraitDetails"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	UI.rect(scroll, Rect2(142, 662, 484, 132))
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	for path in ["DetailName", "DetailNumber", "DetailRarity", "DetailDescription", "DetailEffect"]:
		var label := root.get_node(path) as Label
		label.reparent(body)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.y = 24
	place(root, "StatusLabel", 14, 798, 612, 28)
	var hint := Label.new()
	hint.name = "PortraitActions"
	hint.text = UI.hints(root, "K: Select / Replace   I: Back   ENTER: Play")
	root.add_child(hint)
	UI.typography(hint)
	UI.rect(hint, Rect2(14, 830, 612, 28))

static func result(root: Control) -> void:
	UI.typography(root)
	root.get_node("Backdrop").hide()
	root.get_node("FooterHints").hide()
	UI.panel(root, "PortraitBackdrop", Rect2(0, 0, 640, 864))
	place(root, "PromptPanel", 14, 16, 612, 88)
	place(root, "PromptPanel/PromptLabel", 12, 8, 588, 72)
	root.get_node("PromptPanel/PromptLabel").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	place(root, "OpponentRowRoot", 14, 130, 604, 132)
	place(root, "PlayerRowRoot", 14, 580, 604, 132)
	place(root, "InfoPanel", 14, 730, 612, 62)
	place(root, "InfoPanel/InfoLabel", 12, 4, 588, 54)
	root.get_node("InfoPanel/InfoLabel").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	place(root, "HelpLabel", 14, 806, 612, 42)
