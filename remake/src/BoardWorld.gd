extends Node2D
const LevelLoader := preload("res://src/LevelLoader.gd")

## Renders the playfield using the geometry measured from the shipped
## screenshots (assets/Game-*.png -> design 800x600 space):
##   * twig artwork origin = (40*col + 5, 40*row)      (Squares_Points.dat)
##   * brick map origin    = (map_x + 5 + 40*i, map_y + 40*j)
##   * camera y            = CurrentY - 247            (measured)
## The playfield is a 600x500 window on that world; the panel/belt art comes
## from GamePlay1.jpg which is drawn by Main.

const CELL := LevelLoader.CELL
const DIRS := [
	{"d": Vector2i(0, -1), "bit": LevelLoader.UP, "opp": LevelLoader.DOWN},
	{"d": Vector2i(1, 0), "bit": LevelLoader.RIGHT, "opp": LevelLoader.LEFT},
	{"d": Vector2i(0, 1), "bit": LevelLoader.DOWN, "opp": LevelLoader.UP},
	{"d": Vector2i(-1, 0), "bit": LevelLoader.LEFT, "opp": LevelLoader.RIGHT},
]

var level: Dictionary = {}
var cells: Dictionary = {}          # Vector2i -> {type, locked, unhammer, piece?}
var pieces: Array = []              # multi-cell twigs: {shape, base, cells}; null once removed
var ghosts: Dictionary = {}         # Vector2i -> type
var cam_y := 0.0
var preview_cell := Vector2i(-9999, -9999)
var preview_type := 0
var preview_shape: Dictionary = {}
var preview_valid := false
var bonus_points: Array = []
var effects: Array = []
var map_removed: Dictionary = {}     # Vector2i(col, row) -> true (bombed wall bricks)
var explosions: Array = []           # {pos, tex, t, life}
## Cells of the level's <Point> markers (state-5 bonus twigs in the original).
## They occupy the board and carry a joint mask but are never drawn.
var point_cells: Dictionary = {}     # Vector2i -> true
## The element that each point cell belongs to (for the trigger check).
var point_element: Dictionary = {}   # Vector2i -> element dictionary
var _bg_ref := 0.0
var _light_tint := 0.6               # green light lerp amount (random every 200 ms)
var _light_t := 0.0
var _pictures_back: Array = []
var _pictures_front: Array = []
var _camera: Camera2D
var _time := 0.0
var rain := ""
var show_hints := true

func setup(p_level: Dictionary) -> void:
	level = p_level
	ghosts.clear()
	cells.clear()
	pieces.clear()
	bonus_points.clear()
	effects.clear()
	map_removed.clear()
	explosions.clear()
	point_cells.clear()
	point_element.clear()
	for g in level.get("ghosts", []):
		ghosts[g.cell] = g.type
	for f in level.get("fishkas", []):
		cells[f.cell] = {"type": f.type, "locked": true, "unhammer": f.unhammer}
	# Bonus points are hidden twigs in the original (state 5, FUN_0049a7e4);
	# they occupy their cell with the <Point border> mask and can neither be
	# picked nor hammered.  They join the network like a normal twig.
	for b in level.get("bonus_elements", []):
		b["triggered"] = false
		for p in b.points:
			var pcell: Vector2i = p.cell
			cells[pcell] = {"type": int(p.border), "locked": true, "unhammer": true, "point": true}
			point_cells[pcell] = true
			point_element[pcell] = b
			bonus_points.append({"cell": pcell, "active": true, "border": int(p.border)})
	_pictures_back = []
	_pictures_front = []
	for pic in level.get("pictures", []):
		if float(pic.get("z", 0)) >= 100.0:
			_pictures_back.append(pic)
		else:
			_pictures_front.append(pic)
	_pictures_back.sort_custom(func(a, b): return float(a.z) > float(b.z))
	# "Fone" pictures (z >= 100) are screen anchored: at the level's initial camera
	# the first one sits at screen y = -88, measured from assets/Game-*.png.
	_bg_ref = 0.0
	if not _pictures_back.is_empty():
		_bg_ref = float(_pictures_back[0].y)
	rain = str(level.get("rain", ""))
	if _camera == null:
		_camera = Camera2D.new()
		_camera.enabled = true
		add_child(_camera)
	update_camera()

