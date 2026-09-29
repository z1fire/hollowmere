class_name InputCtl
extends Control
## Unified input: keyboard + mouse (captured) on desktop, multi-touch joystick / look / buttons on phones.
## Also draws the touch controls.

var game
var move := Vector2.ZERO
var look := Vector2.ZERO
var attack := false
var jump := false
var sprint := false
var touch := false
var sens := 1.0
var is_touch := false

var _keys := {}
var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_ids := {}
var _btn_ids := {}   # touch index -> button name
var _pressed := {}   # button name -> true
var _font: Font


func setup(g) -> InputCtl:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_touch = DisplayServer.is_touchscreen_available()
	return self


func blocked() -> bool:
	return game.ui.modal_open or not game.running


# ------------------------------------------------ layout of touch buttons
func _unit() -> float:
	var s := get_viewport_rect().size
	return clampf(minf(s.x, s.y) * 0.3, 150.0, 240.0)


func _buttons() -> Dictionary:
	var s := get_viewport_rect().size
	var u := _unit()
	var br := s - Vector2(18, 18) - Vector2(u, u)   # top-left of the cluster box
	return {
		"attack": {"c": br + Vector2(u * 0.79, u * 0.79), "r": u * 0.21, "icon": "⚔️"},
		"interact": {"c": br + Vector2(u * 0.39, u * 0.83), "r": u * 0.15, "icon": "✋"},
		"jump": {"c": br + Vector2(u * 0.82, u * 0.4), "r": u * 0.12, "icon": "⤒"},
		"hp": {"c": br + Vector2(u * 0.53, u * 0.5), "r": u * 0.11, "icon": "❤"},
		"mp": {"c": br + Vector2(u * 0.28, u * 0.54), "r": u * 0.11, "icon": "💧"},
	}


func _draw() -> void:
	if not is_touch or not game.running or game.ui.modal_open:
		return
	var s := get_viewport_rect().size
	# joystick
	if _joy_id >= 0:
		var r := _unit() * 0.36
		draw_circle(_joy_origin, r, Color(1, 1, 1, 0.12))
		draw_arc(_joy_origin, r, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
		draw_circle(_joy_pos, r * 0.45, Color(0.95, 0.85, 0.6, 0.8))
	else:
		var c := Vector2(90, s.y - 110)
		draw_arc(c, 55, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0, true)
		draw_string(get_theme_default_font(), c + Vector2(-22, 5), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 44, 11, Color(1, 1, 1, 0.4))
	var ready: bool = game.focus != null
	for name in _buttons():
		var b: Dictionary = _buttons()[name]
		var down: bool = _pressed.has(name)
		var bg := Color(0.35, 0.27, 0.16, 0.85) if not down else Color(0.63, 0.47, 0.2, 0.9)
		var ring := Color(0.91, 0.77, 0.42, 0.7)
		var alpha := 1.0
		if name == "interact" and not ready:
			alpha = 0.5
		if name == "interact" and ready:
			ring = Color(1.0, 0.88, 0.54, 1.0)
			draw_circle(b.c, b.r + 6.0 + sin(Time.get_ticks_msec() / 200.0) * 2.0, Color(1.0, 0.88, 0.54, 0.25))
		draw_circle(b.c, b.r, Color(bg.r, bg.g, bg.b, bg.a * alpha))
		draw_arc(b.c, b.r, 0, TAU, 40, Color(ring.r, ring.g, ring.b, ring.a * alpha), 2.5, true)
		var fs := int(b.r * 0.9)
		draw_string(get_theme_default_font(), b.c + Vector2(-b.r, fs * 0.35), b.icon, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, Color(1, 1, 1, alpha))


# ------------------------------------------------ events
func _input(e: InputEvent) -> void:
	if game == null:
		return
	if e is InputEventScreenTouch:
		_touch(e)
		return
	if e is InputEventScreenDrag:
		_drag(e)
		return
	if e is InputEventMouse and (e as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return  # mouse events synthesized from touch: handled above
	if e is InputEventKey:
		var k := e as InputEventKey
		_keys[k.physical_keycode] = k.pressed
		if k.pressed and not k.echo:
			_key_pressed(k.physical_keycode)
		touch = false
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not blocked():
		look += (e as InputEventMouseMotion).relative * 0.0022 * sens
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				attack = mb.pressed
			elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var p = game.player
				p.select((p.sel + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else 5)) % 6)
		elif not mb.pressed:
			attack = false


func _unhandled_input(e: InputEvent) -> void:
	# clicking the 3D view (not the HUD) captures the mouse on desktop
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).device != InputEvent.DEVICE_ID_EMULATION:
		if not is_touch and game.running and not blocked() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func _key_pressed(code: int) -> void:
	var G = game
	if code == KEY_ESCAPE:
		G.ui.back()
		return
	if not G.running:
		return
	match code:
		KEY_I, KEY_B, KEY_TAB:
			G.ui.toggle("inventory")
		KEY_K, KEY_C:
			G.ui.toggle("skills")
		KEY_J, KEY_L:
			G.ui.toggle("quests")
		KEY_M:
			G.ui.toggle("map")
	if blocked():
		return
	match code:
		KEY_E, KEY_F:
			G.interact()
		KEY_SPACE:
			jump = true
		KEY_H:
			G.quick_potion("hp")
		KEY_G:
			G.quick_potion("mp")
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			G.player.select(code - KEY_1)


