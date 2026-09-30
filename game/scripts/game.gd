class_name Game
extends Node3D
## Owns one play session: world, player, NPCs, enemies, quests, saving.

const SAVE_PATH := "user://save.json"
const SEC_PER_HOUR := 30.0
const REPO := "z1fire/hollowmere"

var settings := {}
var version := "0.0.0"
var running := false
var day := 1
var hours := 8.0
var seed_value := 0

var world: World
var player: Player
var ui: GameUI
var input: InputCtl
var combat: Combat
var farm: Farm
var audio: GameAudio
var npcs: Array = []
var enemies: Array = []
var quests := {}
var focus = null
var autosave_t := 60.0
var marker_t := 0.0
var well_t := 0.0
var clock := 0.0


func setup(p_seed: int, save_data: Dictionary, p_settings: Dictionary, p_version: String, progress: Callable) -> void:
	settings = p_settings
	version = p_version
	seed_value = int(save_data.seed) if not save_data.is_empty() else p_seed
	audio = GameAudio.new()
	add_child(audio)
	audio.setup()
	_apply_render_quality()
	world = World.new()
	add_child(world)
	await world.generate(seed_value, settings.quality, progress)
	progress.call("Waking the villagers...", 0.95)
	await get_tree().process_frame
	combat = Combat.new()
	add_child(combat)
	combat.setup(self)
	ui = GameUI.new()
	add_child(ui)
	ui.setup(self)
	input = ui.input_ctl
	player = Player.new()
	add_child(player)
	player.setup(self)
	# NPCs
	var R := U.make_rng(seed_value + 99)
	var used := {}
	var name_for := func() -> String:
		var n := ""
		for i in 50:
			n = U.pick(R, Data.NAMES.m if R.randf() < 0.5 else Data.NAMES.f)
			if not used.has(n):
				break
		used[n] = true
		return n
	var spots: Array = world.npc_spots.duplicate()
	for b in world.buildings:
		spots.append_array(b.get("npcs", []))
	for s in spots:
		var n := NPC.new()
		add_child(n)
		n.setup(self, s, R, name_for.call())
		npcs.append(n)
	for i in 7:
		var wi := R.randi_range(0, world.waypoints.size() - 1)
		var p: Vector2 = world.waypoints[wi].p
		var n := NPC.new()
		add_child(n)
		n.setup(self, {"role": "villager", "x": p.x, "z": p.y, "y": world.plaza_y + 0.1, "wander": true, "wp": wi}, R, name_for.call())
		npcs.append(n)
	for s in world.spawns:
		var e := Enemy.new()
		add_child(e)
		e.setup(self, s)
		e.respawn()
		enemies.append(e)
	farm = Farm.new()
	add_child(farm)
	farm.setup(self)
	progress.call("Drawing the map...", 0.98)
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	ui.build_map_image()
	print("[gen] Drawing the map... %d ms" % (Time.get_ticks_msec() - t0))
	for id in Data.QUESTS:
		quests[id] = {"state": "available", "progress": 0}
	if not save_data.is_empty():
		_load(save_data)
	else:
		var sp: Dictionary = world.spawn_point
		player.position = sp.pos + Vector3(0, 0.3, 0)
		player.yaw = sp.yaw
	player.vm.set_item(player.held())
	apply_settings()


func start(is_new: bool) -> void:
	running = true
	ui.dirty = true
	if is_new:
		get_tree().create_timer(0.6).timeout.connect(func(): ui.banner("Hollowmere", "Your family farm awaits. Speak with the old farmer."))
		get_tree().create_timer(4.5).timeout.connect(func(): ui.toast("Tip: talk to villagers with a ❗ above their heads"))
		save_game(true)
	check_update(false)


func _apply_render_quality() -> void:
	var vp := get_viewport()
	var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	match settings.quality:
		"low":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.6 if mobile else 0.8
		"med":
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 0.8 if mobile else 1.0
		_:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.scaling_3d_scale = 1.0
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if settings.quality == "high" else Viewport.SCREEN_SPACE_AA_FXAA


