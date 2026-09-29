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
	game.ui.close()
	game.save_game(true)
	check("save written", FileAccess.file_exists(Game.SAVE_PATH))
	print("[t] done")
	quit()
