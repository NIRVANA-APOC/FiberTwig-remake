extends Control
## Fiber Twig remake.
##
## The screen flow and every widget action are taken from the original
## LabInterface file (Game/FiberTwig.li): ShowModal / HideModal / ChangeModal /
## SetProp / RunMethod are interpreted, so the interaction wiring is the one
## authored for the original game.  The RunMethod handlers implement the game
## logic itself.
##
## Geometry, camera, conveyor and placement rules were measured against the
## shipped reference screenshots and the recorded demo (see
## ../REVERSE_ENGINEERING.md §10).

const LevelLoader := preload("res://src/LevelLoader.gd")
const BoardWorld := preload("res://src/BoardWorld.gd")
const LayerOverlay := preload("res://src/Overlay.gd")
const OriginalUI := preload("res://src/OriginalUI.gd")

const SCREEN := Vector2(800, 600)
const BOARD_RECT := Rect2(0, 0, 600, 500)
const BELT_Y := 490.0               # top of the conveyor strip
const BELT_SLOT := 40.0
const BELT_BOTTOM := 585.0          # belt items are bottom aligned here (original: 0x249)
const BELT_SPEED := 25.0            # original: measured from demo.dat (10259 px / 409 s)
const BELT_SPEED_SCALE := 2.0       # playability: the original feels slow at 60 fps
const BELT_ENTRY := 799.0           # new twigs enter here (original)
const BELT_CAPACITY := 26           # original: belt count < 0x1a
const BELT_GAP := 2.0               # original spacing constant _DAT_004b977c
const DROP_RECT := Rect2(600, 400, 200, 100)   # original drop section (600,400)-(800,500)
const DROP_X := 615.0               # dropped twig start (original 0x267)
const DROP_BOTTOM := 480.0          # dropped twig bottom edge (original 0x1e0)
const DROP_END := 795.0             # dropped twig is removed at x >= 0x31b
const OVERFULL_TIME := 2.0          # original overfill delay DAT_004b97a8 (2000 ms)
# Camera motion: the executable advances a velocity byte by exactly 1 px/tick
# every game tick (FUN_0048b2d0 0x48b3e4) and moves the camera by that many
# pixels.  Under Wine the loop runs at ~180 ticks/s, which is why the start
# view pans ~930 px in ~0.3 s; the remake simulates the same fixed tick rate.
const CAM_HZ := 180.0
const CAM_TICK := 1.0 / CAM_HZ
const CAM_FINISH_SPEED := 360.0     # original finish pan: ±2 px/tick
const SCREENS := ["WTitle", "WGame", "WBetweenLevelMenu"]
## Original background music (FiberTwig.exe): WTitle and WBetweenLevelMenu play
## "In the lost forest2.mo3" (0x4aecc8 / 0x48693c), completing a level switches
## to "Be happy!.mo3" (0x4ab1d4) and the level itself plays its <PlayMusic>.
const MENU_MUSIC := "In the lost forest2.mo3"
const FINISH_MUSIC := "Be happy!.mo3"
## Original pointer textures (FiberTwig.exe 0x4a2cd0 sets DAT_004baf2c; the
## render pass draws the surface with its top-left at the mouse position, so
## the hotspot of every cursor is (0,0)).
const CURSOR_DEFAULT := "MouseCursor.png"
const CURSOR_HAMMER := "hammer1.png"
const CURSOR_AMPHORA := "cap1.png"

enum Tool { NONE, HAMMER, AMPHORA }

var ui: OriginalUI
var stack: Array = ["WTitle"]
var level_index := 0
var level: Dictionary = {}
var world: BoardWorld
var viewport: SubViewport
var board_container: SubViewportContainer
var fg: Control
var bg: Control

# ---- options (original options.cfg layout) --------------------------------
var opt_music := 2                  # index into 100/80/60/40/20/No
var opt_sound := 1
var opt_hints_off := false
var opt_fullscreen := false
var opt_bpp32 := true
var opt_language := "enu"
var opt_snapshot := {}
var opt_put_allow := 0              # options.cfg PutAllow: 0=paBorderFish 1=paAll 2=paNearlight
var debug_complex := false
var hint_take_fishka := true
var hint_take_quest := true
var hint_take_bonus := true
var belt_speed := BELT_SPEED * BELT_SPEED_SCALE
## Board cache: "next cells" of the PutAllow rule, the component id of every
## cell and the open joints per component.  It is rebuilt lazily whenever the
## board changes, so the placement checks (which run on every mouse move) stay
## cheap - the original maintains the same information incrementally.
var _board_dirty := true
var _lights_cache := {}
var _comp_of := {}          # cell (twig or transparent target) -> component id
var _comp_open := {}        # component id -> Array of [cell, direction index]
var _comp_count := 0

# ---- progress ------------------------------------------------------------
var total_score := 0
var hammers_total := 3
var caps_total := 3
var experience := 0
var plus := {"otb": 0, "luck": 0, "cap": 0, "life": 0, "hammer": 0}
var skills := {"otb": 90, "luck": 0, "life": 90}
var diff_flags := {"no_lose": false, "easy": false, "normal": true, "hard": false}
var start_bonus := -1
var save_names: Array[String] = []
var save_sel := 0
var scores: Array = []
var player_name := "Player"

# ---- per level -----------------------------------------------------------
var cam_y := 0.0
var cam_target := 0.0
var cam_vel := 0.0                  # finish animation speed (px/s)
var _cam_v := 0.0                   # camera velocity in px/tick (original signed byte)
var _cam_t := 0.0                   # fractional tick accumulator
var cam_mid := 0.0                  # original deceleration threshold (DAT_004badd0)
var cam_initial := 0.0
var cam_top_limit := 0.0
var cam_bottom_limit := 0.0
var belt: Array = []
var belt_moved := false             # original DAT_004baf6c (any belt twig moved)
var overfull := false
var overfull_t := 0.0
var drop_belt: Array = []           # reverse (drop section) conveyor
var drop_cd := 0.0
var held: Dictionary = {}
var has_held := false
var tool := Tool.NONE
var hammers := 0
var caps := 0
var score := 0
var combos: Array = []
var ghosts_covered := 0
var ghosts_total := 0
var generator_t := 0.0
var generator_period := 4.0
var no_lose_t := 0.0
var speed_up_t := 0.0
var all_bonus := false
var debug_all_bonus := false       # --allbonus: every generated twig is lucky
var sequence: Array = []
var sequence_index := 0
var quest_pic := ""
var quest_prob := 0.0
var bonus_prob := 0.0
var combo_preview := []
# debug: --capture=<path>,<delay>[,<interval>,<count>] saves viewport PNGs
var capture_path := ""
var capture_delay := 5.0
var capture_interval := 1.0
var capture_count := 1
var capture_t := 0.0
var capture_saved := 0
var combo_counter := 0
var level_done := false
## The game only runs while WGame is the topmost form (the level start progress
## bar and the pause menu are pushed on top of it).
var playing: bool:
	get:
		return not stack.is_empty() and stack.back() == "WGame"

var mouse_pos := Vector2(300, 250)
var hover_cell := Vector2i(-9999, -9999)
var message := ""
var message_t := 0.0
var hint_label := ""
var progress_t := 0.0

# ---- demo -----------------------------------------------------------------
var demo_events: Array = []          # [{t, kind, data}]
var demo_index := 0
var demo_time := 0.0
var demo_loops := 0

var _music_player: AudioStreamPlayer
var _current_music := ""
var _cursor_image := ""
var _audio_players: Array[AudioStreamPlayer] = []
var _audio_next := 0
var _time := 0.0
var _all_combos: Array = []

var autotest := false
var autotest_level := 0
var autotest_iter := 0
var autotest_done := false
var autotest_started := false
var wintest := false

func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -6.0
	add_child(_music_player)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_audio_players.append(p)
	_build_tree()
	ui = OriginalUI.new()
	_load_options()
	_apply_language(opt_language)
	_apply_options()
	_refresh_saves()
	_refresh_scores()
	_load_progress()
	_play_music(MENU_MUSIC)
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	if "--testsound" in args:
		_test_sounds()
		get_tree().quit()
		return
	if "--closetest" in args:
		_close_test()
		get_tree().quit()
		return
	if "--piecetest" in args:
		_piece_test()
		get_tree().quit()
		return
	for a in args:
		if a == "--filltest" or a.begins_with("--filltest="):
			var flevel := 0
			if a.begins_with("--filltest="):
				flevel = clampi(int(a.split("=")[1]), 0, 17)
			_fill_test(flevel)
			get_tree().quit()
			return
	for a in args:
		if a.begins_with("--level="):
			level_index = clampi(int(a.split("=")[1]), 0, 17)
		elif a == "--complex":
			debug_complex = true
		elif a.begins_with("--beltspeed="):
			belt_speed = maxf(5.0, float(a.split("=")[1]))
		elif a == "--allbonus":
			debug_all_bonus = true
	for a in args:
		if a == "--wintest":
			wintest = true
			autotest = true
		elif a.begins_with("--autotest="):
			autotest = true
			autotest_level = int(a.split("=")[1])
		elif a == "--autotest":
			autotest = true
		elif a.begins_with("--screen="):
			var sc := a.split("=")[1]
			if sc in SCREENS:
				if sc == "WGame":
					start_level(level_index)
				else:
					stack = [sc]
					if sc == "WBetweenLevelMenu":
						level = LevelLoader.parse_level("res://assets/levels/Level%d.txt" % level_index)
						_between_captions()
			else:
				stack = [sc if sc in SCREENS else "WTitle", sc]
				if sc == "WOptions":
					_snapshot_options()
				if sc == "WBetweenLevelMenu":
					level = LevelLoader.parse_level("res://assets/levels/Level%d.txt" % level_index)
				_enter_form(sc)
			break
		elif a.begins_with("--shot="):
			hammers_total = 8
			caps_total = 3
			start_level(int(a.split("=")[1]))
	for a in args:
		if a.begins_with("--capture="):
			var parts := a.split("=", true, 1)[1].split(",")
			capture_path = parts[0]
			if parts.size() > 1:
				capture_delay = maxf(0.0, float(parts[1]))
			if parts.size() > 2:
				capture_interval = maxf(0.05, float(parts[2]))
			if parts.size() > 3:
				capture_count = maxi(1, int(parts[3]))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()

