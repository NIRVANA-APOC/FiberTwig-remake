extends RefCounted

## Parses Fiber Twig level files (reverse engineered "Lab" XML format) and the
## original binary lookup tables (Squares_Frags.dat / Squares_Points.dat).

# Joint bits used by the twig ("fishka") type bitmask.
const UP := 1
const RIGHT := 2
const DOWN := 4
const LEFT := 8

const CELL := 40

# type index -> shape name, from Squares_FishkasTypes.dat
const TYPE_NAMES := {
	1: "1", 2: "2", 3: "12", 4: "3", 5: "13", 6: "23", 7: "123",
	8: "4", 9: "14", 10: "24", 11: "124", 12: "34", 13: "134",
	14: "234", 15: "1234",
}

# Bonus kind indexes (BonusTypes.dat order).
const BONUS_CLEAR_STECK := 0
const BONUS_HAMMERS := 1
const BONUS_CAPS := 2
const BONUS_SCORE := 3
const BONUS_SPEED_UP := 4
const BONUS_ALL_BONUS := 5
const BONUS_TIME_CONTROL := 6

static var _frag_to_cell := {}
static var _tables_ready := false

static func ensure_tables() -> void:
	if _tables_ready:
		return
	var frags := FileAccess.get_file_as_bytes("res://assets/data/Squares_Frags.dat")
	var pts := FileAccess.get_file_as_bytes("res://assets/data/Squares_Points.dat")
	var n_points := pts.size() / 4
	var n := frags.size() / 22
	for i in n:
		var idx := frags.decode_u16(i * 22 + 2)
		if idx >= n_points:
			continue
		var v := pts.decode_u32(idx * 4)
		var x := v & 0xffff
		var y := v >> 16
		_frag_to_cell[i] = Vector2i(int(round((x - 5) / float(CELL))), int(round(y / float(CELL))))
	_tables_ready = true

static func frag_cell(frag: int) -> Vector2i:
	ensure_tables()
	return _frag_to_cell.get(frag, Vector2i(-999, -999))

## GhostFishka x/y use a different lattice anchor than the frag table.
static func ghost_cell(x: int, y: int) -> Vector2i:
	return Vector2i(int(round((x - 25) / float(CELL))), int(round((y - 20) / float(CELL))))

## Top-left pixel of a cell's artwork in the original world coordinate system.
## Measured from assets/Game-*.png: the twig artwork sits at (40*col + 5, 40*row),
## which is exactly the grid stored in Squares_Points.dat (x = 5 + 40*c, y = 40*r).
static func cell_origin(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + 5, c.y * CELL)

static func rotate_cw(t: int) -> int:
	return ((t << 1) | (t >> 3)) & 0xF

static func rotate_ccw(t: int) -> int:
	return ((t >> 1) | ((t & 1) << 3)) & 0xF

static func type_name(t: int) -> String:
	return TYPE_NAMES.get(t, "0")

## Reverse of TYPE_NAMES: the shape name used by FishkaProb entries.
static func type_from_name(name: String) -> int:
	for k in TYPE_NAMES:
		if TYPE_NAMES[k] == name:
			return k
	return 1

static func type_texture(t: int) -> Texture2D:
	return AssetLib.texture("res://assets/squares/%s_1.png" % type_name(t))

# ---------------------------------------------------------------------------
# Complex (multi cell) fishkas
# ---------------------------------------------------------------------------
# FishkaProb may ask for a piece that covers several cells.  The name encodes
# the connection mask of every occupied cell in row major order ("13_124_34" =
# cell 1 up+down, cell 2 up+right+left, cell 3 down+left) and the shipped
# artwork fixes where those cells sit inside the piece's box:
#   123_134     1x2 vertical     124_234     2x1 horizontal
#   13_124_34   2x2 with tl,bl,br 123_24_14  2x2 with tl,tr,bl
#   12_234_13   2x2 with tl,tr,br 23_24_134 2x2 with tr,bl,br
#   Skoba1/2    closed ring, horizontal / vertical
#   Skoba3/4    arch opening up / opening right
#   a*          decorated variant of the same shape
const COMPLEX := {
	"double2": ["123_134_1.png", "124_234_1.png"],
	"double1": ["123_134_1.png", "124_234_1.png"],
	"double2a": ["124_234_1a.png", "123_134_1a.png"],
	"double1a": ["124_234_1a.png", "123_134_1a.png"],
	"adouble1": ["a123_134_1.png", "a234_124_1.png"],
	"adouble2": ["a123_134_1.png", "a234_124_1.png"],
	"tripl1": ["13_124_34_1.png"],
	"tripl2": ["13_124_34_1.png"],
	"tripl3": ["123_24_14_1.png"],
	"tripl4": ["12_234_13_1.png", "23_24_134_1.png"],
	"skoba1": ["Skoba1.png"],
	"skoba2": ["Skoba2.png"],
	"skoba3": ["Skoba3.png"],
	"skoba4": ["Skoba4.png"],
}

