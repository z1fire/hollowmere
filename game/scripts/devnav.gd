extends SceneTree
## Dev harness (not shipped): generate worlds and check, against the real colliders, that a
## player-sized capsule can walk from the mine entrance to every cavern.
## godot --headless --path game -s res://scripts/devnav.gd -- seeds=20 start=1

const STEP := 0.5
const PLAYER_R := 0.36

var seeds := 12
var start := 1
var out := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv[0] == "seeds":
			seeds = int(kv[1])
		elif kv[0] == "out":
			out = kv[1]
		elif kv[0] == "start":
			start = int(kv[1])
	_run.call_deferred()


func _run() -> void:
	await Assets.load_all(root, func(p): pass)
	var bad := 0
	for s in range(start, start + seeds):
		var W := World.new()
		root.add_child(W)
		await W.generate(s, "low", func(l, p): pass)
		await physics_frame
		await physics_frame
		var blocked := check(W, out.path_join("nav_%d.png" % s) if out != "" else "")
		if blocked.size() > 0:
			bad += 1
			print("[nav] seed %d: unreachable %s" % [s, blocked])
		W.free()
		await process_frame
	print("[nav] %d/%d worlds had unreachable caverns" % [bad, seeds])
	quit()


## returns descriptions of caverns the player cannot walk to from the entrance
static func check(W: World, dump := "") -> Array:
	var M: Dictionary = W.mine
	var space := W.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = PLAYER_R
	cap.height = 1.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	var n := int(M.size / STEP)
	var walk := PackedByteArray()
	walk.resize(n * n)
	var fy := PackedFloat32Array()
	fy.resize(n * n)
	for j in n:
		for i in n:
			var x: float = M.x0 + (i + 0.5) * STEP
			var z: float = M.z0 + (j + 0.5) * STEP
			if Mine.open_at(M, x, z) < 0.2:
				continue
			var y := Mine.floor_y(M, x, z)
			fy[j * n + i] = y
			# capsule from 0.3 m above the floor (leaves room for gentle slopes) to 1.6 m
			q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + 0.3 + 0.65, z))
			if space.intersect_shape(q, 1).is_empty():
				walk[j * n + i] = 1
	var cell := func(p: Vector2) -> int:
		var best := -1
		var bd := 1e9
		var ci := int((p.x - M.x0) / STEP)
		var cj := int((p.y - M.z0) / STEP)
		for dj in range(-6, 7):
			for di in range(-6, 7):
				var i := ci + di
				var j := cj + dj
				if i < 0 or j < 0 or i >= n or j >= n or walk[j * n + i] == 0:
					continue
				var d := float(di * di + dj * dj)
				if d < bd:
					bd = d
					best = j * n + i
		return best
	var src: int = cell.call(Vector2(M.entry_pos.x, M.entry_pos.z))
	if src < 0:
		return ["entry spawn is inside a collider"]
	var seen := PackedByteArray()
	seen.resize(n * n)
	seen[src] = 1
	var queue := [src]
	var head := 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		var ci := c % n
		var cj := c / n
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var i: int = ci + d.x
			var j: int = cj + d.y
			if i < 0 or j < 0 or i >= n or j >= n:
				continue
			var k := j * n + i
			if seen[k] == 1 or walk[k] == 0 or absf(fy[k] - fy[c]) > 0.35:
				continue
			seen[k] = 1
			queue.append(k)
	if dump != "":
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for k in n * n:
			var col := Color.BLACK
			var x: float = M.x0 + (k % n + 0.5) * STEP
			var z: float = M.z0 + (k / n + 0.5) * STEP
			if Mine.open_at(M, x, z) >= 0.2:
				col = Color(0.3, 0.3, 0.3) if walk[k] == 0 else (Color(0.2, 0.8, 0.3) if seen[k] == 1 else Color(0.9, 0.9, 0.9))
				if walk[k] == 1 and seen[k] == 0:
					col = Color(0.5 + clampf((fy[k] - M.rooms[0].y) * 0.1, -0.4, 0.4), 0.5, 0.9)
			img.set_pixel(k % n, k / n, col)
		img.resize(n * 4, n * 4, Image.INTERPOLATE_NEAREST)
		img.save_png(dump)
	var out: Array = []
	# a cavern counts as reached when the player can stand within reach of its centre
	# (2 m; 2.8 m for the cave-in, whose rubble fills the dead end on purpose)
	for rm in M.rooms:
		var reach := 2.8 if rm.type == "cavein" else 2.0
		var ok := false
		var ci := int((rm.c.x - M.x0) / STEP)
		var cj := int((rm.c.y - M.z0) / STEP)
		var span := int(reach / STEP) + 1
		for dj in range(-span, span + 1):
			for di in range(-span, span + 1):
				var i := ci + di
				var j := cj + dj
				if i >= 0 and j >= 0 and i < n and j < n and seen[j * n + i] == 1 and Vector2(di, dj).length() * STEP <= reach:
					ok = true
		if not ok:
			out.append(rm.type)
	return out
