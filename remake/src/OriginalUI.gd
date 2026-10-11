extends RefCounted
## Renders the shipped LabInterface ("FiberTwig.li") and executes its
## interaction actions (ShowModal / HideModal / ChangeModal / SetProp /
## RunMethod) so the screen flow is literally the one authored for the
## original game.
##
## Text uses the original bitmap fonts: Arial12lat.png with the LATIN metrics
## and Arial12cyr.png with the RUSSIAN metrics from Arial12.xml.  Captions are
## kept byte-wise (CP1251 / CP1252) and indexed directly into the atlas, which
## is how the original font files are laid out.
##
## The Simplified Chinese localization cannot use that 12 px atlas, so its
## language file is UTF-8 and its captions are drawn with the bundled subset of
## Noto Sans SC (assets/fonts/NotoSansSC-UI.ttf) and wrapped per character.
## Strings outside the subset (say a name typed by the user) fall back to a
## system CJK font.

var nodes: Dictionary = {}
var children: Dictionary = {}
var metrics: Array = []          # active metric table (per character index)
var metrics_lat: Array = []
var metrics_cyr: Array = []
var atlas: Texture2D
var atlas_lat: Texture2D
var atlas_cyr: Texture2D
var lang := "enu"
var overrides: Dictionary = {}   # widget -> {property: value} from the lng file
var captions: Dictionary = {}    # runtime captions (game state)
var hidden: Dictionary = {}
var checked: Dictionary = {}
var props: Dictionary = {}       # runtime property overrides (Visible ...)
var tabs := {"WHelp": "TIntroductionWHelp"}
var level_tab := 0
var pics: Dictionary = {}        # widget -> runtime Picture override
var grid_items: Dictionary = {}  # grid widget -> Array[String] of rows
var grid_sel: Dictionary = {}    # grid widget -> selected row index
var grid_first: Dictionary = {}  # grid widget -> first visible row
var focus_edit := ""             # widget name of the focused TLabEdit
var edit_text := ""
var edit_caret := 0
var mouse := Vector2.ZERO
var pressed := ""
var hits: Array = []

## Localization: the .lng suffix is five times the internal language id of the
## original engine (enu 2 -> 10, deu 3 -> 15, ... rus 18 -> 90); the added
## Simplified Chinese entry therefore uses 105.
const LANGS := ["enu", "deu", "fra", "ptb", "rus", "chs"]
const LANG_SUFFIX := {"enu": "10", "deu": "15", "fra": "20", "ptb": "60", "rus": "90", "chs": "105"}
## Fallback captions for language entries the active .lng does not declare.  The
## five original names are localized by the shipped files themselves; the
## Chinese one is always its native name.
const LANG_NAMES := {"enu": "English", "deu": "German", "fra": "French",
	"ptb": "Portuguese", "rus": "Russian", "chs": "简体中文"}
const CJK_FONT_PATH := "res://assets/fonts/NotoSansSC-UI.ttf"
const CJK_FONT_SIZE := 14
const CJK_FONT_NAMES := ["Microsoft YaHei UI", "Microsoft YaHei",
	"Noto Sans CJK SC", "Noto Sans SC", "Source Han Sans SC", "PingFang SC",
	"Hiragino Sans GB", "WenQuanYi Micro Hei", "SimHei", "DengXian", "sans-serif"]
var cjk_font: Font = null
var _utf8_lang := false

func _init() -> void:
	_load_cjk_font()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/interface.json"))
	metrics_lat = data.metrics
	atlas_lat = AssetLib.texture("res://assets/game/Arial12lat.png")
	atlas_cyr = AssetLib.texture("res://assets/game/Arial12cyr.png")
	# Arial12.xml carries one metric table + atlas per charset (EASTEUROPE ->
	# Arial12lat.png, RUSSIAN -> Arial12cyr.png).
	for cs in data.get("charsets", []):
		if str(cs.get("charset", "")) == "RUSSIAN":
			if not cs.get("metrics", []).is_empty():
				metrics_cyr = cs["metrics"]
			var t := AssetLib.texture("res://assets/game/" + str(cs.get("picture", "")))
			if t != null:
				atlas_cyr = t
	if metrics_cyr.is_empty():
		metrics_cyr = metrics_lat
	_set_font(false)
	for n in data.nodes:
		nodes[n.Name] = n
		var parent: String = n.get("ParentName", "")
		if not children.has(parent): children[parent] = []
		children[parent].append(n.Name)
		checked[n.Name] = n.get("Checked", "False") == "True"
	# Runtime state of the reference session (assets/*.png).
	for name in ["RHammerWStartDialog", "RNormalWStartDialog", "RENUWLanguage", "RIntroductionWHelp"]:
		checked[name] = true
	for name in ["RRegistrationWHelp", "LCombDoneWGame", "LLiveCountWGame", "LDropAccelCounWGame", "LFiveMinutModeTime"]:
		hidden[name] = true

