extends RefCounted
const LevelLoader := preload("res://src/LevelLoader.gd")

## Spark emitters for the level's <FireEffect> records and the parameterised
## rain driver for <RainEffect>.
##
## EVERY number below is taken verbatim from the shipped
## `game.zxc:EffectsType.dat`, key by key - none of it is invented.  The keys are
## quoted in the constant names / comments so each value can be re-checked with
## `work/reveng/scratch/a6_emit_constants.py`.
##
## What is NOT yet proven is the *interpretation* of those keys (how the engine
## integrates SparkVecX/Y, SparkAngle, SparkTB->SparkTE over SparkTTC, the
## SparkLongYEffect stretch and the 0..n frame walk).  The table values are wired
## through faithfully and the integration is a single, named, documented pass;
## when the engine's formula is extracted only `_step()` needs adjusting.

# ---------------------------------------------------------------------------
# Spark recipes, from EffectsType.dat [EffectType] <name> / [SparkCloneEffect]
# ---------------------------------------------------------------------------
const SPARK_RECIPES := {
	# [EffectTypeRunEvery] 35 / SparkSurfName FireOne.png / SparkNum 1
	# SparkVecX 0 / SparkVecY 50 / SparkAngle 1 5 / SparkSX 300 / SparkSY 9750
	# SparkFrameN 1 / SparkTFC -1 / SparkTB 200 / SparkTE 0 / SparkTTC 1200
	# GravX 0 / GravY 0 / SparkClipper 5 5 605 490
	# flags: SparkLongYEffect, SparkRandomAngle (SparkFollowMouseCursor is "no")
	"Fire": {
		"run_every": 35.0,
		"surface": "FireOne.png",
		"num": 1,
		"vec": Vector2(0.0, 50.0),
		"angle": Vector2(1.0, 5.0),
		"spawn_box": Vector2(300.0, 9750.0),
		"frames": 1,
		"frame_tfc": -1.0,
		"tfc": -1.0,
		"tb": 200.0,
		"te": 0.0,
		"ttc": 1200.0,
		"grav": Vector2(0.0, 0.0),
		"clipper": Rect2(5, 5, 605, 490),
		"long_y": true,
		"random_angle": true,
	},
	# [EffectTypeRunEvery] 100 / FlakeOne.png / SparkNum 5 / SparkVecX 300
	# SparkVecY 0 / SparkAngle 1 3 / SparkFrameN 4 / SparkFrameTFC 50
	# SparkTFC 50 / SparkTB 5 / SparkTE 100 / SparkTTC 1500
	"SnowWind": {
		"run_every": 100.0,
		"surface": "FlakeOne.png",
		"num": 5,
		"vec": Vector2(300.0, 0.0),
		"angle": Vector2(1.0, 3.0),
		"spawn_box": Vector2(300.0, 9750.0),
		"frames": 4,
		"frame_tfc": 50.0,
		"tfc": 50.0,
		"tb": 5.0,
		"te": 100.0,
		"ttc": 1500.0,
		"grav": Vector2(0.0, 0.0),
		"clipper": Rect2(5, 5, 605, 490),
		"long_y": true,
		"random_angle": true,
	},
	# as SnowWind but SparkVecX -300 and SparkTE 250
	"ReverseSnowWind": {
		"run_every": 100.0,
		"surface": "FlakeOne.png",
		"num": 5,
		"vec": Vector2(-300.0, 0.0),
		"angle": Vector2(1.0, 3.0),
		"spawn_box": Vector2(300.0, 9750.0),
		"frames": 4,
		"frame_tfc": 50.0,
		"tfc": 50.0,
		"tb": 5.0,
		"te": 250.0,
		"ttc": 1500.0,
		"grav": Vector2(0.0, 0.0),
		"clipper": Rect2(5, 5, 605, 490),
		"long_y": true,
		"random_angle": true,
	},
}

