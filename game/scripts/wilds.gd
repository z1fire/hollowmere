class_name Wilds
extends RefCounted
## Goblin camp, graveyard, collapsed mine, pond, herbs, treasure chests and enemy spawns.

const DARK := "#6a5040"


static func build(W: World) -> void:
	var R := U.make_rng(W.seed_value + 41)
	var batch := MeshBatch.new()
	_goblin_camp(W, R, batch)
	_graveyard(W, R, batch)
	_mine(W, R, batch)
	_pond(W, R, batch)
	var mi := batch.build(W.mats)
	mi.name = "Wilds"
	W.add_child(mi)
	_wolf_spawns(W, R)


static func _at(W: World, batch: MeshBatch, p: Vector2) -> Builder:
	return Builder.at(W, batch, p.x, W.height_at(p.x, p.y), p.y, atan2(-p.x, -p.y))  # local +z faces the village


static func _spawn(W: World, B: Builder, type: String, lx: float, lz: float, leash: float) -> void:
	var p := B.P(lx, lz)
	W.spawns.append({"type": type, "x": p.x, "z": p.z, "leash": leash})


static func _goblin_camp(W: World, R: RandomNumberGenerator, batch: MeshBatch) -> void:
	var c: Vector2 = W.pois.camp
	var B := _at(W, batch, c)
	W.map_labels.append({"x": c.x, "z": c.y, "text": "Goblin Camp", "danger": true})
	B.prop("village", "Bonfire_Fire", 0, 0, 0, 0.0, 0.75, {"collide": false})
	B.geo("fire", ["cyl", 0.0, 0.35, 0.9, 6], 0, 0.55, 0, 0, "#ff7a1a")
	B.geo("fire", ["cyl", 0.0, 0.2, 0.6, 5], 0.05, 0.5, 0.05, 1.0, "#ffd35a")
	W.add_cylinder_collider(B.P(0, 0, 0.5), 0.9, 1.0)
	var tents: Array = []
	for i in 6:
		var a := PI * 0.35 + i / 5.0 * PI * 1.3
		var r := 10.5 if i == 3 else R.randf_range(7.5, 9.5)
		var s := 1.6 if i == 3 else R.randf_range(0.9, 1.2)
		var x := sin(a) * r
		var z := cos(a) * r
		B.prop("village", "Tent", x, -0.05, z, a + PI, 0.2 * s, {"collide": false, "tint": Color(U.pick(R, ["#ffffff", "#e8d8c0", "#d0c0a0"]))})
		W.add_cylinder_collider(B.P(x, z, 1.2), 1.6 * s, 2.5)
		tents.append(Vector2(x, z))
	var a := PI * 0.25
	while a < PI * 1.75:
		var x := sin(a) * 15.0
		var z := cos(a) * 15.0
		var h := R.randf_range(2.0, 2.8)
		B.cyl("log", x, h / 2, z, 0.2, h, "#d8c0a0", false, 6)
		B.geo("log", ["cyl", 0.0, 0.2, 0.5, 6], x, h + 0.25, z, 0, "#d8c0a0")
		W.add_cylinder_collider(B.P(x, z, h / 2), 0.32, h)
		a += 0.075
	for s in [-1.0, 1.0]:
		B.prop("halloween", "post_skull", s * 3.2, 0, 13.0, -PI / 2 if s > 0 else PI / 2, 1.1)
	for i in 5:
		var aa := R.randf_range(0, TAU)
		var rr := R.randf_range(4.0, 6.0)
		B.prop("dungeon", U.pick(R, ["box_small", "box_large", "barrel_small", "crates_stacked"]), sin(aa) * rr, 0, cos(aa) * rr, R.randi_range(0, 3) * PI / 2, 0.6)
	for i in 10:
		var aa := R.randf_range(0, TAU)
		var rr := R.randf_range(2.0, 8.0)
		B.prop("halloween", U.pick(R, ["bone_A", "bone_B", "skull", "ribcage"]), sin(aa) * rr, 0.05, cos(aa) * rr, R.randf_range(0, 6), 0.5, {"collide": false})
	B.prop("village", "Pot", 1.6, 0, -1.2, 0.5, 0.5, {"collide": false})
	B.prop("village", "WoodLog", -1.8, 0, 0.8, 1.2, 0.45)
	B.prop("village", "WoodLog", 0.6, 0, 1.9, 2.6, 0.45)
	var big: Vector2 = tents[3]
	_spawn(W, B, "goblin_chief", big.x * 0.7, big.y * 0.7, 26.0)
	for i in 5:
		var aa := R.randf_range(0, TAU)
		var rr := R.randf_range(3.0, 7.0)
		_spawn(W, B, "goblin", sin(aa) * rr, cos(aa) * rr, 26.0)
	_spawn(W, B, "goblin_archer", -5, 10, 26.0)
	_spawn(W, B, "goblin_archer", 5, 10, 26.0)
	for i in 2:
		_spawn(W, B, "goblin", R.randf_range(-8, 8), R.randf_range(18, 26), 26.0)


