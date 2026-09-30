class_name GameUI
extends CanvasLayer
## HUD, minimap, hotbar, dialogue/shop/inventory panels, death & update banners.

const GOLD := Color("#e8c46a")
const GOLD_D := Color("#a07c2c")
const INK := Color("#f3e7c9")
const INK_D := Color("#bfae88")

var game
var theme: Theme
var font: FontFile
var title_font: FontFile
var root: Control
var dirty := true
var modal_open := false
var panel := ""
var data := {}
var inv_sel := -1
var shop_tab := "buy"

var class_lbl: Label
var lvl_lbl: Label
var hp_bar: ProgressBar
var mp_bar: ProgressBar
var hp_lbl: Label
var mp_lbl: Label
var tracker: RichTextLabel
var gold_lbl: Label
var clock_lbl: Label
var prompt: Label
var toasts: VBoxContainer
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var hurt: ColorRect
var hotbar: HBoxContainer
var held_lbl: Label
var menu_btns: HBoxContainer
var minimap: Minimap
var modal: Control
var panel_title: Label
var panel_body: VBoxContainer
var scroll: ScrollContainer
var death: Control
var death_lbl: Label
var update_bar: PanelContainer
var hurt_a := 0.0
var input_ctl: InputCtl
var map_img: ImageTexture


func setup(g) -> GameUI:
	game = g
	layer = 5
	_make_theme()
	root = Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	input_ctl = InputCtl.new()
	root.add_child(input_ctl)
	input_ctl.setup(g)
	_build_hud()
	_build_modal()
	return self


# ================================================================ theme
func _make_theme() -> void:
	font = Assets.fonts["AlegreyaSans-Regular"].duplicate()
	font.fallbacks = [Assets.fonts.Emoji]
	var bold: FontFile = Assets.fonts["AlegreyaSans-Bold"].duplicate()
	bold.fallbacks = [Assets.fonts.Emoji]
	title_font = Assets.fonts.Cinzel.duplicate()
	title_font.fallbacks = [Assets.fonts.Emoji]
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	var sb := func(bg: Color, border: Color, radius := 10, bw := 1, pad := 10) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(bw)
		s.set_corner_radius_all(radius)
		s.set_content_margin_all(pad)
		return s
	theme.set_stylebox("normal", "Button", sb.call(Color("#3a2c1a"), Color(GOLD, 0.35)))
	theme.set_stylebox("hover", "Button", sb.call(Color("#4a3822"), Color(GOLD, 0.6)))
	theme.set_stylebox("pressed", "Button", sb.call(Color("#6a4a1a"), GOLD))
	theme.set_stylebox("disabled", "Button", sb.call(Color("#2a2016"), Color(GOLD, 0.15)))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", Color(INK, 0.35))
	theme.set_font("font", "Button", bold)
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	theme.set_stylebox("panel", "PanelContainer", sb.call(Color(0.1, 0.07, 0.04, 0.96), GOLD_D, 16, 1, 0))
	theme.set_stylebox("panel", "Panel", sb.call(Color(0, 0, 0, 0.3), Color(GOLD, 0.35), 12, 1, 10))
	theme.set_color("default_color", "RichTextLabel", INK)
	theme.set_font("bold_font", "RichTextLabel", bold)
	theme.set_stylebox("normal", "LineEdit", sb.call(Color("#2e2214"), Color(GOLD, 0.35)))


func _lbl(text: String, size := 18, color := INK, outline := 0, fnt: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
	if fnt:
		l.add_theme_font_override("font", fnt)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _btn(text: String, cb: Callable, size := 18, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size.y = 44
	if primary:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#8a6a2a")
		s.border_color = GOLD
		s.set_border_width_all(1)
		s.set_corner_radius_all(10)
		s.set_content_margin_all(10)
		b.add_theme_stylebox_override("normal", s)
	b.pressed.connect(func():
		game.audio.play("click")
		cb.call())
	return b


func _bar(color: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 22)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.border_color = Color(GOLD, 0.45)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(11)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(11)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fill)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# ================================================================ HUD
func _build_hud() -> void:
	# top-left: class, bars, quest tracker
	var tl := VBoxContainer.new()
	tl.position = Vector2(16, 12)
	tl.custom_minimum_size = Vector2(300, 0)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)
	var row := HBoxContainer.new()
	class_lbl = _lbl("Farmhand", 26, GOLD, 6, title_font)
	lvl_lbl = _lbl("Lv 1", 16, INK, 4)
	row.add_child(class_lbl)
	row.add_child(lvl_lbl)
	tl.add_child(row)
	for which in ["hp", "mp"]:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(300, 22)
		var bar := _bar(Color("#d8453a") if which == "hp" else Color("#3f7fe0"))
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(bar)
		var l := _lbl("", 14, INK, 4)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(l)
		tl.add_child(holder)
		if which == "hp":
			hp_bar = bar
			hp_lbl = l
		else:
			mp_bar = bar
			mp_lbl = l
	tracker = RichTextLabel.new()
	tracker.bbcode_enabled = true
	tracker.fit_content = true
	tracker.scroll_active = false
	tracker.custom_minimum_size = Vector2(300, 0)
	tracker.add_theme_font_size_override("normal_font_size", 15)
	tracker.add_theme_constant_override("outline_size", 5)
	tracker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(tracker)
	# top-right: minimap, gold, clock, menu buttons
	var tr := VBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.position = Vector2(-16, 10)
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tr)
	minimap = Minimap.new()
	minimap.setup(game, self)
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	tr.add_child(minimap)
	gold_lbl = _lbl("🪙 0", 20, GOLD, 5)
	gold_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	tr.add_child(gold_lbl)
	clock_lbl = _lbl("", 16, INK, 5)
	clock_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	tr.add_child(clock_lbl)
	menu_btns = HBoxContainer.new()
	menu_btns.size_flags_horizontal = Control.SIZE_SHRINK_END
	for pair in [["🎒", "inventory"], ["📜", "skills"], ["📖", "quests"], ["🗺️", "map"], ["⚙️", "menu"]]:
		var b := _btn(pair[0], func(): toggle(pair[1]), 24)
		b.custom_minimum_size = Vector2(50, 50)
		menu_btns.add_child(b)
	tr.add_child(menu_btns)
	# centre: crosshair, prompt, toasts, banner
	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.85)
	cross.size = Vector2(6, 6)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position -= Vector2(3, 3)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	prompt = _lbl("", 20, INK, 6)
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.position.y += 60
	root.add_child(prompt)
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.position.y = 12
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER)
	banner_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner_box.position.y -= 120
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_title = _lbl("", 48, GOLD, 12, title_font)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub = _lbl("", 20, INK, 6)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_title)
	banner_box.add_child(banner_sub)
	banner_box.modulate.a = 0.0
	root.add_child(banner_box)
	hurt = ColorRect.new()
	hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := ShaderMaterial.new()
	hs.shader = Shader.new()
	hs.shader.code = "shader_type canvas_item;\nuniform float a = 0.0;\nvoid fragment(){ float d = distance(UV, vec2(0.5)); COLOR = vec4(0.8, 0.0, 0.0, smoothstep(0.3, 0.75, d) * a); }"
	hurt.material = hs
	root.add_child(hurt)
	# bottom: held item name + hotbar
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y -= 10
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	held_lbl = _lbl("", 15, INK, 4)
	held_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(held_lbl)
	var hb_panel := PanelContainer.new()
	var hps := StyleBoxFlat.new()
	hps.bg_color = Color(0.05, 0.035, 0.02, 0.55)
	hps.border_color = Color(GOLD, 0.35)
	hps.set_border_width_all(1)
	hps.set_corner_radius_all(14)
	hps.set_content_margin_all(5)
	hb_panel.add_theme_stylebox_override("panel", hps)
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 5)
	hb_panel.add_child(hotbar)
	bottom.add_child(hb_panel)
	for i in 6:
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 56)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(func(): game.player.select(i))
		hotbar.add_child(b)
	# death screen
	death = ColorRect.new()
	(death as ColorRect).color = Color(0.15, 0, 0, 0.7)
	death.set_anchors_preset(Control.PRESET_FULL_RECT)
	death.visible = false
	var dv := VBoxContainer.new()
	dv.set_anchors_preset(Control.PRESET_CENTER)
	dv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dv.grow_vertical = Control.GROW_DIRECTION_BOTH
	var dt := _lbl("You have fallen", 56, Color("#d84a3a"), 12, title_font)
	dt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_lbl = _lbl("", 20, INK, 5)
	death_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(dt)
	dv.add_child(death_lbl)
	death.add_child(dv)
	root.add_child(death)