func _build_tree() -> void:
	bg = LayerOverlay.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.draw_cb = _draw_background
	add_child(bg)
	board_container = SubViewportContainer.new()
	board_container.position = Vector2.ZERO
	board_container.size = Vector2(600, 500)
	board_container.stretch = true
	board_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_container.visible = false
	add_child(board_container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(600, 500)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.world_2d = World2D.new()
	board_container.add_child(viewport)
	world = BoardWorld.new()
	viewport.add_child(world)
	fg = LayerOverlay.new()
	fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fg.set_anchors_preset(Control.PRESET_FULL_RECT)
	fg.draw_cb = _draw_foreground
	add_child(fg)

# ---------------------------------------------------------------------------
# modal stack (the original LabScreen + ShowModal/HideModal/ChangeModal)
# ---------------------------------------------------------------------------

func _top() -> String:
	return str(stack.back())

func _is_screen(form: String) -> bool:
	return form in SCREENS

func _push_modal(form: String) -> void:
	if OS.get_environment("FT_DEBUG") == "1":
		print("[push] %s stack=%s" % [form, str(stack)])
	if stack.has(form):
		return
	stack.append(form)
	if form == "WOptions":
		_snapshot_options()
	_enter_form(form)
	queue_redraw()

func _pop_modal(form: String) -> void:
	if OS.get_environment("FT_DEBUG") == "1":
		print("[pop] %s stack=%s" % [form, str(stack)])
	var i := stack.find(form)
	if i > 0:
		stack.remove_at(i)
	else:
		if stack.size() > 1:
			stack.pop_back()
	_leave_form(form)
	queue_redraw()

func _change_modal(form: String) -> void:
	if OS.get_environment("FT_DEBUG") == "1":
		print("[change] %s stack=%s" % [form, str(stack)])
	if _is_screen(form):
		for s in stack:
			_leave_form(s)
		stack = [form]
	elif stack.size() > 1:
		_leave_form(str(stack.back()))
		stack[stack.size() - 1] = form
	else:
		# Changing to a dialog keeps the screen it belongs to behind it, so the
		# screen background stays (the dialog artworks are 450x450 panels).
		var base := str(stack[0]) if not stack.is_empty() and _is_screen(stack[0]) else ""
		if base != "":
			stack = [base, form]
		else:
			stack = [form]
	_enter_form(form)
	queue_redraw()

func _enter_form(form: String) -> void:
	board_container.visible = form == "WGame" or stack.has("WGame")
	match form:
		"WTitle":
			_play_music(MENU_MUSIC)
		"WStartDialog":
			ui.checked["RHammerWStartDialog"] = true
			ui.checked["RAmphoraWStartDialog"] = false
			ui.checked["RScoreWStartDialog"] = false
			ui.checked["RNoLoseWStartDialog"] = diff_flags.no_lose
			ui.checked["REasyWStartDialog"] = diff_flags.easy
			ui.checked["RNormalWStartDialog"] = diff_flags.normal
			ui.checked["RHardWStartDialog"] = diff_flags.hard
		"WBetweenLevelMenu":
			_play_music(MENU_MUSIC)
			_refresh_scores()
			if level.is_empty():
				level = LevelLoader.parse_level("res://assets/levels/Level%d.txt" % level_index)
			_between_captions()
		"WLoad":
			ui.focus_edit = "EditWLoad"
			ui.edit_text = save_names[save_sel] if not save_names.is_empty() else ""
			ui.edit_caret = ui.edit_text.length()
		"WSave":
			ui.focus_edit = "EditWSave"
			ui.edit_text = save_names[save_sel] if not save_names.is_empty() else "autosave"
			ui.edit_caret = ui.edit_text.length()
		"WGameFinishedDialog":
			ui.focus_edit = "EditWGameFinishedDialogue"
			ui.edit_text = player_name
			ui.edit_caret = ui.edit_text.length()

func _leave_form(form: String) -> void:
	if form in ["WLoad", "WSave", "WGameFinishedDialog", "WReplaceGameDialog"]:
		if ui.focus_edit.begins_with("Edit"):
			ui.focus_edit = ""
	if form == "WGame" and not stack.has("WGame"):
		_stop_game()

func _stop_game() -> void:
	board_container.visible = false
	# The music is not stopped here: the screen that takes over decides the
	# track (WTitle/WBetweenLevelMenu -> menu music, a level -> its PlayMusic).

## Execute the actions authored for a widget in the .li data.
func _exec_actions(widget: String, phase: String) -> void:
	if OS.get_environment("FT_DEBUG") == "1":
		print("[actions] %s %s -> %s" % [widget, phase, str(ui.actions(widget, phase))])
	for a in ui.actions(widget, phase):
		var parts: PackedStringArray = str(a).split(" ", false)
		if parts.is_empty():
			continue
		match parts[0]:
			"ShowModal":
				_push_modal(parts[1])
			"HideModal":
				_pop_modal(parts[1])
			"ChangeModal":
				_change_modal(parts[1])
			"SetProp":
				if parts.size() >= 4:
					ui.props[parts[1]] = (parts[3] == "True")
			"RunMethod":
				_method(parts[1])

func _play_widget_sound(widget: String) -> void:
	var s := str(ui.prop(widget, "SoundOnMDown", ""))
	if s != "":
		_play_sound(s)

# ---------------------------------------------------------------------------
# input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = get_local_mouse_position()
		if _top() == "WGame":
			_update_hover()
		queue_redraw()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_pos = event.position
		if event.pressed:
			if _top() == "WGame":
				_update_hover()
			_press(event.position)
		else:
			_release(event.position)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _top() == "WGame":
			_on_right_click()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
		if _top() == "WGame":
			_on_right_click()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)

func _press(pos: Vector2) -> void:
	var form := _top()
	if ui.focus_edit != "" and not _hits_edit(pos):
		ui.focus_edit = ""
	var name := ui.hit(pos)
	if OS.get_environment("FT_DEBUG") == "1":
		print("[press] stack=%s hit=%s pos=%s" % [str(stack), name, str(pos)])
	ui.pressed = name
	if name != "":
		_play_widget_sound(name)
		_exec_actions(name, "down")
		_click_widget(name, pos)
		if ui.nodes[name].Class != "TLabButton":
			_exec_actions(name, "up")
			ui.pressed = ""
	elif form == "WGame":
		_game_click(pos)
	queue_redraw()

func _release(pos: Vector2) -> void:
	var name := ui.pressed
	ui.pressed = ""
	if name == "":
		return
	if ui.hit(pos) == name:
		_exec_actions(name, "up")
	queue_redraw()

func _hits_edit(pos: Vector2) -> bool:
	for h in ui.hits:
		if ui.nodes[h.name].Class == "TLabEdit" and h.rect.has_point(pos):
			return true
	return false

## Non-action behaviour of a widget press (toggles, selections, focus ...)
func _click_widget(name: String, pos: Vector2) -> void:
	var cls: String = ui.nodes[name].Class
	match cls:
		"TLabRadioButton":
			ui.select_radio(name)
		"TLabCheckBox":
			ui.checked[name] = not ui.checked.get(name, false)
		"TLabEdit":
			ui.focus_edit = name
			ui.edit_caret = ui.edit_text.length()
		"TLabGrid":
			_grid_click(name, pos)

func _handle_key(event: InputEventKey) -> void:
	if ui.focus_edit != "":
		if event.keycode == KEY_BACKSPACE:
			ui.edit_backspace()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_pass_edit_to_handler()
		elif event.unicode > 31 and event.unicode < 127:
			ui.edit_insert(char(event.unicode))
		queue_redraw()
		return
	var form := _top()
	if event.keycode == KEY_ESCAPE:
		if form == "WGame":
			if has_held:
				_return_held()
			elif tool != Tool.NONE:
				tool = Tool.NONE
			else:
				_push_modal("WMenu")
		elif not _is_screen(form) and stack.size() > 1:
			_pop_modal(form)
		queue_redraw()
		return
	if form != "WGame":
		return
	if event.keycode == KEY_DELETE:
		if has_held:
			_discard_held()
		return
	if event.keycode == KEY_F3:
		tool = Tool.NONE if tool == Tool.HAMMER else Tool.HAMMER
		_play_sound("Click.wav")
		return
	if event.keycode == KEY_F4:
		tool = Tool.NONE if tool == Tool.AMPHORA else Tool.AMPHORA
		_play_sound("Click.wav")
		return
	if event.keycode == KEY_SPACE:
		if not has_held:
			if not belt.is_empty():
				_pickup(0)
			else:
				_spawn_twig(true)
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var idx := int(event.keycode - KEY_1)
		if not has_held and idx < belt.size():
			_pickup(idx)

func _pass_edit_to_handler() -> void:
	var form := _top()
	if form == "WLoad" or form == "WSave":
		save_names[save_sel] = ui.edit_text
	elif form == "WGameFinishedDialog":
		player_name = ui.edit_text
		ui.focus_edit = ""

func _grid_click(grid: String, pos: Vector2) -> void:
	var n: Dictionary = ui.nodes[grid]
	var o := _abs_origin(grid)
	var r := Rect2(o.x, o.y, float(n.Width), float(n.Height))
	if not r.has_point(pos):
		return
	var row_h := float(ui.prop(grid, "RowHeight", 20))
	var first := int(ui.grid_first.get(grid, 0))
	var idx := first + int((pos.y - r.position.y) / row_h)
	var count: int = (ui.grid_items.get(grid, []) as Array).size()
	if count == 0:
		return
	idx = clampi(idx, 0, count - 1)
	if grid == "GridWHighScores":
		ui.grid_sel[grid] = idx
		_play_sound("Click.wav")
		return
	save_sel = idx
	if ui.focus_edit.begins_with("Edit") and not save_names.is_empty():
		ui.edit_text = save_names[save_sel]
		ui.edit_caret = ui.edit_text.length()
	_play_sound("Click.wav")

## Fill the list grids of the visible dialogs (TLabGrid has no own content
## storage in the interface file, the game keeps the strings).
func _prepare_grids() -> void:
	ui.grid_items.clear()
	ui.grid_sel.clear()
	var grid := ""
	if stack.has("WLoad"):
		grid = "GridWLoad"
	elif stack.has("WSave"):
		grid = "GridWSave"
	if grid != "":
		var names: Array = []
		for n in save_names:
			names.append(n)
		ui.grid_items[grid] = names
		ui.grid_sel[grid] = save_sel
	if stack.has("WHighScores"):
		var lines: Array = []
		for sc in scores:
			lines.append("%s %d" % [str(sc.name), int(sc.score)])
		ui.grid_items["GridWHighScores"] = lines
		ui.grid_sel["GridWHighScores"] = int(ui.grid_sel.get("GridWHighScores", -1))

## The up/down arrows scroll the active list grid by one row.
func _grid_scroll(delta: int) -> void:
	var grid := ""
	for g in ["GridWLoad", "GridWSave", "GridWHighScores"]:
		if ui.grid_items.has(g):
			grid = g
	if grid == "":
		return
	var n: Dictionary = ui.nodes[grid]
	var row_h := float(ui.prop(grid, "RowHeight", 20))
	var visible := int(floor(float(n.Height) / row_h))
	var count: int = (ui.grid_items[grid] as Array).size()
	var first := int(ui.grid_first.get(grid, 0)) + delta
	ui.grid_first[grid] = clampi(first, 0, maxi(0, count - visible))

func _abs_origin(name: String) -> Vector2:
	var p := Vector2.ZERO
	var n: Variant = ui.nodes.get(name)
	var guard := 0
	while n != null and guard < 8:
		p += Vector2(float(n.get("Left", 0)), float(n.get("Top", 0)))
		n = ui.nodes.get(str(n.get("ParentName", "")))
		guard += 1
	return p

# ---------------------------------------------------------------------------
# RunMethod handlers (the game logic behind the interface actions)
# ---------------------------------------------------------------------------

func _method(name: String) -> void:
	if OS.get_environment("FT_DEBUG") == "1":
		print("[method] %s" % name)
	match name:
		"BNewWTitleMouseUp", "BLoadWTitleMouseUp", "BScoresWTitleMouseUp", "BOptionsWTitleMouseUp", \
		"BHelpWTitleMouseUp", "BNewWTitleMouseDown", "BOptionsWTitleMouseDown", "BQuitWTitleMouseDown":
			pass
		"BQuitWTitleMouseUp":
			_push_modal("WQuitGameDialog")
		"BPlayWStartDialogMouseUp":
			_apply_start_bonus()
			start_level(level_index)
		"BBackWStartDialogMouseUp", "BResumeWMenuMouseUp", "BCancelWAbortLivelDialogMouseUp":
			pass
		"BCancelWOptionsMouseUp": _restore_options()
		"BCancelWQuitGameDialogMouseUp", "BCancelWLoadMouseUp", \
		"BCancelWDeleteGameDialogMouseUp", "BCancelWClearDialogMouseUp", "BCancelWHighScoresMouseUp":
			pass
		"BAbortWMenuMouseUp":
			pass
		"BUpWLoadMouseUp", "BUpWSaveMouseUp", "BUpWHighScoresMouseUp": _grid_scroll(-1)
		"BDownWLoadMouseUp", "BDownWSaveMouseUp", "BDownWHighScoresMouseUp": _grid_scroll(1)
		"BOkWAbortLivelDialogMouseUp":
			_level_aborted()
		"BQuitWMenuMouseUp":
			pass
		"BOkWQuitGameDialogMouseUp":
			get_tree().quit()
		"BMenuWGameMouseUp":
			pass
		"BNextLevelWBetweenLevelMenuMouseUp":
			_next_level()
		"BMainMenuWBetweenLevelMenuMouseUp":
			_stop_game()
		"BOkWFinishLevelDialogMouseUp":
			_finish_level()
		"BOkWGameOverDialogMouseUp":
			start_level(level_index)
		"BOkWGameFinishedDialogMouseUp":
			_save_score(player_name, total_score)
		"BRightLiveWBetweenLevelMenuMouseUp": _add_skill("life", 1)
		"BLeftLiveWBetweenLevelMenuMouseUp": _add_skill("life", -1)
		"BRightDropAccelWBetweenLevelMenuMouseUp": _add_skill("otb", 1)
		"BLeftDropAccelWBetweenLevelMenuMouseUp": _add_skill("otb", -1)
		"BRightLuckyTwigWBetweenLevelMenuMouseUp": _add_skill("luck", 1)
		"BLeftLuckyTwigWBetweenLevelMenuMouseUp": _add_skill("luck", -1)
		"BRightAmphoraWBetweenLevelMenuMouseUp": _add_skill("cap", 1)
		"BLeftAmphoraWBetweenLevelMenuMouseUp": _add_skill("cap", -1)
		"BRightHammerWBetweenLevelMenuMouseUp": _add_skill("hammer", 1)
		"BLeftHammerWBetweenLevelMenuMouseUp": _add_skill("hammer", -1)
		"BOkWClearDialogMouseUp":
			scores.clear()
			_save_scores()
		"BOkWDeleteGameDialogMouseUp":
			_delete_save()
		"BLoadWLoadMouseUp":
			_load_selected()
		"BSaveWSaveMouseUp":
			_save_selected()
		"BOkWReplaceGameDialogMouseUp":
			_write_save(save_names[save_sel])
			_save_progress()
			_pop_modal("WSave")
		"BOkWOptionsMouseUp":
			_save_options()
		"BOkWLanguageMouseUp":
			_apply_language(_selected_language())
			_save_options()
		"BLanguageWOptionsMouseUp":
			pass
		"BDemoWTitleMouseUp":
			_start_demo()
		"BGenerateFishWGameMouseUp":
			_spawn_twig(true)
		_:
			# option radios / checkboxes / help topics
			var widget := name.trim_suffix("MouseUp").trim_suffix("MouseDown")
			if widget.begins_with("RMusic") or widget.begins_with("RNoMusic"):
				opt_music = _volume_index(widget, "Music")
				_apply_options()
			elif widget.begins_with("RSound") or widget.begins_with("RNoSound"):
				opt_sound = _volume_index(widget, "Sound")
				_apply_options()
			elif widget.begins_with("CheckBox"):
				_apply_checkbox(widget)
				_apply_options()