func update_camera() -> void:
	if _camera:
		_camera.position = Vector2(300, cam_y + 250)

func _process(delta: float) -> void:
	_time += delta
	_light_t += delta
	if _light_t >= 0.2:
		_light_t -= 0.2
		_light_tint = randf_range(0.4, 1.0)
	queue_redraw()

## Show/hide a <Picture> by name (RemovePicture / ShowPicture of a bonus
## element).  Pictures the level declares invisible start hidden.
func set_picture_visible(pic_name: String, visible: bool) -> void:
	for pic in _pictures_back + _pictures_front:
		if str(pic.get("name", "")) == pic_name:
			pic["visible"] = visible

## A picture bomb removes the wall bricks inside `radius` (pixels) around the
## world point (x, y) and plays the `image` tile as the destruction effect
## (FiberTwig.exe FUN_004a2094).  Returns how many bricks were removed.
func bomb_bricks(x: float, y: float, radius: float, image: String) -> int:
	var pm: Dictionary = level.get("picture_map", {})
	if pm.is_empty():
		return 0
	var mx := float(pm.x) + 5.0
	var my := float(pm.y)
	var removed := 0
	var rows: Array = pm.rows
	var r0 := maxi(int(floor((y - radius - my) / CELL)), 0)
	var r1 := mini(int(ceil((y + radius - my) / CELL)), rows.size() - 1)
	for r in range(r0, r1 + 1):
		var row: Array = rows[r]
		var c0 := maxi(int(floor((x - radius - mx) / CELL)), 0)
		var c1 := mini(int(ceil((x + radius - mx) / CELL)), row.size() - 1)
		for c in range(c0, c1 + 1):
			if int(row[c]) <= 0 or map_removed.has(Vector2i(c, r)):
				continue
			var px := mx + c * CELL
			var py := my + r * CELL
			# the original tests the distance to the brick's four corners
			var near := false
			for corner in [Vector2(0, 0), Vector2(CELL, 0), Vector2(0, CELL), Vector2(CELL, CELL)]:
				if Vector2(px, py).distance_to(Vector2(x, y) - corner) < radius:
					near = true
					break
			if near:
				map_removed[Vector2i(c, r)] = true
				if image != "":
					var tex := AssetLib.texture("res://assets/squares/%s" % image)
					explosions.append({"pos": Vector2(px, py), "tex": tex, "t": 0.0, "life": 0.6})
				removed += 1
	return removed

func _picture_texture(pic: Dictionary) -> Texture2D:
	var images: Array = pic.get("images", [])
	if images.is_empty():
		return null
	if images.size() == 1:
		return AssetLib.texture("res://assets/squares/%s" % images[0].name)
	var total := 0.0
	for im in images:
		total += max(im.t, 0.01)
	var tt := fmod(_time * 1000.0, total)
	var acc := 0.0
	for im in images:
		acc += max(im.t, 0.01)
		if tt <= acc:
			return AssetLib.texture("res://assets/squares/%s" % im.name)
	return AssetLib.texture("res://assets/squares/%s" % images[0].name)

## Screen space of a world point for the current camera.
func to_screen(world: Vector2) -> Vector2:
	return Vector2(world.x, world.y - cam_y)