func _set_font(cyr: bool) -> void:
	atlas = atlas_cyr if cyr else atlas_lat
	metrics = metrics_cyr if cyr else metrics_lat

## The bitmap fonts of the original are indexed by the bytes of the CP1251 /
## CP1252 captions, so a legacy language file has its high bytes escaped as
## numeric character references (the parser then hands back U+0080..U+00FF and
## the byte index survives).  A UTF-8 file is parsed unchanged.
func _is_utf8(data: PackedByteArray) -> bool:
	var i := 0
	var wide := false
	while i < data.size():
		var b := data[i]
		if b < 0x80:
			i += 1
			continue
		wide = true
		var n := 0
		if b >= 0xC2 and b <= 0xDF:
			n = 1
		elif b >= 0xE0 and b <= 0xEF:
			n = 2
		elif b >= 0xF0 and b <= 0xF4:
			n = 3
		else:
			return false
		if i + n >= data.size():
			return false
		for k in range(1, n + 1):
			var c := data[i + k]
			if c < 0x80 or c > 0xBF:
				return false
		i += n + 1
	return wide

## Load a language file (lng/*.lng); it only overrides properties.
func apply_language(code: String) -> bool:
	var path := "res://assets/lng/%s_%s.lng" % [code, _lang_suffix(code)]
	if not FileAccess.file_exists(path):
		return false
	lang = code
	_set_font(code == "rus")
	overrides.clear()
	var raw := FileAccess.get_file_as_bytes(path)
	_utf8_lang = _is_utf8(raw)
	var safe := PackedByteArray()
	if _utf8_lang:
		safe = raw
	else:
		for b in raw:
			if b < 0x80:
				safe.append(b)
			else:
				for c in ("&#%d;" % b).to_utf8_buffer():
					safe.append(c)
	var parser := XMLParser.new()
	if parser.open_buffer(safe) != OK:
		return false
	var curname := ""
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := parser.get_node_name()
				if tag == "o":
					var cls := ""
					for i in parser.get_attribute_count():
						if parser.get_attribute_name(i) == "c":
							cls = parser.get_attribute_value(i)
					curname = ""
					_cur_class = cls
				elif tag == "p":
					var key := ""
					for i in parser.get_attribute_count():
						if parser.get_attribute_name(i) == "n":
							key = parser.get_attribute_value(i)
					_pending_key = key
			XMLParser.NODE_TEXT:
				if _pending_key == "Name":
					curname = parser.get_node_data().strip_edges()
					if curname != "" and not nodes.has(curname) and _cur_class != "":
						_add_widget(curname, _cur_class)
				elif curname != "":
					if not overrides.has(curname):
						overrides[curname] = {}
					overrides[curname][_pending_key] = _decode(parser.get_node_data())
					if _pending_key == "Caption" and nodes.has(curname):
						pass
				_pending_key = ""
			XMLParser.NODE_ELEMENT_END:
				_pending_key = ""
	_ensure_language_widgets()
	return true

var _pending_key := ""
var _cur_class := ""

func _lang_suffix(code: String) -> String:
	return str(LANG_SUFFIX.get(code, "10"))

## The language dialog must offer every language even when the active .lng does
## not declare all entries (the shipped files rely on the widgets added by the
## previously loaded one).  Any missing radio button is cloned from its
## siblings; the list is kept in LANGS order so it does not depend on which
## language was loaded first.
func _ensure_language_widgets() -> void:
	var parent := "WLanguage"
	var langs: Array = []
	for code in LANGS:
		var name := "R%sWLanguage" % code.to_upper()
		langs.append(name)
		if not nodes.has(name):
			_add_widget(name, "TLabRadioButton")
			nodes[name]["Caption"] = str(LANG_NAMES.get(code, code))
	var order: Array = langs.duplicate()
	for child in children.get(parent, []):
		if not order.has(child):
			order.append(child)
	children[parent] = order
	for i in langs.size():
		var name: String = langs[i]
		# The radio buttons are cloned from a sibling, so a language the active
		# .lng does not declare (Chinese in all the others) would otherwise show
		# the sibling's caption after a language switch; keep the fallback name.
		if not (overrides.has(name) and overrides[name].has("Caption")):
			nodes[name]["Caption"] = str(LANG_NAMES.get(LANGS[i], name))
		nodes[name]["Left"] = 40
		nodes[name]["Top"] = 32 + i * 30
		nodes[name]["Width"] = 160
		nodes[name]["Height"] = 20