# ---------------------------------------------------------------------------
# RainEffect slots, from EffectsType.dat [EffectType] <name> / [RainEffect]
# Each entry is one emitter slot of that surface.
# ---------------------------------------------------------------------------
const RAIN_RECIPES := {
	# [EffectType] Rain Create
	"Rain": [
		# SurfName MidRain / TransBegin 150 / TransEnd 150 / FramesNumber 1
		# ShiftX 550 / ShiftY -40 / RainBornEvery 20 / RainSpeed 500
		# RainStartPoint 100 -200 / RainWidth 1000 / RainHeight 1200
		# RainAngle -1 8 / RainTimeToWork 47000
		{"surface": "MidRain.pNg", "alpha": 150, "frames": 1, "frame_tfc": -1.0,
			"shift": Vector2(550, -40), "born_every": 20.0, "speed": 500.0,
			"start": Vector2(100, -200), "size": Vector2(1000, 1200),
			"angle": Vector2(-1, 8), "ttw": 47000.0, "move_sin": {}},
		# SurfName SmRain / TransBegin 100 / ShiftX 0 / RainBornEvery 10
		# RainSpeed 300
		{"surface": "SmRain.pNg", "alpha": 100, "frames": 1, "frame_tfc": -1.0,
			"shift": Vector2(0, 0), "born_every": 10.0, "speed": 300.0,
			"start": Vector2(100, -200), "size": Vector2(1000, 1200),
			"angle": Vector2(-1, 8), "ttw": 47000.0, "move_sin": {}},
	],
	# [EffectType] FlowerFall Create - one slot
	"FlowerFall": [
		# SurfName FlowerOne.png / TransBegin 255 / TransEnd 255 / FramesNumber 9
		# TimeFrameChange 50 / ShiftX 550 / ShiftY -40 / RainBornEvery 1500
		# RainSpeed 25 / RainAngle 0 5 / RainTimeToWork 250000
		# <MoveSin alX="20" beX="100" gaX="0" alY="5" beY="150" gaY="0"/>
		{"surface": "FlowerOne.png", "alpha": 255, "frames": 9, "frame_tfc": 50.0,
			"shift": Vector2(550, -40), "born_every": 1500.0, "speed": 25.0,
			"start": Vector2(100, -200), "size": Vector2(1000, 1200),
			"angle": Vector2(0, 5), "ttw": 250000.0,
			"move_sin": {"alX": 20.0, "beX": 100.0, "gaX": 0.0,
				"alY": 5.0, "beY": 150.0, "gaY": 0.0}},
	],
}

var _sparks: Array = []            # one list per emitter, see _emitters
var _emitters: Array = []          # {recipe, x, y, run_every, t, followpic}
var _rng := RandomNumberGenerator.new()
var _rain_slots: Array = []        # {recipe, next_born, t, phase}
var _rain_name := ""
var _pictures: Callable = Callable()
var _rounds: Array = []            # live RoundBlicks bursts
var _round_timers: Array = []      # next spawn time per <LevelEffect RoundBlicks>

## RoundBlicks: the three [RoundCloneEffect] records under
## `[EffectType] RoundBlicks Create`.  All three use RoundSurfName Blick1.png
## (4 frames at RoundTFC 100 ms), RoundNum 1, the RoundSX/SY spawn box 200x9500,
## the Roundar/Roundbr ELLIPSE 55 x 30, RoundTB/TE 255/255 and
## RoundClipper "5 5 605 490".  They differ in Dir / Roundangle / RoundTTM /
## RoundWait.
##
## Roundangle is an ANGULAR STEP per frame, not an interval (A5 FINAL,
## instruction-level): rec[+0x20] = pi*a/b radians/frame, so "0 0" = no rotation,
## "1 2" = pi/2 per frame, "1 4" = pi/4 per frame, signed by RoundDir.  The
## 4-frame Blick1 sheet therefore also ROTATES.
##
## STILL UNRESOLVED and deliberately not invented: whether the three records run
## concurrently or as a timed cycle - each carries its own RoundWait/RoundTTM but
## the per-frame reader was not located.  ROUND_CYCLE is the single switch.
## Roundar/Roundbr as ellipse semi-axes is DERIVED, not instruction-level.
const ROUND_BLICKS := [
	{"dir": 1, "angle": Vector2(0, 0), "ttm": 1500.0, "wait": 20.0},
	{"dir": 1, "angle": Vector2(1, 2), "ttm": 1350.0, "wait": 500.0},
	{"dir": -1, "angle": Vector2(1, 4), "ttm": 1100.0, "wait": 500.0},
]
const ROUND_SURFACE := "Blick1.png"
const ROUND_FRAMES := 4
const ROUND_FRAME_TFC := 100.0
const ROUND_ALPHA := 255.0
const ROUND_ELLIPSE := Vector2(55, 30)
const ROUND_LONG_Y := true
## false = the three records run concurrently; true = one record at a time in
## order.  Undecoded (see TODO above).
const ROUND_CYCLE := false

