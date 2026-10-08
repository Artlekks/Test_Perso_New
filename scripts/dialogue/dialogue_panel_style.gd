extends RefCounted

## Panel.png is an authored tile atlas, not a complete stretchable background.
## Its first tile supplies four 8px corners; adjoining tiles supply 16px
## edge/fill repeats. Assemble once, then let StyleBoxTexture tile the center.
static func create(atlas: Texture2D) -> StyleBoxTexture:
	var source := atlas.get_image()
	var panel := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	source.convert(Image.FORMAT_RGBA8)
	for region in [
		[Rect2i(0, 0, 8, 8), Vector2i(0, 0)],
		[Rect2i(8, 0, 8, 8), Vector2i(24, 0)],
		[Rect2i(0, 8, 8, 8), Vector2i(0, 24)],
		[Rect2i(8, 8, 8, 8), Vector2i(24, 24)],
		[Rect2i(16, 0, 16, 8), Vector2i(8, 0)],
		[Rect2i(16, 8, 16, 8), Vector2i(8, 24)],
		[Rect2i(0, 16, 8, 16), Vector2i(0, 8)],
		[Rect2i(8, 16, 8, 16), Vector2i(24, 8)],
		[Rect2i(16, 16, 16, 16), Vector2i(8, 8)],
	]:
		panel.blit_rect(source, region[0], region[1])
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(panel)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 8.0)
		style.set_content_margin(side, 4.0)
	return style