## The bundled font (a Noto Sans SC subset) draws the Chinese captions; a
## system CJK font covers characters outside the subset.
func _load_cjk_font() -> void:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(CJK_FONT_NAMES)
	sys.allow_system_fallback = true
	var file := FontFile.new()
	if file.load_dynamic_font(CJK_FONT_PATH) == OK:
		var fallbacks: Array[Font] = [sys]
		file.fallbacks = fallbacks
		cjk_font = file
	else:
		cjk_font = sys

## The language files may add widgets that the base .li does not contain
## (the five language radio buttons).  They are created with the class
## defaults and stacked below the first one.
func _add_widget(name: String, cls: String) -> void:
	# The original clones the first sibling of the same class (that is why its
	# language dialog lists the first language's name several times).
	var parent := "WLanguage"
	var base: Dictionary = {}
	# The language files even declare the extra language entries as TLabButton
	# (the shipped enu_10.lng does), so clone the sibling with the same name
	# suffix (R<lang><rest>) instead of trusting the declared class.
	var suffix := name
	var re := RegEx.new()
	re.compile("^R[A-Z]{3}(.*)$")
	var m := re.search(name)
	if m != null:
		suffix = m.get_string(1)
	for sib in children.get(parent, []):
		var cand: Dictionary = nodes[sib]
		if sib == name:
			continue
		var cm := re.search(str(cand.Name))
		if m != null and cm != null and cm.get_string(1) == suffix:
			base = cand.duplicate()
			break
	if base.is_empty():
		for sib in children.get(parent, []):
			if nodes[sib].Class == cls:
				base = (nodes[sib] as Dictionary).duplicate()
				break
	if base.is_empty():
		for n in nodes.values():
			if n.Class == cls:
				base = (n as Dictionary).duplicate()
				break
	base["Name"] = name
	base["ParentName"] = parent
	nodes[name] = base
	if not children.has(parent):
		children[parent] = []
	children[parent].append(name)
	checked[name] = false
	# measured from assets/Options-Language.png: the created entries start
	# below RENUWLanguage (Top=32 in the .li) with a 30 px pitch.
	var count := 0
	for sib in children[parent]:
		if nodes[sib].Class == "TLabRadioButton":
			count += 1
	base["Left"] = 40
	base["Top"] = 32 + (count - 1) * 30
	base["Width"] = 160
	base["Height"] = 20

## CP1251/CP1252 bytes -> one codepoint per byte, so the atlas index works.
## (High bytes arrive as U+0080..U+00FF from the numeric character references.)
## A UTF-8 language file has already the final codepoints.
func _decode(raw: String) -> String:
	if _utf8_lang:
		return raw
	var out := ""
	for i in raw.length():
		out += char(raw.unicode_at(i) & 0xFF)
	return out

## Value of a widget property honouring language overrides and runtime state.
func prop(name: String, key: String, default_value: Variant) -> Variant:
	if overrides.has(name) and overrides[name].has(key):
		return overrides[name][key]
	if key == "Picture" and pics.has(name):
		return pics[name]
	if key == "Caption" and captions.has(name):
		return captions[name]
	var n: Variant = nodes.get(name)
	if n != null and n.has(key):
		return n[key]
	return default_value

func color_bgr(value: String) -> Color:
	var n := int(value)
	return Color8(n & 255, (n >> 8) & 255, (n >> 16) & 255)

## True for strings the bitmap atlas cannot draw (anything above U+00FF, and
## every caption while the Chinese localization is active).
func use_cjk(s: String) -> bool:
	if cjk_font == null:
		return false
	if lang == "chs":
		return true
	for i in s.length():
		if s.unicode_at(i) > 0xFF:
			return true
	return false

func text_width(s: String) -> float:
	if use_cjk(s):
		return cjk_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, CJK_FONT_SIZE).x
	var w := 0.0
	for i in s.length():
		var c := s.unicode_at(i) - 32
		if c >= 0 and c + 1 < metrics.size(): w += float(metrics[c + 1]) - float(metrics[c])
	return w