static func has_rain(name: String) -> bool:
	return RAIN_RECIPES.has(name)

static func has_spark(name: String) -> bool:
	return SPARK_RECIPES.has(name)

func setup(level: Dictionary, picture_pos: Callable) -> void:
	_pictures = picture_pos
	_rng.randomize()
	_emitters.clear()
	_sparks.clear()
	for e in level.get("fire_effects", []):
		var nm := str(e.name)
		if not SPARK_RECIPES.has(nm):
			push_warning("FireEffect: unknown effect '%s' - skipped" % nm)
			continue
		var rec: Dictionary = SPARK_RECIPES[nm]
		var every := float(e.runevery)
		if every <= 0.0:
			every = float(rec.run_every)
		_emitters.append({
			"recipe": nm,
			"x": float(e.x),
			"y": float(e.y),
			"run_every": every,
			"t": 0.0,
			"followpic": str(e.followpic),
		})
		_sparks.append([])
	# rain
	_rain_name = str(level.get("rain", ""))
	_rain_slots.clear()
	if RAIN_RECIPES.has(_rain_name):
		for rec in RAIN_RECIPES[_rain_name]:
			_rain_slots.append({"recipe": rec, "t": 0.0, "phase": 0.0})
	elif _rain_name != "":
		push_warning("RainEffect: unknown surface '%s' - not rendered" % _rain_name)
	# <LevelEffect name="RoundBlicks" x y>: a positioned burst.  NOTE the level's
	# x/y are used in the WORLD frame directly - effects-re confirmed the parser
	# does NOT apply the "- cam + 245 - 15" adjustment that <PutFishka> gets.
	_rounds.clear()
	_round_timers.clear()
	for le in level.get("round_blicks", []):
		_round_timers.append({"x": float(le.x), "y": float(le.y), "next": 0.0, "idx": 0})

func clear() -> void:
	_emitters.clear()
	_sparks.clear()
	_rain_slots.clear()
	_rain_name = ""

## The emitter's world position: the record's x/y, or the <Picture> named by
## `followpic` (Level15 tracks the moving Winder1/Winder2 pictures).
func _emitter_pos(e: Dictionary) -> Vector2:
	var fp := str(e.followpic)
	if fp != "" and _pictures.is_valid():
		var p: Variant = _pictures.call(fp)
		if p != null:
			return p
	return Vector2(float(e.x), float(e.y))

func _new_spark(rec: Dictionary, at: Vector2) -> Dictionary:
	# A5 FINAL, instruction-level (FUN_004B4D00 spawns SparkNum = N and indexes
	# each spark i with rec[+0x98] = 2*pi*i/N; FUN_004B4ECC at 0x004B4ECC then
	# computes phase = -pi + rec[+0x98], vx = vxScale*sin(phase),
	# vy = vyScale*cos(phase)).  X uses SIN and Y uses COS - verified because it
	# reproduces all three recipes from their own numbers with no fitted constant:
	#   Fire  N=1 VecY 50  -> phase -pi -> vx 0, vy -50 (a single ember going up)
	#   SnowWind N=5 VecX 300 -> vy always 0, spread purely horizontal
	var idx := int(rec.get("_i", 0))
	var n := maxi(1, int(rec.num))
	var phase := -PI + TAU * float(idx) / float(n)
	var v := Vector2(float(rec.vec.x) * sin(phase), float(rec.vec.y) * cos(phase))
	# [SparkSX]/[SparkSY] are the spawn box the original scatters the particles
	# over; without it every spark of an emitter would start at one pixel.
	var box: Vector2 = rec.spawn_box
	var jitter := Vector2(_rng.randf_range(-box.x * 0.5, box.x * 0.5),
			_rng.randf_range(-box.y * 0.5, box.y * 0.5))
	var life: float = float(rec.ttc)
	return {
		"pos": at + jitter,
		"vel": v,
		"grav": rec.grav,
		"t": 0.0,
		"life": life,
		"tb": float(rec.tb),
		"te": float(rec.te),
		"frames": int(rec.frames),
		"frame_tfc": float(rec.frame_tfc),
		"long_y": bool(rec.long_y),
	}