## true when a touch at `pos` lands on an interactive HUD element
func hud_hit(pos: Vector2) -> bool:
	for c in [hotbar, menu_btns, minimap]:
		if (c as Control).get_global_rect().grow(6).has_point(pos):
			return true
	if update_bar and update_bar.visible and update_bar.get_global_rect().has_point(pos):
		return true
	return false


func _process(dt: float) -> void:
	if game == null or not game.running:
		return
	var P = game.player
	hp_bar.max_value = P.max_hp
	hp_bar.value = P.hp
	mp_bar.max_value = P.max_mp
	mp_bar.value = P.mp
	hp_lbl.text = "%d / %d" % [ceili(P.hp), P.max_hp]
	mp_lbl.text = "%d / %d" % [floori(P.mp), P.max_mp]
	clock_lbl.text = "%s Day %d · %s" % ["🌙" if game.world.night > 0.5 else "☀️", game.day, U.fmt_time(game.hours)]
	if dirty:
		dirty = false
		gold_lbl.text = "🪙 %d" % P.gold
		class_lbl.text = P.cls.title
		lvl_lbl.text = "  Lv %d" % maxi(1, P.cls.level)
		for i in 6:
			var b: Button = hotbar.get_child(i)
			var id = P.hotbar[i]
			var it: Dictionary = Data.ITEMS.get(id, {}) if id != null else {}
			var c: int = P.count(id) if id != null else 0
			b.text = it.icon if not it.is_empty() else ""
			b.tooltip_text = it.get("name", "")
			var sel: bool = i == P.sel
			var s := StyleBoxFlat.new()
			s.bg_color = Color(0.16, 0.12, 0.07, 0.85)
			s.border_color = GOLD if sel else Color(1, 1, 1, 0.08)
			s.set_border_width_all(2)
			s.set_corner_radius_all(10)
			if sel:
				s.shadow_color = Color(GOLD, 0.5)
				s.shadow_size = 6
			b.add_theme_stylebox_override("normal", s)
			b.add_theme_stylebox_override("hover", s)
			b.add_theme_stylebox_override("pressed", s)
			b.modulate.a = 0.45 if (id != null and c == 0) else 1.0
			for ch in b.get_children():
				ch.queue_free()
			var num := _lbl(str(i + 1), 11, Color(INK, 0.6))
			num.position = Vector2(4, 1)
			b.add_child(num)
			if not it.is_empty() and it.kind in ["seed", "consumable", "crop"]:
				var q := _lbl(str(c), 13, INK, 4)
				q.position = Vector2(38, 36)
				b.add_child(q)
		var h: Dictionary = P.held()
		held_lbl.text = h.get("name", "Bare hands")
		_render_tracker()
		if panel != "" and panel != "dialog":
			refresh()
	var f = game.focus
	var text: String = "" if f == null else (("✋ " if input_ctl.is_touch else "[E] ") + f.label)
	if prompt.text != text:
		prompt.text = text
	if hurt_a > 0.0:
		hurt_a = maxf(0.0, hurt_a - dt * 2.2)
		hurt.material.set_shader_parameter("a", hurt_a)


func _render_tracker() -> void:
	var rows: Array = []
	for id in game.quests:
		var q: Dictionary = game.quests[id]
		if q.state != "active":
			continue
		var d: Dictionary = Data.QUESTS[id]
		var have: int = q.progress if d.type == "kill" else game.player.count(d.item)
		var col := "#9aff8a" if game.quest_ready(id) else "#f3e7c9"
		rows.append("[color=%s]◆ %s [color=#e8c46a]%d/%d[/color][/color]" % [col, d.title, mini(have, d.count), d.count])
	tracker.text = "\n".join(rows.slice(0, 4))


func toast(msg: String, color := GOLD) -> void:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.045, 0.03, 0.88)
	s.border_color = color
	s.border_width_left = 4
	s.set_corner_radius_all(8)
	s.set_content_margin_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	p.add_theme_stylebox_override("panel", s)
	p.add_child(_lbl(msg, 17))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(p)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func banner(title: String, sub := "") -> void:
	banner_title.text = title
	banner_sub.text = sub
	var tw := banner_box.create_tween()
	banner_box.modulate.a = 0.0
	tw.tween_property(banner_box, "modulate:a", 1.0, 0.4)
	tw.tween_interval(3.0)
	tw.tween_property(banner_box, "modulate:a", 0.0, 0.8)


func hurt_flash() -> void:
	hurt_a = 1.0
	hurt.material.set_shader_parameter("a", 1.0)