func _touch(e: InputEventScreenTouch) -> void:
	is_touch = true
	var i := e.index
	if e.pressed:
		if blocked() or game.ui.hud_hit(e.position):
			return
		touch = true
		var btns := _buttons()
		for name in btns:
			if e.position.distance_to(btns[name].c) < btns[name].r * 1.25:
				_btn_ids[i] = name
				_pressed[name] = true
				match name:
					"attack":
						attack = true
					"jump":
						jump = true
					"interact":
						game.interact()
					"hp":
						game.quick_potion("hp")
					"mp":
						game.quick_potion("mp")
				queue_redraw()
				return
		var s := get_viewport_rect().size
		if e.position.x < s.x * 0.42 and e.position.y > s.y * 0.3 and _joy_id < 0:
			_joy_id = i
			_joy_origin = e.position
			_joy_pos = e.position
		else:
			_look_ids[i] = e.position
	else:
		if _btn_ids.has(i):
			var name: String = _btn_ids[i]
			_pressed.erase(name)
			_btn_ids.erase(i)
			if name == "attack":
				attack = false
		if i == _joy_id:
			_joy_id = -1
			move = Vector2.ZERO
		_look_ids.erase(i)
	queue_redraw()


func _drag(e: InputEventScreenDrag) -> void:
	var i := e.index
	var k := 0.0048 * sens * (900.0 / clampf(get_viewport_rect().size.x, 600.0, 1400.0))
	if i == _joy_id:
		var r := _unit() * 0.36
		var d := e.position - _joy_origin
		if d.length() > r:
			d = d.normalized() * r
		_joy_pos = _joy_origin + d
		move = Vector2(d.x / r, -d.y / r)
		queue_redraw()
	elif _look_ids.has(i) or (_btn_ids.get(i, "") == "attack"):
		look += e.relative * k


func release_all() -> void:
	_joy_id = -1
	_look_ids.clear()
	_btn_ids.clear()
	_pressed.clear()
	move = Vector2.ZERO
	attack = false
	queue_redraw()


func _process(_dt: float) -> void:
	if game == null:
		return
	if blocked():
		move = Vector2.ZERO
		if game.ui.modal_open:
			attack = false
		return
	if not touch:
		var x := 0.0
		var y := 0.0
		if _keys.get(KEY_W, false) or _keys.get(KEY_UP, false):
			y += 1
		if _keys.get(KEY_S, false) or _keys.get(KEY_DOWN, false):
			y -= 1
		if _keys.get(KEY_D, false) or _keys.get(KEY_RIGHT, false):
			x += 1
		if _keys.get(KEY_A, false) or _keys.get(KEY_LEFT, false):
			x -= 1
		move = Vector2(x, y)
		sprint = _keys.get(KEY_SHIFT, false)
	if is_touch:
		queue_redraw()