func _draw() -> void:
	var top := cam_y - 64.0
	var bottom := cam_y + 564.0
	for pic in _pictures_back:
		if pic.get("visible", true) == false:
			continue
		var tex := _picture_texture(pic)
		if tex == null:
			continue
		var y: float = float(pic.y) - _bg_ref - 88.0     # screen space
		if y > 500.0 or y + tex.get_height() < 0:
			continue
		draw_texture(tex, Vector2(float(pic.x), cam_y + y))   # world space = camera + screen
	# brick map
	var pm: Dictionary = level.get("picture_map", {})
	if not pm.is_empty():
		var rows: Array = pm.rows
		var images: Array = pm.images
		var my := float(pm.y)
		var mx := float(pm.x) + 5.0
		var r0 := maxi(int(floor((cam_y - 40 - my) / CELL)), 0)
		var r1 := mini(int(ceil((cam_y + 540 - my) / CELL)), rows.size() - 1)
		for r in range(r0, r1 + 1):
			var row: Array = rows[r]
			for c in row.size():
				var v: int = row[c]
				if v <= 0 or v > images.size():
					continue
				if map_removed.has(Vector2i(c, r)):
					continue
				var t := AssetLib.texture("res://assets/squares/%s" % images[v - 1])
				if t:
					draw_texture(t, Vector2(mx + c * CELL, my + r * CELL))
	for pic in _pictures_front:
		if pic.get("visible", true) == false:
			continue
		var tex2 := _picture_texture(pic)
		if tex2 == null:
			continue
		var y2 := float(pic.y)
		if y2 > bottom or y2 + tex2.get_height() < top:
			continue
		draw_texture(tex2, Vector2(float(pic.x), y2))
	if show_hints:
		for bp in bonus_points:
			if bp.active:
				var o := LevelLoader.cell_origin(bp.cell)
				draw_rect(Rect2(o.x + 8, o.y + 8, 24, 24), Color(1, 0.85, 0.2, 0.35), true)
	# transparent target twigs
	for cell in ghosts:
		var o := LevelLoader.cell_origin(cell)
		if o.y < top - 44 or o.y > bottom + 44:
			continue
		var t := LevelLoader.type_texture(ghosts[cell])
		if t:
			draw_texture(t, o, Color(1, 1, 1, 0.30))
	# placed single-cell twigs (multi-cell pieces are drawn as one artwork below)
	for cell in cells:
		var o := LevelLoader.cell_origin(cell)
		if o.y < top - 44 or o.y > bottom + 44:
			continue
		var info: Dictionary = cells[cell]
		if bool(info.get("point", false)):
			continue
		if not info.has("piece"):
			var t := LevelLoader.type_texture(info.type)
			if t:
				draw_texture(t, o)
	# multi-cell fishkas (double / triple / skoba) keep their whole artwork after
	# they are placed - the original stores one twig record per piece, not one
	# per covered cell, and drawing each cell separately would mutate the piece
	# into a combination of basic twigs.
	for piece in pieces:
		if piece == null:
			continue
		var shape: Dictionary = piece.shape
		var st := LevelLoader.shape_texture(shape)
		if st == null:
			continue
		var o2 := LevelLoader.cell_origin(piece.base)
		if o2.y + st.get_height() < top - 44 or o2.y > bottom + 44:
			continue
		draw_texture(st, o2 + LevelLoader.shape_art_offset(shape))
	# light from open joints (Blick1.png, 32x8)
	if show_hints:
		_draw_joint_lights(top, bottom)
	if preview_cell.x > -999 and preview_type != 0:
		var o := LevelLoader.cell_origin(preview_cell)
		var col := Color(1, 1, 1, 0.85)
		if not preview_valid:
			col = Color(1, 0.55, 0.55, 0.75)
		if not preview_shape.is_empty() and str(preview_shape.get("art", "")) != "":
			var st := LevelLoader.shape_texture(preview_shape)
			if st:
				draw_texture(st, o + LevelLoader.shape_art_offset(preview_shape), col)
		else:
			var t := LevelLoader.type_texture(preview_type)
			if t:
				draw_texture(t, o, col)
	if rain == "Rain":
		_draw_rain()
	for e in effects:
		var tt: float = e.t
		var o := LevelLoader.cell_origin(e.cell)
		draw_rect(Rect2(o.x + 8 - tt * 20, o.y + 8 - tt * 20, 24 + tt * 40, 24 + tt * 40),
			Color(e.color.r, e.color.g, e.color.b, max(0.0, 1.0 - tt)), false, 3.0)
	# exploding wall bricks (a picture bomb draws the bombimage tile and fades)
	for ex in explosions:
		var t2: Texture2D = ex.tex
		if t2 == null:
			continue
		var f: float = clampf(float(ex.t) / float(ex.life), 0.0, 1.0)
		draw_texture(t2, ex.pos, Color(1, 1, 1, 1.0 - f))

