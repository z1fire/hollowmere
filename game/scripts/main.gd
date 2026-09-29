extends Node
## Entry point: title screen, loading screen, then a Game session.

var settings := {}
var ui_root: Control
var title_box: Control
var loading: Control
var load_label: Label
var load_bar: ProgressBar
var game: Game
var save := {}
var confirm_new := false
var theme: Theme


func _ready() -> void:
	get_tree().quit_on_go_back = false
	var touch := DisplayServer.is_touchscreen_available()
	settings = {"quality": "med" if touch else "high", "sens": 1.0, "vol": 0.7, "music": 0.5, "fov": 72.0 if touch else 75.0}
	if FileAccess.file_exists("user://settings.json"):
		var d = JSON.parse_string(FileAccess.open("user://settings.json", FileAccess.READ).get_as_text())
		if d is Dictionary:
			settings.merge(d, true)
	save = Game.load_data()
	_build_title()


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if game and game.running:
				game.ui.back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if game and game.running:
				game.save_game(true)


func _lbl(text: String, size: int, color: Color, fnt: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if fnt:
		l.add_theme_font_override("font", fnt)
	return l


func _build_title() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui_root)
	# painted dusk backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = """
shader_type canvas_item;
uniform float t;
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.07, 0.10, 0.17), mid = vec3(0.16, 0.13, 0.19), low = vec3(0.23, 0.14, 0.09);
	vec3 col = mix(top, mid, smoothstep(0.0, 0.5, uv.y));
	col = mix(col, low, smoothstep(0.5, 0.8, uv.y));
	col += vec3(1.0, 0.59, 0.24) * 0.35 * smoothstep(0.6, 1.1, uv.y) * (1.0 - abs(uv.x - 0.5));
	float x = uv.x * 14.0;
	float ridge = 0.72 - 0.06 * abs(sin(x * 0.9 + 1.3)) - 0.04 * sin(x * 2.3);
	if (uv.y > ridge) col = mix(vec3(0.08, 0.06, 0.04), vec3(0.05, 0.035, 0.024), smoothstep(ridge, 1.0, uv.y));
	float tree = step(0.93, fract(uv.x * 38.0)) * step(ridge - 0.05, uv.y) * step(uv.y, ridge + 0.02);
	col = mix(col, vec3(0.04, 0.03, 0.02), tree * 0.6);
	float star = step(0.9985, hash(floor(uv.x * 400.0) + floor(uv.y * 225.0) * 400.0)) * (1.0 - smoothstep(0.0, 0.45, uv.y));
	col += star * (0.6 + 0.4 * sin(t * 3.0 + uv.x * 50.0));
	COLOR = vec4(col, 1.0);
}
"""
	bg.material = sm
	ui_root.add_child(bg)
	var tw := create_tween().set_loops()
	tw.tween_method(func(v): sm.set_shader_parameter("t", v), 0.0, 100.0, 100.0)
	var ui_theme := Theme.new()
	var font: FontFile = Assets.fonts["AlegreyaSans-Regular"].duplicate() if Assets.loaded else null
	title_box = VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_CENTER)
	title_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	(title_box as VBoxContainer).add_theme_constant_override("separation", 12)
	ui_root.add_child(title_box)
	var cinzel: Font = load("res://assets/fonts/Cinzel.ttf")
	var sans: Font = load("res://assets/fonts/AlegreyaSans-Regular.ttf")
	var bold: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
	var emoji: Font = load("res://assets/fonts/Emoji.ttf")
	for f in [sans, bold]:
		(f as FontFile).fallbacks = [emoji]
	ui_theme.default_font = sans
	ui_theme.default_font_size = 20
	var sb := func(bg_c: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg_c
		s.border_color = border
		s.set_border_width_all(1)
		s.set_corner_radius_all(12)
		s.set_content_margin_all(14)
		return s
	ui_theme.set_stylebox("normal", "Button", sb.call(Color(0.12, 0.09, 0.05, 0.85), Color("#a07c2c")))
	ui_theme.set_stylebox("hover", "Button", sb.call(Color(0.2, 0.15, 0.08, 0.9), Color("#e8c46a")))
	ui_theme.set_stylebox("pressed", "Button", sb.call(Color("#6a4a12"), Color("#e8c46a")))
	ui_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	ui_theme.set_font("font", "Button", cinzel)
	ui_theme.set_color("font_color", "Button", Color("#f3e7c9"))
	ui_root.theme = ui_theme
	theme = ui_theme
	title_box.add_child(_lbl("⚜", 54, Color("#e8c46a"), emoji))
	var t := _lbl("HOLLOWMERE", 96, Color("#e8c46a"), cinzel)
	t.add_theme_constant_override("outline_size", 16)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title_box.add_child(t)
	title_box.add_child(_lbl("A   F A R M E R ' S   T A L E", 18, Color("#bfae88"), cinzel))
	title_box.add_child(_lbl("Till the soil. Take up arms. Become what you do.", 22, Color("#f3e7c9")))
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	title_box.add_child(gap)
	if not save.is_empty():
		var c := Button.new()
		c.text = "Continue\n" + "Day %d · %d gold" % [int(save.day), int(save.player.gold)]
		c.custom_minimum_size = Vector2(320, 70)
		c.add_theme_font_size_override("font_size", 22)
		c.pressed.connect(func(): _begin(false))
		title_box.add_child(c)
		c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var n := Button.new()
	n.text = "New Game"
	n.custom_minimum_size = Vector2(320, 58)
	n.add_theme_font_size_override("font_size", 22)
	n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	n.pressed.connect(func():
		if not save.is_empty() and not confirm_new:
			confirm_new = true
			n.text = "Tap again to overwrite save"
			get_tree().create_timer(3.0).timeout.connect(func():
				confirm_new = false
				n.text = "New Game")
			return
		_begin(true))
	title_box.add_child(n)
	var q := HBoxContainer.new()
	q.alignment = BoxContainer.ALIGNMENT_CENTER
	var ql := Label.new()
	ql.text = "Graphics  "
	ql.add_theme_color_override("font_color", Color("#bfae88"))
	q.add_child(ql)
	var opt := OptionButton.new()
	for s in ["Low", "Medium", "High"]:
		opt.add_item(s)
	opt.selected = ["low", "med", "high"].find(settings.quality)
	opt.item_selected.connect(func(i):
		settings.quality = ["low", "med", "high"][i]
		var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(settings)))
	q.add_child(opt)
	title_box.add_child(q)
	if OS.get_name() == "Web":
		var dl := Button.new()
		dl.text = "📱 Download the Android app (APK)"
		dl.flat = true
		dl.add_theme_color_override("font_color", Color("#e8c46a"))
		dl.pressed.connect(func(): OS.shell_open("https://github.com/%s/releases/latest/download/Hollowmere.apk" % Game.REPO))
		title_box.add_child(dl)
	var ver := Label.new()
	ver.text = "v" + _version()
	ver.modulate.a = 0.5
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.position -= Vector2(12, 8)
	ui_root.add_child(ver)
	# loading screen
	loading = ColorRect.new()
	(loading as ColorRect).color = Color("#0c0906")
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.visible = false
	var lv := VBoxContainer.new()
	lv.set_anchors_preset(Control.PRESET_CENTER)
	lv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lv.grow_vertical = Control.GROW_DIRECTION_BOTH
	lv.add_theme_constant_override("separation", 14)
	lv.add_child(_lbl("⚜", 48, Color("#e8c46a"), emoji))
	load_label = _lbl("Loading...", 22, Color("#bfae88"), cinzel)
	lv.add_child(load_label)
	load_bar = ProgressBar.new()
	load_bar.custom_minimum_size = Vector2(360, 10)
	load_bar.show_percentage = false
	load_bar.max_value = 1.0
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(1, 1, 1, 0.08)
	bgs.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#e8c46a")
	fill.set_corner_radius_all(5)
	load_bar.add_theme_stylebox_override("background", bgs)
	load_bar.add_theme_stylebox_override("fill", fill)
	lv.add_child(load_bar)
	loading.add_child(lv)
	ui_root.add_child(loading)


func _begin(is_new: bool) -> void:
	title_box.visible = false
	loading.visible = true
	await get_tree().process_frame
	await Assets.load_all(self, func(p: float):
		load_label.text = "Loading models & textures..."
		load_bar.value = p * 0.4)
	if is_new:
		Game.clear_save()
	game = Game.new()
	add_child(game)
	await game.setup(randi() % 1000000000, {} if is_new else save, settings, _version(), func(label: String, p: float):
		load_label.text = label
		load_bar.value = 0.4 + p * 0.6)
	ui_root.get_parent().queue_free()
	game.start(is_new)
