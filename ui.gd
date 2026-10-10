extends Node
## What's on screen besides the visuals, and the controls: level meters,
## song / mode announcements (bottom-left, like the iTunes one), the
## right-click menu and the keys. It only reports what the user asked for;
## main.gd decides what happens.
##
## Keys: right-click = menu, 1-7 = lock a mode, 0 or A = auto, N = next,
##       F / F11 = fullscreen, D = level meters, Esc = quit.

signal lock_requested(mode: int)  # -1 = auto
signal next_requested
signal quit_requested

const MENU_AUTO := 100
const MENU_NEXT := 200
const MENU_FULLSCREEN := 201
const MENU_METERS := 202
const MENU_QUIT := 203

var locked := -1  # for the menu's check marks; main.gd keeps it up to date

var _mode_names: Array
var _hud: Label
var _toast: Label
var _toast_tween: Tween
var _menu: PopupMenu


func _init(mode_names: Array) -> void:
	_mode_names = mode_names


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.8))
	_hud.visible = false
	layer.add_child(_hud)

	_toast = Label.new()
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = 40
	_toast.offset_top = -240
	_toast.offset_bottom = -40
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	layer.add_child(_toast)

	_menu = PopupMenu.new()
	_menu.add_radio_check_item("Auto: change with each song   (0)", MENU_AUTO)
	_menu.add_separator("Lock on")
	for i in _mode_names.size():
		_menu.add_radio_check_item("%s   (%d)" % [_mode_names[i], i + 1], i)
	_menu.add_separator()
	_menu.add_item("Next mode   (N)", MENU_NEXT)
	_menu.add_item("Fullscreen   (F)", MENU_FULLSCREEN)
	_menu.add_item("Level meters   (D)", MENU_METERS)
	_menu.add_item("Quit   (Esc)", MENU_QUIT)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.5)
	_toast_tween.tween_interval(4.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 2.0)


func meters_visible() -> bool:
	return _hud.visible


## Level meters (D): a header line, then one row per [label, value]; a
## number shows as a bar, a string as is.
func set_meters(header: String, rows: Array) -> void:
	var text := header
	for row: Array in rows:
		var v: Variant = row[1]
		text += "\n%-9s%s" % [row[0], v if v is String else _bar(v)]
	_hud.text = text


func _bar(v: float) -> String:
	var n := int(clampf(v, 0.0, 1.0) * 30.0)
	return "#".repeat(n) + ".".repeat(30 - n) + " %.2f" % v


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_open_menu(event.position)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.keycode
	if key >= KEY_1 and key < KEY_1 + _mode_names.size():
		lock_requested.emit(key - KEY_1)
		return
	match key:
		KEY_0, KEY_A:
			_on_menu(MENU_AUTO)
		KEY_N:
			_on_menu(MENU_NEXT)
		KEY_F, KEY_F11:
			_on_menu(MENU_FULLSCREEN)
		KEY_D:
			_on_menu(MENU_METERS)
		KEY_ESCAPE:
			_on_menu(MENU_QUIT)


func _open_menu(at: Vector2) -> void:
	for idx in _menu.item_count:
		var id := _menu.get_item_id(idx)
		if id == MENU_AUTO:
			_menu.set_item_checked(idx, locked < 0)
		elif id >= 0 and id < _mode_names.size():
			_menu.set_item_checked(idx, id == locked)
	_menu.position = Vector2i(at)
	_menu.popup()


func _on_menu(id: int) -> void:
	match id:
		MENU_AUTO:
			lock_requested.emit(-1)
		MENU_NEXT:
			next_requested.emit()
		MENU_FULLSCREEN:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		MENU_METERS:
			_hud.visible = not _hud.visible
		MENU_QUIT:
			quit_requested.emit()
		_:
			if id >= 0 and id < _mode_names.size():
				lock_requested.emit(id)
