class_name UiTheme
extends Object
## HUD v2 look (ART_BIBLE section 11): SIL-OFL pixel fonts at their crisp sizes,
## 9-slice pixel frames in the player-accent teal, parchment text with an ink
## outline. Set on the HUD and inventory roots; Label3Ds call label3d().
##
## Crisp sizes were measured (other sizes grey the glyph edges):
##   Pixelify Sans   20 / 40 / 60 px  (1/20 em grid)   body, keys, numbers
##   Jacquard 24     43 / 86 px                        titles, boss + place names
## Pixel rendering is set on the FontFile at runtime: the same options in the
## .import file crash Godot 4.6.3's headless font reimport.

const BODY_PATH := "res://assets/fonts/PixelifySans.ttf"
const TITLE_PATH := "res://assets/fonts/Jacquard24-Regular.ttf"
const UI_DIR := "res://assets/ui/"
const BODY := 20
const BIG := 40
const HUGE := 60
## Titles use Pixelify at its 40 px crisp size (user, 2026-09-24: the
## Jacquard blackletter was unreadable everywhere, not only on world labels).
const TITLE := 40
const TEXT := Color("#EDE6D6")
const MUTED := Color("#A9A2B4")
const INK := Color("#0B0810")
const OUTLINE := 4

static var _theme: Theme
static var _fonts: Dictionary = {}


## Shared pixel font. `title` is kept for the callers but resolves to the
## same Pixelify Sans: Jacquard 24 (TITLE_PATH) is retired as unreadable.
static func font(_title: bool = false) -> FontFile:
	var path := BODY_PATH
	if not _fonts.has(path):
		var f: FontFile = load(path) if ResourceLoader.exists(path) else null
		if f != null:
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			f.hinting = TextServer.HINTING_NONE
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			f.generate_mipmaps = false
		_fonts[path] = f
	return _fonts[path]


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var body := font()
	if body != null:
		t.default_font = body
	t.default_font_size = BODY
	for type: String in ["Label", "Button", "RichTextLabel", "LineEdit", "ItemList"]:
		t.set_color("font_color", type, TEXT)
		t.set_color("font_outline_color", type, INK)
		t.set_constant("outline_size", type, OUTLINE)
	t.set_color("font_hover_color", "Button", ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")))
	t.set_color("font_pressed_color", "Button", ArtKit.color("color_roles.player_accent.body", Color("#3CBEB4")))
	t.set_color("font_disabled_color", "Button", MUTED)
	var frame := nine("frame.png", 16, 12)
	t.set_stylebox("panel", "Panel", frame)
	t.set_stylebox("panel", "PanelContainer", frame)
	t.set_stylebox("normal", "Button", nine("button.png", 16, 8))
	t.set_stylebox("hover", "Button", nine("button_hover.png", 16, 8))
	t.set_stylebox("pressed", "Button", nine("button_pressed.png", 16, 8))
	t.set_stylebox("disabled", "Button", nine("button_pressed.png", 16, 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "ItemList", nine("slot.png", 12, 8))
	_theme = t
	return t


## Pixel-art 9-slice from the UI kit (art is saved at 2x, drawn 1:1).
static func nine(file: String, margin: int, content: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	var path := UI_DIR + file
	if ResourceLoader.exists(path):
		sb.texture = load(path)
	sb.texture_margin_left = margin
	sb.texture_margin_top = margin
	sb.texture_margin_right = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = content
	sb.content_margin_top = content
	sb.content_margin_right = content
	sb.content_margin_bottom = content
	return sb


## Apply to a UI root: theme, and nearest filtering for the pixel textures.
static func apply(root: Control) -> void:
	root.theme = theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## World label (plates, loot, portals, damage numbers) in the UI font, drawn at
## a FIXED screen size with one font pixel per screen pixel. A pixel font
## scaled by distance drops glyph pixels and turns unreadable, so labels keep
## their anchor in the world but not a world size.
## The "X" in a window's top-right corner (user, 2026-09-24: every window
## closes by button too, not only by its key or Esc).
static func close_button(on_close: Callable) -> Button:
	var btn := Button.new()
	btn.text = "X"
	btn.custom_minimum_size = Vector2(44, 44)
	btn.add_theme_font_size_override("font_size", BODY)
	btn.add_theme_color_override("font_color", Color("#E08A7A"))
	btn.tooltip_text = "Close (Esc)"
	btn.pressed.connect(on_close)
	return btn


static func label3d(label: Label3D, crisp_size: int = BODY, title: bool = false) -> void:
	var f := font(title)
	if f == null:
		return
	label.font = f
	label.font_size = crisp_size
	label.fixed_size = true
	label.pixel_size = 1.0 / screen_px_per_m()
	label.outline_size = OUTLINE
	label.outline_modulate = INK
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST


## Screen pixels per metre at 1 m from the current 3D camera (fixed_size
## Label3Ds are drawn as if 1 m away): 900 px / (2 tan(68 deg / 2)) = 667.
static func screen_px_per_m() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return 667.2
	var cam := tree.root.get_camera_3d()
	var fov := cam.fov if cam != null else 68.0
	var height := float(tree.root.get_visible_rect().size.y)
	return height / (2.0 * tan(deg_to_rad(fov) * 0.5)) if height > 0.0 else 667.2


## Shutdown hygiene (GameFeel._exit_tree).
static func clear() -> void:
	_item_icons.clear()
	_theme = null
	_fonts.clear()


static var _item_icons: Dictionary = {}


## Inventory icon (tools/texgen/ui.py): a legendary's own art, else its slot's.
static func item_icon(item: ItemData) -> Texture2D:
	var key: String = String(item.legendary_id) if item.legendary_id != &"" else ["weapon", "armor", "relic", "helm", "gloves", "boots", "ring"][item.slot]
	if not _item_icons.has(key):
		var path := UI_DIR + "items/%s.png" % key
		if not ResourceLoader.exists(path):  # legendaries without own art use their slot's
			path = UI_DIR + "items/%s.png" % ["weapon", "armor", "relic", "helm", "gloves", "boots", "ring"][item.slot]
		_item_icons[key] = load(path) if ResourceLoader.exists(path) else null
	return _item_icons[key]
