extends SceneTree
## Dev harness: godot --path game -s res://scripts/devtest.gd -- shots=plaza,tavern out=C:/tmp
## Generates a world and saves screenshots from preset viewpoints (not shipped in exports).

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var t0 := Time.get_ticks_msec()
	await Assets.load_all(root, func(p): pass)
	print("[test] assets loaded in %d ms" % (Time.get_ticks_msec() - t0))
	var world := World.new()
	root.add_child(world)
	t0 = Time.get_ticks_msec()
	await world.generate(int(args.get("seed", "12345")), args.get("quality", "high"), func(label, p): print("[test] ", label))
	print("[test] world generated in %d ms" % (Time.get_ticks_msec() - t0))
	var cam := Camera3D.new()
	cam.fov = 75
	cam.far = 600
	root.add_child(cam)
	cam.current = true
	var hours := float(args.get("hours", "10"))
	var out: String = args.get("out", "user://")
	for shot in args.get("shots", "plaza").split(","):
		var pos := Vector3.ZERO
		var look := Vector3.ZERO
		match shot:
			"plaza":
				pos = Vector3(0, world.plaza_y + 1.7, 20)
				look = Vector3(0, world.plaza_y + 1.2, 0)
			"aerial":
				pos = Vector3(60, 70, 90)
				look = Vector3(0, 0, 0)
			"tavern", "store", "smithy", "chapel", "magetower", "farmhouse":
				for b in world.buildings:
					if b.type == shot:
						var fwd := Vector3(sin(b.ang), 0, cos(b.ang))
						pos = Vector3(b.x, b.floorY + 1.6, b.z) + fwd * (b.d / 2.0 - 1.0)
						look = Vector3(b.x, b.floorY + 1.2, b.z) - fwd * 2.0
			"front":
				var b = world.buildings[1]
				var fwd := Vector3(sin(b.ang), 0, cos(b.ang))
				pos = Vector3(b.x, b.floorY + 1.7, b.z) + fwd * (b.d / 2.0 + 9.0)
				look = Vector3(b.x, b.floorY + 2.0, b.z)
			"camp", "grave", "mine", "pond":
				var p: Vector2 = world.pois[shot]
				var dir := p.normalized()
				var cp := p - dir * 24.0
				pos = Vector3(cp.x, world.height_at(cp.x, cp.y) + 2.0, cp.y)
				look = Vector3(p.x, world.height_at(p.x, p.y) + 1.0, p.y)
			"forest":
				var p := Vector2(0, 120).rotated(world.gates[0] + 0.9)
				pos = Vector3(p.x, world.height_at(p.x, p.y) + 1.7, p.y)
				look = pos + Vector3(10, 0, 3)
		cam.global_position = pos
		cam.look_at(look)
		for i in 30:
			world.update(0.016, hours, pos)
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(out.path_join("shot_%s.png" % shot))
		print("[test] saved ", shot, "  fps=", Engine.get_frames_per_second(), "  draw calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	quit()