func apply_settings() -> void:
	if input:
		input.sens = settings.sens
	audio.set_volume(settings.vol)
	audio.set_music(settings.music * 0.6)
	if player:
		player.camera.fov = settings.fov
	save_settings()


func save_settings() -> void:
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


# ================================================================ frame
func _process(dt: float) -> void:
	if not running:
		return
	dt = minf(dt, 0.05)
	clock += dt
	hours += dt / SEC_PER_HOUR
	if hours >= 24.0:
		hours -= 24.0
		day += 1
	world.update(dt, hours, player.position)
	_update_focus()
	_update_herbs(dt)
	marker_t -= dt
	if marker_t <= 0.0:
		marker_t = 0.5
		_update_markers()
	var danger := false
	for e in enemies:
		if not e.dead and e.state == "chase" and e.position.distance_to(player.position) < 25.0:
			danger = true
			break
	audio.update_music(dt, "danger" if danger else ("night" if world.night > 0.6 else "day"))
	autosave_t -= dt
	if autosave_t <= 0.0:
		autosave_t = 60.0
		save_game(true)


func line_clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func npc_by_role(role: String):
	for n in npcs:
		if n.role == role:
			return n
	return null


# ================================================================ interaction
func _update_focus() -> void:
	var P := player
	if P.dead:
		focus = null
		return
	var f := P.forward()
	var best = null
	var bs := 1e9
	for it in world.interactables:
		if it.type == "herb" and it.respawn > 0.0:
			continue
		var d3: Vector3 = it.pos - P.position
		var d := Vector2(d3.x, d3.z).length()
		if d > it.r or absf(it.pos.y - (P.position.y + 1.0)) > 2.5:
			continue
		var dot := Vector2(d3.x, d3.z).normalized().dot(Vector2(f.x, f.z))
		if dot < 0.25 and d > 1.2:
			continue
		var s := d - dot * 1.5
		if s < bs:
			bs = s
			best = it
	if best == null or best.type != "npc":
		var p = P.target_plot()
		if p:
			var h := P.held()
			var label := ""
			if p.state == "planted" and farm.ripe(p):
				label = "Harvest " + Data.ITEMS[p.crop].name
			elif p.state == "planted":
				label = "%s growing (%d%%)" % [Data.ITEMS[p.crop].name, int(farm.progress(p) * 100)]
			elif p.state == "grass":
				label = "Till soil" if h.get("id", "") == "hoe" else "Weedy soil - use your Hoe"
			elif p.state == "tilled":
				label = ("Plant " + h.name) if h.get("kind", "") == "seed" else "Tilled soil - select seeds to plant"
			if label != "" and (best == null or bs > 0.5):
				best = {"type": "plot", "plot": p, "label": label, "pos": p.pos}
	focus = best