func show_death(text: String) -> void:
	death_lbl.text = text
	death.visible = true


func hide_death() -> void:
	death.visible = false


func show_update(version: String, cb: Callable) -> void:
	if update_bar:
		update_bar.queue_free()
	update_bar = PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_lbl("⬆️ Update v%s is available!" % version, 18))
	h.add_child(_btn("Download", cb, 18, true))
	var close := _btn("✕", func(): update_bar.visible = false)
	h.add_child(close)
	update_bar.add_child(h)
	update_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	update_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	update_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	update_bar.position.y -= 110
	root.add_child(update_bar)


# ================================================================ panels
func _build_modal() -> void:
	modal = ColorRect.new()
	(modal as ColorRect).color = Color(0, 0, 0, 0.45)
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	modal.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close())
	root.add_child(modal)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_top = 0.04
	pc.anchor_bottom = 0.96
	pc.offset_left = -380
	pc.offset_right = 380
	pc.gui_input.connect(func(e): pc.accept_event())
	modal.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	pc.add_child(v)
	var head := HBoxContainer.new()
	var hm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		hm.add_theme_constant_override("margin_" + side, 12)
	hm.add_child(head)
	v.add_child(hm)
	panel_title = _lbl("", 26, GOLD, 0, title_font)
	panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(panel_title)
	var x := _btn("✕", close, 20)
	x.custom_minimum_size = Vector2(44, 44)
	head.add_child(x)
	var sep := HSeparator.new()
	v.add_child(sep)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		bm.add_theme_constant_override("margin_" + side, 16)
	bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_body = VBoxContainer.new()
	panel_body.add_theme_constant_override("separation", 10)
	panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bm.add_child(panel_body)
	scroll.add_child(bm)
	v.add_child(scroll)


func open(name: String, d := {}) -> void:
	panel = name
	data = d
	modal_open = true
	modal.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	input_ctl.release_all()
	scroll.scroll_vertical = 0
	refresh()


func close() -> void:
	if not modal_open:
		return
	if panel == "dialog" and data.has("npc"):
		data.npc.talking = false
	panel = ""
	modal_open = false
	modal.visible = false
	game.save_game(true)


func toggle(name: String) -> void:
	if panel == name:
		close()
	elif game.running:
		open(name)


func back() -> void:
	if modal_open:
		close()
	elif game.running:
		open("menu")


func refresh() -> void:
	for c in panel_body.get_children():
		c.queue_free()
	match panel:
		"inventory": _p_inventory()
		"skills": _p_skills()
		"quests": _p_quests()
		"board": _p_board()
		"map": _p_map()
		"dialog": _p_dialog()
		"shop": _p_shop()
		"menu": _p_menu()
		"settings": _p_settings()
		"help": _p_help()


func _title(t: String) -> void:
	panel_title.text = t


func _rich(bb: String, size := 18) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bb
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _card() -> VBoxContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.25)
	s.border_color = Color(GOLD, 0.3)
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	s.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", s)
	var v := VBoxContainer.new()
	p.add_child(v)
	panel_body.add_child(p)
	return v


func _item_detail(id: String, parent: Control) -> void:
	var it: Dictionary = Data.ITEMS[id]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.add_child(_lbl(it.icon, 48))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_lbl(it.name, 22, GOLD, 0, title_font))
	var desc := _rich(it.get("desc", ""), 17)
	v.add_child(desc)
	var stats: Array = []
	if it.has("dmg"):
		stats.append("Damage %d–%d" % [it.dmg[0], it.dmg[1]])
	if it.has("rate"):
		stats.append("Speed %.1f/s" % (1.0 / it.rate))
	if it.has("mana") and it.kind == "weapon":
		stats.append("Mana %d" % it.mana)
	if it.has("heal"):
		stats.append("Heals %d" % it.heal)
	if it.has("def"):
		stats.append("Armor %d" % it.def)
	if it.kind == "armor" and it.has("mana"):
		stats.append("+%d Mana" % it.mana)
	if it.has("skill") and it.kind == "weapon":
		stats.append("[color=#%s]%s[/color]" % [Data.SKILLS[it.skill].color.to_html(false), Data.SKILLS[it.skill].name])
	v.add_child(_rich("[color=#bfae88]" + "   ·   ".join(stats) + "[/color]", 16))
	h.add_child(v)
	parent.add_child(h)


func _p_inventory() -> void:
	var P = game.player
	_title("🎒 Inventory")
	panel_body.add_child(_rich("[color=#e8c46a][b]🪙 %d gold[/b][/color]      🛡️ Armor: %s (%d)" % [P.gold, Data.ITEMS[P.armor].name, P.def_]))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	for i in P.inv.size():
		var s: Dictionary = P.inv[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(72, 72)
		b.text = Data.ITEMS[s.id].icon
		b.add_theme_font_size_override("font_size", 32)
		if i == inv_sel:
			var st := StyleBoxFlat.new()
			st.bg_color = Color("#4a3822")
			st.border_color = GOLD
			st.set_border_width_all(2)
			st.set_corner_radius_all(10)
			b.add_theme_stylebox_override("normal", st)
		if s.qty > 1:
			var q := _lbl(str(s.qty), 14, INK, 4)
			q.position = Vector2(52, 50)
			b.add_child(q)
		if P.hotbar.has(s.id):
			var hk := _lbl(str(P.hotbar.find(s.id) + 1), 13, GOLD, 4)
			hk.position = Vector2(56, 2)
			b.add_child(hk)
		if P.armor == s.id:
			var e := _lbl("E", 13, Color("#9aff8a"), 4)
			e.position = Vector2(5, 2)
			b.add_child(e)
		b.pressed.connect(func():
			inv_sel = i
			refresh())
		grid.add_child(b)
	panel_body.add_child(grid)
	if inv_sel < 0 or inv_sel >= P.inv.size():
		panel_body.add_child(_lbl("Tap an item to see what it does.", 16, INK_D))
		return
	var s: Dictionary = P.inv[inv_sel]
	var it: Dictionary = Data.ITEMS[s.id]
	var card := _card()
	_item_detail(s.id, card)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 8)
	if it.kind == "armor":
		if P.armor == s.id:
			var b := _btn("Equipped", func(): pass)
			b.disabled = true
			acts.add_child(b)
		else:
			acts.add_child(_btn("Wear", func():
				P.equip_armor(s.id)
				refresh()))
	if it.kind == "consumable" or (it.kind == "crop" and it.has("heal")):
		acts.add_child(_btn("Use", func():
			P.consume(s.id)
			if inv_sel >= P.inv.size():
				inv_sel = -1
			refresh()))
	if it.kind in ["weapon", "tool", "seed", "consumable"] or (it.kind == "crop" and it.has("heal")):
		acts.add_child(_lbl("Hotbar:", 16, INK_D))
		for k in 6:
			var b := _btn(str(k + 1), func():
				var prev: int = P.hotbar.find(s.id)
				if prev >= 0:
					P.hotbar[prev] = null
				if prev != k:
					P.hotbar[k] = s.id
				P.vm.set_item(P.held())
				dirty = true
				refresh())
			b.custom_minimum_size = Vector2(44, 44)
			if P.hotbar[k] == s.id:
				b.add_theme_color_override("font_color", GOLD)
			acts.add_child(b)
	card.add_child(acts)


