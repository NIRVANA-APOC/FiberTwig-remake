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

## <PutFishka x y type> places a pre-placed twig at level start.  ENGINE-CONFIRMED
## rule (effects-re, handler in FUN_0049A7E4, callee FUN_00499E80): the parser
## computes local_68 = yFile - camY + 245 - 15 and FUN_00499E80 re-adds camY - 245,
## so the camera cancels and worldY = yFile - 15; the cell is admitted by the
## strict window pointsY < worldY < pointsY + 60 with an exact x match.  That is
## floor((x-5)/40), floor((y-15)/40) - the same -15 convention as <GhostFishka>
## and <Point>/<Bomb>.
## The six shipped Level13 records, all unambiguous under this rule:
##   (580,8058,t1)->(14,201)  (347,7860,t2)->(8,196)   (505,7860,t15)->(12,196)
##   (268,7700,t2)->( 6,192)  (576,7694,t8)->(14,191)  (420,7580,t5)->(10,189)
## The (5,18) offset seen earlier reproduces all six under flooring but is not
## the rule; (5,15) is (it is simply -15, so the row is floor((y-15)/40)).
const PUTFISHKA_OFF_X := 5
const PUTFISHKA_OFF_Y := 15

static func putfishka_cell(x: int, y: int) -> Vector2i:
	return Vector2i(int(floor((x - PUTFISHKA_OFF_X) / float(CELL))),
			int(floor((y - PUTFISHKA_OFF_Y) / float(CELL))))

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
	# The "a" variants are the horizontally mirrored artwork of the base tiles
	# (123_134 -> 134_123), so their joint masks are mirrored as well.
	"123_134_1a.png": [[[0, 0], [0, 1]], ["134", "123"]],
	"124_234_1a.png": [[[0, 0], [1, 0]], ["234", "124"]],
	"a123_134_1.png": [[[0, 0], [1, 0]], ["123", "134"]],
	"a234_124_1.png": [[[0, 0], [0, 1]], ["234", "124"]],
	"13_124_34_1.png": [[[0, 0], [0, 1], [1, 1]], ["13", "124", "34"]],
	"123_24_14_1.png": [[[0, 0], [1, 0], [0, 1]], ["123", "24", "14"]],
	"12_234_13_1.png": [[[0, 0], [1, 0], [1, 1]], ["12", "234", "13"]],
	"23_24_134_1.png": [[[1, 0], [0, 1], [1, 1]], ["23", "24", "134"]],
	# Skoba1 is an arch with both feet cut at the bottom edge, Skoba2 a "C"
	# opening to the right; the masks follow the artwork, not the old guess.
	"Skoba1.png": [[[0, 0], [1, 0]], ["23", "34"]],
	"Skoba2.png": [[[0, 0], [0, 1]], ["34", "14"]],
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
		"fire_effects": [],
		"round_blicks": [],
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
						# <LevelEffect name="RoundBlicks" x y>: a positioned
						# Blick1 burst.  x/y are WORLD pixels - the parser does
						# NOT apply the PutFishka/-15 adjustment here.
						if str(attrs.get("name", "")) == "RoundBlicks":
							lvl.round_blicks.append({
								"x": _f(attrs.get("x", "0")),
								"y": _f(attrs.get("y", "0")),
							})
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
							current_picture.curve = _curve_from(attrs)
					"MapMovingCurve":
						if not current_map.is_empty():
							current_map["curve"] = _curve_from(attrs)
					"MoveSin":
						# <MoveSin> feeds the TWIG-SPARK record (FUN_004A3E9C),
						# NOT the picture curve evaluator - keep the two paths
						# separate.
						if not current_map.is_empty():
							current_map["move_sin"] = attrs
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
								"curve": {},
								"move_sin": {},
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
							current_bonus = {"points": [], "remove": [], "show": [],
								"bombs": [], "effects": [], "start_effect": {}, "triggered": false}
							lvl.bonus_elements.append(current_bonus)
					"Point":
						if not current_bonus.is_empty():
							(current_bonus.points as Array).append({
								"x": _f(attrs.get("x", "0")), "y": _f(attrs.get("y", "0")),
								"border": int(_f(attrs.get("border", "0"))),
							})
					"RemovePicture":
						if not current_bonus.is_empty():
							(current_bonus.remove as Array).append(attrs.get("name", ""))
					"ShowPicture":
						if not current_bonus.is_empty():
							(current_bonus.show as Array).append(attrs.get("name", ""))
					"Bomb":
						lvl.bombs.append(attrs)
						if not current_bonus.is_empty():
							(current_bonus.bombs as Array).append({
								"x": _f(attrs.get("x", "0")), "y": _f(attrs.get("y", "0")),
								"r": _f(attrs.get("r", "0")),
								"ghost": attrs.get("ghost", "") == "true",
								"picturebomb": attrs.get("picturebomb", "") == "true",
								"effectname": attrs.get("effectname", ""),
								"bombimage": attrs.get("bombimage", ""),
							})
					"StartEffect":
						if not current_bonus.is_empty():
							(current_bonus.effects as Array).append(attrs)
							(current_bonus.start_effect as Dictionary).merge(attrs, true)
					"MakeGhostRect":
						lvl.make_ghost_rects.append(attrs)
					"PutFishka":
						lvl.put_fishkas.append({
							"x": _f(attrs.get("x", "0")),
							"y": _f(attrs.get("y", "0")),
							"type": int(_f(attrs.get("type", "0"))),
							# the handler also reads `ghost` and marks the
							# element ghost-class when its screen y resolves to
							# 0; no shipped record does, but keep the field
							# rather than silently dropping it
							"ghost": attrs.get("ghost", "") == "true",
						})
					"FireEffect":
						lvl.fire_effects.append({
							"name": attrs.get("name", ""),
							"x": _f(attrs.get("x", "0")),
							"y": _f(attrs.get("y", "0")),
							# the record's runevery overrides the effect's
							# [EffectTypeRunEvery]; 0 = use the table value
							"runevery": _f(attrs.get("runevery", "0")),
							"followpic": attrs.get("followpic", ""),
						})
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

	# The bonus point / bomb positions use the level editor's screen lattice
	# with a 15 px vertical offset (FiberTwig.exe FUN_00499e80 called with
	# y - 0xf, see FUN_0049a7e4); the cell is the artwork anchor cell.
	for b in lvl.bonus_elements:
		for p in b.points:
			p["cell"] = Vector2i(int(floor((float(p.x) - 5.0) / CELL)), int(floor((float(p.y) - 15.0) / CELL)))
		for bo in b.bombs:
			bo["cell"] = Vector2i(int(floor((float(bo.x) - 5.0) / CELL)), int(floor((float(bo.y) - 15.0) / CELL)))

	# Derived data -----------------------------------------------------------
	var fishkas := []
	for f in lvl.fishkas:
		var cell := frag_cell(f.frag)
		if cell.x < -100:
			continue
		fishkas.append({"cell": cell, "type": f.type, "unhammer": f.unhammer, "frag": f.frag})
	lvl["fishkas"] = fishkas
	# <PutFishka> = pre-placed twigs.  They join the board exactly like <Fishka>
	# (they count towards the network, they never score and they are locked), so
	# they are appended to the same list; `source` keeps them distinguishable for
	# the self-test and for the ledger.
	var put := []
	for p in lvl.put_fishkas:
		var pc := putfishka_cell(int(p.get("x", 0)), int(p.get("y", 0)))
		var rec := {
			"cell": pc,
			"type": int(p.get("type", 0)),
			"unhammer": false,
			"frag": -1,
			"source": "putfishka",
			"px": int(p.get("x", 0)),
			"py": int(p.get("y", 0)),
		}
		put.append(rec)
		fishkas.append(rec)
	lvl["put_fishka_cells"] = put
	var ghosts := []
	for g in lvl.ghosts:
		ghosts.append({"cell": ghost_cell(g.x, g.y), "type": g.type, "x": g.x, "y": g.y})
	lvl["ghosts"] = ghosts
	# <MakeGhostRect> runs HERE, on the parsed level data, so that the level's own
	# counts stay honest: a converted twig LEAVES `fishkas` and ENTERS `ghosts`.
	# Doing it later (in BoardWorld.setup) left `fishkas` still containing the
	# converted twigs, so the printed pattern size no longer described the board.
	apply_make_ghost_rects(lvl)
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

