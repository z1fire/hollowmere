extends SceneTree
## Dev harness for a full game session (not shipped):
## godot --path game -s res://scripts/devgame.gd -- out=C:/tmp

var out := "user://"
var game: Game


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv[0] == "out":
			out = kv[1]
	_run.call_deferred()


func shot(name: String, frames := 20) -> void:
	for i in frames:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("g_%s.png" % name))
	print("[t] shot %s fps=%d calls=%d prims=%d" % [name, Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func tp(pos: Vector3, yaw: float, pitch := 0.0) -> void:
	game.player.position = pos
	game.player.velocity = Vector3.ZERO
	game.player.yaw = yaw
	game.player.pitch = pitch


func check(label: String, ok: bool) -> void:
	print("[t] %s %s" % ["PASS" if ok else "FAIL", label])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await Assets.load_all(root, func(p): pass)
	game = Game.new()
	root.add_child(game)
	var t0 := Time.get_ticks_msec()
	await game.setup(4242, {}, {"quality": "high", "sens": 1.0, "vol": 0.0, "music": 0.0, "fov": 75.0}, "0.3.0", func(l, p): pass)
	print("[t] session ready in %d ms: %d npcs, %d enemies" % [Time.get_ticks_msec() - t0, game.npcs.size(), game.enemies.size()])
	game.start(true)
	game.input.is_touch = true
	await shot("spawn", 40)
	var P := game.player
	check("player on ground", P.is_on_floor())
	# ---- farming quest
	var farmer = game.npc_by_role("farmer")
	game.talk_to(farmer)
	var opts: Array = game.dialog_options(farmer)
	check("farmer offers quest", opts[0].label.contains("Farmer's Start"))
	opts[0].fn.call()
	game.dialog_options(farmer)[0].fn.call()
	check("quest active", game.quests.harvest.state == "active")
	await shot("dialog", 5)
	game.ui.close()
	var plot: Dictionary = game.world.plots[0]
	tp(plot.pos + Vector3(0, 0.2, 1.3), 0.0)
	await physics_frame
	await physics_frame
	P.select(1)
	P.cool = 0
	P.primary()
	check("tilled", plot.state == "tilled")
	P.select(2)
	P.cool = 0
	P.primary()
	check("planted", plot.state == "planted")
	plot.t = 999.0
	await shot("crop", 10)
	game._update_focus()
	check("focus harvest", game.focus != null and String(game.focus.label).begins_with("Harvest"))
	game.interact()
	check("harvested", P.count("wheat") >= 1)
	P.add_item("wheat", 3)
	game.talk_to(farmer)
	game.dialog_options(farmer)[0].fn.call()
	check("quest done", game.quests.harvest.state == "done")
	game.ui.close()
	# ---- interiors & plaza
	for type in ["tavern", "smithy"]:
		for b in game.world.buildings:
			if b.type == type:
				var fwd := Vector3(sin(b.ang), 0, cos(b.ang))
				tp(Vector3(b.x, b.floorY + 0.1, b.z) + fwd * (b.d / 2.0 - 1.0), b.ang, -0.1)
		await shot(type, 30)
	tp(Vector3(0, game.world.plaza_y + 0.2, 18), 0.0)
	await shot("plaza", 30)
	# ---- combat
	P.add_item("iron_sword")
	P.add_item("hunting_bow")
	P.add_item("tome_fireball")
	P.hotbar = ["iron_sword", "hunting_bow", "tome_fireball", "pitchfork", "hoe", "bread"]
	P.select(0)
	var gob = null
	for e in game.enemies:
		if e.type == "goblin":
			gob = e
			break
	var gp: Vector3 = gob.position
	tp(gp + Vector3(1.6, 0.3, 0), atan2(1.6, 0.0))
	await shot("camp", 30)
	var hp0: float = gob.hp
	for i in 12:
		P.hp = P.max_hp
		P.yaw = atan2(-(gob.position.x - P.position.x), -(gob.position.z - P.position.z))
		P.cool = 0
		P.primary()
		await create_timer(0.3).timeout
		if gob.dead:
			break
	check("goblin damaged/killed (hp %d -> %d)" % [hp0, gob.hp], gob.hp < hp0)
	check("melee xp", P.skills.melee.xp > 0 or P.skills.melee.lvl > 0)
	P.select(2)
	P.mp = P.max_mp
	P.cool = 0
	P.primary()
	await shot("fireball", 6)
	game.hours = 21.5
	tp(Vector3(0, game.world.plaza_y + 0.2, 22), 0.0)
	await shot("night", 40)
	game.ui.open("skills")
	await shot("skills", 5)
	game.ui.open("inventory")
	await shot("inventory", 5)
	game.ui.open("map")
	await shot("map", 5)
	game.ui.close()
	# ---- the old silver mine
	game.hours = 12.0
	var guard = game.npc_by_role("guard")
	game.talk_to(guard)
	var gopts: Array = game.dialog_options(guard)
	check("guard offers the mine quest", gopts[0].label.contains("Silence in the Deep"))
	gopts[0].fn.call()
	game.dialog_options(guard)[0].fn.call()
	check("mine quest active", game.quests.mine.state == "active")
	game.ui.close()
	var M: Dictionary = game.world.mine
	print("[t] mine: %d rooms, %d tunnels, %d torches, %d ores, %d chests" % [M.rooms.size(), M.tunnels.size(), M.torches.size(), game.world.ores.size(), game.world.chests.size()])
	var ms: Dictionary = game.world.mine_surface
	tp(ms.pos, ms.yaw + PI)
	await shot("mine_outside", 30)
	for it in game.world.interactables:
		if it.type == "mine":
			var to: Vector3 = (ms.pos - it.pos) * Vector3(1, 0, 1)
			tp(Vector3(it.pos.x, ms.pos.y, it.pos.z) + to.normalized() * 1.8, ms.yaw + PI)
	await physics_frame
	game._update_focus()
	check("mine entrance focus", game.focus != null and game.focus.type == "mine")
	game.interact()
	check("in mine", game.in_mine and game.world.underground)
	for i in 40:
		await physics_frame
	check("standing on the mine floor (y %.1f)" % P.position.y, P.is_on_floor() and absf(P.position.y - M.entry_pos.y) < 1.5)
	await shot("mine_entry", 10)
	for e in game.enemies:
		if e.under and e.type != "foreman":
			e.die()
	for ti in 2:
		var t: Dictionary = M.tunnels[ti]
		var a2: Vector2 = t.pts[0].lerp(t.pts[1], 0.75)
		var b2: Vector2 = t.pts[1]
		var f2 := (b2 - a2).normalized()
		tp(Vector3(a2.x, Mine.floor_y(M, a2.x, a2.y) + 0.4, a2.y), atan2(-f2.x, -f2.y), -0.05)
		await shot("mine_tunnel%d" % ti, 30)
	for rm in M.rooms:
		if rm.type == "entry":
			continue
		var c: Vector2 = rm.c
		var a := randf() * TAU
		var at: Vector2 = c + Vector2(sin(a), cos(a)) * rm.r * 0.45
		if Mine.open_at(M, at.x, at.y) < 1.0:
			at = c
		var f := (c - at).normalized() if at != c else Vector2(0, 1)
		tp(Vector3(at.x, Mine.floor_y(M, at.x, at.y) + 0.4, at.y), atan2(-f.x, -f.y), -0.05)
		P.hp = P.max_hp
		await shot("mine_" + rm.type, 30)
		check("floor in %s" % rm.type, P.is_on_floor() and P.position.y > Mine.Y - 20.0)
	game.ui.open("map")
	await shot("mine_map", 5)
	game.ui.close()
	for e in game.enemies:
		if e.type == "foreman":
			e.damage(99999.0, null)
			game.on_kill(e, "melee")
	check("foreman quest progress", game.quests.mine.progress >= 1)
	var ore: Dictionary = game.world.ores[0]
	tp(ore.pos - Vector3(0, 0.9, 0) + (Vector3(M.rooms[0].c.x, 0, M.rooms[0].c.y) - ore.pos).normalized() * 0.0, 0.0)
	var ore_before := P.count("silver_ore")
	game.focus = ore
	game.interact()
	check("mined silver ore", P.count("silver_ore") > ore_before and ore.respawn > 0.0)
	game.leave_mine()
	await physics_frame
	check("left the mine", not game.in_mine and P.position.distance_to(ms.pos) < 1.0)
	await shot("mine_back", 20)
	game.talk_to(guard)
	game.dialog_options(guard)[0].fn.call()
	check("mine quest turned in", game.quests.mine.state == "done")
	game.ui.close()
	game.save_game(true)
	check("save written", FileAccess.file_exists(Game.SAVE_PATH))
	print("[t] done")
	quit()