static func _graveyard(W: World, R: RandomNumberGenerator, batch: MeshBatch) -> void:
	var c: Vector2 = W.pois.grave
	var B := _at(W, batch, c)
	W.map_labels.append({"x": c.x, "z": c.y, "text": "Old Graveyard", "danger": true})
	var hw := 13.0
	var hd := 11.0
	var fence_run := func(x0: float, z0: float, x1: float, z1: float) -> void:
		var L := Vector2(x1 - x0, z1 - z0).length()
		var n := maxi(1, roundi(L / 2.9))
		var ry := atan2(x1 - x0, z1 - z0) - PI / 2.0
		for i in n:
			var t := (i + 0.5) / n
			B.prop("halloween", "fence_broken" if R.randf() < 0.2 else "fence", lerpf(x0, x1, t), 0, lerpf(z0, z1, t), ry, (L / n) / 2.9)
			B.prop("halloween", "fence_pillar", lerpf(x0, x1, float(i) / n), 0, lerpf(z0, z1, float(i) / n), 0.0, 1.0)
	fence_run.call(-hw, -hd, hw, -hd)
	fence_run.call(-hw, -hd, -hw, hd)
	fence_run.call(hw, -hd, hw, hd)
	fence_run.call(-hw, hd, -2.2, hd)
	fence_run.call(2.2, hd, hw, hd)
	B.prop("halloween", "arch_gate", 0, 0, hd, 0.0, 1.05, {"collide": false})
	for s in [-1.0, 1.0]:
		B.col_box(s * 1.9, hd, 0.5, 0.6, 0, 3)
	for i in range(-4, 5):
		for j in range(-3, 3):
			if absi(i) < 1 or R.randf() < 0.3:
				continue
			var x := i * 2.6 + R.randf_range(-0.3, 0.3)
			var z := j * 2.8 + R.randf_range(-0.3, 0.3)
			B.prop("halloween", U.pick(R, ["grave_A", "grave_B", "grave_A_destroyed", "gravestone", "gravemarker_A", "gravemarker_B", "gravestone"]), x, 0, z, R.randf_range(-0.15, 0.15), R.randf_range(0.8, 1.0))
	var K := B.sub(0, -hd + 4.0, 0)
	K.prop("halloween", "crypt", 0, 0, 0, PI, 1.05)
	var kp := K.P(0, 3.4)
	W.interactables.append({"type": "crypt", "pos": Vector3(kp.x, B.y + 1.0, kp.z), "r": 2.6, "label": "Crypt Door"})
	for p in [Vector2(-hw + 1.5, hd - 1.5), Vector2(hw - 1.5, hd - 1.5), Vector2(-hw + 1.5, -hd + 1.5), Vector2(hw - 1.5, -hd + 1.5)]:
		B.prop("halloween", "post_lantern", p.x, 0, p.y, atan2(-p.x, -p.y), 1.0)
	for i in 5:
		B.prop("halloween", U.pick(R, ["tree_dead_large", "tree_dead_medium", "tree_dead_small"]), U.pick(R, [-1.0, 1.0]) * R.randf_range(hw + 2, hw + 6), 0, R.randf_range(-hd, hd), R.randf_range(0, 6), 1.3)
	for i in 6:
		B.prop("halloween", U.pick(R, ["pumpkin_orange", "pumpkin_orange_jackolantern", "skull_candle", "candle_triple", "bone_A"]), R.randf_range(-hw + 1, hw - 1), 0, R.randf_range(-hd + 6, hd - 1), R.randf_range(0, 6), 0.8, {"collide": false})
	B.prop("halloween", "coffin", 6, 0, -hd + 3, 0.3, 0.8)
	B.prop("halloween", "shrine_candles", -6, 0, -hd + 3, 0.0, 0.9)
	for i in 6:
		B.geo("glow", ["sphere", 0.08, 0, 0, 6], R.randf_range(-hw + 2, hw - 2), 0.6, R.randf_range(-hd + 2, hd - 2), 0, "#66ffcc")
	for i in 5:
		_spawn(W, B, "skeleton", R.randf_range(-9, 9), R.randf_range(-6, 6), 24.0)
	_spawn(W, B, "skeleton_archer", -7, -6, 24.0)
	_spawn(W, B, "skeleton_archer", 7, -6, 24.0)
	_spawn(W, B, "skeleton", 0, 16, 24.0)