## Multi cell layouts: artwork -> [occupied cells (x, y), mask digit per cell].
const LAYOUTS := {
	"123_134_1.png": [[[0, 0], [0, 1]], ["123", "134"]],
	"124_234_1.png": [[[0, 0], [1, 0]], ["124", "234"]],
	"123_134_1a.png": [[[0, 0], [0, 1]], ["123", "134"]],
	"124_234_1a.png": [[[0, 0], [1, 0]], ["124", "234"]],
	"a123_134_1.png": [[[0, 0], [1, 0]], ["123", "134"]],
	"a234_124_1.png": [[[0, 0], [0, 1]], ["234", "124"]],
	"13_124_34_1.png": [[[0, 0], [0, 1], [1, 1]], ["13", "124", "34"]],
	"123_24_14_1.png": [[[0, 0], [1, 0], [0, 1]], ["123", "24", "14"]],
	"12_234_13_1.png": [[[0, 0], [1, 0], [1, 1]], ["12", "234", "13"]],
	"23_24_134_1.png": [[[1, 0], [0, 1], [1, 1]], ["23", "24", "134"]],
	"Skoba1.png": [[[0, 0], [1, 0]], ["123", "134"]],
	"Skoba2.png": [[[0, 0], [0, 1]], ["234", "124"]],
	"Skoba3.png": [[[0, 0], [1, 0]], ["12", "14"]],
	"Skoba4.png": [[[0, 0], [0, 1]], ["23", "12"]],
}

## "123" -> 1|2|4 (1=up 2=right 3=down 4=left)
static func mask_from_digits(digits: String) -> int:
	var bits := {"1": 1, "2": 2, "3": 4, "4": 8}
	var m := 0
	for i in digits.length():
		m |= int(bits.get(digits[i], 0))
	return m

## A fishka shape: cells (offset -> cell), masks (per cell), artwork and the
## bounding box in cells.  rot counts clockwise quarter turns of the artwork.
static func _make_shape(art: String, cells: Array, masks: Array) -> Dictionary:
	var box := Vector2i(1, 1)
	for c in cells:
		box.x = maxi(box.x, int(c[0]) + 1)
		box.y = maxi(box.y, int(c[1]) + 1)
	return {"art": art, "cells": cells, "digits": masks,
		"masks": masks.map(func(d): return mask_from_digits(str(d))), "box": box,
		"off": _art_offset(cells), "rot": 0}

## Top left cell of the artwork box, relative to the piece's first cell.
static func _art_offset(cells: Array) -> Vector2i:
	var off := Vector2i(9999, 9999)
	for c in cells:
		off.x = mini(off.x, int(c[0]))
		off.y = mini(off.y, int(c[1]))
	return off if off.x < 9999 else Vector2i.ZERO

static func single_shape(t: int) -> Dictionary:
	return {"art": "", "cells": [Vector2i.ZERO], "digits": [type_name(t)], "masks": [t], "box": Vector2i.ONE, "off": Vector2i.ZERO, "rot": 0}

## Shape asked for by a FishkaProb name (numeric mask name or complex name).
static func shape_of_name(name: String) -> Dictionary:
	if TYPE_NAMES.values().has(name):
		return single_shape(type_from_name(name))
	var variants: Array = COMPLEX.get(name, [])
	if variants.is_empty():
		return single_shape(maxi(1, mask_from_digits(name)))
	var art := str(variants[randi() % variants.size()])
	var layout: Array = LAYOUTS.get(art, [])
	if layout.is_empty():
		return single_shape(1)
	return _make_shape(art, layout[0], layout[1])

static func shape_cells(shape: Dictionary) -> Array:
	var out: Array = []
	for c in shape.cells:
		out.append(Vector2i(int(c[0]) if c is Array else int(c.x), int(c[1]) if c is Array else int(c.y)))
	return out

## Rotate a shape a quarter turn clockwise inside its (possibly swapped) box.
static func rotate_shape(shape: Dictionary) -> Dictionary:
	var box: Vector2i = shape.box
	var cells: Array = []
	var masks: Array = []
	for i in shape.cells.size():
		var c: Variant = shape.cells[i]
		var x: int = int(c[0]) if c is Array else int(c.x)
		var y: int = int(c[1]) if c is Array else int(c.y)
		cells.append([box.y - 1 - y, x])
		masks.append(rotate_cw(int(shape.masks[i])))
	var out := shape.duplicate()
	out["cells"] = cells
	out["masks"] = masks
	out["digits"] = masks.map(func(m): return type_name(int(m)))
	out["box"] = Vector2i(box.y, box.x)
	out["off"] = _art_offset(cells)
	out["rot"] = int(shape.rot) + 1
	return out