func interact() -> void:
	var it = focus
	if it == null or player.dead:
		return
	var P := player
	match it.type:
		"npc":
			talk_to(it.npc)
		"plot":
			var p: Dictionary = it.plot
			var h := P.held()
			if p.state == "planted" and farm.ripe(p):
				farm.harvest(p)
			elif p.state == "grass" and h.get("id", "") == "hoe":
				farm.till(p)
			elif p.state == "tilled" and h.get("kind", "") == "seed":
				farm.plant(p, h.id)
			else:
				ui.toast(it.label)
		"bed":
			var is_night := hours >= 19.0 or hours < 5.0
			P.hp = P.max_hp
			P.mp = P.max_mp
			if is_night:
				sleep()
				ui.banner("You slept soundly", "Day %d · Game saved" % day)
			else:
				ui.toast("You rest a moment. Health restored. Game saved.")
			save_game(true)
		"board":
			ui.open("board")
		"well":
			if well_t > clock:
				ui.toast("The water is cool and refreshing.")
			else:
				well_t = clock + 30.0
				P.hp = minf(P.max_hp, P.hp + 20)
				P.mp = minf(P.max_mp, P.mp + 10)
				combat.heal_fx(P.position + Vector3(0, 1, 0))
				audio.play("drink")
				ui.toast("You drink from the well. +20 Health")
		"herb":
			P.add_item("moonpetal", 1)
			it.respawn = 180.0
			it.node.visible = false
			P.gain_xp("nature", 4)
			audio.play("pickup")
			ui.toast("Picked a Moonpetal 🌸", Color("#8ad8ff"))
			check_collect_quests()
		"chest":
			if it.opened_day == day:
				ui.toast("Empty. Maybe it refills tomorrow...")
			else:
				it.opened_day = day
				_chest_visual(it)
				var gold := randi_range(15, 49)
				P.gold += gold
				var pool := ["hp_potion", "mp_potion", "old_coin", "hp_potion", "leather", "hunting_bow", "iron_sword", "tome_thorns", "tome_sparks", "pumpkin_seed"]
				var item: String = pool[randi() % pool.size()]
				P.add_item(item, 1)
				audio.play("chest")
				ui.toast("Found %d gold and %s!" % [gold, Data.ITEMS[item].name], Color("#ffd23a"))
				combat.burst(it.pos + Vector3(0, 0.4, 0), Color("#ffd23a"), 80, 2.5, 1.4, -3.0, 1.0)
				ui.dirty = true
		"crypt":
			ui.toast("The crypt is sealed by an ancient ward. (Coming in a future update)", Color("#66ffcc"))
		"mine":
			ui.banner("The Collapsed Mine", "Rubble blocks the way. A new region will open here in a future update.")


func _chest_visual(it: Dictionary) -> void:
	var open: bool = it.opened_day == day
	it.closed.visible = not open
	it.opened.visible = open


func sleep() -> void:
	if hours >= 19.0:
		day += 1
	hours = 7.0
	for c in world.chests:
		_chest_visual(c)


func _update_herbs(dt: float) -> void:
	for h in world.herbs:
		if h.respawn > 0.0:
			h.respawn -= dt
			if h.respawn <= 0.0:
				h.node.visible = true
	for c in world.chests:
		if c.opened.visible and c.opened_day != day:
			_chest_visual(c)


func quick_potion(kind: String) -> void:
	var order := ["hp_potion", "stew", "bread", "carrot"] if kind == "hp" else ["mp_potion", "stew"]
	for id in order:
		if player.count(id) > 0:
			player.consume(id)
			return
	ui.toast("No healing items" if kind == "hp" else "No mana potions")


# ================================================================ dialogue & quests
func talk_to(npc, text := "") -> void:
	npc.talking = true
	var role: Dictionary = Data.ROLES[npc.role]
	var lines: Array = role.lines
	var greet := text
	if greet == "":
		greet = lines[randi() % lines.size()]
		if player.cls.line != "farming" and randf() < 0.35:
			greet = "Well met, %s. %s" % [player.cls.title, greet]
	ui.open("dialog", {"npc": npc, "text": greet})


func quest_ready(id: String) -> bool:
	var q: Dictionary = quests[id]
	var d: Dictionary = Data.QUESTS[id]
	if q.state != "active":
		return false
	return q.progress >= d.count if d.type == "kill" else player.count(d.item) >= d.count