## The original hint lights (FUN_004921d0): every open joint projects the soft
## light1..4.PNG glow of `EffectsType`/level art into the empty cell it points
## at.  The glow faces the joint, so the sprite is picked by the direction from
## the light cell back to the joint (up/right/down/left -> light1..4).  The
## light cells on the row the camera follows (the lowest one) are tinted green
## and flicker (colour 0x8000, a random intensity refreshed every 200 ms); an
## UpArrow at (570, 5) points at light cells above the view.
func _draw_joint_lights(top: float, bottom: float) -> void:
	var lights: Array = []          # {cell, back} back = dir from cell to the joint
	var max_y := -9999
	var above := false
	for cell in cells:
		var info: Dictionary = cells[cell]
		for dir in DIRS:
			if not (info.type & dir.bit):
				continue
			var n: Vector2i = cell + dir.d
			var occupied: Variant = cells.get(n)
			if occupied != null and (int(occupied.type) & int(dir.opp)) != 0:
				continue
			lights.append({"cell": n, "back": int(dir.opp)})
			max_y = maxi(max_y, n.y)
			if float(n.y) * 40.0 < cam_y:
				above = true
	# the green flicker of the original is one random value for all lights
	for l in lights:
		var cell: Vector2i = l.cell
		var o := LevelLoader.cell_origin(cell)
		if o.y < top - 44 or o.y > bottom + 44:
			continue
		var tex := _light_texture(int(l.back))
		if tex == null:
			continue
		if cell.y == max_y and not ghosts.has(cell):
			# FUN_004b293c lerps the light picture towards TColor 0x8000 (green)
			# by a random amount refreshed every 200 ms
			draw_texture(tex, o, Color(1, 1, 1).lerp(Color(0.0, 0.5, 0.0), _light_tint))
		else:
			draw_texture(tex, o)
	if above and not lights.is_empty():
		var arrow := AssetLib.texture("res://assets/game/UpArrow.png")
		if arrow:
			# screen anchored at (570, 5) - this is the world space viewport
			draw_texture(arrow, Vector2(570, 5 + cam_y))

func _light_texture(back_bit: int) -> Texture2D:
	match back_bit:
		1: return AssetLib.texture("res://assets/squares/light1.PNG")
		2: return AssetLib.texture("res://assets/squares/light2.PNG")
		4: return AssetLib.texture("res://assets/squares/light3.PNG")
		8: return AssetLib.texture("res://assets/squares/light4.PNG")
	return null

## Rain effect: RainDrop.png sprites (the .aim files scale it to 20x40 "MidRain"
## and 13x24 "SmRain"), alpha 150 / 100 per EffectsType.dat.
var _drops: Array = []
func _init_drops() -> void:
	if not _drops.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240501
	for i in 110:
		_drops.append({
			"x": rng.randf() * 680.0 - 40.0,
			"y": rng.randf() * 560.0,
			"v": rng.randf_range(320.0, 620.0),
			"small": i % 3 == 0,
		})

func _draw_rain() -> void:
	var mid := AssetLib.texture("res://assets/squares/MidRain.pNg")
	var sm := AssetLib.texture("res://assets/squares/SmRain.pNg")
	if mid == null or sm == null:
		return
	_init_drops()
	for d in _drops:
		var v := float(d.v)
		var y := cam_y + fmod(float(d.y) + _time * v, 560.0) - 60.0
		var x := float(d.x) - (y - cam_y) * 0.10
		if bool(d.small):
			draw_texture(sm, Vector2(x, y), Color(1, 1, 1, 0.55))
		else:
			draw_texture(mid, Vector2(x, y), Color(1, 1, 1, 0.75))

func add_effect(cell: Vector2i, color: Color) -> void:
	effects.append({"cell": cell, "color": color, "t": 0.0})

func _physics_process(delta: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		effects[i].t += delta * 1.6
		if effects[i].t >= 1.0:
			effects.remove_at(i)
	for i in range(explosions.size() - 1, -1, -1):
		explosions[i].t += delta
		if explosions[i].t >= float(explosions[i].life):
			explosions.remove_at(i)