func _p_skills() -> void:
	var P = game.player
	var c: Dictionary = P.cls
	_title("📜 Character")
	var head := _card()
	var cn := _lbl(c.title, 40, GOLD, 0, title_font)
	cn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(cn)
	var line: String = "Humble beginnings" if c.line == "farming" else ("Hybrid class" if "+" in c.line else Data.SKILLS[c.line].name + " specialist")
	var sub := _lbl("Level %d · %s" % [maxi(1, c.level), line], 17, INK_D)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 6
	for pair in [[P.stats.str, "Strength"], [P.stats.dex, "Dexterity"], [P.stats.int, "Intelligence"], [P.max_hp, "Health"], [P.max_mp, "Mana"], [P.def_, "Armor"]]:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var a := _lbl(str(pair[0]), 24, INK)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var b := _lbl(pair[1], 13, INK_D)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(a)
		v.add_child(b)
		grid.add_child(v)
	head.add_child(grid)
	for k in Data.SKILL_ORDER:
		var s: Dictionary = Data.SKILLS[k]
		var sk: Dictionary = P.skills[k]
		var need := Data.xp_to_next(sk.lvl)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var ico := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = s.color
		st.set_corner_radius_all(12)
		st.set_content_margin_all(8)
		ico.add_theme_stylebox_override("panel", st)
		ico.add_child(_lbl(s.icon, 26))
		h.add_child(ico)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := HBoxContainer.new()
		var n := _lbl(s.name, 19, INK)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(n)
		top.add_child(_lbl(str(sk.lvl), 24, GOLD, 0, title_font))
		v.add_child(top)
		var bar := _bar(s.color)
		bar.custom_minimum_size.y = 9
		bar.max_value = need
		bar.value = sk.xp
		v.add_child(bar)
		v.add_child(_lbl("%d / %d XP · %s" % [floori(sk.xp), need, s.desc], 14, INK_D))
		h.add_child(v)
		panel_body.add_child(h)
	var guide := _card()
	guide.add_child(_lbl("How classes work", 20, GOLD))
	guide.add_child(_rich("There are no class choices in Hollowmere - [b]you become what you do[/b]. Every hit you land trains the skill of the weapon you used. Your class is named after your strongest combat skill, and if two skills are close you become a hybrid.", 16))
	for k in Data.COMBAT_SKILLS:
		var names: Array = []
		for pair in Data.LINES[k]:
			names.append("%s[color=#bfae88][font_size=12]%d[/font_size][/color]" % [pair[1], pair[0]])
		guide.add_child(_rich("[color=#%s][b]%s:[/b][/color] %s" % [Data.SKILLS[k].color.to_html(false), Data.SKILLS[k].name, " → ".join(names)], 16))
	var hy: Array = []
	for key in Data.HYBRIDS:
		var parts: Array = []
		for p in key.split("+"):
			parts.append(Data.SKILLS[p].name.split(" ")[0])
		hy.append("%s = %s / %s" % [" + ".join(parts), Data.HYBRIDS[key][0], Data.HYBRIDS[key][1]])
	guide.add_child(_rich("[color=#bfae88]" + "\n".join(hy) + "[/color]", 15))


func _quest_card(id: String, board := false) -> void:
	var q: Dictionary = game.quests[id]
	var d: Dictionary = Data.QUESTS[id]
	var giver = game.npc_by_role(d.giver)
	var gname: String = giver.npc_name if giver else "someone"
	var card := _card()
	var status := ""
	if board:
		status = "✅ Completed" if q.state == "done" else ("❗ See %s the %s" % [gname, Data.ROLES[d.giver].title] if q.state == "available" else "📌 In progress")
	else:
		var have: int = q.progress if d.type == "kill" else game.player.count(d.item)
		status = "Complete" if q.state == "done" else ("[color=#9aff8a]Return to %s[/color]" % gname if game.quest_ready(id) else "%d/%d" % [mini(have, d.count), d.count])
	card.add_child(_rich("[color=#e8c46a][font_size=20]%s[/font_size][/color]    %s" % [d.title, status]))
	card.add_child(_rich(d.desc, 16))
	var reward: Array = ["%d gold" % d.reward.gold]
	for it in d.reward.items:
		reward.append(Data.ITEMS[it[0]].name)
	card.add_child(_rich("[color=#bfae88]From %s the %s · Reward: %s[/color]" % [gname, Data.ROLES[d.giver].title, ", ".join(reward)], 15))
	if q.state == "done":
		card.get_parent().modulate.a = 0.6


func _p_quests() -> void:
	_title("📖 Quest Journal")
	var any := false
	for id in game.quests:
		if game.quests[id].state != "available":
			_quest_card(id)
			any = true
	if not any:
		panel_body.add_child(_rich("[color=#bfae88]No quests yet. Look for villagers with a [color=#ffd23a][b]![/b][/color] over their heads, or check the Quest Board in the plaza.[/color]"))


func _p_board() -> void:
	_title("📋 Quest Board")
	panel_body.add_child(_lbl("Notices pinned by the good folk of Hollowmere.", 16, INK_D))
	for id in Data.QUESTS:
		_quest_card(id, true)


func _p_map() -> void:
	_title("🗺️ Map of Hollowmere")
	var bm := BigMap.new()
	bm.setup(game, self)
	bm.custom_minimum_size = Vector2(700, 700)
	bm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel_body.add_child(bm)
	panel_body.add_child(_lbl("More regions will open beyond the collapsed mine in future updates.", 15, INK_D))


func _p_dialog() -> void:
	var n = data.npc
	_title(n.npc_name + "  ·  " + Data.ROLES[n.role].title)
	var say := _card()
	say.add_child(_rich("[i]“%s”[/i]" % data.text, 20))
	for o in game.dialog_options(n):
		var b := _btn(o.label, o.fn, 19, o.get("primary", false))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		panel_body.add_child(b)