static func _mine(W: World, R: RandomNumberGenerator, batch: MeshBatch) -> void:
	var c: Vector2 = W.pois.mine
	var B := _at(W, batch, c)
	W.map_labels.append({"x": c.x, "z": c.y, "text": "Collapsed Mine"})
	B.prop("dungeon", "rubble_large", 0, 0, -1.2, 0.0, 0.55, {"collide": false})
	for s in [-1.0, 1.0]:
		B.prop("dungeon", "torch_lit", s * 2.6, 0, -1.4, 0.0, 1.2, {"collide": false})
	for i in 14:
		var a := R.randf_range(-1.4, 1.4)
		var r := R.randf_range(5.0, 9.0)
		var s := R.randf_range(2.0, 4.0)
		B.prop("nature", U.pick(R, ["Rock_Moss_1", "Rock_Moss_4", "Rock_2", "Rock_3"]), sin(a) * r, -0.3, -cos(a) * r, R.randf_range(0, 6), s * 1.6, {"shrink": 0.7})
	B.prop("nature", "Rock_Moss_4", 0, -0.5, -5.5, 0.0, 6.5, {"shrink": 0.7})
	B.box("color", 0, 1.6, -2.4, 3.4, 3.2, 0.3, "#0a0806", false)
	for s in [-1.0, 1.0]:
		B.box("wood", s * 1.7, 1.7, -2.2, 0.35, 3.4, 0.35, DARK)
	B.box("wood", 0, 3.4, -2.2, 4.2, 0.4, 0.4, DARK, false)
	for i in 4:
		B.box("wood", 0, 0.6 + i * 0.75, -2.0, 3.3, 0.22, 0.08, "#7a5634", false)
	B.b.add_box("wood", B.t * U.xf(Vector3(0, 1.7, -1.95), 0.0, Vector3(3.6, 0.22, 0.08), 0.0, 0.7), "#6a4a2a")
	B.col_box(0, -2.2, 3.6, 0.6, 0, 3.4)
	for s in [-1.0, 1.0]:
		B.box("metal", s * 0.5, 0.05, 0.5, 0.08, 0.08, 5, "#555555", false)
	var z := -1.5
	while z < 3.0:
		B.box("wood", 0, 0.02, z, 1.4, 0.06, 0.2, DARK, false)
		z += 0.6
	B.box("metal", 0, 0.6, 1.2, 1.0, 0.6, 1.4, "#5a5048", true)
	B.box("color", 0, 0.93, 1.2, 0.85, 0.1, 1.2, "#4a4a4a", false)
	B.cyl("color", 2.4, 1.0, 0.3, 0.06, 2.0, "#2a2a2a", true, 6)
	B.box("window", 2.4, 2.0, 0.3, 0.22, 0.3, 0.22, null, false)
	var ip := B.P(0, -0.8)
	W.interactables.append({"type": "mine", "pos": Vector3(ip.x, B.y + 1.2, ip.z), "r": 3.0, "label": "Mine Entrance"})


static func _pond(W: World, R: RandomNumberGenerator, batch: MeshBatch) -> void:
	var p: Dictionary = W.water
	var B := Builder.at(W, batch, 0, 0, 0, 0)
	W.map_labels.append({"x": p.x, "z": p.z, "text": "Mirror Pond"})
	for i in 70:
		var a := R.randf_range(0, TAU)
		var r: float = p.r * R.randf_range(0.85, 1.1)
		var x: float = p.x + sin(a) * r
		var z: float = p.z + cos(a) * r
		var y := W.height_at(x, z)
		B.geo("color", ["cyl", 0.02, 0.03, 1.2, 3], x, y + 0.5, z, 0, "#6a8a3a", Vector3(1, R.randf_range(0.6, 1.4), 1), R.randf_range(-0.15, 0.15), R.randf_range(-0.15, 0.15))
		if R.randf() < 0.3:
			B.geo("color", ["cyl", 0.05, 0.05, 0.22, 5], x, y + 1.05, z, 0, "#5a3a1a")
	for i in 10:
		var a := R.randf_range(0, TAU)
		var r: float = p.r * R.randf_range(0.2, 0.7)
		W.props.add("nature", "Lilypad", U.xf(Vector3(p.x + sin(a) * r, p.y + 0.02, p.z + cos(a) * r), R.randf_range(0, TAU), Vector3.ONE * R.randf_range(0.5, 0.9)))
	var a := atan2(-p.x, -p.z)
	var D := B.sub(p.x + sin(a) * (p.r - 1.0), p.z + cos(a) * (p.r - 1.0), a + PI, p.y + 0.35)
	D.box("wood", 0, 0, 0, 1.6, 0.12, 5, "#8a6a44", false)
	D.col_box(0, 0, 1.6, 5, -0.4, 0.06)
	for s in [-1.0, 1.0]:
		for zz in [-2.0, 0.0, 2.0]:
			D.box("wood", s * 0.7, -0.6, zz, 0.15, 1.4, 0.15, "#5a3a1a", false)