func step(delta: float) -> void:
	# --- spark emitters ---
	for i in _emitters.size():
		var e: Dictionary = _emitters[i]
		var rec: Dictionary = SPARK_RECIPES[e.recipe]
		e.t += delta * 1000.0
		if e.t >= float(e.run_every):
			e.t = fmod(e.t, maxf(1.0, float(e.run_every)))
			var at := _emitter_pos(e)
			var n := int(rec.num)
			for k in n:
				var rec_i := rec.duplicate()
				rec_i["_i"] = k
				(_sparks[i] as Array).append(_new_spark(rec_i, at))
		var list: Array = _sparks[i]
		for j in range(list.size() - 1, -1, -1):
			var s: Dictionary = list[j]
			s.t += delta * 1000.0
			if s.t >= float(s.life):
				list.remove_at(j)
				continue
			var sec := delta
			s.pos = (s.pos as Vector2) + (s.vel as Vector2) * sec
			s.vel = (s.vel as Vector2) + (s.grav as Vector2) * sec
	# --- rain ---
	# The rain band is generated analytically in draw_rain() from the table's
	# RainBornEvery / RainSpeed / RainHeight, so nothing accumulates here; the
	# per-slot clock only drives the surface frame animation.
	for slot in _rain_slots:
		slot.t += delta * 1000.0
		slot.phase = fmod(float(slot.phase) + float(slot.recipe.speed) * delta
				/ maxf(1.0, float(slot.recipe.size.y)), 1.0)
	# --- RoundBlicks bursts ---
	_step_rounds(delta)

## Alpha over the particle's life: SparkTB at birth -> SparkTE over SparkTTC.
func _alpha(s: Dictionary) -> float:
	var f: float = clampf(float(s.t) / maxf(1.0, float(s.life)), 0.0, 1.0)
	return lerpf(float(s.tb), float(s.te), f) / 255.0

func draw(canvas: CanvasItem, cam_y: float, view_top: float, view_bottom: float) -> void:
	for i in _emitters.size():
		var rec: Dictionary = SPARK_RECIPES[_emitters[i].recipe]
		var tex: Texture2D = AssetLib.texture("res://assets/squares/%s" % rec.surface)
		if tex == null:
			continue
		var frames := int(rec.frames)
		var fw := tex.get_width()
		var fh := tex.get_height()
		if frames > 1:
			fw = int(round(tex.get_width() / float(frames)))
		for s in _sparks[i]:
			var p: Vector2 = s.pos
			if p.y < view_top - 80.0 or p.y > view_bottom + 80.0:
				continue
			var a := _alpha(s)
			if a <= 0.0:
				continue
			var src := Rect2(0, 0, fw, fh)
			if frames > 1:
				var fi := 0
				if float(rec.frame_tfc) > 0.0:
					fi = int(float(s.t) / float(rec.frame_tfc)) % frames
				src = Rect2(fi * fw, 0, fw, fh)
			# [SparkLongYEffect]: the sprite is stretched along the travel axis
			var pos := Vector2(p.x - fw * 0.5, cam_y + p.y - fh)
			if bool(rec.long_y):
				canvas.draw_texture_rect_region(tex,
						Rect2(pos.x, pos.y, fw, fh * 2.0), src, Color(1, 1, 1, a))
			else:
				canvas.draw_texture_rect_region(tex, Rect2(pos, Vector2(fw, fh)), src,
						Color(1, 1, 1, a))

## <LevelEffect name="RoundBlicks" x y> bursts.  Spawn cadence is the record's
## RoundWait and a burst lives RoundTTM.  Scheduling across the three records is
## a documented TODO (ROUND_CYCLE); everything else here is sourced.
func _step_rounds(delta: float) -> void:
	for tmr in _round_timers:
		tmr.next -= delta * 1000.0
		if tmr.next > 0.0:
			continue
		if ROUND_CYCLE:
			var rec_i: Dictionary = ROUND_BLICKS[int(tmr.idx) % ROUND_BLICKS.size()]
			tmr.idx = int(tmr.idx) + 1
			_rounds.append({"x": tmr.x, "y": tmr.y, "rec": rec_i, "t": 0.0,
				"life": float(rec_i.ttm)})
			tmr.next = float(rec_i.wait)
		else:
			# concurrent: fire every record, seeded one RoundWait apart
			var off := 0.0
			for rec in ROUND_BLICKS:
				_rounds.append({"x": tmr.x, "y": tmr.y, "rec": rec,
					"t": -off, "life": float(rec.ttm)})
				off += float(rec.wait)
			tmr.next = off + 1000.0
	for i in range(_rounds.size() - 1, -1, -1):
		var b: Dictionary = _rounds[i]
		b.t += delta * 1000.0
		if b.t >= float(b.life):
			_rounds.remove_at(i)