func _sell_price(id: String) -> int:
	var it: Dictionary = Data.ITEMS[id]
	return it.price if it.kind in ["crop", "material"] else maxi(1, floori(it.price * 0.4))


func _p_shop() -> void:
	var P = game.player
	var shop: Dictionary = Data.SHOPS[data.shop]
	_title("🛒 " + shop.name)
	var tabs := HBoxContainer.new()
	tabs.add_child(_btn("Buy", func():
		shop_tab = "buy"
		refresh(), 18, shop_tab == "buy"))
	tabs.add_child(_btn("Sell", func():
		shop_tab = "sell"
		refresh(), 18, shop_tab == "sell"))
	var gl := _lbl("🪙 %d" % P.gold, 20, GOLD)
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs.add_child(gl)
	panel_body.add_child(tabs)
	var row := func(id: String, subtitle: String, btns: Array) -> void:
		var it: Dictionary = Data.ITEMS[id]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(_lbl(it.icon, 32))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_lbl(it.name + subtitle, 18, INK))
		var d := _lbl(it.desc, 14, INK_D)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		h.add_child(v)
		for b in btns:
			h.add_child(b)
		panel_body.add_child(h)
		panel_body.add_child(HSeparator.new())
	if shop_tab == "buy":
		for id in shop.stock:
			var it: Dictionary = Data.ITEMS[id]
			var own: int = P.count(id)
			var b := _btn("🪙 %d" % it.price, func():
				if P.gold >= it.price:
					P.gold -= it.price
					P.add_item(id, 1)
					game.audio.play("coin")
					toast("Bought " + it.name)
					dirty = true
					refresh(), 18)
			b.disabled = P.gold < it.price
			row.call(id, ("   (you have %d)" % own) if own > 0 else "", [b])
	else:
		var any := false
		var seen := {}
		for s in P.inv:
			if seen.has(s.id) or s.id == "farm_clothes" or (P.armor == s.id and P.count(s.id) <= 1):
				continue
			seen[s.id] = true
			any = true
			var id: String = s.id
			var sell := func(n: int) -> void:
				for k in n:
					P.gold += _sell_price(id)
					P.remove_item(id, 1)
				game.audio.play("coin")
				dirty = true
				refresh()
			var btns: Array = [_btn("+🪙 %d" % _sell_price(id), func(): sell.call(1))]
			var total: int = P.count(id)
			if total > 1:
				btns.append(_btn("All", func(): sell.call(P.count(id))))
			row.call(id, ("  ×%d" % total) if total > 1 else "", btns)
		if not any:
			panel_body.add_child(_lbl("Nothing to sell.", 16, INK_D))
	panel_body.add_child(_btn("← Back to " + data.npc.npc_name, func(): game.talk_to(data.npc)))


func _p_menu() -> void:
	_title("⚙️ Menu")
	panel_body.add_child(_btn("Resume", close, 20, true))
	panel_body.add_child(_btn("💾 Save Game", func():
		game.save_game()
		toast("Game saved"), 20))
	panel_body.add_child(_btn("🎛️ Settings", func(): open("settings"), 20))
	panel_body.add_child(_btn("❓ How to Play", func(): open("help"), 20))
	panel_body.add_child(_btn("⬆️ Check for Updates", func(): game.check_update(true), 20))
	panel_body.add_child(_btn("🏠 Save & Quit to Title", func():
		game.save_game()
		get_tree().reload_current_scene(), 20))
	panel_body.add_child(_lbl("Hollowmere v%s · World seed %d" % [game.version, game.world.seed_value], 14, INK_D))


func _slider(label: String, lo: float, hi: float, step: float, value: float, cb: Callable) -> void:
	var h := HBoxContainer.new()
	var l := _lbl(label, 18, INK)
	l.custom_minimum_size.x = 220
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 40
	s.value_changed.connect(cb)
	h.add_child(s)
	panel_body.add_child(h)


func _p_settings() -> void:
	var s: Dictionary = game.settings
	_title("🎛️ Settings")
	var h := HBoxContainer.new()
	var l := _lbl("Graphics quality", 18, INK)
	l.custom_minimum_size.x = 220
	h.add_child(l)
	var opt := OptionButton.new()
	for q in ["Low (fastest)", "Medium", "High"]:
		opt.add_item(q)
	opt.selected = ["low", "med", "high"].find(s.quality)
	opt.item_selected.connect(func(i):
		s.quality = ["low", "med", "high"][i]
		game.save_settings()
		toast("Restart to apply graphics quality"))
	h.add_child(opt)
	panel_body.add_child(h)
	_slider("Look sensitivity", 0.3, 2.5, 0.1, s.sens, func(v):
		s.sens = v
		game.apply_settings())
	_slider("Sound volume", 0, 1, 0.05, s.vol, func(v):
		s.vol = v
		game.apply_settings())
	_slider("Music volume", 0, 1, 0.05, s.music, func(v):
		s.music = v
		game.apply_settings())
	_slider("Field of view", 60, 95, 1, s.fov, func(v):
		s.fov = v
		game.apply_settings())
	panel_body.add_child(_lbl("Graphics quality applies after restarting the game.", 15, INK_D))
	panel_body.add_child(_btn("← Back", func(): open("menu")))


func _p_help() -> void:
	_title("❓ How to Play")
	panel_body.add_child(_rich("You're a farmer in the village of [b]Hollowmere[/b]. There are no classes to pick: [b][color=#e8c46a]you become what you do[/color][/b]. Swing swords and you'll grow into a Fighter. Loose arrows and you'll become a Ranger. Cast spells and the world will call you Mage. Mix two and you become a hybrid like a Paladin or Spellblade."))
	panel_body.add_child(_lbl("Controls", 22, GOLD, 0, title_font))
	panel_body.add_child(_rich("[b]Move[/b] - left thumb joystick (push fully to run) · WASD, Shift to run\n[b]Look[/b] - drag the right side of the screen · mouse (click to lock)\n[b]Attack / use[/b] - ⚔️ button (drag it to aim) · left click\n[b]Talk / interact[/b] - ✋ button · E\n[b]Jump[/b] - ⤒ button · Space\n[b]Items[/b] - tap the hotbar · 1–6 / mouse wheel\n[b]Potions[/b] - ❤ / 💧 · H / G\n[b]Menus[/b] - top-right buttons · I, K, J, M, Esc", 17))
	panel_body.add_child(_lbl("Getting started", 22, GOLD, 0, title_font))
	panel_body.add_child(_rich("1. Talk to the old farmer by your field.\n2. Select the hoe and use it on the field to till the soil.\n3. Select wheat seeds and plant them on tilled soil. Harvest ripe crops with ✋.\n4. Sell crops at the General Store, buy weapons, and venture beyond the fence.\n5. Sleep in your bed to save and pass the night.", 17))