static func herbs_and_chests(W: World) -> void:
	var R := U.make_rng(W.seed_value + 43)
	W.herbs = []
	W.chests = []
	var stem := StandardMaterial3D.new()
	stem.albedo_color = Color("#3a6a3a")
	var petal := StandardMaterial3D.new()
	petal.albedo_color = Color("#8ad8ff")
	petal.emission_enabled = true
	petal.emission = Color("#5ab8ff")
	petal.emission_energy_multiplier = 2.5
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.015
	stem_mesh.bottom_radius = 0.015
	stem_mesh.height = 0.4
	stem_mesh.radial_segments = 3
	stem_mesh.material = stem
	var petal_mesh := SphereMesh.new()
	petal_mesh.radius = 0.09
	petal_mesh.height = 0.18
	petal_mesh.radial_segments = 4
	petal_mesh.rings = 2
	petal_mesh.material = petal
	var tries := 0
	while W.herbs.size() < 26 and tries < 2000:
		tries += 1
		var a := R.randf_range(0, TAU)
		var r := R.randf_range(70.0, 170.0)
		var x := sin(a) * r
		var z := cos(a) * r
		if not W.is_clear(x, z, 2.0):
			continue
		var y := W.height_at(x, z)
		var hb := MeshBatch.new()
		for i in 5:
			var o := Vector3(R.randf_range(-0.2, 0.2), 0, R.randf_range(-0.2, 0.2))
			hb.add_arrays("stem", stem_mesh.get_mesh_arrays(), U.xf(o + Vector3(0, 0.2, 0)), Color.WHITE)
			hb.add_arrays("petal", petal_mesh.get_mesh_arrays(), U.xf(o + Vector3(0, 0.42, 0)), Color.WHITE)
		var g := hb.build({"stem": stem, "petal": petal}, false)
		g.position = Vector3(x, y, z)
		g.visibility_range_end = 90.0
		W.add_child(g)
		var it := {"type": "herb", "pos": Vector3(x, y + 0.4, z), "r": 1.8, "label": "Pick Moonpetal", "node": g, "respawn": 0.0}
		W.herbs.append(it)
		W.interactables.append(it)
	var spots: Array = W.rock_spots.filter(func(p): return Vector2(p.x, p.z).length() > 80.0 and Vector2(p.x, p.z).length() < 170.0)
	U.shuffle(R, spots)
	var id := 0
	for s in spots:
		if W.chests.size() >= 6:
			break
		var x: float = s.x + 1.8
		var z: float = s.z + 1.0
		if not W.is_clear(x, z, 1.0):
			continue
		var y := W.height_at(x, z)
		var g := Node3D.new()
		g.position = Vector3(x, y, z)
		g.rotation.y = R.randf_range(0, 6)
		var closed := Assets.instance("village", "Chest_Closed")
		var opened := Assets.instance("village", "Chest_Open")
		closed.scale = Vector3.ONE * 1.1
		opened.scale = Vector3.ONE * 1.1
		opened.visible = false
		g.add_child(closed)
		g.add_child(opened)
		W.add_child(g)
		W.add_cylinder_collider(Vector3(x, y + 0.4, z), 0.5, 0.8)
		var it := {"type": "chest", "id": id, "pos": Vector3(x, y + 0.4, z), "r": 2.0, "label": "Open Chest", "closed": closed, "opened": opened, "opened_day": -1}
		id += 1
		W.chests.append(it)
		W.interactables.append(it)


static func _wolf_spawns(W: World, R: RandomNumberGenerator) -> void:
	var n := 0
	var tries := 0
	while n < 13 and tries < 500:
		tries += 1
		var a := R.randf_range(0, TAU)
		var r := R.randf_range(78.0, 168.0)
		var p := Vector2(sin(a) * r, cos(a) * r)
		if p.distance_to(W.pois.camp) < 35.0 or p.distance_to(W.pois.grave) < 35.0:
			continue
		if not W.is_clear(p.x, p.y, 0.0):
			continue
		for i in R.randi_range(1, 2):
			W.spawns.append({"type": "wolf", "x": p.x + R.randf_range(-3, 3), "z": p.y + R.randf_range(-3, 3), "leash": 30.0})
		n += 1