func _volume_index(widget: String, kind: String) -> int:
	if widget == "RNo%sWOptions" % kind:
		return 5
	var steps := ["100", "80", "60", "40", "20"]
	for i in steps.size():
		if widget == "R%s%sWOptions" % [kind, steps[i]]:
			return i
	return 0

func _apply_checkbox(widget: String) -> void:
	var value: bool = ui.checked.get(widget, false)
	match widget:
		"CheckBoxColorWOptions":
			opt_bpp32 = value
		"CheckBoxHintsWOptions":
			opt_hints_off = value
			world.show_hints = not value
		"CheckBoxFullScreenWOptions":
			opt_fullscreen = value
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)

func _add_skill(which: String, delta: int) -> void:
	var remaining := experience - int(plus.otb) - int(plus.luck) - int(plus.cap) - int(plus.life) - int(plus.hammer)
	if delta > 0 and remaining <= 0:
		return
	if delta < 0 and int(plus[which]) <= 0:
		return
	plus[which] = int(plus[which]) + delta
	if which == "hammer":
		hammers_total += delta
	elif which == "cap":
		caps_total += delta
	else:
		skills[which] += delta
	_write_save("autosave")

func _selected_language() -> String:
	for code in ["enu", "deu", "fra", "ptb", "rus"]:
		if ui.checked.get("R%sWLanguage" % code.to_upper(), false):
			return code
	return "enu"

func _apply_language(code: String) -> void:
	if not ui.apply_language(code):
		ui.apply_language("enu")
		code = "enu"
	opt_language = code
	# refresh captions that the game owns
	ui.captions["LLevelNumWGame"] = str(level_index + 1)
	ui.captions["LLevelNumWBetweenLevelMenu"] = "%02d." % (level_index + 1)
	queue_redraw()

# ---------------------------------------------------------------------------
# options.cfg / progress / saves / scores
# ---------------------------------------------------------------------------

const OPTIONS_PATH := "user://options.cfg"
const SAVE_DIR := "user://saves"

func _load_options() -> void:
	if not FileAccess.file_exists(OPTIONS_PATH):
		return
	var f := FileAccess.open(OPTIONS_PATH, FileAccess.READ)
	if f == null:
		return
	var section := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("["):
			section = line.trim_prefix("[").trim_suffix("]")
			continue
		var kv := line.split("=", false, 1)
		if kv.size() != 2:
			continue
		match kv[0].strip_edges():
			"SoundVolumeIdx": opt_sound = int(kv[1])
			"MusicVolumeIdx": opt_music = int(kv[1])
			"TurnOffHint": opt_hints_off = int(kv[1]) != 0
			"FullScreenMode": opt_fullscreen = int(kv[1]) != 0
			"BitsPerPixel": opt_bpp32 = int(kv[1]) == 32
			"PlayerName": player_name = kv[1].strip_edges()
			"Language": opt_language = kv[1].strip_edges()
			"PutAllow":
				var v := kv[1].strip_edges().to_lower()
				if v == "paall":
					opt_put_allow = 1
				elif v == "panearlight":
					opt_put_allow = 2
				else:
					opt_put_allow = 0