func draw_text(o: CanvasItem, s: String, pos: Vector2, color := Color.BLACK) -> void:
	if use_cjk(s):
		# Centre the font's line box on the 18 px line grid of the bitmap font.
		var baseline := pos.y + (18.0 - cjk_font.get_height(CJK_FONT_SIZE)) * 0.5
		baseline += cjk_font.get_ascent(CJK_FONT_SIZE)
		o.draw_string(cjk_font, Vector2(pos.x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, CJK_FONT_SIZE, color)
		return
	var x := pos.x
	for i in s.length():
		var c := s.unicode_at(i) - 32
		if c < 0 or c + 1 >= metrics.size(): continue
		var w := float(metrics[c + 1]) - float(metrics[c])
		if w > 0:
			o.draw_texture_rect_region(atlas, Rect2(x, pos.y, w, 18), Rect2(float(metrics[c]), 0, w, 18), color)
		x += w

func wrapped(s: String, width: float) -> Array[String]:
	var re := RegEx.new()
	re.compile(" {10,}")
	s = re.sub(s, "\n\n", true)
	var lines: Array[String] = []
	for paragraph in s.split("\n"):
		lines.append_array(_wrap_paragraph(paragraph, width))
	return lines

## Word wrap that can also break inside a word: the Chinese text has no spaces
## between words, so a paragraph is a single "word" there.
func _wrap_paragraph(p: String, width: float) -> Array[String]:
	var lines: Array[String] = []
	var line := ""
	for word in p.split(" ", false):
		var sep := "" if line.is_empty() else " "
		if text_width(line + sep + word) <= width:
			line += sep + word
			continue
		if not line.is_empty():
			lines.append(line)
			line = ""
		# The word starts a new line; break it by character when it does not
		# fit on its own (Chinese text has no spaces to break at).
		var chunk := ""
		for i in word.length():
			var ch := word[i]
			if not chunk.is_empty() and text_width(chunk + ch) > width:
				lines.append(chunk)
				chunk = ""
			chunk += ch
		line = chunk
	if not line.is_empty() or lines.is_empty():
		lines.append(line)
	return lines

func begin_frame(pos: Vector2) -> void:
	mouse = pos
	hits.clear()

func draw_form(o: CanvasItem, name: String, interactive := true) -> void:
	if not nodes.has(name): return
	_draw_node(o, name, Vector2.ZERO, interactive)

## Forms are shown/hidden by the modal stack, so the editor time Visible
## property of the .li is ignored; SetProp and the language files override it.
func _visible(name: String) -> bool:
	if hidden.get(name, false):
		return false
	if props.has(name):
		return bool(props[name])
	if overrides.has(name) and overrides[name].has("Visible"):
		return str(overrides[name]["Visible"]) == "True"
	return true

func _is_tab_visible(name: String) -> bool:
	# TLevelN (1 based) belongs to LevelN.txt, i.e. to level_index N.
	if name.begins_with("TLevel"):
		return name == "TLevel%dWBetweenLevelMenu" % level_tab
	if name.ends_with("WHelp"):
		return tabs.get("WHelp", "") == name
	return true

func _draw_node(o: CanvasItem, name: String, origin: Vector2, interactive: bool, root := false) -> void:
	if not _visible(name): return
	var n: Dictionary = nodes[name]
	var cls: String = n.Class
	if cls == "TLabTabForm" and not _is_tab_visible(name): return
	var pos := origin + Vector2(float(prop(name, "Left", 0)), float(prop(name, "Top", 0)))
	var size := Vector2(float(prop(name, "Width", 0)), float(prop(name, "Height", 0)))
	var rect := Rect2(pos, size)
	var over := interactive and rect.has_point(mouse)
	var picnames: PackedStringArray = str(prop(name, "Picture", "")).split(";", true)
	var index := 0
	if cls == "TLabButton" and over: index = 2 if pressed == name else 1
	elif cls in ["TLabRadioButton", "TLabCheckBox"] and checked.get(name, false): index = 1
	var tex: Texture2D = null
	if index < picnames.size() and not picnames[index].is_empty():
		tex = AssetLib.texture("res://assets/game/" + picnames[index])
	if tex:
		o.draw_texture(tex, pos)
	if cls in ["TLabButton", "TLabRadioButton", "TLabCheckBox", "TLabGrid", "TLabEdit"] and interactive:
		hits.append({"name": name, "rect": rect})
	if cls == "TLabGrid":
		_draw_grid(o, name, pos, size)
	var caption: String = str(prop(name, "Caption", ""))
	if cls == "TLabEdit":
		caption = edit_text
	if not caption.is_empty():
		# TLabEdit uses Color for the box, its text is always dark.
		var c := Color.BLACK if cls == "TLabEdit" else color_bgr(str(prop(name, "Color", "0")))
		if over: c = color_bgr(str(prop(name, "ColorOnMMove", prop(name, "Color", "0"))))
		if cls == "TLabRadioButton" and checked.get(name, false): c = color_bgr(str(prop(name, "ColorOnChecked", "0")))
		var shift := Vector2(float(prop(name, "TShiftX", 0)), float(prop(name, "TShiftY", 0)))
		# A radio/checkbox glyph (picture[0]) sits directly left of the caption.
		if cls in ["TLabRadioButton", "TLabCheckBox"] and not picnames.is_empty() and not picnames[0].is_empty():
			var glyph := AssetLib.texture("res://assets/game/" + picnames[0])
			shift.x = (glyph.get_width() + 4.0) if glyph != null else shift.x
		if pressed == name and over:
			shift += Vector2(float(prop(name, "DShiftX", 0)), float(prop(name, "DShiftY", 0)))
		var lines := wrapped(caption, maxf(size.x - shift.x, 20.0))
		var y := pos.y + shift.y
		match str(prop(name, "Layout", "tlCenter")):
			"tlCenter": y += (size.y - lines.size() * 18) / 2
			"tlBottom": y += size.y - lines.size() * 18
		for line in lines:
			var x := pos.x + shift.x
			match str(prop(name, "Alignment", "taLeft")):
				"taCenter": x += (size.x - text_width(line)) / 2
				"taRight": x += size.x - text_width(line)
			draw_text(o, line, Vector2(x, y), c)
			y += 18
		if cls == "TLabEdit" and focus_edit == name:
			var cx := pos.x + shift.x + text_width(edit_text.substr(0, edit_caret))
			var caret: Texture2D = null
			var cpics: PackedStringArray = str(prop(name, "Picture", "")).split(";", true)
			if cpics.size() > 1 and not cpics[1].is_empty():
				caret = AssetLib.texture("res://assets/game/" + cpics[1])
			var cy := pos.y + shift.y
			if caret != null:
				o.draw_texture(caret, Vector2(cx, cy))
			else:
				o.draw_rect(Rect2(cx, cy, 1, 18), Color.BLACK, true)
	for child in children.get(name, []):
		_draw_node(o, child, pos, interactive)

## TLabGrid rows: RowHeight pixel cells, the selected one filled with
## CursorColor, item text at (ColTShiftX, ColTShiftY) inside the cell.
func _draw_grid(o: CanvasItem, name: String, pos: Vector2, size: Vector2) -> void:
	var items: Array = grid_items.get(name, [])
	if items.is_empty():
		return
	var row_h := float(prop(name, "RowHeight", 20))
	var first := int(grid_first.get(name, 0))
	var sel := int(grid_sel.get(name, -1))
	var rows := int(floor(size.y / row_h))
	var tx := float(prop(name, "ColTShiftX", 4))
	var ty := float(prop(name, "ColTShiftY", 2))
	if str(prop(name, "ColLayout", "tlCenter")) == "tlCenter":
		ty += (row_h - 18.0) / 2.0
	var cc := color_bgr(str(prop(name, "ColColor", "0")))
	var cursor := color_bgr(str(prop(name, "CursorColor", "12632256")))
	for i in rows:
		var idx := first + i
		if idx >= items.size():
			break
		var y := pos.y + i * row_h
		if idx == sel:
			o.draw_rect(Rect2(pos.x, pos.y + i * row_h, size.x, row_h), cursor, true)
		draw_text(o, str(items[idx]), Vector2(pos.x + tx, y + ty), cc)

func hit(pos: Vector2) -> String:
	for i in range(hits.size() - 1, -1, -1):
		if hits[i].rect.has_point(pos): return hits[i].name
	return ""

## Ordered OnMouseUp/OnMouseDown actions of a widget.
func actions(name: String, phase: String) -> Array:
	var out: Array = []
	if actions_live.has(name):
		for a in actions_live[name]:
			out.append(a)
	var n: Variant = nodes.get(name)
	if n == null: return out
	var key := "OnMouseDown" if phase == "down" else "OnMouseUp"
	if n.has(key):
		for a in n[key]:
			if not out.has(a): out.append(a)
	return out

var actions_live: Dictionary = {}   # extra actions registered at runtime

func select_radio(name: String) -> void:
	var n: Dictionary = nodes.get(name, {})
	for sibling in children.get(str(n.get("ParentName", "")), []):
		var other: Dictionary = nodes[sibling]
		if other.Class == "TLabRadioButton" and other.get("RadioGroup", "") == n.get("RadioGroup", ""):
			checked[sibling] = sibling == name

func edit_insert(s: String) -> void:
	edit_text = edit_text.substr(0, edit_caret) + s + edit_text.substr(edit_caret)
	edit_caret += s.length()

func edit_backspace() -> void:
	if edit_caret > 0:
		edit_text = edit_text.substr(0, edit_caret - 1) + edit_text.substr(edit_caret)
		edit_caret -= 1