## <MakeGhostRect left top right bottom> is world-pixel.  A pre-placed twig
## converts when its cell origin (40*col + 5, 40*row) lies inside the rectangle.
## The twig LEAVES `fishkas` (so it no longer blocks, connects or carries a joint
## light) and ENTERS `ghosts` with the same joint mask (which is what keeps it
## coverable by the same shape).  Mutates `lvl` and records the converted cells in
## `lvl.ghost_rect_converted` so callers can assert
##   ghosts_after == ghosts_before + converted   AND
##   fishkas_after == fishkas_before - converted
static func apply_make_ghost_rects(lvl: Dictionary) -> Array:
	var rects: Array = lvl.get("make_ghost_rects", [])
	lvl["ghosts_before_rects"] = (lvl.get("ghosts", []) as Array).size()
	lvl["fishkas_before_rects"] = (lvl.get("fishkas", []) as Array).size()
	var converted: Array = []
	if rects.is_empty():
		lvl["ghost_rect_converted"] = converted
		return converted
	var ghosts: Array = lvl.get("ghosts", [])
	var existing := {}
	for g in ghosts:
		existing[g.cell] = true
	var kept: Array = []
	for f in lvl.get("fishkas", []):
		var hit := false
		for r in rects:
			var left := _f(str(r.get("left", "0")))
			var top := _f(str(r.get("top", "0")))
			var right := _f(str(r.get("right", "0")))
			var bottom := _f(str(r.get("bottom", "0")))
			if right < left:
				var tl := left
				left = right
				right = tl
			if bottom < top:
				var tt := top
				top = bottom
				bottom = tt
			var o := cell_origin(f.cell)
			if o.x >= left and o.x <= right and o.y >= top and o.y <= bottom:
				hit = true
				break
		if hit and not existing.has(f.cell):
			ghosts.append({"cell": f.cell, "type": int(f.type), "x": 0, "y": 0,
				"from_rect": true})
			existing[f.cell] = true
			converted.append(f.cell)
		else:
			kept.append(f)
	lvl["fishkas"] = kept
	lvl["ghosts"] = ghosts
	lvl["ghost_rect_converted"] = converted
	return converted

## <MovingCurve>/<MapMovingCurve> attribute set.  Formula is implementation-grade
## from A5: offsetX = alX*sin(beX*T) + gaX*cos(beX*T) + laX*T + lbX (same for Y),
## final position = picture base position + offset, T = elapsed MILLISECONDS
## wrapping at 20 000 000 (the parser OVERWRITES the authored `t` with that limit,
## so `t` is NOT a period).  <MapMovingCurve> is the same evaluator with laX/lbX
## zero; it is not a separate code path.  Missing attributes default to 0.
static func _curve_from(attrs: Dictionary) -> Dictionary:
	var keys := ["alX", "beX", "gaX", "laX", "lbX", "alY", "beY", "gaY", "laY", "lbY"]
	var out := {}
	var any := false
	for k in keys:
		if attrs.has(k):
			out[k] = _f(str(attrs[k]))
			any = true
		else:
			out[k] = 0.0
	if not any:
		return {}
	out["source"] = attrs
	return out

static func _vec2(s: String) -> Vector2:
	var parts := s.split(",", false)
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(_f(parts[0]), _f(parts[1]))