func _save_options() -> void:
	var f := FileAccess.open(OPTIONS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("[Options]")
	f.store_line("ScreenWidth=800")
	f.store_line("ScreenHeight=600")
	f.store_line("BitsPerPixel=%d" % (32 if opt_bpp32 else 16))
	f.store_line("SoundVolumeIdx=%d" % opt_sound)
	f.store_line("MusicVolumeIdx=%d" % opt_music)
	f.store_line("PlayerName=%s" % player_name)
	f.store_line("FullScreenMode=%d" % (1 if opt_fullscreen else 0))
	f.store_line("TurnOffHint=%d" % (1 if opt_hints_off else 0))
	f.store_line("Language=%s" % opt_language)
	f.store_line("[Game]")
	f.store_line("PutAllow=paBorder")
	f.store_line("TakeAllow=taDenied")

## The original applies radio/checkbox changes at once but only writes
## options.cfg when the dialog is confirmed; Cancel restores the snapshot.
func _snapshot_options() -> void:
	opt_snapshot = {
		"music": opt_music, "sound": opt_sound, "hints": opt_hints_off,
		"fullscreen": opt_fullscreen, "bpp": opt_bpp32,
	}

func _restore_options() -> void:
	if opt_snapshot.is_empty():
		return
	opt_music = int(opt_snapshot["music"])
	opt_sound = int(opt_snapshot["sound"])
	opt_hints_off = bool(opt_snapshot["hints"])
	opt_fullscreen = bool(opt_snapshot["fullscreen"])
	opt_bpp32 = bool(opt_snapshot["bpp"])
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if opt_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	_apply_options()

func _apply_options() -> void:
	ui.checked["CheckBoxColorWOptions"] = opt_bpp32
	ui.checked["CheckBoxHintsWOptions"] = opt_hints_off
	ui.checked["CheckBoxFullScreenWOptions"] = opt_fullscreen
	for i in 6:
		ui.checked["RMusic%sWOptions" % ["100", "80", "60", "40", "20", "No"][i]] = i == opt_music
		ui.checked["RSound%sWOptions" % ["100", "80", "60", "40", "20", "No"][i]] = i == opt_sound
	for code in ["enu", "deu", "fra", "ptb", "rus"]:
		ui.checked["R%sWLanguage" % code.to_upper()] = code == opt_language
	world.show_hints = not opt_hints_off
	_music_player.volume_db = [6.0, -2.0, -6.0, -12.0, -20.0, -80.0][opt_music]
	for p in _audio_players:
		p.volume_db = [0.0, -3.0, -6.0, -10.0, -16.0, -80.0][opt_sound]

func _save_path(name: String) -> String:
	return "%s/%s.sav" % [SAVE_DIR, name]

func _refresh_saves() -> void:
	save_names.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var d := DirAccess.open(SAVE_DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".sav"):
				save_names.append(f.get_basename())
	save_names.sort()
	if save_names.is_empty():
		save_names.append("autosave")
	save_sel = clampi(save_sel, 0, save_names.size() - 1)

func _write_save(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var lines := [
		'CurrentLevel="%d"' % level_index,
		'TotalScore="%d"' % total_score,
		'TotalHammerNum="%d"' % hammers_total,
		'TotalCapNum="%d"' % caps_total,
		'Experience="%d"' % experience,
		'PlusOtb="%d"' % plus.otb,
		'PlusLuck="%d"' % plus.luck,
		'PlusCap="%d"' % plus.cap,
		'PlusLife="%d"' % plus.life,
		'PlusHammer="%d"' % plus.hammer,
		'SkillOtb="%d"' % skills.otb,
		'SkillLuck="%d"' % skills.luck,
		'SkillLife="%d"' % skills.life,
		'NoLoose="%s"' % ("true" if diff_flags.no_lose else "false"),
		'Easy="%s"' % ("true" if diff_flags.easy else "false"),
		'Hard="%s"' % ("true" if diff_flags.hard else "false"),
	]
	var text := ""
	for l in lines:
		text += l + "\r\n"
	var f := FileAccess.open(_save_path(name), FileAccess.WRITE)
	if f:
		var out := PackedByteArray()
		for b in text.to_utf8_buffer():
			out.append((b + 0x33) & 0xFF)
		f.store_buffer(out)
	if not save_names.has(name):
		save_names.append(name)
		save_names.sort()
	_save_progress()

func _read_save(name: String) -> bool:
	var path := _save_path(name)
	if not FileAccess.file_exists(path):
		return false
	var raw := FileAccess.get_file_as_bytes(path)
	var text := ""
	for b in raw:
		text += char((b - 0x33) & 0xFF)
	var data := {}
	for line in text.split("\r\n", false):
		var kv := line.split("=", false, 1)
		if kv.size() == 2:
			data[kv[0].strip_edges()] = kv[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
	level_index = clampi(int(data.get("CurrentLevel", "0")), 0, 17)
	total_score = int(data.get("TotalScore", "0"))
	hammers_total = int(data.get("TotalHammerNum", "3"))
	caps_total = int(data.get("TotalCapNum", "3"))
	experience = int(data.get("Experience", "0"))
	plus.otb = int(data.get("PlusOtb", "0"))
	plus.luck = int(data.get("PlusLuck", "0"))
	plus.cap = int(data.get("PlusCap", "0"))
	plus.life = int(data.get("PlusLife", "0"))
	plus.hammer = int(data.get("PlusHammer", "0"))
	skills.otb = int(data.get("SkillOtb", "90"))
	skills.luck = int(data.get("SkillLuck", "0"))
	skills.life = int(data.get("SkillLife", "90"))
	diff_flags.no_lose = data.get("NoLoose", "false") == "true"
	diff_flags.easy = data.get("Easy", "false") == "true"
	diff_flags.hard = data.get("Hard", "false") == "true"
	diff_flags.normal = not (diff_flags.no_lose or diff_flags.easy or diff_flags.hard)
	return true

func _save_progress() -> void:
	var f := FileAccess.open("user://fibertwig_progress.save", FileAccess.WRITE)
	if f:
		f.store_string("%d\n%d\n%d\n%d\n" % [level_index, total_score, hammers_total, caps_total])

func _load_progress() -> void:
	if not _read_save("autosave"):
		level_index = 0
		total_score = 0
		hammers_total = 3
		caps_total = 3

func _load_selected() -> void:
	if save_names.is_empty():
		return
	if _read_save(save_names[save_sel]):
		total_score = total_score
		_pop_modal("WLoad")
		_change_modal("WStartDialog")

func _save_selected() -> void:
	save_names[save_sel] = ui.edit_text if ui.edit_text != "" else "autosave"
	var path := _save_path(save_names[save_sel])
	if FileAccess.file_exists(path):
		_push_modal("WReplaceGameDialog")
	else:
		_write_save(save_names[save_sel])

func _delete_save() -> void:
	if save_names.is_empty():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path(save_names[save_sel])))
	save_names.remove_at(save_sel)
	_refresh_saves()

func _refresh_scores() -> void:
	scores = []
	var f := FileAccess.open("user://fibertwig_scores.dat", FileAccess.READ)
	if f:
		while not f.eof_reached():
			var line := f.get_line()
			if line.is_empty():
				continue
			var parts := line.split("\t")
			if parts.size() >= 2:
				scores.append({"name": parts[0], "score": int(parts[1])})
	scores.sort_custom(func(a, b): return int(a.score) > int(b.score))

func _save_scores() -> void:
	var f := FileAccess.open("user://fibertwig_scores.dat", FileAccess.WRITE)
	if f:
		for s in scores:
			f.store_line("%s\t%d" % [s.name, s.score])

func _save_score(who: String, value: int) -> void:
	scores.append({"name": who if who != "" else "Player", "score": value})
	_refresh_scores()
	scores = scores.slice(0, 20)
	_save_scores()

# ---------------------------------------------------------------------------
# level flow
# ---------------------------------------------------------------------------

func _apply_start_bonus() -> void:
	var kind := 0
	for i in 3:
		if ui.checked.get(["RHammerWStartDialog", "RAmphoraWStartDialog", "RScoreWStartDialog"][i], false):
			kind = i
	start_bonus = kind
	match kind:
		0: hammers_total += 5
		1: caps_total += 5
		2: total_score += 200

func _set_difficulty_from_ui() -> void:
	diff_flags.no_lose = ui.checked.get("RNoLoseWStartDialog", false)
	diff_flags.easy = ui.checked.get("REasyWStartDialog", false)
	diff_flags.normal = ui.checked.get("RNormalWStartDialog", false)
	diff_flags.hard = ui.checked.get("RHardWStartDialog", false)
	if not (diff_flags.no_lose or diff_flags.easy or diff_flags.normal or diff_flags.hard):
		diff_flags.normal = true

func start_level(idx: int) -> void:
	_set_difficulty_from_ui()
	level_index = clampi(idx, 0, 17)
	level = LevelLoader.parse_level("res://assets/levels/Level%d.txt" % level_index)
	world.setup(level)
	world.show_hints = not opt_hints_off
	ghosts_covered = 0
	ghosts_total = world.ghosts.size()
	# The original camera is anchored to the pre-placed pattern: it may range
	# from the topmost to the bottommost initial twig and starts 1000 px above
	# the level bottom; placements then pull it towards the open joints.
	var top_y := 1.0e9
	var bot_y := -1.0e9
	for f in level.fishkas:
		top_y = minf(top_y, float(f.cell.y) * 40.0)
		bot_y = maxf(bot_y, float(f.cell.y) * 40.0)
	for g in level.ghosts:
		top_y = minf(top_y, float(g.cell.y) * 40.0)
		bot_y = maxf(bot_y, float(g.cell.y) * 40.0)
	if top_y > bot_y:
		top_y = 0.0
		bot_y = float(level.board_bottom) * 40.0
	cam_top_limit = top_y
	cam_bottom_limit = maxf(cam_top_limit, bot_y + 40.0 - 500.0)
	cam_initial = bot_y + 40.0 - 1000.0
	cam_y = cam_initial
	cam_target = cam_initial
	cam_mid = cam_initial
	cam_vel = 0.0
	_cam_v = 0.0
	_cam_t = 0.0
	world.cam_y = cam_y
	world.update_camera()
	belt.clear()
	belt_moved = false
	overfull = false
	overfull_t = 0.0
	drop_belt.clear()
	drop_cd = 0.0
	_invalidate_board()
	hint_take_fishka = true
	hint_take_quest = true
	hint_take_bonus = true
	has_held = false
	held = {}
	tool = Tool.NONE
	hammers = hammers_total
	caps = caps_total
	score = 0
	no_lose_t = 0.0
	speed_up_t = 0.0
	all_bonus = false
	level_done = false
	generator_period = max(0.3, float(level.generator_period) / 1000.0)
	# original: Easy multiplies the generator period by 1.5, Hard by ~0.85
	if diff_flags.easy:
		generator_period *= 1.5
	elif diff_flags.hard:
		generator_period *= 0.85
	generator_t = generator_period
	sequence.clear()
	for v in level.fish_type_sequence:
		sequence.append(int(v))
	sequence_index = 0
	quest_pic = str(level.hidden_fishka)
	quest_prob = float(level.hidden_fishka_prob)
	bonus_prob = float(level.fishka_with_bonus)
	_load_combos()
	_parse_combos()
	combo_counter = 0
	combo_preview = _combo_stamp(0)
	message = ""
	message_t = 0.0
	hint_label = ""
	demo_index = 0
	demo_time = 0.0
	_play_music(str(level.music))
	for s in stack:
		_leave_form(s)
	stack = ["WGame"]
	_enter_form("WGame")
	_push_modal("WProgressBar")
	progress_t = 0.45
	ui.captions["LLevelNumWGame"] = str(level_index + 1)
	# the original aims the camera at the lowest open joint already at level start
	_camera_follow()
	print("[level] %s fishkas=%d ghosts=%d maprows=%d pictures=%d period=%d cam=%.0f" % [level.name, level.fishkas.size(), world.ghosts.size(), level.picture_map.get("rows", []).size(), level.pictures.size(), level.generator_period, cam_y])
	queue_redraw()

func _level_aborted() -> void:
	score = 0
	_stop_game()
	stack = ["WBetweenLevelMenu"]
	_enter_form("WBetweenLevelMenu")
	queue_redraw()

func _next_level() -> void:
	if level_index >= 17:
		stack = ["WGame"]
		_enter_form("WGame")
		_push_modal("WGameFinishedDialog")
		return
	level_index += 1
	_write_save("autosave")
	_save_progress()
	stack = ["WBetweenLevelMenu"]
	_enter_form("WBetweenLevelMenu")
	_change_modal("WStartDialog")

func _finish_level() -> void:
	total_score += score
	var used := world.cells.size()
	var exp_gain := int(used / 10) + combos_done_count()
	if combos.size() > 0 and combos_done_count() >= combos.size():
		exp_gain += 2
	experience += exp_gain
	if level_index >= 17:
		stack = ["WGame"]
		_enter_form("WGame")
		_push_modal("WGameFinishedDialog")
	else:
		level_index += 1
		_write_save("autosave")
		_save_progress()
		_stop_game()
		stack = ["WBetweenLevelMenu"]
		_enter_form("WBetweenLevelMenu")
	queue_redraw()

func _check_state() -> void:
	if _top() != "WGame" or level_done:
		return
	if _level_complete():
		level_done = true
		cam_vel = CAM_FINISH_SPEED   # original ±2 px/tick finish pan
		# the original stops the level track and switches to Be happy!; the
		# completion itself has no extra effect sound (FUN_004ab084)
		_play_music(FINISH_MUSIC)
		_push_modal("WFinishLevelDialog")

# ---------------------------------------------------------------------------
# gameplay
# ---------------------------------------------------------------------------

func _update_hover() -> void:
	if mouse_pos.y < 500.0 and BOARD_RECT.has_point(mouse_pos):
		var wp := mouse_pos + Vector2(0, cam_y)
		hover_cell = Vector2i(int(floor((wp.x - 5.0) / 40.0)), int(floor(wp.y / 40.0)))
	else:
		hover_cell = Vector2i(-9999, -9999)
	world.preview_cell = hover_cell if (has_held and _top() == "WGame") else Vector2i(-9999, -9999)
	world.preview_shape = held.get("shape", {}) if has_held else {}
	world.preview_type = int(held.get("type", 0))
	world.preview_valid = can_place_shape(hover_cell, held.get("shape", {})) if has_held else false

func _game_click(pos: Vector2) -> void:
	# With a twig in hand the drop section (panel rectangle) or the play field
	# is used; otherwise a twig is taken or a tool is selected.
	if has_held:
		if DROP_RECT.has_point(pos):
			if drop_belt.is_empty() and drop_cd <= 0.0:
				_drop_held()
			return
		if BOARD_RECT.has_point(pos):
			if tool == Tool.HAMMER:
				_use_hammer(hover_cell)
			elif tool == Tool.AMPHORA:
				_use_amphora(hover_cell)
			else:
				_place(hover_cell)
		return
	var icon := _tool_icon_at(pos)
	if icon != Tool.NONE:
		if icon == Tool.HAMMER and hammers > 0:
			tool = Tool.HAMMER
			_play_sound("Click.wav")
		elif icon == Tool.AMPHORA and caps > 0:
			tool = Tool.AMPHORA
			_play_sound("Click.wav")
		return
	if tool == Tool.HAMMER or tool == Tool.AMPHORA:
		if tool == Tool.HAMMER:
			_use_hammer(hover_cell)
		elif BOARD_RECT.has_point(pos):
			_use_amphora(hover_cell)
		return
	var slot := _drop_hit(pos)
	if slot >= 0:
		_pickup(slot, true)
		return
	if pos.y >= BELT_Y:
		slot = _belt_hit(pos)
		if slot >= 0:
			_pickup(slot)
	return

## The hammer / amphora icons in the information panel (original DAT_004baf30/40).
func _tool_icon_at(pos: Vector2) -> int:
	var hammer_tex := AssetLib.texture("res://assets/game/hammer1.png")
	var cap_tex := AssetLib.texture("res://assets/game/cap1.png")
	if hammer_tex and Rect2(Vector2(620, 300), hammer_tex.get_size()).has_point(pos):
		return Tool.HAMMER
	if cap_tex and Rect2(Vector2(700, 300), cap_tex.get_size()).has_point(pos):
		return Tool.AMPHORA
	return Tool.NONE

func _on_right_click() -> void:
	if tool != Tool.NONE:
		tool = Tool.NONE
		_play_sound("Click.wav")
		return
	if has_held:
		held.shape = LevelLoader.rotate_shape(held.shape)
		held.type = int(held.shape.masks[0])
		_play_sound("RotateFishka.wav")

func _belt_hit(pos: Vector2) -> int:
	for i in range(belt.size() - 1, -1, -1):
		var t: Dictionary = belt[i]
		var h := float(t.get("h", BELT_SLOT))
		var y := float(t.get("y", BELT_BOTTOM - h))
		if Rect2(float(t.x), y, float(t.get("span", BELT_SLOT)), h).has_point(pos):
			return i
	return -1

func _drop_hit(pos: Vector2) -> int:
	for i in range(drop_belt.size() - 1, -1, -1):
		var t: Dictionary = drop_belt[i]
		var h := float(t.get("h", BELT_SLOT))
		var y := float(t.get("y", BELT_BOTTOM - h))
		if Rect2(float(t.x), y, float(t.get("span", BELT_SLOT)), h).has_point(pos):
			return i
	return -1

func _pickup(slot: int, from_drop := false) -> void:
	var t: Dictionary = (drop_belt[slot] if from_drop else belt[slot])
	var quest := bool(t.quest)
	# the original reveals a mystery twig the moment it is taken
	held = {"type": t.type, "shape": t.shape, "bonus": t.bonus, "quest": false, "revealed": true}
	has_held = true
	if from_drop:
		drop_belt.remove_at(slot)
	else:
		belt.remove_at(slot)
	_play_effect("TakeQuestFishka" if quest else "TakeFishka")
	if quest:
		if hint_take_quest:
			_show_hint("LHintFirstTakeQuestFishka")
			hint_take_quest = false
	elif bool(held.bonus):
		if hint_take_bonus:
			_show_hint("LHintFirstTakeBonusFishka")
			hint_take_bonus = false
	elif hint_take_fishka:
		_show_hint("LHintFirstTakeFishka")
		hint_take_fishka = false
	_update_hover()

func _return_held() -> void:
	if not has_held:
		return
	var shape: Dictionary = held.shape
	var h := _belt_height(shape)
	belt.append({"type": held.type, "shape": shape, "x": BELT_ENTRY, "y": BELT_BOTTOM - h,
		"span": _belt_span(shape), "h": h, "bonus": bool(held.get("bonus", false)), "quest": bool(held.get("quest", false)),
		"phase": randf() * TAU})
	has_held = false
	held = {}
	_play_sound("Click.wav")
	_update_hover()

## Throw the held twig into the drop section: it is put on the reverse
## conveyor and carried off the right end of the belt.
func _drop_held() -> void:
	if not has_held:
		return
	var shape: Dictionary = held.shape
	var h := _belt_height(shape)
	drop_belt.append({"type": held.type, "shape": shape, "x": DROP_X, "y": DROP_BOTTOM - h,
		"span": _belt_span(shape), "h": h, "bonus": bool(held.get("bonus", false)), "quest": false,
		"phase": randf() * TAU})
	has_held = false
	held = {}
	# the original uses a cooldown which the Drop Section Accelerator shortens
	drop_cd = 0.15 if speed_up_t > 0.0 else maxf(0.1, 0.6 * (1.0 - clampf(float(skills.otb) / 100.0, 0.0, 0.9)))
	_play_effect("PutFishkaInOtboynik")
	_update_hover()

func _discard_held() -> void:
	has_held = false
	held = {}
	_play_effect("PutFishkaInOtboynik")
	_update_hover()

func _spawn_twig(force := false) -> bool:
	# the original only checks the number of twigs on the belt (count < 26)
	if belt.size() >= BELT_CAPACITY:
		return false
	var shape := _next_twig_shape()
	var is_quest := false
	var is_bonus := false
	if quest_pic != "" and quest_prob > 0.0 and randf() < quest_prob:
		is_quest = true
	if all_bonus or debug_all_bonus:
		is_bonus = true
	elif bonus_prob > 0.0 and randf() < bonus_prob * (1.0 + float(skills.luck) / 100.0):
		is_bonus = true
	# new twigs enter at x=799, bottom aligned with the belt
	var h := _belt_height(shape)
	belt.append({"shape": shape, "type": int(shape.masks[0]), "x": BELT_ENTRY, "y": BELT_BOTTOM - h,
		"span": _belt_span(shape), "h": h, "bonus": is_bonus, "quest": is_quest,
		"phase": randf() * TAU})
	return true

## Pieces that are wider than one cell need their own slot spacing on the belt.
func _belt_span(shape: Dictionary) -> float:
	return float(shape.box.x) * BELT_SLOT

## Belt twigs are bottom aligned: y = 585 - image height (original 0x249 - h).
func _belt_height(shape: Dictionary) -> float:
	return float(shape.get("box", Vector2i.ONE).y) * BELT_SLOT

func _next_twig_shape() -> Dictionary:
	if debug_complex:
		var names := ["double2", "double2a", "adouble1", "tripl1", "tripl3", "tripl4", "skoba1", "skoba2", "skoba3", "skoba4"]
		return LevelLoader.shape_of_name(names[randi() % names.size()])
	if not sequence.is_empty():
		var t := int(sequence[sequence_index % sequence.size()])
		sequence_index += 1
		return LevelLoader.single_shape(t)
	var probs: Array = level.fishka_prob
	if probs.is_empty():
		return LevelLoader.single_shape(1 + randi() % 15)
	var total := 0
	for p in probs:
		total += maxi(0, int(p.prob))
	if total <= 0:
		return LevelLoader.single_shape(1 + randi() % 15)
	var r := randi() % total
	var acc := 0
	for p in probs:
		acc += maxi(0, int(p.prob))
		if r < acc:
			return LevelLoader.shape_of_name(str(p.name))
	return LevelLoader.single_shape(1)

## Cells a shape would occupy when its top left cell is placed at `cell`.
func shape_placement(cell: Vector2i, shape: Dictionary) -> Array:
	var out: Array = []
	var cells: Array = shape.get("cells", [Vector2i.ZERO])
	var masks: Array = shape.get("masks", [1])
	for i in cells.size():
		var c: Variant = cells[i]
		var dx: int = int(c[0]) if c is Array else int(c.x)
		var dy: int = int(c[1]) if c is Array else int(c.y)
		if dx >= 0 and dy >= 0:
			out.append({"cell": Vector2i(cell.x + dx, cell.y + dy), "type": int(masks[i])})
	return out

func can_place(cell: Vector2i, type: int) -> bool:
	return can_place_shape(cell, LevelLoader.single_shape(type))

func can_place_shape(cell: Vector2i, shape: Dictionary, check_lock := true) -> bool:
	if shape.is_empty():
		return false
	var placement := shape_placement(cell, shape)
	if placement.is_empty():
		return false
	for p in placement:
		var c: Vector2i = p.cell
		var t: int = p.type
		if c.x < 0 or c.x > 14:
			return false
		if c.y < level.board_top or c.y > level.board_bottom:
			return false
		if world.cells.has(c):
			return false
		if world.ghosts.has(c) and int(world.ghosts[c]) != t:
			return false
	if not _joints_consistent(placement):
		return false
	if not _put_allowed(placement):
		return false
	return not (check_lock and _closes_link(placement))

## Every joint that meets a neighbour (twig or transparent target) must be
## answered by the opposite joint on the other side - original FUN_0049f6f0.
func _joints_consistent(placement: Array) -> bool:
	for p in placement:
		for dir in BoardWorld.DIRS:
			var mine: bool = (int(p.type) & int(dir.bit)) != 0
			var q: Vector2i = p.cell + dir.d
			var info: Variant = world.cells.get(q)
			if info != null:
				if mine != ((int(info.type) & int(dir.opp)) != 0):
					return false
				continue
			var g: Variant = world.ghosts.get(q)
			if g != null and mine != ((int(g) & int(dir.opp)) != 0):
				return false
	return true

## Cells that must be covered next: empty (or transparent) cells next to an
## open joint - original DAT_004bae38.
func _invalidate_board() -> void:
	_board_dirty = true

## Rebuilds the PutAllow light cells, the component ids and the open joints of
## every component in one pass.
func _rebuild_board_cache() -> void:
	if not _board_dirty:
		return
	_board_dirty = false
	var nodes := {}
	for c in world.cells:
		nodes[c] = int(world.cells[c].type)
	for g in world.ghosts:
		nodes[g] = int(world.ghosts[g])
	_lights_cache = {}
	_comp_of = {}
	_comp_open = {}
	_comp_count = 0
	var stack: Array = []
	for c in nodes:
		if _comp_of.has(c):
			continue
		var cid := _comp_count
		_comp_count += 1
		_comp_of[c] = cid
		_comp_open[cid] = []
		stack.append(c)
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			var t: int = int(nodes[p])
			for di in BoardWorld.DIRS.size():
				var dir: Dictionary = BoardWorld.DIRS[di]
				if (t & int(dir.bit)) == 0:
					continue
				var q: Vector2i = p + dir.d
				var n2: Variant = nodes.get(q)
				var matched: bool = n2 != null and (int(n2) & int(dir.opp)) != 0
				if not matched:
					(_comp_open[cid] as Array).append([p, di])
				if n2 == null or world.ghosts.has(q):
					# empty or transparent target: one of the "next cells"
					_lights_cache[q] = true
				elif matched and not _comp_of.has(q):
					_comp_of[q] = cid
					stack.append(q)

func _light_cells() -> Dictionary:
	_rebuild_board_cache()
	return _lights_cache

func _covers_light(placement: Array) -> bool:
	var lights := _light_cells()
	for p in placement:
		if lights.has(p.cell):
			return true
	return false

func _connects_light(placement: Array) -> bool:
	var lights := _light_cells()
	for p in placement:
		for dir in BoardWorld.DIRS:
			if (int(p.type) & dir.bit) == 0:
				continue
			if lights.has(p.cell + dir.d):
				return true
	return false

## PutAllow policy (options.cfg): 0 = paBorderFish (must cover the next cell
## of the pattern), 1 = paAll, 2 = paNearlight (or link to a light cell).
func _put_allowed(placement: Array) -> bool:
	match opt_put_allow:
		1:
			return true
		2:
			return _covers_light(placement) or _connects_light(placement)
		_:
			return _covers_light(placement)

## Original ClosedLink rule (FUN_004a1130/FUN_004a1360): a placement is refused
## when its connected component ends up without any open joint (it can never be
## linked again) while other components still exist.  Loops are not affected;
## a placement that completes the level is always allowed.
## Original ClosedLink rule (FUN_004a1130/FUN_004a1360): a placement is refused
## when its connected component ends up without any open joint (it could never
## be linked again) while other components still exist.  Loops are not
## affected; a placement that completes the level is always allowed.
func _closes_link(placement: Array) -> bool:
	_rebuild_board_cache()
	var pl_types := {}
	for p in placement:
		pl_types[p.cell] = int(p.type)
	# components touched by the placement
	var touched := {}
	for p in placement:
		for dir in BoardWorld.DIRS:
			var q: Vector2i = p.cell + dir.d
			if _comp_of.has(q):
				touched[int(_comp_of[q])] = true
	# would the resulting component still have an open joint?
	var sealed := true
	for cid in touched:
		for open_joint in _comp_open[cid]:
			var oc: Vector2i = open_joint[0]
			var dir2: Dictionary = BoardWorld.DIRS[int(open_joint[1])]
			if not pl_types.has(oc + dir2.d):
				sealed = false
				break
		if not sealed:
			break
	if sealed:
		for p in placement:
			for dir in BoardWorld.DIRS:
				if (int(p.type) & int(dir.bit)) == 0:
					continue
				var q2: Vector2i = p.cell + dir.d
				if world.cells.has(q2) or world.ghosts.has(q2):
					continue
				if not pl_types.has(q2):
					sealed = false
					break
			if not sealed:
				break
	if not sealed:
		return false
	# the rule only applies while other components still exist
	var others := (_comp_count > 0) if touched.is_empty() else (_comp_count > touched.size())
	if not others:
		return false
	# a placement that completes the level is always allowed
	for p in placement:
		world.cells[p.cell] = {"type": p.type, "locked": false, "unhammer": false}
	var complete := _level_complete()
	for p in placement:
		world.cells.erase(p.cell)
	return not complete

## Win condition: one connected network, reaching the top row, all transparent
## twigs covered.
## Original completion rule (FUN_004a0538 returning true): every placed twig
## belongs to the one network and **no joint is left open** - a joint pointing
## at an empty cell or at an uncovered transparent twig keeps the level
## unfinished.  (There is no separate "reach the top row" test in the
## executable: the top of the pattern is closed like everything else.)
func _level_complete() -> bool:
	if not world.ghosts.is_empty():
		return false
	if _connected_components().size() != 1:
		return false
	for c in world.cells:
		var t: int = int(world.cells[c].type)
		for dir in BoardWorld.DIRS:
			if (t & int(dir.bit)) == 0:
				continue
			var q: Vector2i = c + dir.d
			var info: Variant = world.cells.get(q)
			if info == null or (int(info.type) & int(dir.opp)) == 0:
				return false
	return true

## The original camera target: the lowest open joint's next cell, 80 px below
## the top of the view (clamped to the level's initial pattern).
func _camera_follow() -> void:
	if not level.has("board_top"):
		return
	var lowest := -1.0e9
	for c in world.cells:
		var t: int = int(world.cells[c].type)
		for dir in BoardWorld.DIRS:
			if (t & dir.bit) == 0:
				continue
			var q: Vector2i = c + dir.d
			if world.cells.has(q) or world.ghosts.has(q):
				continue
			lowest = maxf(lowest, float(q.y) * 40.0)
	if lowest <= -1.0e8:
		return
	_set_cam_target(lowest - 80.0)

func _set_cam_target(y: float) -> void:
	cam_target = clampf(y, cam_top_limit, cam_bottom_limit)
	cam_mid = (cam_target + cam_y) / 2.0

## Original camera motion: accelerate one step per frame until half way, then
## decelerate; snap to the target when it is reached.
func _update_camera(delta: float) -> void:
	if cam_y == cam_target:
		_cam_t = 0.0
		_cam_v = 0.0
		return
	# Simulate the original per-tick integrator; a low render frame rate only
	# batches ticks, it does not change the motion.
	_cam_t += delta
	var budget := 16
	while _cam_t >= CAM_TICK and budget > 0:
		_cam_t -= CAM_TICK
		budget -= 1
		_cam_step()
	world.cam_y = cam_y
	world.update_camera()

## One original camera tick: velocity changes by exactly 1 px/tick until half
## of the way (0x4badd0), then back; the camera moves by `_cam_v` pixels and
## snaps to the target when it arrives.
func _cam_step() -> void:
	if cam_y < cam_target:
		if cam_y < cam_mid:
			_cam_v += 1.0
		elif cam_mid < cam_y and _cam_v > 1.0:
			_cam_v -= 1.0
		cam_y += _cam_v
		if cam_target < cam_y:
			cam_y = cam_target
			cam_mid = cam_y
			_cam_v = 0.0
	else:
		if cam_mid < cam_y:
			_cam_v -= 1.0
		elif cam_y < cam_mid and _cam_v < -1.0:
			_cam_v += 1.0
		cam_y += _cam_v
		if cam_y < cam_target:
			cam_y = cam_target
			cam_mid = cam_y
			_cam_v = 0.0
	_cam_v = clampf(_cam_v, -127.0, 127.0)   # original velocity is a signed byte

func _place(cell: Vector2i) -> void:
	var shape: Dictionary = held.get("shape", {})
	var valid := can_place_shape(cell, shape)
	if OS.get_environment("FT_DEBUG") == "1":
		print("[place] cell=%s shape=%s span=%s valid=%s" % [str(cell), str(shape.get("digits", [])), str(shape.get("box", Vector2i.ONE)), str(valid)])
	if not valid:
		_play_effect("ClosedLink")
		_show_hint("LHintClosedLink")
		return
	var placement := shape_placement(cell, shape)
	_play_effect("PutFishka")
	# A multi-cell fishka is one twig record in the original.  Keep the whole
	# shape on the board so the artwork is drawn (and removed) as a unit
	# instead of degrading into several basic single-cell twigs.
	var piece_id := -1
	if str(shape.get("art", "")) != "":
		piece_id = world.pieces.size()
		var covered: Array = []
		for p in placement:
			covered.append(p.cell)
		world.pieces.append({"shape": shape.duplicate(true), "base": cell, "cells": covered})
	var connected := false
	for p in placement:
		var t: int = p.type
		var info := {"type": t, "locked": false, "unhammer": false, "glow": 0.5}
		if piece_id >= 0:
			info["piece"] = piece_id
		world.cells[p.cell] = info
		if world.ghosts.has(p.cell) and int(world.ghosts[p.cell]) == t:
			world.ghosts.erase(p.cell)
			ghosts_covered += 1
			_play_effect("TwinkleFishka")
			_show_hint("LHintFirstTransparentFishka")
	for p in placement:
		for dir in BoardWorld.DIRS:
			if (p.type & dir.bit) == 0:
				continue
			var n: Variant = world.cells.get(p.cell + dir.d)
			if n != null and (int(n.type) & dir.opp) != 0:
				connected = true
	if connected:
		_play_effect("ConnectLink")
	for p in placement:
		var t2: int = p.type
		var sc := 10
		if t2 < level.fishka_score.size():
			sc = int(level.fishka_score[t2])
		score += sc
	if bool(held.get("bonus", false)):
		_play_effect("PutBonusFishka")
		_give_bonus(_roll_bonus(level.fishka_bonus_prob))
	has_held = false
	held = {}
	_invalidate_board()
	_camera_follow()
	_check_combos()
	_check_state()
	_update_hover()

func _use_hammer(cell: Vector2i) -> void:
	if hammers <= 0:
		_play_effect("UnableHammer")
		return
	if world.cells.has(cell):
		var info: Dictionary = world.cells[cell]
		# initial twigs and the locked top part cannot be smashed
		if bool(info.get("locked", false)) or bool(info.get("unhammer", false)):
			_play_effect("UnableHammer")
			return
		_remove_fishka(cell)
		hammers -= 1
		_play_effect("HammerFishka")
		_play_effect("HammerFishkaSound")
		_invalidate_board()
		_camera_follow()
		_check_state()
		_update_hover()
		return
	# belt and drop-section twigs can be smashed as well
	var slot := _belt_hit(mouse_pos)
	if slot < 0:
		slot = _drop_hit(mouse_pos)
		if slot >= 0:
			drop_belt.remove_at(slot)
			hammers -= 1
			_play_effect("HammerFishka")
			_play_effect("HammerFishkaSound")
		return
	belt.remove_at(slot)
	hammers -= 1
	_play_effect("HammerFishka")
	_play_effect("HammerFishkaSound")

func _use_amphora(cell: Vector2i) -> void:
	if caps <= 0:
		_play_effect("UnableHammer")
		return
	if world.cells.has(cell):
		var info: Dictionary = world.cells[cell]
		if bool(info.get("locked", false)) or bool(info.get("unhammer", false)):
			_play_effect("UnableHammer")
			return
		_remove_fishka(cell)
		caps -= 1
		_play_effect("ClipperFishkaNew")
		_invalidate_board()
		_camera_follow()
		_check_state()
		_update_hover()
		return
	if cell.x < 0 or cell.x > 14 or cell.y < level.board_top or cell.y > level.board_bottom:
		return
	# create the missing twig: a transparent target is matched exactly, other
	# places get the joint mask required by the surrounding twigs
	var t := 0
	if world.ghosts.has(cell):
		t = int(world.ghosts[cell])
	else:
		for dir in BoardWorld.DIRS:
			var n: Vector2i = cell + dir.d
			var info2: Variant = world.cells.get(n)
			if info2 != null and (int(info2.type) & dir.opp) != 0:
				t |= dir.bit
		if t == 0:
			return
	var shape := LevelLoader.single_shape(t)
	if not can_place_shape(cell, shape):
		_play_effect("ClosedLink")
		_show_hint("LHintClosedLink")
		return
	for p in shape_placement(cell, shape):
		world.cells[p.cell] = {"type": p.type, "locked": false, "unhammer": false, "glow": 0.5}
		if world.ghosts.has(p.cell) and int(world.ghosts[p.cell]) == p.type:
			world.ghosts.erase(p.cell)
			ghosts_covered += 1
			_play_effect("TwinkleFishka")
	score += 10
	caps -= 1
	_play_effect("ClipperFishkaNew")
	_invalidate_board()
	_camera_follow()
	_check_combos()
	_check_state()
	_update_hover()

## Removes the twig that occupies `cell`.  Multi-cell pieces (double / triple /
## skoba) are a single twig record in the original, so the whole piece goes
## away when any of its cells is hammered / clipped.
func _remove_fishka(cell: Vector2i) -> void:
	if not world.cells.has(cell):
		return
	var info: Dictionary = world.cells[cell]
	if info.has("piece"):
		var pid := int(info.piece)
		for c in world.cells.keys():
			if int(world.cells[c].get("piece", -1)) == pid:
				world.cells.erase(c)
		if pid >= 0 and pid < world.pieces.size():
			world.pieces[pid] = null
	else:
		world.cells.erase(cell)

func _load_combos() -> void:
	if not _all_combos.is_empty():
		return
	var raw := FileAccess.get_file_as_bytes("res://assets/data/FishCombinations.dat")
	for i in raw.size():
		if raw[i] >= 0x80:
			raw[i] = 0x20
	var parser := XMLParser.new()
	parser.open_buffer(raw)
	var stamps: Array = []
	var stamp: Array = []
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := parser.get_node_name()
				if tag == "FishkaCombination":
					stamps = []
				elif tag == "Stamp":
					stamp = []
				elif tag == "FishkaInStamp":
					var attrs := {}
					for i in parser.get_attribute_count():
						attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
					stamp.append({"d": Vector2i(int(attrs.get("x", "0")) / 40, int(attrs.get("y", "0")) / 40), "type": int(attrs.get("type", "0"))})
			XMLParser.NODE_ELEMENT_END:
				var tag2 := parser.get_node_name()
				if tag2 == "Stamp" and not stamp.is_empty():
					stamps.append(stamp)
				elif tag2 == "FishkaCombination" and not stamps.is_empty():
					_all_combos.append(stamps)

func _parse_combos() -> void:
	combos = []
	for v in level.comb_sequence:
		var idx := int(v) - 1
		if idx >= 0 and idx < _all_combos.size():
			combos.append({"stamps": _all_combos[idx], "done": false})

func _combo_stamp(i: int) -> Array:
	if combos.is_empty():
		return []
	var stamps: Array = combos[i % combos.size()].stamps
	if stamps.is_empty():
		return []
	return stamps[0]

func _check_combos() -> void:
	for c in combos:
		if bool(c.get("done", false)):
			continue
		if _matches_combo(c):
			c.done = true
			combo_counter += 1
			combo_preview = _combo_stamp(combo_counter % maxi(1, combos.size()))
			_play_effect("CombinationSound")
			_show_hint("LHintFishComb")
			_give_bonus(_roll_bonus(level.one_comb_bonus_prob))
			if combos_done_count() >= combos.size():
				_give_bonus(_roll_bonus(level.all_comb_bonus_prob))
			queue_redraw()
			return

func combos_done_count() -> int:
	var n := 0
	for c in combos:
		if bool(c.get("done", false)):
			n += 1
	return n

func _matches_combo(c: Dictionary) -> bool:
	for stamp in c.stamps:
		if stamp.is_empty():
			continue
		var first: Dictionary = stamp[0]
		for anchor in world.cells:
			var base: Vector2i = anchor - first.d
			var ok := true
			for item in stamp:
				var cell: Vector2i = base + item.d
				var info: Variant = world.cells.get(cell)
				if info == null or int(info.type) != int(item.type):
					ok = false
					break
			if ok:
				return true
	return false

func _roll_bonus(probs: Array) -> int:
	var total := 0
	for p in probs:
		total += maxi(0, int(p))
	if total <= 0:
		return -1
	var r := randi() % total
	var acc := 0
	for i in probs.size():
		acc += maxi(0, int(probs[i]))
		if r < acc:
			return i
	return -1

func _give_bonus(kind: int) -> void:
	match kind:
		0:
			hammers += 2
			_play_effect("GiveHammer")
		1:
			# ClearSteck: the original hammers every twig on the belt
			# (HammerFishka is visual only, HammerFishkaSound is BreakFishka)
			belt.clear()
			_play_effect("BombFishka")
			_play_effect("HammerFishkaSound")
		2:
			caps += 2
			_play_effect("GiveClipper")
		3:
			score += 100
			_play_effect("GiveScore")
		4:
			speed_up_t = 60.0
			_play_effect("GiveSpeedUpOtb")
		5:
			all_bonus = true
			for t in belt:
				t.bonus = true
			_play_effect("GiveBonusFishka")
		6:
			no_lose_t = 60.0
			_play_effect("GiveTimeToNoLose")

func _connected_components() -> Array:
	var seen := {}
	var comps := []
	for cell in world.cells:
		if seen.has(cell):
			continue
		var comp := []
		var st := [cell]
		seen[cell] = true
		while not st.is_empty():
			var c: Vector2i = st.pop_back()
			comp.append(c)
			var info: Dictionary = world.cells[c]
			for dir in BoardWorld.DIRS:
				if (int(info.type) & dir.bit) == 0:
					continue
				var n: Vector2i = c + dir.d
				var ni: Variant = world.cells.get(n)
				if ni == null or (int(ni.type) & dir.opp) == 0:
					continue
				if not seen.has(n):
					seen[n] = true
					st.append(n)
		comps.append(comp)
	return comps

# ---------------------------------------------------------------------------
# hints / effects / audio
# ---------------------------------------------------------------------------

func _show_hint(label: String) -> void:
	if opt_hints_off or message_t > 0.0:
		return
	if not ui.nodes.has(label):
		return
	message = str(ui.prop(label, "Caption", ""))
	hint_label = label
	message_t = 6.0

## Sound part of the original named effects (the `[PlaySound]` records of
## EffectsType.dat).  Effects without a `[PlaySound]` stay silent even when a
## similarly named WAV exists: BurnFishka.wav and Combination.wav are not
## referenced by any effect type in the shipped data.  The executable also
## triggers ClosedLink (visual only) when a placement is refused, so the
## refusal itself has no sound.
func _play_effect(name: String) -> void:
	match name:
		"PutFishka": _play_sound("PutFishka.wav")
		"TakeFishka", "TakeQuestFishka": _play_sound("GetFishka.wav")
		"RotateFishka", "RotateFishkaReverse": _play_sound("RotateFishka.wav")
		"PutFishkaInOtboynik": _play_sound("GetFishka.wav")
		"HammerFishkaSound": _play_sound("BreakFishka.wav")
		"ClipperFishkaNew": _play_sound("Clipper.wav")
		"PutBonusFishka": _play_sound("Link.wav")
		"UnableHammer": _play_sound("GameOver.wav")
		"ClosedLinkSound": _play_sound("ClosedLink.wav")
		"ExpSound": _play_sound("LaBomb.wav")
		"ElementSound": _play_sound("BonusElement.wav")
		"GiveHammer", "GiveClipper", "GiveScore": _play_sound("GetFishka.wav")
		"CombinationSound": _play_sound("ClosedLink.wav")
		"GameOver": _play_sound("GameOver.wav")
		"Roundy", "BonusSmall": _play_sound("BonusDone.wav")
		_: pass

func _play_music(file_name: String) -> void:
	if file_name.is_empty() or file_name == _current_music:
		return
	if OS.get_environment("FT_DEBUG") == "1":
		print("[music] %s -> %s" % [_current_music, file_name])
	_current_music = file_name
	var stream := AssetLib.music("res://assets/music/%s.ogg" % file_name.get_basename())
	if stream == null:
		_music_player.stop()
		return
	_music_player.stream = stream
	_music_player.play()

func _play_sound(name: String) -> void:
	var s := AssetLib.sound("res://assets/game/%s" % name)
	if s == null:
		return
	var p := _audio_players[_audio_next]
	_audio_next = (_audio_next + 1) % _audio_players.size()
	p.stream = s
	p.play()

## The original game hides the OS pointer and draws its own cursor surface
## (FiberTwig.exe 0x4a2cd0 / the render pass at 0x4945d2): MouseCursor.png
## normally, hammer1.png / cap1.png while a usable tool is armed and no twig
## is held.  The surface's top-left corner sits at the mouse position, so the
## custom cursor hotspot is (0,0).  Using an OS-level custom cursor keeps the
## pointer out of pixel-diff screenshots, exactly like the shipped captures.
func _sync_cursor() -> void:
	var name := CURSOR_DEFAULT
	if _top() == "WGame" and not has_held:
		if tool == Tool.HAMMER and hammers > 0:
			name = CURSOR_HAMMER
		elif tool == Tool.AMPHORA and caps > 0:
			name = CURSOR_AMPHORA
	if name == _cursor_image:
		return
	var tex := AssetLib.texture("res://assets/game/%s" % name)
	if tex == null:
		return
	_cursor_image = name
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2.ZERO)