# ================================================================ map image
const MAP_PX := 2  # map pixels per world meter (map covers -200..200 m)


func build_map_image() -> ImageTexture:
	if map_img:
		return map_img
	var W: World = game.world
	var S := 400 * MAP_PX
	# terrain colors per height-grid cell, hill-shaded, then smoothly upscaled
	var N := World.N
	var hs: PackedFloat32Array = W.heights
	var cells := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for j in N:
		var wz := -World.SIZE / 2.0 + j * World.RES
		for i in N:
			var wx := -World.SIZE / 2.0 + i * World.RES
			var h := hs[j * N + i]
			var hx := hs[j * N + mini(i + 1, N - 1)] - hs[j * N + maxi(i - 1, 0)]
			var hz := hs[mini(j + 1, N - 1) * N + i] - hs[maxi(j - 1, 0) * N + i]
			var r := sqrt(wx * wx + wz * wz)
			var col := Color8(100, 142, 62).lerp(Color8(128, 160, 72), clampf(W.nz2.get_noise_2d(wx * 0.05, wz * 0.05) + 0.5, 0.0, 1.0))
			if r > 66.0:
				col = col.lerp(Color8(62, 100, 48), U.smoothstep(-0.1, 0.35, W.nz3.get_noise_2d(wx * 0.013 + 3.0, wz * 0.013)))
			var rock := maxf(U.smoothstep(11.0, 16.0, h), U.smoothstep(182.0, 192.0, r))
			col = col.lerp(Color8(138, 130, 118), rock)
			var shade := clampf(1.0 + (hx + hz) * 0.1, 0.62, 1.3)  # light from the north-west
			cells.set_pixel(i, j, Color(col.r * shade, col.g * shade, col.b * shade))
	var full := (N - 1) * int(World.RES) * MAP_PX + 1
	cells.resize(full, full, Image.INTERPOLATE_CUBIC)
	var off := int((World.SIZE / 2.0 - 200.0) * MAP_PX)
	var img := cells.get_region(Rect2i(off, off, S, S))
	var brushes := {}
	var stamp := func(x: float, z: float, r_px: float, c: Color, soft: float) -> void:
		var b := _map_disc(brushes, r_px, c, soft)
		var n := b.get_width()
		img.blend_rect(b, Rect2i(0, 0, n, n), Vector2i(roundi((x + 200.0) * MAP_PX - n / 2.0), roundi((z + 200.0) * MAP_PX - n / 2.0)))
	var rect := func(x0: float, z0: float, w: float, d: float, c: Color) -> void:
		var r := Rect2i(roundi((x0 + 200.0) * MAP_PX), roundi((z0 + 200.0) * MAP_PX), maxi(1, roundi(w * MAP_PX)), maxi(1, roundi(d * MAP_PX)))
		if c.a >= 1.0:
			img.fill_rect(r, c)
		else:
			var tmp := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
			tmp.fill(c)
			img.blend_rect(tmp, Rect2i(Vector2i.ZERO, r.size), r.position)
	# pond with a sandy shore and deeper middle
	var wt: Dictionary = W.water
	stamp.call(wt.x, wt.z, (wt.r + 1.8) * MAP_PX, Color8(196, 182, 132), 2.0)
	stamp.call(wt.x, wt.z, wt.r * MAP_PX, Color8(62, 128, 170), 1.5)
	stamp.call(wt.x, wt.z, wt.r * 0.7 * MAP_PX, Color(0.13, 0.33, 0.52, 0.6), wt.r * 0.5 * MAP_PX)
	# roads: darker edge, then the surface
	for pass_i in 2:
		for rd in W.roads:
			var rr: float = rd.w / 2.0 * MAP_PX + (1.2 if pass_i == 0 else 0.0)
			var rc := Color8(128, 106, 74) if pass_i == 0 else Color8(202, 178, 132)
			for k in rd.pts.size() - 1:
				var a: Vector2 = rd.pts[k]
				var b: Vector2 = rd.pts[k + 1]
				var L := a.distance_to(b)
				var t := 0.0
				while t <= L:
					var p := a.lerp(b, t / L)
					stamp.call(p.x, p.y, rr, rc, 1.0)
					t += 0.5
	# plaza
	stamp.call(0.0, 0.0, 13.2 * MAP_PX, Color8(120, 112, 100), 1.0)
	stamp.call(0.0, 0.0, 12.5 * MAP_PX, Color8(172, 164, 148), 1.0)
	stamp.call(0.0, 0.0, 6.0 * MAP_PX, Color8(158, 150, 136), 1.0)
	stamp.call(0.0, 0.0, 2.0 * MAP_PX, Color8(70, 130, 168), 1.0)
	# your field: tilled rows inside a wooden border
	var fr: Dictionary = W.farm.frect
	var fx0: float = fr.minX + 1.5
	var fz0: float = fr.minZ + 1.5
	var fw: float = fr.maxX - fr.minX - 3.0
	var fd: float = fr.maxZ - fr.minZ - 3.0
	rect.call(fx0 - 0.5, fz0 - 0.5, fw + 1.0, fd + 1.0, Color8(96, 66, 38))
	rect.call(fx0, fz0, fw, fd, Color8(118, 86, 50))
	var row := 0.0
	while row < fd:
		rect.call(fx0, fz0 + row, fw, 0.5, Color8(140, 104, 62))
		row += 1.5
	# village fence (with gaps at the gates)
	var fa := 0.0
	while fa < TAU:
		if not Village._near_gate(W, fa):
			var fp := U.polar(fa, W.fence_r)
			stamp.call(fp.x, fp.y, 1.1, Color8(92, 62, 34), 0.8)
		fa += 0.25 / W.fence_r
	# points of interest
	stamp.call(W.pois.camp.x, W.pois.camp.y, 15.0 * MAP_PX, Color8(124, 102, 76), 8.0)
	stamp.call(W.pois.camp.x, W.pois.camp.y, 1.5 * MAP_PX, Color8(230, 120, 40), 2.0)
	var gp: Vector2 = W.pois.grave
	rect.call(gp.x - 12.5, gp.y - 12.5, 25.0, 25.0, Color8(84, 84, 72))
	rect.call(gp.x - 12.0, gp.y - 12.0, 24.0, 24.0, Color8(112, 114, 98))
	for gi in range(-9, 10, 4):
		for gj in range(-9, 10, 4):
			rect.call(gp.x + gi - 0.5, gp.y + gj - 0.5, 1.0, 1.0, Color8(190, 188, 176))
	stamp.call(W.pois.mine.x, W.pois.mine.y, 5.0 * MAP_PX, Color8(110, 104, 96), 1.5)
	stamp.call(W.pois.mine.x, W.pois.mine.y, 3.5 * MAP_PX, Color8(28, 26, 24), 1.5)
	# trees: soft shadow, canopy, sunlit highlight
	var tree_col := {"common": Color8(56, 106, 44), "pine": Color8(36, 82, 54), "birch": Color8(108, 150, 64), "willow": Color8(78, 130, 74), "dead": Color8(112, 98, 80)}
	for tr in W.tree_spots:
		var tc: Color = tree_col.get(tr[3], tree_col.common)
		var rp: float = snappedf(tr[2] * 0.75 * MAP_PX, 0.5)
		stamp.call(tr[0] + 0.8, tr[1] + 0.8, rp + 0.5, Color(0, 0, 0, 0.3), 2.0)
		stamp.call(tr[0], tr[1], rp, tc, 1.0)
		stamp.call(tr[0] - rp * 0.12, tr[1] - rp * 0.12, snappedf(rp * 0.45, 0.5), tc.lightened(0.22), 1.5)
	# buildings: drop shadow, dark outline, two-tone gabled roof with a ridge
	for bd in W.buildings:
		var w2: float = bd.d if bd.rot % 2 else bd.w
		var d2: float = bd.w if bd.rot % 2 else bd.d
		var x0: float = bd.x - w2 / 2.0
		var z0: float = bd.z - d2 / 2.0
		var roof := Color8(226, 178, 82) if bd.type == "farmhouse" else Color8(192, 98, 58).lerp(Color8(150, 110, 84), float(hash(bd.get("name", "")) % 100) / 200.0)
		rect.call(x0 + 1.0, z0 + 1.0, w2, d2, Color(0, 0, 0, 0.35))
		rect.call(x0 - 0.5, z0 - 0.5, w2 + 1.0, d2 + 1.0, Color8(60, 40, 28))
		rect.call(x0, z0, w2, d2, roof)
		if w2 >= d2:
			rect.call(x0, z0 + d2 / 2.0, w2, d2 / 2.0, roof.darkened(0.18))
			rect.call(x0, z0 + d2 / 2.0 - 0.25, w2, 0.5, roof.lightened(0.25))
		else:
			rect.call(x0 + w2 / 2.0, z0, w2 / 2.0, d2, roof.darkened(0.18))
			rect.call(x0 + w2 / 2.0 - 0.25, z0, 0.5, d2, roof.lightened(0.25))
	img.generate_mipmaps()
	map_img = ImageTexture.create_from_image(img)
	return map_img