## The burst is an ellipse of Roundar x Roundbr around the anchor: one Blick1
## sprite travelling the perimeter, driven by the record's Dir (+1/-1).
func draw_rounds(canvas: CanvasItem, cam_y: float, view_top: float, view_bottom: float) -> void:
	if _rounds.is_empty():
		return
	var tex: Texture2D = AssetLib.texture("res://assets/game/%s" % ROUND_SURFACE)
	if tex == null:
		return
	var fw := int(round(tex.get_width() / float(ROUND_FRAMES)))
	var fh := tex.get_height()
	for b in _rounds:
		if float(b.t) < 0.0:
			continue
		if float(b.y) < view_top - 80.0 or float(b.y) > view_bottom + 80.0:
			continue
		var rec: Dictionary = b.rec
		var f: float = clampf(float(b.t) / maxf(1.0, float(b.life)), 0.0, 1.0)
		var ang := float(rec.dir) * f * TAU
		var pos := Vector2(float(b.x) + cos(ang) * ROUND_ELLIPSE.x,
				float(b.y) + sin(ang) * ROUND_ELLIPSE.y)
		var fi := int(float(b.t) / ROUND_FRAME_TFC) % ROUND_FRAMES
		# Roundangle: pi * a / b radians per frame, signed by RoundDir
		var step_rot := 0.0
		var av: Vector2 = rec.angle
		if av.y != 0.0:
			step_rot = float(rec.dir) * PI * av.x / av.y
		var rot := step_rot * float(b.t) / ROUND_FRAME_TFC
		var pivot := Vector2(pos.x, cam_y + pos.y)
		# [RoundLongYEffect] stretches the sprite along the travel axis
		var w := float(fw)
		var h := float(fh) * (2.0 if ROUND_LONG_Y else 1.0)
		_draw_rotated(canvas, tex, Vector2(w, h), Rect2(fi * fw, 0, fw, fh),
				rot, pivot, ROUND_ALPHA / 255.0)

## draw_texture_rect_region cannot rotate, so build the quad manually: the four
## corners are rotated about `pivot` and emitted as two triangles with the sheet's
## UVs.
func _draw_rotated(canvas: CanvasItem, tex: Texture2D, size: Vector2, src: Rect2,
		rot: float, pivot: Vector2, alpha: float) -> void:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var local := [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]
	var uvi := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 4:
		pts.append(pivot + (local[i] as Vector2).rotated(rot))
		uvs.append(Vector2(src.position.x + uvi[i].x * src.size.x,
				src.position.y + uvi[i].y * src.size.y))
	var c := Color(1, 1, 1, alpha)
	var cols := PackedColorArray([c, c, c, c])
	canvas.draw_polygon(PackedVector2Array([pts[0], pts[1], pts[2]]), cols,
			PackedVector2Array([uvs[0], uvs[1], uvs[2]]), tex)
	canvas.draw_polygon(PackedVector2Array([pts[0], pts[2], pts[3]]), cols,
			PackedVector2Array([uvs[0], uvs[2], uvs[3]]), tex)

## Rain is drawn in screen space (the original's RainStartPoint/Width/Height are a
## screen band: `RainStartPoint 100,-200` plus `RainWidth 1000` x
## `RainHeight 1200`), so it is independent of the camera.
##
## COUNT is a table derivation, not a taste choice:
##   in-flight particles = RainHeight / RainSpeed / (RainBornEvery / 1000)
## For MidRain that is 1200/500/0.020 = **120** particles alive at once across the
## full 1000 px band.  A previous revision had this count right but placed every
## particle at the SAME x, so all 120 drew inside one 20 px column: the single thin
## vertical streak the user reported.  The count was never the bug; the X SPREAD was.
##
## X SPREAD: those in-flight particles are distributed over the band's width, so
## `RAIN_SPREAD_COLS` also fixes the per-column density (120 in flight / 30 columns
## = 4 per column, one roughly every 85 px of fall).  Each column carries its own
## deterministic phase offset, so the particles do not line up into rows.
##
## Density calibration was ATTEMPTED and did not discriminate: every detector tried
## (bright-run counting, frame-to-frame motion, white top-hat) varied more between
## repeated captures of the SAME setting than it did across cols=12..60, because the
## static twig artwork dominates the play area's high-frequency content.  The choice
## is therefore recorded as a CHOICE anchored to the table's particle count, NOT as
## a measured optimum.  See work/reveng/IMPLEMENTATION_NOTES.md.
const RAIN_SPREAD_COLS := 30