# ---------------------------------------------------------------------------
# demo playback (demo.dat recorded session)
# ---------------------------------------------------------------------------

func _start_demo() -> void:
	demo_events.clear()
	demo_index = 0
	demo_time = 0.0
	var raw := FileAccess.get_file_as_bytes("res://assets/demo.dat")
	if raw.is_empty():
		return
	for i in raw.size():
		if raw[i] == 0x0D or raw[i] == 0x0A:
			raw[i] = 0x20
	var text := ""
	for b in raw:
		text += char(b)
	var re := RegEx.new()
	re.compile("<(\\w+)([^>]*)/>")
	for m in re.search_all(text):
		var attrs := {}
		var are := RegEx.new()
		are.compile("(\\w+)=\"([^\"]*)\"")
		for a in are.search_all(m.get_string(2)):
			attrs[a.get_string(1)] = a.get_string(2)
		var kind := m.get_string(1)
		if kind == "MouseMove":
			continue
		demo_events.append({"t": int(attrs.get("time", "0")), "kind": kind, "a": attrs})
	demo_events.sort_custom(func(x, y): return int(x.t) < int(y.t))
	# the demo was recorded on Level3
	level_index = 3
	start_level(3)
	demo_time = 0.0
	demo_index = 0
	for s in stack:
		_leave_form(s)
	stack = ["WGame"]
	_enter_form("WGame")