func dialog_options(npc) -> Array:
	var role: Dictionary = Data.ROLES[npc.role]
	var P := player
	var opts: Array = []
	var say := func(t: String) -> void: ui.open("dialog", {"npc": npc, "text": t})
	if ui.data.has("offer") and ui.data.npc == npc:
		var qid: String = ui.data.offer
		return [
			{"label": "✔ Accept", "primary": true, "fn": func():
				quests[qid].state = "active"
				quests[qid].progress = 0
				audio.play("quest")
				ui.toast("New quest: " + Data.QUESTS[qid].title, Color("#ffd23a"))
				ui.dirty = true
				say.call("Good. Come back to me when it's done.")
				check_collect_quests()},
			{"label": "Not now", "fn": func(): say.call("Suit yourself.")},
		]
	if role.has("quest"):
		var id: String = role.quest
		var q: Dictionary = quests[id]
		var d: Dictionary = Data.QUESTS[id]
		if q.state == "available":
			opts.append({"label": "❗ " + d.title, "primary": true, "fn": func(): ui.open("dialog", {"npc": npc, "text": d.offer, "offer": id})})
		elif quest_ready(id):
			opts.append({"label": "✅ Complete: " + d.title, "primary": true, "fn": func():
				complete_quest(id)
				say.call(d.thanks)})
		elif q.state == "active":
			var have: int = q.progress if d.type == "kill" else P.count(d.item)
			opts.append({"label": "… " + d.title, "fn": func(): say.call("%s (%d/%d)" % [d.desc, have, d.count])})
	if role.has("shop"):
		opts.append({"label": "🛒 Trade", "fn": func():
			ui.shop_tab = "buy"
			ui.open("shop", {"shop": role.shop, "npc": npc})})
	if role.get("service", "") == "rest":
		opts.append({"label": "🛏️ Rent a room (10 gold)", "fn": func():
			if P.gold < 10:
				say.call("Ten gold for a room, love. Come back when you have it.")
				return
			P.gold -= 10
			P.hp = P.max_hp
			P.mp = P.max_mp
			sleep()
			save_game(true)
			ui.dirty = true
			audio.play("coin")
			ui.close()
			ui.banner("A good night's rest", "Day %d · Game saved" % day)})
	if role.get("service", "") == "heal":
		opts.append({"label": "✨ Heal me", "fn": func():
			P.hp = P.max_hp
			P.mp = P.max_mp
			combat.heal_fx(P.position + Vector3(0, 1, 0))
			audio.play("heal")
			say.call("Go with the Light, child. You are mended.")})
	var lines: Array = role.lines
	opts.append({"label": "💬 Chat", "fn": func(): say.call(lines[randi() % lines.size()])})
	opts.append({"label": "📜 Any news?", "fn": func(): say.call(Data.LORE[randi() % Data.LORE.size()])})
	opts.append({"label": "Goodbye", "fn": func(): ui.close()})
	return opts


func complete_quest(id: String) -> void:
	var q: Dictionary = quests[id]
	var d: Dictionary = Data.QUESTS[id]
	if d.type == "collect" and d.get("consume", false):
		player.remove_item(d.item, d.count)
	q.state = "done"
	player.gold += d.reward.gold
	var names: Array = []
	for it in d.reward.items:
		player.add_item(it[0], it[1])
		names.append(Data.ITEMS[it[0]].name)
	for sk in d.reward.get("xp", {}):
		player.gain_xp(sk, d.reward.xp[sk])
	audio.play("quest")
	ui.banner("Quest Complete", "%s · +%d gold%s" % [d.title, d.reward.gold, (", " + ", ".join(names)) if names.size() else ""])
	ui.dirty = true
	save_game(true)


func check_collect_quests() -> void:
	for id in quests:
		var q: Dictionary = quests[id]
		if q.state == "active" and Data.QUESTS[id].type == "collect" and quest_ready(id) and not q.get("notified", false):
			q.notified = true
			ui.toast(Data.QUESTS[id].title + ": ready to turn in!", Color("#ffd23a"))
	ui.dirty = true


func _update_markers() -> void:
	for n in npcs:
		if n.marker == null:
			continue
		var id: String = Data.ROLES[n.role].quest
		n.set_marker("!" if quests[id].state == "available" else ("?" if quest_ready(id) else ""))