## Soft-edged disc brush (cached), radius in map pixels.
func _map_disc(cache: Dictionary, r: float, col: Color, soft: float) -> Image:
	var key := "%d|%s|%d" % [int(r * 4.0), col.to_html(), int(soft * 4.0)]
	if cache.has(key):
		return cache[key]
	var n := int(ceil(r + soft)) * 2 + 2
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n / 2.0
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
			var a := clampf((r - d) / soft + 0.5, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	cache[key] = img
	return img


## Map color for a crop plot's state (transparent while still weedy).
func plot_color(p: Dictionary) -> Color:
	if p.state == "planted":
		return Color("#ffd23a") if game.farm.ripe(p) else Color("#9be05a")
	if p.state == "tilled":
		return Color("#4a2e16")
	return Color(0, 0, 0, 0)  # untouched soil: the map already shows it


## True while none of the field is planted, so the maps point new players at it.
func field_idle() -> bool:
	for p in game.world.plots:
		if p.state == "planted":
			return false
	return true


func field_corners() -> Array:
	var fr: Dictionary = game.world.farm.frect
	return [Vector2(fr.minX + 1.5, fr.minZ + 1.5), Vector2(fr.maxX - 1.5, fr.minZ + 1.5), Vector2(fr.maxX - 1.5, fr.maxZ - 1.5), Vector2(fr.minX + 1.5, fr.maxZ - 1.5)]


# ================================================================ minimap & big map widgets
class Minimap extends Control:
	var game
	var ui
	var tex_rect: TextureRect
	var mat: ShaderMaterial

	func setup(g, u) -> void:
		game = g
		ui = u
		custom_minimum_size = Vector2(180, 180)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tex_rect = TextureRect.new()
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tex_rect.show_behind_parent = true  # markers drawn in _draw go on top of the map
		mat = ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = """
shader_type canvas_item;
uniform vec2 center;
uniform float yaw;
uniform float zoom = 0.24;
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d);
	vec2 rd = vec2(d.x * cos(yaw) + d.y * sin(yaw), -d.x * sin(yaw) + d.y * cos(yaw));
	vec2 uv = center + rd * zoom;
	vec3 c = texture(TEXTURE, uv).rgb;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) c = vec3(0.36, 0.34, 0.31);
	c *= 1.0 - 0.35 * smoothstep(0.3, 0.45, r);   // soft inner vignette
	float px = fwidth(r);
	// bronze rim lit from the top-left, with dark inner and outer lines
	vec3 rim = mix(vec3(0.42, 0.29, 0.1), vec3(0.98, 0.84, 0.48), clamp(0.55 - (d.x + d.y) * 1.3, 0.0, 1.0));
	c = mix(c, vec3(0.08, 0.05, 0.02), smoothstep(0.438 - px, 0.438, r));
	c = mix(c, rim, smoothstep(0.446 - px, 0.446, r));
	c = mix(c, vec3(0.08, 0.05, 0.02), smoothstep(0.492 - px, 0.492, r));
	COLOR = vec4(c, 1.0 - smoothstep(0.5 - px, 0.5, r));
}
"""
		tex_rect.material = mat
		add_child(tex_rect)
		gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:
				ui.toggle("map"))

	func _process(_dt: float) -> void:
		if game == null or not game.running:
			return
		if tex_rect.texture == null:
			tex_rect.texture = ui.build_map_image()
		var P = game.player
		mat.set_shader_parameter("center", Vector2((P.position.x + 200.0) / 400.0, (P.position.z + 200.0) / 400.0))
		mat.set_shader_parameter("yaw", P.yaw)
		queue_redraw()

	func _draw() -> void:
		if game == null or not game.running:
			return
		var P = game.player
		var S := size.x
		var R := 48.0
		var k := S / (R * 2.0)
		var c := size / 2.0
		var inner := S * 0.43
		var rot := func(wx: float, wz: float) -> Vector2:
			var d := Vector2(wx - P.position.x, wz - P.position.z)
			# rotate so the view direction points up
			var a: float = P.yaw
			return c + Vector2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a)) * k
		# your field: plot states, plus a pulsing outline (or an edge arrow) until something is planted
		var gold := Color("#ffd23a")
		var idle: bool = ui.field_idle()
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		var corners := PackedVector2Array()
		var fc := Vector2.ZERO
		for q in ui.field_corners():
			var sp: Vector2 = rot.call(q.x, q.y)
			corners.append(sp)
			fc += sp / 4.0
		if fc.distance_to(c) < inner - 14.0:
			for pl in game.world.plots:
				draw_circle(rot.call(pl.pos.x, pl.pos.z), 1.35, ui.plot_color(pl))
			corners.append(corners[0])
			draw_polyline(corners, Color(gold, 0.45 + 0.55 * pulse) if idle else Color(gold, 0.5), 1.5 + pulse * 1.5 if idle else 1.2, true)
		elif idle:
			var dir := (fc - c).normalized()
			var tip := c + dir * (inner - 3.0)
			var side := Vector2(-dir.y, dir.x)
			var arrow := PackedVector2Array([tip, tip - dir * 11.0 + side * 6.0, tip - dir * 11.0 - side * 6.0])
			draw_colored_polygon(arrow, Color(gold, 0.6 + 0.4 * pulse))
			draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0, 0.7), 1.0, true)
		for n in game.npcs:
			var p: Vector2 = rot.call(n.position.x, n.position.z)
			if p.distance_to(c) < inner - 4.0:
				var quest: bool = n.marker_state != ""
				draw_circle(p, 4.2 if quest else 2.8, Color(0, 0, 0, 0.6))
				draw_circle(p, 3.2 if quest else 1.9, gold if quest else Color("#f4f0e6"))
		for e in game.enemies:
			if e.dead:
				continue
			var p: Vector2 = rot.call(e.position.x, e.position.z)
			if p.distance_to(c) < inner - 4.0:
				var boss: bool = e.def.get("boss", false)
				draw_circle(p, 4.5 if boss else 3.1, Color(0, 0, 0, 0.6))
				draw_circle(p, 3.5 if boss else 2.2, Color("#ff8a1a") if boss else Color("#e8322a"))
		# player: view cone + arrow
		var cone := PackedVector2Array([c, c + Vector2(-17, -30), c + Vector2(17, -30)])
		draw_colored_polygon(cone, Color(1, 1, 1, 0.12))
		var pts := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 7), c + Vector2(0, 3), c + Vector2(-6, 7)])
		draw_colored_polygon(pts, Color.WHITE)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.4, true)
		# north marker riding on the rim
		var npos: Vector2 = rot.call(P.position.x, P.position.z - 1000.0)
		var nd := (npos - c).normalized() * (S * 0.469)
		draw_circle(c + nd, 8.5, Color(0.1, 0.07, 0.03))
		draw_string(ui.title_font, c + nd + Vector2(-5.5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, gold)


class BigMap extends Control:
	var game
	var ui

	func setup(g, u) -> void:
		game = g
		ui = u
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _process(_dt: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var tex: Texture2D = ui.build_map_image()
		var s := minf(size.x, size.y)
		draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(s, s)), false)
		var k := s / 400.0
		var tp := func(x: float, z: float) -> Vector2: return Vector2((x + 200.0) * k, (z + 200.0) * k)
		# your field: plot states and a gold outline (pulsing until something is planted)
		var gold := Color("#ffd23a")
		var idle: bool = ui.field_idle()
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		var corners := PackedVector2Array()
		for q in ui.field_corners():
			corners.append(tp.call(q.x, q.y))
		corners.append(corners[0])
		for pl in game.world.plots:
			var pp: Vector2 = tp.call(pl.pos.x, pl.pos.z)
			draw_rect(Rect2(pp - Vector2.ONE * 0.6 * k, Vector2.ONE * 1.2 * k), ui.plot_color(pl))
		draw_polyline(corners, Color(gold, 0.45 + 0.55 * pulse) if idle else Color(gold, 0.6), 2.0 + (pulse * 2.0 if idle else 0.0), true)
		# labels: most important first; each tries a few spots and is skipped if none is free
		var labels: Array = game.world.map_labels.duplicate()
		var rank := func(l: Dictionary) -> int:
			if l.text == "Your Field":
				return 0
			return 1 if Vector2(l.x, l.z).length() > game.world.fence_r else 3
		labels.sort_custom(func(a, b): return rank.call(a) < rank.call(b))
		var placed: Array[Rect2] = []
		for l in labels:
			var p: Vector2 = tp.call(l.x, l.z)
			var fs := 14 if rank.call(l) < 2 else 12
			var tw: float = ui.title_font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			for dy in [0.0, -13.0, 13.0, -26.0, 26.0]:
				var box := Rect2(p.x - tw / 2.0 - 2.0, p.y + dy - fs * 0.7, tw + 4.0, fs * 1.1)
				if placed.any(func(o: Rect2) -> bool: return o.intersects(box)):
					continue
				placed.append(box)
				var col := Color("#ff8a6a") if l.get("danger", false) else Color("#fff4d0")
				if l.text == "Your Field":
					col = gold
				if dy != 0.0:
					draw_circle(p, 2.0, col)
				var at := Vector2(p.x - tw / 2.0, p.y + dy + fs * 0.35)
				draw_string_outline(ui.title_font, at, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
				draw_string(ui.title_font, at, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
				break
		for n in game.npcs:
			if n.marker_state != "":
				var p: Vector2 = tp.call(n.position.x, n.position.z)
				draw_string_outline(ui.title_font, p + Vector2(-5, -4), n.marker_state, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
				draw_string(ui.title_font, p + Vector2(-5, -4), n.marker_state, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, gold)
		var P = game.player
		var c: Vector2 = tp.call(P.position.x, P.position.z)
		var f := Vector2(-sin(P.yaw), -cos(P.yaw))  # facing direction (map x = world x, map y = world z)
		var r := Vector2(-f.y, f.x)
		var pts := PackedVector2Array([c + f * 10.0, c - f * 8.0 + r * 7.0, c - f * 4.0, c - f * 8.0 - r * 7.0])
		draw_colored_polygon(pts, Color.WHITE)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.5)