func _demo_step(delta: float) -> void:
	demo_time += delta * 1000.0
	var placements := 0
	while demo_index < demo_events.size() and float(demo_events[demo_index].t) <= demo_time:
		var e: Dictionary = demo_events[demo_index]
		demo_index += 1
		var a: Dictionary = e.a
		match str(e.kind):
			"NewFishkaInSteck":
				var t := int(a.get("fishtype", "1"))
				var demo_shape := LevelLoader.single_shape(t if t >= 1 and t <= 15 else 1)
				belt.append({"type": t, "shape": demo_shape, "x": BELT_ENTRY, "y": BELT_BOTTOM - BELT_SLOT,
					"span": BELT_SLOT, "h": BELT_SLOT, "bonus": a.get("bonus", "false") == "true", "quest": a.get("quest", "false") == "true",
					"phase": randf() * TAU})
			"MoveSteck":
				var incr := float(a.get("incr", "1"))
				for tw in belt:
					tw.x = maxf(5.0, float(tw.x) - incr)
			"MouseMove":
				mouse_pos = Vector2(float(a.get("x", "0")), float(a.get("y", "0")))
				_update_hover()
			"MouseLDown":
				mouse_pos = Vector2(float(a.get("x", "0")), float(a.get("y", "0")))
				_update_hover()
				var before := world.cells.size()
				_game_click(mouse_pos)
				if world.cells.size() > before:
					placements += 1
			"MouseRDown":
				_on_right_click()
			"GiveBonus":
				_give_bonus(int(a.get("ind", "0")))
			_: pass
	if demo_index >= demo_events.size():
		demo_index = 0
		demo_time = 0.0