func on_kill(e, skill: String) -> void:
	var d: Dictionary = e.def
	player.gain_xp(skill, d.xp)
	var gold := randi_range(d.gold[0], d.gold[1])
	player.gold += gold
	audio.play("coin")
	var loot: Array = []
	for drop in d.drops:
		if randf() < drop[1]:
			player.add_item(drop[0], 1)
			loot.append(Data.ITEMS[drop[0]].name)
	ui.toast("%s defeated · +%d gold%s" % [d.name, gold, (" · " + ", ".join(loot)) if loot.size() else ""], Color("#ff8a1a") if d.get("boss", false) else GameUI.GOLD)
	for id in quests:
		var q: Dictionary = quests[id]
		var qd: Dictionary = Data.QUESTS[id]
		if q.state == "active" and qd.type == "kill" and qd.target == d.group:
			q.progress += 1
			if q.progress <= qd.count:
				ui.toast("%s: %d/%d" % [qd.title, q.progress, qd.count], Color("#ffd23a"))
	if d.get("boss", false):
		ui.banner("The Warchief has fallen!", "Return to the Mayor with the news")
	check_collect_quests()


func on_death() -> void:
	audio.play("die")
	var lost := int(player.gold * 0.1)
	ui.show_death("You lost %d gold. You'll wake up at home." % lost)
	await get_tree().create_timer(3.5).timeout
	player.gold -= lost
	player.dead = false
	player.hp = player.max_hp
	player.mp = player.max_mp
	var bp: Dictionary = world.bed_point
	player.position = bp.pos + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	player.yaw = bp.yaw
	player.pitch = 0.0
	for e in enemies:
		if not e.dead:
			e.state = "return"
	ui.hide_death()
	ui.dirty = true


# ================================================================ save / load
func save_game(silent := false) -> void:
	if not running:
		return
	var plots: Array = []
	for p in world.plots:
		plots.append({"s": p.state, "c": p.crop, "t": p.t})
	var chests: Array = []
	for c in world.chests:
		chests.append(c.opened_day)
	var data := {"v": 2, "seed": seed_value, "day": day, "hours": hours, "player": player.serialize(), "quests": quests, "plots": plots, "chests": chests, "saved_at": Time.get_unix_time_from_system()}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		if not silent:
			ui.toast("💾 Game saved")
	elif not silent:
		ui.toast("Could not save!")


func _load(d: Dictionary) -> void:
	day = int(d.day)
	hours = float(d.hours)
	player.load_data(d.player)
	for id in d.get("quests", {}):
		if quests.has(id):
			quests[id] = {"state": d.quests[id].state, "progress": int(d.quests[id].progress)}
	var plots: Array = d.get("plots", [])
	for i in mini(plots.size(), world.plots.size()):
		var p: Dictionary = world.plots[i]
		p.state = plots[i].s
		p.crop = plots[i].c
		p.t = float(plots[i].t)
		farm.refresh(p)
	var chests: Array = d.get("chests", [])
	for i in mini(chests.size(), world.chests.size()):
		world.chests[i].opened_day = int(chests[i])
		_chest_visual(world.chests[i])


static func load_data() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ================================================================ updates
static func version_cmp(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x - y
	return 0


## Asks GitHub for the newest release; on Android offers the new APK (installs over this one, keeps saves).
func check_update(manual: bool) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			if manual:
				ui.toast("Could not check for updates (offline?)")
			return
		var j = JSON.parse_string(body.get_string_from_utf8())
		if not (j is Dictionary):
			return
		var latest := String(j.get("tag_name", "")).trim_prefix("v")
		if latest != "" and OS.get_name() == "Android" and version_cmp(latest, version) > 0:
			var url: String = j.get("html_url", "")
			for a in j.get("assets", []):
				if String(a.name).ends_with(".apk"):
					url = a.browser_download_url
			ui.show_update(latest, func():
				save_game(true)
				OS.shell_open(url))
		elif manual:
			ui.toast("You have the latest version (v%s)" % version))
	var err := http.request("https://api.github.com/repos/%s/releases/latest" % REPO, ["Accept: application/vnd.github+json", "User-Agent: Hollowmere"])
	if err != OK:
		http.queue_free()