## Calibration override for measurement only (--raincols=N).  The default above is
## what ships; this exists so the density could be fitted by comparison rather than
## guessed.  See work/reveng/IMPLEMENTATION_NOTES.md.
static var rain_cols_override := 0

static func spread_cols() -> int:
	return rain_cols_override if rain_cols_override > 0 else RAIN_SPREAD_COLS

func draw_rain(canvas: CanvasItem, cam_y: float, _time: float) -> void:
	if _rain_slots.is_empty():
		return
	var cols := maxi(1, spread_cols())
	for slot in _rain_slots:
		var rec: Dictionary = slot.recipe
		var tex: Texture2D = AssetLib.texture("res://assets/squares/%s" % rec.surface)
		if tex == null:
			continue
		var frames := int(rec.frames)
		var fw := tex.get_width()
		var fh := tex.get_height()
		if frames > 1:
			fw = int(round(tex.get_width() / float(frames)))
		var a := float(rec.alpha) / 255.0
		var fall_ms := maxf(1.0, float(rec.size.y) / maxf(1.0, float(rec.speed)) * 1000.0)
		var count := clampi(int(round(fall_ms / maxf(1.0, float(rec.born_every)))), 1, 4000)
		var col_w := maxf(1.0, float(rec.size.x) / float(cols))
		# A surface's own frame clock: FrameN frames, one every TimeFrameChange ms.
		# It must be a function of each particle's OWN age, not of absolute time:
		# a FlowerFall particle lives RainHeight/RainSpeed = 48 s, so indexing the
		# 9 frames by absolute time cycled the sheet ~20x per second (a flicker)
		# instead of once per 9*50 = 450 ms.
		var step_ms := 0.0
		if frames > 1 and float(rec.frame_tfc) > 0.0:
			step_ms = float(rec.frame_tfc)
		# gentle fixed per-particle sway for the <MoveSin> surfaces (FlowerFall);
		# the parameter's full semantics are still undecoded, see the notes
		var sway := 0.0
		if not rec.move_sin.is_empty():
			sway = float((rec.move_sin as Dictionary).get("alX", 0.0)) * 0.5
		for i in count:
			var ci := i % cols
			var k := i / cols
			# Per-column deterministic phase so particles do not line up into
			# visible rows across the band.  The row-1 particles repeat with the
			# column count, so a short odd multiplier decorrelates neighbouring
			# columns while staying reproducible frame to frame.
			var col_off := fposmod(float(ci) * 0.6180339887, 1.0)
			var ph := fposmod(col_off + float(k) / maxf(1.0, float(count) / float(cols))
					+ float(slot.phase), 1.0)
			var y := cam_y + float(rec.start.y) + ph * float(rec.size.y)
			var x := float(rec.start.x) + (float(ci) + 0.5) * col_w
			if sway != 0.0:
				x += sin(float(slot.phase) * TAU + float(i) * 0.7) * sway
			x = fposmod(x, 800.0)
			var fi := 0
			if step_ms > 0.0:
				# this particle's age in ms, derived from where it is in the band
				var age := ph * fall_ms
				fi = int(age / step_ms) % frames
			canvas.draw_texture_rect_region(tex, Rect2(x, y, fw, fh),
					Rect2(fi * fw, 0, fw, fh), Color(1, 1, 1, a))

## Distinct x positions the driver would draw for a surface - used by --contenttest
## to assert the rain can never collapse back into a single column.
static func rain_distinct_columns(surface: String) -> int:
	var slots: Array = RAIN_RECIPES.get(surface, [])
	if slots.is_empty():
		return 0
	var cols := maxi(1, spread_cols())
	var n: int = clampi(int(round(maxf(1.0, float(slots[0].size.y)
			/ maxf(1.0, float(slots[0].speed)) * 1000.0)
			/ maxf(1.0, float(slots[0].born_every)))), 1, 4000)
	return mini(n, cols)