# ---------------------------------------------------------------------------
# process
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_update_capture(delta)
	if message_t > 0.0:
		message_t -= delta
	if progress_t > 0.0:
		progress_t -= delta
		if progress_t <= 0.0 and stack.has("WProgressBar"):
			_pop_modal("WProgressBar")
	if _top() == "WGame" and playing:
		_update_game(delta)
	if level_done and stack.has("WFinishLevelDialog"):
		# original finish animation: the camera pans and bounces at the bounds
		cam_y += cam_vel * delta
		if cam_y <= cam_top_limit:
			cam_y = cam_top_limit
			cam_vel = absf(cam_vel)
		elif cam_y >= cam_bottom_limit:
			cam_y = cam_bottom_limit
			cam_vel = -absf(cam_vel)
		world.cam_y = cam_y
		world.update_camera()
	if stack.has("WBetweenLevelMenu"):
		_between_captions()
		_skill_hover()
	if autotest and _top() == "WTitle" and not autotest_started:
		autotest_started = true
		start_level(autotest_level)
	elif autotest and wintest and _top() == "WGame" and not autotest_done:
		autotest_done = true
		world.ghosts.clear()
		world.cells.clear()
		# a closed 2x2 ring: one component and not a single open joint
		world.cells[Vector2i(7, level.board_top)] = {"type": 6, "locked": false}
		world.cells[Vector2i(8, level.board_top)] = {"type": 12, "locked": false}
		world.cells[Vector2i(7, level.board_top + 1)] = {"type": 3, "locked": false}
		world.cells[Vector2i(8, level.board_top + 1)] = {"type": 9, "locked": false}
		_check_state()
		print("[wintest] top=%s components=%d complete=%s" % [_top(), _connected_components().size(), str(_level_complete())])
		get_tree().quit()
	elif autotest and _top() == "WGame":
		for _i in 25:
			if _top() == "WGame" and autotest_started:
				_run_autotest_step()
	elif autotest and (stack.has("WFinishLevelDialog") or stack.has("WGameOverDialog")):
		_finish_autotest()
	if world:
		world.queue_redraw()
	if fg:
		fg.queue_redraw()
	if bg:
		bg.queue_redraw()
	_sync_cursor()

func _update_game(delta: float) -> void:
	if no_lose_t > 0.0:
		no_lose_t = maxf(0.0, no_lose_t - delta)
	if speed_up_t > 0.0:
		speed_up_t = maxf(0.0, speed_up_t - delta)
	if drop_cd > 0.0:
		drop_cd = maxf(0.0, drop_cd - delta)
	_update_camera(delta)
	_update_belt(delta)
	_update_drop_belt(delta)
	_update_generator(delta)
	_update_overfull(delta)

## The conveyor moves every twig left by one step as long as there is room;
## the queue piles up at x<=5 with a 2 px gap (original FUN_0048bf78).
func _update_belt(delta: float) -> void:
	belt_moved = false
	if belt.is_empty():
		return
	var step := belt_speed * delta
	if float(belt[0].x) > 5.0:
		belt[0].x = maxf(5.0, float(belt[0].x) - step)
	for i in range(1, belt.size()):
		var prev: Dictionary = belt[i - 1]
		var t: Dictionary = belt[i]
		if float(t.x) > 5.0 and float(prev.x) + _belt_span(prev.shape) + BELT_GAP < float(t.x):
			t.x = maxf(5.0, float(t.x) - step)
			belt_moved = true

## Drop section: reverse conveyor at twice the belt speed; the twig is
## removed when it reaches the right end (original x >= 795).
func _update_drop_belt(delta: float) -> void:
	for i in range(drop_belt.size() - 1, -1, -1):
		var d: Dictionary = drop_belt[i]
		d.x = float(d.x) + belt_speed * 2.0 * delta
		if float(d.x) >= DROP_END:
			drop_belt.remove_at(i)

## The original generator adds a twig every Generator period as long as the
## belt holds less than 26 twigs (no game over here; the overfill rule does
## that).
func _update_generator(delta: float) -> void:
	generator_t += delta
	if generator_t >= generator_period:
		generator_t = 0.0
		_spawn_twig()

## Game over when the belt is completely jammed: more than 5 twigs, the first
## one at the left stop, the last one pressed against the previous one, no twig
## moved, no Time Control - for about two seconds (original FUN_0048b2d0).
func _update_overfull(delta: float) -> void:
	var full_now := false
	if belt.size() > 5 and not belt_moved and no_lose_t <= 0.0 and not level_done:
		var last: Dictionary = belt[belt.size() - 1]
		var prev: Dictionary = belt[belt.size() - 2]
		if float(belt[0].x) <= 5.0 and is_equal_approx(float(last.x), float(prev.x)):
			full_now = true
	if full_now:
		overfull = true
		overfull_t += delta
		if overfull_t >= OVERFULL_TIME:
			overfull_t = 0.0
			_play_effect("GameOver")
			_write_save("autosave")
			_push_modal("WGameOverDialog")
	else:
		overfull = false
		overfull_t = 0.0

func _update_capture(delta: float) -> void:
	if capture_path == "" or capture_saved >= capture_count:
		return
	capture_t += delta
	if _top() != "WGame" or capture_t < capture_delay + float(capture_saved) * capture_interval:
		return
	var base := capture_path
	var ext := base.get_extension()
	if ext == "":
		base += ".png"
		ext = "png"
	var path := base
	if capture_count > 1:
		path = "%s_%02d.%s" % [base.get_basename(), capture_saved, ext]
	get_viewport().get_texture().get_image().save_png(path)
	print("[capture] %s at t=%.2f" % [path, capture_t])
	capture_saved += 1
	if capture_saved >= capture_count:
		get_tree().quit()

# ---------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------

func _draw_background(o: Control) -> void:
	var base := str(stack[0])
	if base == "WGame":
		o.draw_texture_rect(AssetLib.texture("res://assets/game/GamePlay1.jpg"), Rect2(0, 0, 800, 600), false)
		return
	var pic := str(ui.prop(base, "Picture", ""))
	var tex: Texture2D = null
	if pic != "":
		tex = AssetLib.texture("res://assets/game/%s" % pic)
	if tex:
		o.draw_texture_rect(tex, Rect2(0, 0, 800, 600), false)
	else:
		o.draw_rect(Rect2(0, 0, 800, 600), Color(0.06, 0.1, 0.06), true)

func _draw_foreground(o: Control) -> void:
	ui.begin_frame(mouse_pos)
	_prepare_grids()
	if stack.has("WLanguage"):
		pass
	for i in stack.size():
		var form := str(stack[i])
		var top := i == stack.size() - 1
		match form:
			"WGame":
				world.cam_y = cam_y
				_draw_game(o, top)
			"WProgressBar":
				_draw_progress(o)
			"WHints":
				pass
			_:
				ui.draw_form(o, form, top)
	_draw_hint(o)

func _draw_progress(o: Control) -> void:
	ui.draw_form(o, "WProgressBar", false)
	var p: Dictionary = ui.nodes["ProgressBarWProgressBar"]
	var o0 := _abs_origin("ProgressBarWProgressBar")
	var frac := clampf(1.0 - progress_t / 0.45, 0.0, 1.0)
	var line := AssetLib.texture("res://assets/game/ProgressLine.png")
	var ot := AssetLib.texture("res://assets/game/ProgressOT.png")
	if line:
		o.draw_texture(line, o0)
	if ot:
		o.draw_texture_rect_region(ot, Rect2(o0.x, o0.y, float(p.Width) * frac, float(p.Height) * 0.75),
			Rect2(0, 0, float(ot.get_width()) * frac, float(ot.get_height()) * 0.75))

func _draw_hint(o: Control) -> void:
	if message_t <= 0.0 or message == "":
		return
	var lines := ui.wrapped(message, 330.0)
	var w := 0.0
	for l in lines:
		w = maxf(w, ui.text_width(l))
	var off := Vector2(-143, 165)
	if hint_label != "" and ui.nodes.has(hint_label):
		off = Vector2(float(ui.prop(hint_label, "Left", -143)), float(ui.prop(hint_label, "Top", 165)))
	var anchor := mouse_pos if _top() == "WGame" or stack.has("WBetweenLevelMenu") else Vector2(14, 30)
	var pos := anchor + off
	pos.x = clampf(pos.x, 6.0, 800.0 - w - 12.0)
	pos.y = clampf(pos.y, 6.0, 494.0 - lines.size() * 18.0)
	o.draw_rect(Rect2(pos.x - 8, pos.y - 6, w + 16, lines.size() * 18 + 12), Color(0, 0, 0, 0.78), true)
	for i in lines.size():
		ui.draw_text(o, lines[i], Vector2(pos.x, pos.y + i * 18), Color(1, 1, 1))

func _draw_game(o: Control, interactive: bool) -> void:
	_draw_belt(o)
	# HUD labels from the original layout
	ui.captions["LLevelNumWGame"] = str(level_index + 1)
	ui.captions["LScoreCountWGame"] = "%06d" % (total_score + score)
	ui.captions["LHammerCountWGame"] = str(hammers)
	ui.captions["LClipperCountWGame"] = str(caps)
	ui.captions["LCombCountWGame"] = "%d / %d" % [combos_done_count(), combos.size()]
	ui.captions["LDropAccelCounWGame"] = str(int(ceil(speed_up_t))) if speed_up_t > 0.0 else str(int(skills.otb))
	ui.captions["LLiveCountWGame"] = str(int(ceil(no_lose_t))) if no_lose_t > 0.0 else str(int(skills.life))
	ui.draw_form(o, "WGame", interactive)
	var hammer := AssetLib.texture("res://assets/game/hammer1.png")
	var cap := AssetLib.texture("res://assets/game/cap1.png")
	if hammer:
		o.draw_texture(hammer, Vector2(620, 300), Color(1, 1, 1, 1.0 if tool != Tool.HAMMER else 0.6))
	if cap:
		o.draw_texture(cap, Vector2(700, 300), Color(1, 1, 1, 1.0 if tool != Tool.AMPHORA else 0.6))
	_draw_combo(o)
	if has_held:
		var shape: Dictionary = held.get("shape", {})
		var t := LevelLoader.shape_texture(shape)
		if t:
			o.draw_texture(t, mouse_pos - Vector2(20, 20) + LevelLoader.shape_art_offset(shape), Color(1, 1, 1, 0.9))
	if no_lose_t > 0.0:
		o.draw_rect(Rect2(0, 0, 600, 500), Color(0, 0.4, 0.2, 0.08), true)

func _draw_combo(o: Control) -> void:
	if combo_preview.is_empty():
		return
	var minx := 99
	var maxy := -99
	for item in combo_preview:
		minx = mini(minx, item.d.x)
		maxy = maxi(maxy, item.d.y)
	var cols := 0
	for item in combo_preview:
		cols = maxi(cols, item.d.x - minx)
	var w := (cols + 1) * 40
	var h := (maxy + 1) * 40
	var ox := 700.0 - w / 2.0
	var oy := 222.0 - h / 2.0
	for item in combo_preview:
		var pos := Vector2(ox + (item.d.x - minx) * 40, oy + item.d.y * 40)
		var t := LevelLoader.type_texture(int(item.type))
		if t:
			o.draw_texture(t, pos, Color(1, 1, 1, 0.95))

func _draw_belt(o: Control) -> void:
	var belt_tex := AssetLib.texture("res://assets/game/lenta.png")
	if belt_tex:
		var off := fmod(_time * belt_speed, float(belt_tex.get_width()))
		var x := -off
		while x < SCREEN.x:
			o.draw_texture(belt_tex, Vector2(x, 587))
			x += belt_tex.get_width()
	for t in belt + drop_belt:
		var tex: Texture2D = null
		var h := float(t.get("h", BELT_SLOT))
		if bool(t.quest):
			tex = AssetLib.texture("res://assets/squares/%s" % quest_pic)
		else:
			var shape: Dictionary = t.get("shape", {})
			if shape.is_empty():
				continue
			tex = LevelLoader.shape_texture(shape)
		if tex == null:
			continue
		var pos := Vector2(float(t.x), float(t.get("y", BELT_BOTTOM - h)))
		if bool(t.bonus):
			# original FUN_00490abc: lucky twigs get an additive yellow pulse,
			# amount = Sin(ms/300 + phase)*64 + 150 (period ~1.9 s, per-twig phase);
			# this is the golden "flash" seen on the conveyor.
			var k := (sin(_time * 1000.0 / 300.0 + float(t.get("phase", 0.0))) * 64.0 + 150.0) / 255.0
			o.draw_texture(tex, pos)
			var flash := AssetLib.flash_texture(tex)
			if flash:
				o.draw_texture(flash, pos, Color(1, 1, 1, k))
		else:
			o.draw_texture(tex, pos)
	# overfill indicator while the belt is jammed (original ProgressOTT)
	if overfull and not level_done:
		var ot := AssetLib.texture("res://assets/game/ProgressOTT.png")
		if ot:
			var n := int(clampf(overfull_t / OVERFULL_TIME, 0.0, 1.0) * 10.0)
			for i in n:
				o.draw_texture(ot, Vector2(784, 578.0 - i * 8.0))