## Pixel offset of the artwork relative to the first cell of the shape.
static func shape_art_offset(shape: Dictionary) -> Vector2:
	var off: Vector2i = shape.get("off", Vector2i.ZERO)
	return Vector2(-off.x * CELL, -off.y * CELL)

static func shape_texture(shape: Dictionary) -> Texture2D:
	if str(shape.get("art", "")) == "":
		return type_texture(int(shape.masks[0]))
	return AssetLib.texture_rot("res://assets/squares/%s" % str(shape.art), int(shape.get("rot", 0)) % 4)

# ---------------------------------------------------------------------------
# XML parsing
# ---------------------------------------------------------------------------

static func parse_level(path: String) -> Dictionary:
	var lvl := {
		"name": "",
		"fragmentation": "Squares_",
		"current_y": 9760.0,
		"hero": "",
		"frag_picture": "",
		"generator_period": 4000,
		"music": "",
		"rain": "",
		"hidden_fishka": "",
		"hidden_fishka_prob": 0.0,
		"fishka_with_bonus": 0.0,
		"fish_type_sequence": [],
		"fishka_prob": [],
		"fishka_score": [],
		"fishka_bonus_prob": [],
		"comb_sequence": [],
		"one_comb_bonus_prob": [],
		"all_comb_bonus_prob": [],
		"pictures": [],
		"picture_map": {},
		"fishkas": [],
		"ghosts": [],
		"bonus_elements": [],
		"level_effects": [],
		"bombs": [],
		"make_ghost_rects": [],
		"put_fishkas": [],
	}

	var raw := FileAccess.get_file_as_bytes(path)
	# level files may contain CP1251 comments; XML itself is ASCII
	for i in raw.size():
		if raw[i] >= 0x80:
			raw[i] = 0x20
	var parser := XMLParser.new()
	var err := parser.open_buffer(raw)
	if err != OK:
		push_error("cannot open level %s" % path)
		return lvl

	var current_picture := {}
	var current_bonus := {}
	var current_map := {}
	var pending_text := ""
	var pending_tag := ""

	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := parser.get_node_name()
				var attrs := {}
				for i in parser.get_attribute_count():
					attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
				var empty: bool = parser.is_empty()
				match tag:
					"Level":
						lvl.name = attrs.get("name", "")
						lvl.fragmentation = attrs.get("fragmentation", "Squares_")
						lvl.current_y = _f(attrs.get("CurrentY", "9760"))
					"HeroPicture":
						lvl.hero = attrs.get("name", "")
					"FragPicture":
						lvl.frag_picture = attrs.get("name", "")
					"Generator":
						lvl.generator_period = int(_f(attrs.get("period", "4000")))
					"PlayMusic":
						lvl.music = attrs.get("name", "")
					"RainEffect":
						lvl.rain = attrs.get("name", "")
					"HidenFishkaPicture":
						lvl.hidden_fishka = attrs.get("name", "")
						# the prob attribute uses a decimal comma ("0,1" = 0.1)
						lvl.hidden_fishka_prob = _f(attrs.get("prob", "0"))
					"FishkaWithBonus":
						lvl.fishka_with_bonus = _f(attrs.get("prob", "0"))
					"LevelEffect":
						lvl.level_effects.append(attrs)
					"Picture":
						if not empty:
							current_picture = {
								"name": attrs.get("name", ""),
								"x": _f(attrs.get("x", "0")),
								"y": _f(attrs.get("y", "0")),
								"z": _f(attrs.get("z", "0")),
								"visible": attrs.get("visible", "true") != "false",
								"images": [],
								"curve": {},
							}
							lvl.pictures.append(current_picture)
					"Image":
						if not current_picture.is_empty():
							(current_picture.images as Array).append({
								"name": attrs.get("name", ""),
								"t": _f(attrs.get("t", "0")),
							})
					"MovingCurve":
						if not current_picture.is_empty():
							current_picture.curve = attrs
					"FishkaProb":
						pass
					"FProb":
						lvl.fishka_prob.append({"name": attrs.get("name", "1"), "prob": int(_f(attrs.get("prob", "0")))})
					"FishkaCombination":
						pass
					"PictureMap":
						if not empty:
							current_map = {
								"x": _f(attrs.get("x", "0")),
								"y": _f(attrs.get("y", "0")),
								"z": _f(attrs.get("z", "0")),
								"one_width": _f(attrs.get("OneWidth", "40")),
								"one_height": _f(attrs.get("OneHeight", "40")),
								"images": [],
								"rows": [],
							}
							lvl.picture_map = current_map
					"Fishka":
						lvl.fishkas.append({
							"frag": int(_f(attrs.get("frag", "0"))),
							"type": int(_f(attrs.get("type", "0"))),
							"link": int(_f(attrs.get("link", "0"))),
							"unhammer": attrs.get("unhammer", "") == "true",
						})
					"GhostFishka":
						lvl.ghosts.append({
							"x": int(_f(attrs.get("x", "0"))),
							"y": int(_f(attrs.get("y", "0"))),
							"type": int(_f(attrs.get("type", "0"))),
						})
					"BonusElement":
						if not empty:
							current_bonus = {"points": [], "remove": [], "show": [], "effects": []}
							lvl.bonus_elements.append(current_bonus)
					"Point":
						if not current_bonus.is_empty():
							(current_bonus.points as Array).append({
								"x": _f(attrs.get("x", "0")), "y": _f(attrs.get("y", "0")),
								"border": _f(attrs.get("border", "0")),
							})
					"RemovePicture":
						if not current_bonus.is_empty():
							(current_bonus.remove as Array).append(attrs.get("name", ""))
					"ShowPicture":
						if not current_bonus.is_empty():
							(current_bonus.show as Array).append(attrs.get("name", ""))
					"StartEffect":
						if not current_bonus.is_empty():
							(current_bonus.effects as Array).append(attrs)
					"Bomb":
						lvl.bombs.append(attrs)
					"MakeGhostRect":
						lvl.make_ghost_rects.append(attrs)
					"PutFishka":
						lvl.put_fishkas.append(attrs)
				# Text bearing elements
				if tag in ["FishTypeSequence", "FishkaScore", "FishkaBonusProb", "CombSequence",
						"OneCombBonusProb", "AllCombBonusProb", "Images", "map"]:
					if not empty:
						pending_tag = tag
					else:
						pending_tag = ""
			XMLParser.NODE_TEXT:
				if pending_tag != "":
					var txt := parser.get_node_data().strip_edges()
					match pending_tag:
						"FishTypeSequence":
							for v in txt.split(" ", false):
								lvl.fish_type_sequence.append(int(v))
						"FishkaScore":
							for v in txt.split(" ", false):
								lvl.fishka_score.append(int(v))
						"FishkaBonusProb":
							for v in txt.split(" ", false):
								lvl.fishka_bonus_prob.append(int(v))
						"CombSequence":
							for v in txt.split(" ", false):
								lvl.comb_sequence.append(int(v))
						"OneCombBonusProb":
							for v in txt.split(" ", false):
								lvl.one_comb_bonus_prob.append(int(v))
						"AllCombBonusProb":
							for v in txt.split(" ", false):
								lvl.all_comb_bonus_prob.append(int(v))
						"Images":
							if not current_map.is_empty():
								current_map.images = txt.split(" ", false)
						"map":
							if not current_map.is_empty():
								var row := []
								for v in txt.split(" ", false):
									row.append(int(v))
								(current_map.rows as Array).append(row)
					pending_tag = ""
			XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == "Picture":
					current_picture = {}
				elif parser.get_node_name() == "BonusElement":
					current_bonus = {}

	# Derived data -----------------------------------------------------------
	var fishkas := []
	for f in lvl.fishkas:
		var cell := frag_cell(f.frag)
		if cell.x < -100:
			continue
		fishkas.append({"cell": cell, "type": f.type, "unhammer": f.unhammer, "frag": f.frag})
	lvl["fishkas"] = fishkas
	var ghosts := []
	for g in lvl.ghosts:
		ghosts.append({"cell": ghost_cell(g.x, g.y), "type": g.type, "x": g.x, "y": g.y})
	lvl["ghosts"] = ghosts
	# Board bounds come from the picture map.
	var pm: Dictionary = lvl.picture_map
	if not pm.is_empty():
		lvl["board_top"] = int(round(pm.y / float(CELL)))
		lvl["board_bottom"] = lvl.board_top + (pm.rows as Array).size() - 1
	else:
		lvl["board_top"] = 0
		lvl["board_bottom"] = 250
	lvl["map_x"] = pm.get("x", 0.0)
	lvl["map_y"] = pm.get("y", 0.0)
	return lvl

static func _f(s: String) -> float:
	return s.replace(",", ".").to_float()

static func _vec2(s: String) -> Vector2:
	var parts := s.split(",", false)
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(_f(parts[0]), _f(parts[1]))