# ---------------------------------------------------------------------------
# helper: HUD/preview of the between level screen
# ---------------------------------------------------------------------------

func _between_captions() -> void:
	ui.level_tab = level_index
	ui.captions["LLevelWBetweenLevelMenu"] = "Level"
	ui.captions["LLevelNumWBetweenLevelMenu"] = "%02d." % (level_index + 1)
	ui.captions["LScoreCountWBetweenLevelMenu"] = str(total_score)
	ui.captions["LExperienceCountWBetweenLevelMenu"] = str(experience)
	ui.captions["LHammerCountWBetweenLevelMenu"] = str(hammers_total)
	ui.captions["LClipperCountWBetweenLevelMenu"] = str(caps_total)
	ui.captions["LLiveCountWBetweenLevelMenu"] = str(int(skills.life))
	ui.captions["LDropAccelCountWBetweenLevelMenu"] = str(int(skills.otb))
	ui.captions["LLuckyTwigCountWBetweenLevelMenu"] = str(int(skills.luck))
	ui.captions["LLiveExpWBetweenLevelMenu"] = "%+d" % int(plus.life)
	ui.captions["LDropAccelExpWBetweenLevelMenu"] = "%+d" % int(plus.otb)
	ui.captions["LLuckyTwigExpWBetweenLevelMenu"] = "%+d" % int(plus.luck)
	ui.captions["LAmphoraExpWBetweenLevelMenu"] = "%+d" % int(plus.cap)
	ui.captions["LHammerExpWBetweenLevelMenu"] = "%+d" % int(plus.hammer)
	ui.hidden["LLevelNameWBetweenLevelMenu"] = true
	# The hero portrait comes from <HeroPicture name="..."> of the level that is
	# about to be played; it is drawn at its native size, which is why the
	# shipped elf.png is exactly the size of the label (120x360).
	if OS.get_environment("FT_DEBUG") == "1":
		print("[between] level=%s hero=%s" % [level.get("name", "?"), level.get("hero", "?")])
	if not level.is_empty():
		ui.pics["LLevelHeroWBetweenLevelMenu"] = str(level.get("hero", ""))
	else:
		ui.pics.erase("LLevelHeroWBetweenLevelMenu")

func _skill_hover() -> void:
	if not stack.has("WBetweenLevelMenu"):
		return
	var rows := [
		[Rect2(0, 75, 183, 100), "LHintSkillLive"],
		[Rect2(0, 175, 183, 100), "LHintSkillDropAccel"],
		[Rect2(0, 275, 183, 100), "LHintSkillLuckyTwig"],
		[Rect2(0, 375, 183, 100), "LHintSkillAmphora"],
		[Rect2(0, 475, 183, 100), "LHintSkillHammer"],
	]
	for r in rows:
		if r[0].has_point(mouse_pos) and message_t <= 0.0:
			_show_hint(str(r[1]))
			return

# ---------------------------------------------------------------------------
# headless self test
# ---------------------------------------------------------------------------

func _run_autotest_step() -> void:
	autotest_iter += 1
	if autotest_iter > 4000:
		_finish_autotest()
		return
	if not has_held:
		if belt.is_empty():
			_spawn_twig(true)
		if belt.is_empty():
			return
		_pickup(0)
		if not has_held:
			return
	var best_cell := Vector2i(-9999, -9999)
	var best_shape: Dictionary = {}
	var best_score := -1.0
	var shapes: Array = [held.shape]
	var sh: Dictionary = held.shape
	for _i in 3:
		sh = LevelLoader.rotate_shape(sh)
		shapes.append(sh)
	# The search is capped so the headless test stays fast on big levels.
	var candidates: Array = _autotest_candidates()
	if candidates.size() > 150:
		candidates.shuffle()
		candidates = candidates.slice(0, 150)
	var found_ghost := false
	for cell in candidates:
		for cand in shapes:
			if not can_place_shape(cell, cand, false):
				continue
			var s := 0.0
			var ghost_hit := false
			for p in shape_placement(cell, cand):
				if world.ghosts.has(p.cell) and int(world.ghosts[p.cell]) == int(p.type):
					s += 500.0
					ghost_hit = true
				for dir in BoardWorld.DIRS:
					var n: Variant = world.cells.get(p.cell + dir.d)
					if n != null and (int(p.type) & dir.bit) and (int(n.type) & dir.opp):
						s += 10.0
			s += float(level.board_bottom - cell.y) * 3.0
			s -= float(cell.x - 7) if cell.x > 7 else float(7 - cell.x)
			if s > best_score:
				best_score = s
				best_cell = cell
				best_shape = cand
			if ghost_hit:
				found_ghost = true
		if found_ghost:
			break
	if best_cell.x < -999:
		_discard_held()
		generator_t = 999.0
		return
	held.shape = best_shape
	held.type = int(best_shape.masks[0])
	_place(best_cell)

func _autotest_candidates() -> Array:
	var out := []
	for cell in world.cells:
		for dir in BoardWorld.DIRS:
			var n: Vector2i = cell + dir.d
			if n.x < 0 or n.x > 14 or n.y < level.board_top or n.y > level.board_bottom:
				continue
			if world.cells.has(n) or out.has(n):
				continue
			out.append(n)
	for cell in world.ghosts.keys():
		if not out.has(cell):
			out.append(cell)
	return out

func _finish_autotest() -> void:
	if autotest_iter < 0:
		return
	autotest_iter = -100000
	var comps := _connected_components()
	var reached := false
	for cell in world.cells:
		if cell.y <= level.board_top:
			reached = true
			break
	print("[autotest] level=%d state=%s cells=%d components=%d top=%s ghosts_left=%d ghosts_total=%d score=%d" % [
		autotest_level, _top(), world.cells.size(), comps.size(), str(reached), world.ghosts.size(), ghosts_total, score])
	get_tree().quit()

func _test_sounds() -> void:
	var d := DirAccess.open("res://assets/game")
	for f in d.get_files():
		if not f.ends_with(".wav"):
			continue
		var bytes := FileAccess.get_file_as_bytes("res://assets/game/%s" % f)
		var st := AudioStreamWAV.load_from_buffer(bytes)
		print("[sound] %s -> %s" % [f, "ok" if st != null else "FAIL"])

## Smoke test for multi-cell fishkas: place a complex shape, check that it is
## kept as one piece on the board, and that hammering one of its cells removes
## the whole piece (the original stores one twig record per piece).
func _piece_test() -> void:
	start_level(3)
	progress_t = 0.0
	_pop_modal("WProgressBar")
	var shape := LevelLoader.shape_of_name("tripl1")
	print("[piecetest] shape art=%s cells=%s box=%s" % [shape.art, str(LevelLoader.shape_cells(shape)), str(shape.box)])
	var spot := Vector2i(-9999, -9999)
	for c in _autotest_candidates():
		if can_place_shape(c, shape):
			spot = c
			break
	if spot.x < -999:
		print("[piecetest] no legal spot found")
		return
	held = {"type": int(shape.masks[0]), "shape": shape, "bonus": false, "quest": false}
	has_held = true
	_place(spot)
	var placement := shape_placement(spot, shape)
	var pid := int(world.cells[placement[0].cell].get("piece", -1))
	var cells_ok := pid >= 0
	for p in placement:
		if int(world.cells[p.cell].get("piece", -2)) != pid:
			cells_ok = false
	print("[piecetest] placed=%s piece=%d all_cells_tagged=%s pieces=%d" % [str(spot), pid, str(cells_ok), world.pieces.size()])
	world._physics_process(1.0)   # the placement highlight must fade out
	var glow := 0.0
	for p in placement:
		glow += float(world.cells[p.cell].get("glow", 0.0))
	print("[piecetest] glow_after_1s=%.2f (expect 0.00)" % glow)
	_remove_fishka(placement[0].cell)
	var gone := true
	for p in placement:
		if world.cells.has(p.cell):
			gone = false
	print("[piecetest] after hammering one cell whole_piece_gone=%s slot_null=%s" % [str(gone), str(pid >= 0 and pid < world.pieces.size() and world.pieces[pid] == null)])

## Smoke test for the placement rules (LHintClosedLink).  It replays the
## tutorial session that used to produce the false "you can't lock a pattern"
## rejection and then checks the loop rule on synthetic 2x2 / 3x3 rings.
func _close_test() -> void:
	start_level(0)
	for pl in [[Vector2i(9, 240), 13], [Vector2i(6, 245), 12], [Vector2i(9, 243), 9],
			[Vector2i(7, 246), 13], [Vector2i(5, 241), 5], [Vector2i(5, 234), 3]]:
		var shape := LevelLoader.single_shape(int(pl[1]))
		print("[closetest] session %s t=%d -> can_place=%s" % [str(pl[0]), int(pl[1]), str(can_place_shape(pl[0], shape))])
		world.cells[pl[0]] = {"type": int(pl[1]), "locked": false, "unhammer": false}
		_invalidate_board()
	for pl in [[Vector2i(9, 239), 14], [Vector2i(9, 239), 13], [Vector2i(10, 240), 13],
			[Vector2i(10, 241), 13], [Vector2i(6, 238), 13]]:
		var shape2 := LevelLoader.single_shape(int(pl[1]))
		print("[closetest] retry  %s t=%d -> can_place=%s" % [str(pl[0]), int(pl[1]), str(can_place_shape(pl[0], shape2))])
	# synthetic check of the original lock rule on the real board:
	# three twigs of a tight 2x2 ring are already on the field, the fourth one
	# would leave that ring without any open joint while other components still
	# exist -> it must be refused (original FUN_004a1130).
	var base := Vector2i(11, 250)
	for r in [[Vector2i(0, 0), 6], [Vector2i(1, 0), 12], [Vector2i(0, 1), 3]]:
		world.cells[base + r[0]] = {"type": int(r[1]), "locked": false, "unhammer": false}
	_invalidate_board()
	print("[closetest] closing a locked 2x2 ring -> can_place=%s (expect false)" % str(can_place_shape(base + Vector2i(1, 1), LevelLoader.single_shape(9))))

## Fills a level cell by cell (the twig shape the surrounding open joints ask
## for) and reports whether the original completion rule is reached - the
## end-to-end check of the win condition.
func _fill_test(idx: int) -> void:
	start_level(idx)
	progress_t = 0.0
	_pop_modal("WProgressBar")
	var placed := 0
	for _it in 20000:
		if _level_complete():
			break
		var lights := _light_cells()
		# pick the best valid placement: prefer one that merges components and
		# caps as many joints as possible (a naive first-fit gets stuck)
		var best_cell := Vector2i(-9999, -9999)
		var best_mask := 0
		var best_score := -1
		for c in lights:
			var mask := 0
			var comps := {}
			if world.ghosts.has(c):
				mask = int(world.ghosts[c])
				for dir in BoardWorld.DIRS:
					if _comp_of.has(c + dir.d):
						comps[int(_comp_of[c + dir.d])] = true
			else:
				for dir in BoardWorld.DIRS:
					var n: Vector2i = c + dir.d
					var info: Variant = world.cells.get(n)
					if info != null and (int(info.type) & int(dir.opp)) != 0:
						mask |= int(dir.bit)
					elif lights.has(n):
						# build a bridge towards the next light (the design's shape)
						mask |= int(dir.bit)
					if _comp_of.has(n):
						comps[int(_comp_of[n])] = true
			if mask == 0:
				continue
			if not can_place_shape(c, LevelLoader.single_shape(mask)):
				continue
			var bits := 0
			for b in [1, 2, 4, 8]:
				if mask & b:
					bits += 1
			var score := comps.size() * 100 + bits
			if score > best_score:
				best_score = score
				best_cell = c
				best_mask = mask
		if best_score < 0:
			break
		var shape := LevelLoader.single_shape(best_mask)
		for p in shape_placement(best_cell, shape):
			world.cells[p.cell] = {"type": p.type, "locked": false, "unhammer": false}
			if world.ghosts.has(p.cell) and int(world.ghosts[p.cell]) == p.type:
				world.ghosts.erase(p.cell)
				ghosts_covered += 1
		_invalidate_board()
		placed += 1
		_check_state()
		if level_done:
			break
	var open := 0
	for c in world.cells:
		var t: int = int(world.cells[c].type)
		for dir in BoardWorld.DIRS:
			if (t & int(dir.bit)) == 0:
				continue
			var q: Vector2i = c + dir.d
			var info2: Variant = world.cells.get(q)
			if info2 == null or (int(info2.type) & int(dir.opp)) == 0:
				open += 1
	print("[filltest] level=%d placed=%d state=%s complete=%s components=%d ghosts_left=%d open_joints=%d" % [
		idx, placed, _top(), str(_level_complete()), _connected_components().size(), world.ghosts.size(), open])
