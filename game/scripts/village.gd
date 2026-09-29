class_name Village
extends RefCounted
## Procedural village: layout, enterable furnished buildings, farm, plaza, fence & gates.

const DARK := "#c0a080"
const MID := "#d8bc98"
const LIGHT := "#d8c0a0"
const T := 0.3
const DW := 1.7
const DH := 2.5

const BTYPES := {
	"townhall": {"w": 12.0, "d": 9.0, "h": 4.2, "wall": "plaster", "roof": "shingle", "name": "Town Hall"},
	"tavern": {"w": 12.0, "d": 10.0, "h": 4.0, "wall": "plaster", "roof": "thatch", "name": "The Tipsy Turnip", "chimney": true},
	"smithy": {"w": 9.0, "d": 8.0, "h": 3.6, "wall": "stone", "roof": "shingle", "name": "Smithy", "chimney": true},
	"store": {"w": 9.0, "d": 8.0, "h": 3.6, "wall": "plaster", "roof": "shingle", "name": "General Store"},
	"herbalist": {"w": 7.0, "d": 7.0, "h": 3.3, "wall": "plaster", "roof": "thatch", "name": "Herbalist", "chimney": true},
	"magetower": {"w": 7.0, "d": 7.0, "h": 9.0, "wall": "stone", "roof": "cone", "name": "Mage Tower"},
	"hunter": {"w": 8.0, "d": 7.0, "h": 3.3, "wall": "log", "roof": "thatch", "name": "Hunter's Lodge"},
	"chapel": {"w": 8.0, "d": 13.0, "h": 5.0, "wall": "stone", "roof": "shingle", "name": "Chapel"},
	"house": {"w": 7.0, "d": 6.0, "h": 3.1, "wall": "plaster", "roof": "thatch", "name": "Cottage", "chimney": true},
	"farmhouse": {"w": 9.0, "d": 7.0, "h": 3.3, "wall": "plaster", "roof": "thatch", "name": "Your Farmhouse", "chimney": true},
}


static func _facing_rot(x: float, z: float) -> int:
	var t := atan2(-x, -z)
	return ((roundi(t / (PI / 2.0)) % 4) + 4) % 4


static func _rect(x: float, z: float, w: float, d: float, rot: int, m := 0.0) -> Dictionary:
	var W := d if rot % 2 else w
	var D := w if rot % 2 else d
	return {"minX": x - W / 2 - m, "maxX": x + W / 2 + m, "minZ": z - D / 2 - m, "maxZ": z + D / 2 + m}


static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	return a.minX < b.maxX and a.maxX > b.minX and a.minZ < b.maxZ and a.maxZ > b.minZ


static func _road_hits(W: World, rect: Dictionary) -> bool:
	var cx: float = (rect.minX + rect.maxX) / 2.0
	var cz: float = (rect.minZ + rect.maxZ) / 2.0
	var hd := Vector2(rect.maxX - rect.minX, rect.maxZ - rect.minZ).length() / 2.0
	for r in W.roads:
		for i in r.pts.size() - 1:
			var a: Vector2 = r.pts[i]
			var b: Vector2 = r.pts[i + 1]
			if U.dist_to_seg(cx, cz, a.x, a.y, b.x, b.y) < hd + r.w / 2.0 + 0.5:
				var L := a.distance_to(b)
				var t := 0.0
				while t <= L:
					var p := a.lerp(b, t / L)
					var hw: float = r.w / 2.0
					if p.x > rect.minX - hw and p.x < rect.maxX + hw and p.y > rect.minZ - hw and p.y < rect.maxZ + hw:
						return true
					t += 0.8
	return false


static func _inside(rect: Dictionary, max_r: float) -> bool:
	for c in [Vector2(rect.minX, rect.minZ), Vector2(rect.maxX, rect.minZ), Vector2(rect.minX, rect.maxZ), Vector2(rect.maxX, rect.maxZ)]:
		if c.length() >= max_r:
			return false
	return true


static func _near_plaza(rect: Dictionary) -> bool:
	var cx := maxf(rect.minX, minf(0.0, rect.maxX))
	var cz := maxf(rect.minZ, minf(0.0, rect.maxZ))
	return Vector2(cx, cz).length() < 14.0


# ================================================================ plan
static func plan(W: World) -> void:
	var R := U.make_rng(W.seed_value + 11)
	var placed: Array = []
	var g0: float = W.gates[0]
	var g1: float = W.gates[1]
	var farm_a := g0 + U.angle_diff(g0, g1) / 2.0
	var farm := {}
	var fdef: Dictionary = BTYPES.farmhouse
	for t in 60:
		var a := farm_a + R.randf_range(-0.35, 0.35)
		var p := U.polar(a, R.randf_range(36.0, 42.0))
		var rot := _facing_rot(p.x, p.y)
		var rect := _rect(p.x, p.y, fdef.w, fdef.d, rot, 2.0)
		var ang := rot * PI / 2.0
		var lx: float = fdef.w / 2.0 + 6.5
		var lz := 0.5
		var fx := p.x + lx * cos(ang) + lz * sin(ang)
		var fz := p.y - lx * sin(ang) + lz * cos(ang)
		var frect := _rect(fx, fz, 10.0, 8.5, rot, 1.5)
		if _road_hits(W, rect) or _road_hits(W, frect) or not _inside(rect, 55.0) or not _inside(frect, 56.0):
			continue
		farm = {"x": p.x, "z": p.y, "rot": rot, "fx": fx, "fz": fz, "rect": rect, "frect": frect}
		break
	if farm.is_empty():
		var p := U.polar(farm_a, 38.0)
		var rot := _facing_rot(p.x, p.y)
		farm = {"x": p.x, "z": p.y, "rot": rot, "fx": p.x + 10.0, "fz": p.y, "rect": _rect(p.x, p.y, 9, 7, rot, 2), "frect": _rect(p.x + 10.0, p.y, 10, 8.5, rot, 1.5)}
	W.farm = farm
	placed.append_array([farm.rect, farm.frect])
	var fb := fdef.duplicate()
	fb.merge({"type": "farmhouse", "x": farm.x, "z": farm.z, "rot": farm.rot})
	W.buildings.append(fb)
	for type in ["townhall", "tavern", "smithy", "store", "chapel", "herbalist", "magetower", "hunter", "house", "house", "house", "house", "house"]:
		var def: Dictionary = BTYPES[type]
		for t in 400:
			var relax := t / 400.0
			var min_r := 17.0 if type in ["townhall", "tavern"] else (28.0 if type in ["magetower", "hunter"] else 18.0)
			var max_r := 30.0 + relax * 20.0 if type in ["townhall", "tavern"] else 50.0
			var p := U.polar(R.randf_range(0, TAU), R.randf_range(min_r, max_r))
			var rot := _facing_rot(p.x, p.y)
			var rect := _rect(p.x, p.y, def.w, def.d, rot, 2.5)
			if not _inside(rect, 56.0) or _near_plaza(rect) or _road_hits(W, rect) or placed.any(func(o): return _overlap(o, rect)):
				continue
			placed.append(rect)
			var bd := def.duplicate()
			bd.merge({"type": type, "x": p.x, "z": p.y, "rot": rot})
			W.buildings.append(bd)
			break
	for b in W.buildings:
		b.floorY = W.plaza_y + 0.08
		W.flats.append({"x": b.x, "z": b.z, "r": Vector2(b.w, b.d).length() / 2.0 + 0.8, "fall": 5.0, "h": W.plaza_y})
		var rr := _rect(b.x, b.z, b.w, b.d, b.rot, 1.5)
		rr["t"] = "r"
		W.excl.append(rr)
		var ang: float = b.rot * PI / 2.0
		var lz: float = b.d / 2.0 + 1.3
		var door := Vector2(b.x + lz * sin(ang), b.z + lz * cos(ang))
		b.door_front = door
		W.roads.append({"pts": [door, U.polar(atan2(door.x, door.y), 11.0)], "w": 1.6, "main": false})
	W.flats.append({"x": farm.fx, "z": farm.fz, "r": 7.0, "fall": 5.0, "h": W.plaza_y})
	var fr: Dictionary = farm.frect.duplicate()
	fr["t"] = "r"
	W.excl.append(fr)


# ================================================================ build
static var _shared: MeshBatch


static func build(W: World) -> void:
	var R := U.make_rng(W.seed_value + 23)
	_shared = MeshBatch.new()
	for b in W.buildings:
		_build_building(W, b, R)
	_add(W, _shared.build(W.mats), "Buildings")
	_farm_field(W, R)
	_plaza(W, R)
	_fence(W, R)
	_street_props(W, R)
	_waypoints(W)


static func _add(W: World, mi: MeshInstance3D, label := "") -> void:
	if label != "":
		mi.name = label
	W.add_child(mi)


static func _sign(W: World, text: String, pos: Vector3, yaw: float, width := 1.8) -> void:
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.45, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = Assets.tex.beam.albedo
	mat.albedo_color = Color("#8a6040")
	bm.material = mat
	board.mesh = bm
	board.position = pos
	board.rotation.y = yaw
	W.add_child(board)
	for s in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = text
		l.font = Assets.fonts.Cinzel
		l.font_size = 64
		l.pixel_size = 0.0045
		l.modulate = Color("#f3d98b")
		l.outline_size = 10
		l.outline_modulate = Color("#2a1a0c")
		l.double_sided = false
		l.position = Vector3(0, 0, 0.035 * s)
		l.rotation.y = 0.0 if s > 0 else PI
		l.width = width / l.pixel_size
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		board.add_child(l)


static func _build_building(W: World, b: Dictionary, R: RandomNumberGenerator) -> void:
	var batch := _shared
	var ang: float = b.rot * PI / 2.0
	var B := Builder.at(W, batch, b.x, b.floorY, b.z, ang)
	var w: float = b.w
	var d: float = b.d
	var h: float = b.h
	var hw := w / 2.0
	var hd := d / 2.0
	var wall_key: String = b.wall
	var wall_color = U.pick(R, ["#fff4e0", "#f4e8d0", "#ffeede", "#efe4d6", "#fbe9c9"]) if wall_key == "plaster" else (U.pick(R, ["#ffffff", "#e8e4dc", "#d8d4cc"]) if wall_key == "stone" else "#ffffff")
	var trim = U.pick(R, ["#3f6a8a", "#7a2f2f", "#3f7a4a", "#6a4a8a", "#8a6a2f"])
	b.npcs = []
	# foundation + floor (floor collider top sits at local y=0 so walking in needs no step)
	B.box("stone", 0, -0.35, 0, w + 0.3, 0.7, d + 0.3, "#9a958c", false)
	B.box("wood", 0, 0.02, 0, w - 0.2, 0.06, d - 0.2, "#c8a276", false)
	B.col_box(0, 0, w, d, -0.5, 0.0)
	# walls
	B.box(wall_key, 0, h / 2, -hd + T / 2, w, h, T, wall_color)
	B.box(wall_key, -hw + T / 2, h / 2, 0, T, h, d - 2 * T, wall_color)
	B.box(wall_key, hw - T / 2, h / 2, 0, T, h, d - 2 * T, wall_color)
	var seg := hw - DW / 2.0
	B.box(wall_key, -hw + seg / 2, h / 2, hd - T / 2, seg, h, T, wall_color)
	B.box(wall_key, hw - seg / 2, h / 2, hd - T / 2, seg, h, T, wall_color)
	B.box(wall_key, 0, (DH + h) / 2, hd - T / 2, DW, h - DH, T, wall_color, false)
	# timber framing
	var corners := [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(-hw, hd), Vector2(hw, hd)]
	if wall_key == "plaster":
		for c in corners:
			B.box("beam", c.x, h / 2, c.y, 0.34, h, 0.34, DARK, false)
		B.box("beam", 0, h - 0.1, -hd - 0.02, w, 0.22, T + 0.1, DARK, false)
		B.box("beam", 0, h - 0.1, hd + 0.02, w, 0.22, T + 0.1, DARK, false)
		B.box("beam", -hw - 0.02, h - 0.1, 0, T + 0.1, 0.22, d, DARK, false)
		B.box("beam", hw + 0.02, h - 0.1, 0, T + 0.1, 0.22, d, DARK, false)
		for s in [-1.0, 1.0]:
			var x := -hw + 2.2
			while x < hw - 1.0:
				if absf(x) > 2.2:
					B.box("beam", x, h / 2, s * (hd + 0.03), 0.18, h, 0.06, DARK, false)
				x += 2.8
			var z := -hd + 2.2
			while z < hd - 1.0:
				B.box("beam", s * (hw + 0.03), h / 2, z, 0.06, h, 0.18, DARK, false)
				z += 2.8
	elif wall_key == "stone":
		for c in corners:
			B.box("stone", c.x, h / 2, c.y, 0.5, h + 0.1, 0.5, "#bdb8ae", false)
	else:
		for c in corners:
			B.cyl("log", c.x, h / 2, c.y, 0.2, h + 0.2, "#ffffff", false, 8)
	# door frame + open door
	B.box("beam", -DW / 2 - 0.08, DH / 2, hd, 0.16, DH, T + 0.14, DARK, false)
	B.box("beam", DW / 2 + 0.08, DH / 2, hd, 0.16, DH, T + 0.14, DARK, false)
	B.box("beam", 0, DH + 0.08, hd, DW + 0.32, 0.16, T + 0.14, DARK, false)
	B.box("wood", DW / 2 - 0.05, DH / 2 + 0.02, hd - T - 0.72, 0.08, DH - 0.06, 1.45, "#8a5a30", true)
	# windows
	var win_y := [1.6]
	if b.type == "magetower":
		win_y.append_array([4.6, 7.4])
	if b.type == "chapel":
		win_y[0] = 2.2
	var add_win := func(x: float, z: float, rotated: bool) -> void:
		for y in win_y:
			B.box("beam", x, y, z, T + 0.14 if rotated else 1.0, 1.05, 1.0 if rotated else T + 0.14, DARK, false)
			B.box("window", x, y, z, T + 0.16 if rotated else 0.8, 0.85, 0.8 if rotated else T + 0.16, null, false)
			B.box("beam", x, y, z, T + 0.18 if rotated else 0.06, 0.85, 0.06 if rotated else T + 0.18, DARK, false)
			B.box("beam", x, y, z, T + 0.18 if rotated else 0.8, 0.06, 0.8 if rotated else T + 0.18, DARK, false)
			if b.type != "magetower" and b.type != "chapel":
				var out := signf(x) if rotated else signf(z)
				for s in [-1.0, 1.0]:
					if rotated:
						B.box("color", x + out * (T / 2 + 0.06), y, z + s * 0.72, 0.05, 0.95, 0.42, trim, false)
					else:
						B.box("color", x + s * 0.72, y, z + out * (T / 2 + 0.06), 0.42, 0.95, 0.05, trim, false)
	var nx := maxi(1, int(w / 3.5))
	var nz := maxi(1, int(d / 3.5))
	for i in nx:
		add_win.call(-hw + (i + 0.5) * (w / nx), -hd + T / 2, false)
	for i in nz:
		var z := -hd + (i + 0.5) * (d / nz)
		if z < hd - 1.5:
			add_win.call(-hw + T / 2, z, true)
			add_win.call(hw - T / 2, z, true)
	if w >= 9.0:
		add_win.call(-hw + 1.6, hd - T / 2, false)
		add_win.call(hw - 1.6, hd - T / 2, false)
	# roof
	if b.roof == "cone":
		B.geo("shingle", ["cyl", 0.0, w * 0.78, 4.8, 4], 0, h + 2.4, 0, PI / 4, "#ffffff")
		B.geo("color", ["sphere", 0.25, 0, 0, 4], 0, h + 5.0, 0, 0, "#ffd84a")
		B.box("stone", 0, h + 0.15, 0, w + 0.4, 0.3, d + 0.4, "#bdb8ae", false)
		B.box("wood", 0, h - 0.05, 0, w - 0.3, 0.1, d - 0.3, "#8a6a44", false)
	else:
		_gable_roof(B, b, wall_key, wall_color)
	if b.get("chimney", false):
		var cx := hw - 1.4
		var cz := -hd + 1.2
		B.box("stone", cx, h + 1.4, cz, 0.8, 2.8, 0.8, "#a09a90", false)
		B.box("stone", cx, h + 2.85, cz, 0.95, 0.15, 0.95, "#8a847a", false)
	if b.type == "chapel":
		B.box("stone", 0, h + 3.2, hd - 1.2, 1.8, 3.6, 1.8, "#dedad0", false)
		B.geo("shingle", ["cyl", 0.0, 1.6, 2.4, 4], 0, h + 6.2, hd - 1.2, PI / 4, "#ffffff")
		B.box("color", 0, h + 3.4, hd - 1.2, 1.85, 0.9, 0.5, "#222222", false)
		B.box("color", 0, h + 8.0, hd - 1.2, 0.08, 0.9, 0.08, "#ffd84a", false)
		B.box("color", 0, h + 8.1, hd - 1.2, 0.5, 0.08, 0.08, "#ffd84a", false)
	if b.type != "house":
		_sign(W, b.name, B.P(0, hd + 0.2, minf(h - 0.3, DH + 0.55)), ang)
		W.map_labels.append({"x": b.x, "z": b.z, "text": b.name})
	# interior
	var a := B.P(-hw + T, -hd + T)
	var c := B.P(hw - T, hd - T + 0.05)
	b.inner = {"minX": minf(a.x, c.x), "maxX": maxf(a.x, c.x), "minZ": minf(a.z, c.z), "maxZ": maxf(a.z, c.z)}
	b.light_pos = B.P(0, 0, minf(h - 0.8, 3.2))
	b.ang = ang
	var npc := func(role: String, lx: float, lz: float, lyaw: float) -> void:
		var p := B.P(lx, lz)
		b.npcs.append({"role": role, "x": p.x, "z": p.z, "y": b.floorY + 0.05, "yaw": lyaw + ang})
	match b.type:
		"townhall": _townhall(B, b, R, npc)
		"tavern": _tavern(B, b, R, npc)
		"smithy": _smithy(B, b, R, npc)
		"store": _store(B, b, R, npc)
		"herbalist": _herbalist(B, b, R, npc)
		"magetower": _magetower(B, b, R, npc, W)
		"hunter": _hunter(B, b, R, npc)
		"chapel": _chapel(B, b, R, npc)
		"house": _house(B, b, R)
		"farmhouse": _farmhouse(B, b, R, W)


static func _gable_roof(B: Builder, b: Dictionary, wall_key: String, wall_color) -> void:
	var w: float = b.w
	var d: float = b.d
	var h: float = b.h
	var along_x := w >= d
	var L := w if along_x else d
	var S := d if along_x else w
	var oh := 0.5
	var half := S / 2.0 + oh
	var rh := S * 0.42
	var slope := rh / (S / 2.0)
	var ang_r := atan(slope)
	var slab_len := Vector2(half, half * slope).length()
	var frame := Transform3D.IDENTITY if along_x else Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO)
	var key: String = b.roof
	for s in [1.0, -1.0]:
		var zc: float = s * half / 2.0
		var yc := h + rh - slope * (half / 2.0)
		B.b.add_box(key, B.t * frame * U.xf(Vector3(0, yc + 0.08, zc), 0.0, Vector3(L + 2 * oh, 0.16, slab_len + 0.05), s * ang_r), "#ffffff")
		B.b.add_box("wood", B.t * frame * U.xf(Vector3(0, yc - 0.02, zc * 0.96), 0.0, Vector3(L - 0.1, 0.04, slab_len * 0.93), s * ang_r), "#6a4a2a")
	# gable triangles
	for s in [1.0, -1.0]:
		B.b.add_arrays(wall_key, MeshBatch.prim("prism", S, 0.3, rh), B.t * frame * U.xf(Vector3(s * (L / 2.0 - 0.15), h + rh / 2.0, 0), PI / 2.0), wall_color)
	B.b.add_box("beam", B.t * frame * U.xf(Vector3(0, h + rh + 0.06, 0), 0.0, Vector3(L + 2 * oh + 0.1, 0.2, 0.26)), "#6a5040")
	var x := -L / 2.0 + 1.0
	while x < L / 2.0 - 0.5:
		B.b.add_box("beam", B.t * frame * U.xf(Vector3(x, h - 0.05, 0), 0.0, Vector3(0.14, 0.14, S - 0.4)), DARK)
		x += 2.0


# ================================================================ furniture (KayKit models)
static func table(B: Builder, x: float, z: float, w := 1.4, d := 0.8, ry := 0.0) -> Builder:
	B.prop("dungeon", "table_small", x, 0.04, z, ry, 1.0, {"sx": w / 0.72, "sy": 1.06, "sz": d / 0.72})
	return B.sub(x, z, ry)


static func round_table(B: Builder, x: float, z: float, r := 0.6) -> void:
	B.prop("dungeon", "table_small", x, 0.04, z, 0.0, 1.0, {"sx": r * 2 / 0.72, "sy": 1.06, "sz": r * 2 / 0.72})


static func chair(B: Builder, x: float, z: float, ry := 0.0) -> void:
	B.prop("dungeon", "chair", x, 0.04, z, ry + PI, 1.0)


static func stool(B: Builder, x: float, z: float) -> void:
	B.prop("dungeon", "stool", x, 0.04, z, 0.0, 1.0)


static func bed(B: Builder, x: float, z: float, ry := 0.0) -> void:
	B.prop("furniture", "bed_single_A", x, 0.04, z, ry + PI, 1.12)


static func barrel(B: Builder, x: float, z: float, r := 0.36) -> void:
	B.prop("dungeon", "barrel_small", x, 0.04, z, fmod(x * 7.0 + z, 6.0), r * 2 / 0.72)


static func crate(B: Builder, x: float, z: float, s := 0.7, y := 0.0, ry := 0.0) -> void:
	B.prop("dungeon", "box_small", x, y + 0.04, z, ry, s / 0.72)


static func shelf(B: Builder, x: float, z: float, ry := 0.0, w := 1.8) -> void:
	B.prop("furniture", "cabinet_medium_decorated", x, 0.04, z, ry, 1.0, {"sx": w / 1.26, "sy": 1.25, "sz": 0.85})


static func bookshelf(B: Builder, x: float, z: float, ry := 0.0, w := 1.8) -> void:
	var s := B.sub(x, z, ry)
	s.prop("furniture", "cabinet_medium_decorated", 0, 0.04, 0.05, 0.0, 1.0, {"sx": w / 1.26, "sy": 1.25, "sz": 0.85})
	var k := -w / 2.0 + 0.35
	while k < w / 2.0 - 0.2:
		s.prop("furniture", "book_set", k, 1.46, 0.05, 0.0, 1.0, {"collide": false})
		k += 0.55


static func counter(B: Builder, x: float, z: float, length: float, ry := 0.0) -> void:
	var s := B.sub(x, z, ry)
	s.box("wood", 0, 0.5, 0, length, 1.0, 0.7, "#a07850")
	s.box("beam", 0, 1.03, 0, length + 0.1, 0.06, 0.8, LIGHT, false)
	s.prop("dungeon", "candle_triple", length / 2 - 0.35, 1.06, 0, 0.0, 0.4, {"collide": false})
	s.prop("dungeon", "bottle_A_brown", -length / 2 + 0.4, 1.06, 0.05, 0.0, 0.3, {"collide": false})
	s.prop("dungeon", "bottle_B_green", -length / 2 + 0.7, 1.06, -0.1, 0.0, 0.3, {"collide": false})


static func fireplace(B: Builder, x: float, z: float, ry := 0.0) -> void:
	var s := B.sub(x, z, ry)
	s.box("stone", 0, 0.9, 0, 1.8, 1.8, 0.8, "#d0c8bc")
	s.box("color", 0, 0.45, 0.41, 1.0, 0.8, 0.02, "#1a1410", false)
	s.box("fire", 0, 0.3, 0.3, 0.6, 0.35, 0.25, "#ff8a2a", false)
	s.box("fire", 0, 0.45, 0.3, 0.3, 0.3, 0.2, "#ffd35a", false)
	s.box("stone", 0, 2.5, -0.1, 1.0, 1.6, 0.5, "#c8c0b4", false)
	s.box("beam", 0, 1.85, 0.2, 2.0, 0.1, 0.5, DARK, false)
	s.prop("dungeon", "candle_triple", 0.6, 1.9, 0.2, 0.0, 0.55, {"collide": false})
	s.prop("dungeon", "bottle_A_green", -0.6, 1.9, 0.25, 0.0, 0.45, {"collide": false})


static func rug(B: Builder, x: float, z: float, w: float, d: float, ry := 0.0) -> void:
	var name := "rug_rectangle_A" if int(absf(x * 13.0 + z * 7.0)) % 2 else "rug_rectangle_stripes_A"
	B.prop("furniture", name, x, 0.05, z, ry, 1.0, {"sx": w / 1.86, "sy": 0.6, "sz": d / 1.24, "collide": false})


static func pew(B: Builder, x: float, z: float, length := 2.6) -> void:
	B.box("wood", x, 0.45, z, length, 0.07, 0.45, "#a07850")
	B.box("beam", x, 0.8, z - 0.22, length, 0.6, 0.06, MID, false)
	for s in [-1.0, 1.0]:
		B.box("beam", x + s * (length / 2 - 0.05), 0.45, z, 0.06, 0.9, 0.5, DARK, false)


static func candle(B: Builder, x: float, y: float, z: float) -> void:
	B.prop("dungeon", "candle_lit", x, y, z, 0.0, 0.38, {"collide": false})


static func rack(B: Builder, x: float, z: float, ry: float, kind: String) -> void:
	var s := B.sub(x, z, ry)
	if kind == "bow":
		s.box("beam", 0, 1.3, -0.05, 1.8, 0.1, 0.1, DARK, false)
		for k in [-0.55, 0.0, 0.55]:
			s.prop("village", "Bow_Wooden", k, 1.35, 0.05, 0.0, 0.55, {"collide": false})
	else:
		s.prop("dungeon", "sword_shield", 0, 1.9, 0.1, 0.0, 0.8, {"collide": false})


static func banner(B: Builder, x: float, y: float, z: float, ry: float, name: String) -> void:
	B.prop("dungeon", name, x, y - 2.3, z, ry, 0.8, {"collide": false})


static func torch(B: Builder, x: float, y: float, z: float, ry: float) -> void:
	B.prop("dungeon", "torch_mounted", x, y, z, ry, 0.8, {"collide": false})


# ================================================================ interiors
static func _townhall(B: Builder, b: Dictionary, R: RandomNumberGenerator, npc: Callable) -> void:
	var hw: float = b.w / 2.0
	var hd: float = b.d / 2.0
	rug(B, 0, 0.5, 2.2, b.d - 3.0)
	table(B, 0, -hd + 2.3, 3.2, 1.0)
	chair(B, 0, -hd + 1.4, 0)
	for x in [-1.0, 1.0]:
		bookshelf(B, x * (hw - 1.5), -hd + 0.35, 0, 2)
	banner(B, -2.6, 3.7, -hd + 0.3, 0, "banner_patternA_red")
	banner(B, 2.6, 3.7, -hd + 0.3, 0, "banner_patternB_blue")
	B.prop("dungeon", "table_small_decorated_A", 0.9, 0.84, -hd + 2.3, 0.0, 0.5, {"collide": false})
	B.prop("dungeon", "chest_gold", hw - 0.8, 0.04, hd - 1.4, -PI / 2, 0.6)
	for s in [-1.0, 1.0]:
		torch(B, s * (hw - 0.3), 2.2, 0.8, -PI / 2 if s > 0 else PI / 2)
		var z := -1.0
		while z <= 2.0:
			pew(B, s * (hw - 1.4), z, 1.8)
			z += 1.6
	candle(B, -1.2, 0.8, -hd + 2.3)
	candle(B, 1.2, 0.8, -hd + 2.3)
	npc.call("mayor", 0, -hd + 1.5, 0)


static func _tavern(B: Builder, b: Dictionary, R: RandomNumberGenerator, npc: Callable) -> void:
	var hw: float = b.w / 2.0
	var hd: float = b.d / 2.0
	counter(B, -hw + 2.3, -0.8, 5, PI / 2)
	shelf(B, -hw + 0.35, -0.8, PI / 2, 3.2)
	barrel(B, -hw + 0.7, hd - 1.0)
	barrel(B, -hw + 1.4, hd - 0.8)
	barrel(B, -hw + 0.7, -hd + 0.8)
	B.prop("weapons", "mug_full", -hw + 2.3, 1.06, 0.8, 0.0, 0.3, {"collide": false})
	B.prop("dungeon", "keg_decorated", -hw + 0.9, 0.04, 2.2, PI / 2, 0.55)
	B.prop("dungeon", "barrel_small_stack", hw - 1.0, 0.04, hd - 1.2, 0.0, 0.6)
	banner(B, 0, 3.6, -hd + 0.3, 0, "banner_triple_yellow")
	torch(B, hw - 0.3, 2.2, -1, -PI / 2)
	torch(B, hw - 0.3, 2.2, 2.5, -PI / 2)
	fireplace(B, hw - 2.2, -hd + 0.6, 0)
	for tpos in [Vector2(1.2, -1.6), Vector2(3.4, 0.6), Vector2(0.6, 1.8), Vector2(3.6, 2.8)]:
		round_table(B, tpos.x, tpos.y, 0.6)
		for k in 3:
			var a: float = k * 2.1 + tpos.x
			stool(B, tpos.x + sin(a) * 0.95, tpos.y + cos(a) * 0.95)
		B.prop("dungeon", U.pick(R, ["plate_food_A", "plate_food_B"]), tpos.x - 0.1, 0.84, tpos.y, R.randf_range(0, 6), 0.3, {"collide": false})
		B.prop("weapons", "mug_full", tpos.x + 0.3, 0.84, tpos.y + 0.1, R.randf_range(0, 6), 0.25, {"collide": false})
	rug(B, 2.2, 0.4, 3.5, 4.5)
	npc.call("innkeeper", -hw + 1.3, -0.8, PI / 2)
	npc.call("patron", 1.2, -0.6, PI)
	npc.call("patron", 3.4, 1.55, 0.4 + PI)


static func _smithy(B: Builder, b: Dictionary, R: RandomNumberGenerator, npc: Callable) -> void:
	var hw: float = b.w / 2.0
	var hd: float = b.d / 2.0
	var f := B.sub(-hw + 1.4, -hd + 1.4, 0)
	f.box("stone", 0, 0.5, 0, 2.2, 1.0, 2.2, "#8a847a")
	f.box("fire", 0, 1.02, 0, 1.4, 0.06, 1.4, "#ff6a1a", false)
	f.box("fire", 0.2, 1.08, -0.2, 0.5, 0.08, 0.5, "#ffc34a", false)
	f.box("stone", 0, 2.6, -0.3, 1.6, 1.6, 1.4, "#7a746a", false)
	f.box("stone", 0, 3.6, -0.5, 0.8, 1.0, 0.8, "#7a746a", false)
	var a := B.sub(0.3, -0.6, 0.3)
	a.box("wood", 0, 0.3, 0, 0.5, 0.6, 0.5, DARK)
	a.box("metal", 0, 0.7, 0, 0.3, 0.2, 0.3, "#3a3a3a", false)
	a.box("metal", 0, 0.87, 0, 0.35, 0.14, 0.8, "#454545", false)
	a.geo("metal", ["cyl", 0.0, 0.1, 0.3, 4], 0, 0.87, 0.52, 0, "#454545", Vector3.ONE, PI / 2)
	barrel(B, -hw + 0.8, 0.8)
	B.cyl("color", -hw + 0.8, 0.88, 0.8, 0.3, 0.02, "#2a4a5a", false, 10)
	rack(B, hw - 0.4, -0.5, -PI / 2, "sword")
	table(B, hw - 1.2, -hd + 1.0, 1.6, 0.8)
	crate(B, hw - 0.8, hd - 1.2)
	B.prop("village", "Hammer_Double", hw - 1.1, 0.84, -hd + 1.2, 1.2, 0.3, {"collide": false})
	B.prop("dungeon", "box_stacked", hw - 1.0, 0.04, hd - 2.4, 0.0, 0.35)
	torch(B, -hw + 0.3, 2.2, 1.5, PI / 2)
	npc.call("smith", 0.4, 0.4, 0)


static func _store(B: Builder, b: Dictionary, R: RandomNumberGenerator, npc: Callable) -> void:
	var hw: float = b.w / 2.0
	var hd: float = b.d / 2.0
	counter(B, 0, -hd + 2.2, 4.4)
	for x in [-2.3, 0.0, 2.3]:
		shelf(B, x, -hd + 0.35, 0, 2.1)
	barrel(B, -hw + 0.8, 0.6)
	barrel(B, -hw + 0.8, 1.5)
	crate(B, hw - 0.8, 0.8)
	crate(B, hw - 0.8, 1.6, 0.6)
	crate(B, hw - 0.8, 0.8, 0.5, 0.7)
	for k in 3:
		B.prop("village", "Bags", -hw + 1.8, 0.04, 0.2 + k * 0.6, k, 2.2)
	B.prop("halloween", "pumpkin_orange", 1.4, 1.06, -hd + 2.2, 0.0, 0.4, {"collide": false})
	B.prop("village", "Potion1_Filled", -1.2, 1.06, -hd + 2.2, 0.0, 0.25, {"collide": false})
	B.prop("village", "Potion2_Filled", -0.8, 1.06, -hd + 2.2, 0.0, 0.22, {"collide": false})
	B.prop("village", "Package_1", hw - 1.2, 0.04, -0.6, 0.4, 2.2)
	rug(B, 0, 1.2, 2.5, 2.4)
	npc.call("merchant", 0, -hd + 1.3, 0)


static func _herbalist(B: Builder, b: Dictionary, R: RandomNumberGenerator, npc: Callable) -> void:
	var hw: float = b.w / 2.0
	var hd: float = b.d / 2.0
	B.prop("village", "Cauldron", -1.0, 0.04, -0.8, 0.0, 3.2)
	B.cyl("glow", -1.0, 0.62, -0.8, 0.42, 0.04, "#5aff8a", false, 12)
	B.box("fire", -1.0, 0.05, -0.8, 0.6, 0.08, 0.6, "#ff7a2a", false)
	shelf(B, 0.8, -hd + 0.35, 0, 2.2)
	table(B, hw - 0.9, 0.3, 1.4, 0.8, PI / 2)
	for k in 6:
		B.box("color", -hw + 0.8 + k * 0.9, b.h - 0.5, 1.0, 0.12, 0.5, 0.12, U.pick(R, ["#4a7a2a", "#6a8a2a", "#3a5a2a", "#8a6a3a"]), false)
	for k in 3:
		B.prop("village", U.pick(R, ["Potion1_Filled", "Potion2_Filled", "Potion4_Filled"]), hw - 0.9, 0.84, -0.1 + k * 0.35, k, 0.22, {"collide": false})
	rug(B, -0.4, 1, 2.2, 2.2)
	npc.call("herbalist", 0.3, -0.5, 0)


static func _magetower(B: Builder, b: Dictionary, R: RandomNumberGenerator, npc: Callable, W: World) -> void:
	var hw: float = b.w / 2.0
	var hd: float = b.d / 2.0
	bookshelf(B, -hw + 0.35, -0.5, PI / 2, 2.8)
	bookshelf(B, hw - 0.35, -0.5, -PI / 2, 2.8)
	bookshelf(B, 0, -hd + 0.35, 0, 2.6)
	B.cyl("stone", 1.6, 0.45, -1.6, 0.35, 0.9, "#8a8aa0", true, 8)
	var crystal := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	sm.radial_segments = 4
	sm.rings = 2
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color("#b98aff")
	cm.emission_enabled = true
	cm.emission = Color("#7a3aff")
	cm.emission_energy_multiplier = 3.0
	sm.material = cm
	crystal.mesh = sm
	var cp := B.P(1.6, -1.6, 1.4)
	crystal.position = cp
	W.add_child(crystal)
	W.animated.append(func(dt: float, t: float) -> void:
		crystal.rotation.y += dt
		crystal.position.y = cp.y + sin(t * 2.0) * 0.08)
	table(B, -0.8, 0.8, 1.4, 0.8)
	B.prop("weapons", "spellbook_open", -0.9, 0.84, 0.8, 0.3, 0.35, {"collide": false})
	B.prop("village", "Scroll", -0.4, 0.84, 0.6, 1.0, 0.3, {"collide": false})
	candle(B, -0.3, 0.8, 0.8)
	B.geo("color", ["cyl", 1.6, 1.6, 0.02, 24], 0, 0.07, 0.4, 0, "#2a2a6a")
	for s in [-1.0, 1.0]:
		B.box("wood", -hw + 1.2 + s * 0.3, b.h / 2, -hd + 0.45, 0.08, b.h, 0.08, DARK, false)
	var y := 0.4
	while y < b.h - 0.2:
		B.box("wood", -hw + 1.2, y, -hd + 0.45, 0.6, 0.05, 0.05, MID, false)
		y += 0.4
	npc.call("mage", -0.2, -1.2, 0)


static func _hunter(B: Builder, b: Dictionary, R: RandomNumberGenerator, npc: Callable) -> void:
	var hw: float = b.w / 2.0
	var hd: float = b.d / 2.0
	rack(B, -hw + 0.4, -0.4, PI / 2, "bow")
	table(B, 0.8, -0.6, 1.4, 0.8)
	bed(B, hw - 0.9, -hd + 1.4, 0)
	rug(B, -0.3, 0.8, 2.4, 1.8)
	B.prop("dungeon", "trunk_large_A", 0.8, 0.04, hd - 1.0, 0.0, 0.7)
	B.prop("weapons", "quiver", 1.2, 0.84, -0.6, 0.4, 0.5, {"collide": false})
	barrel(B, -hw + 0.8, hd - 1.0)
	npc.call("hunter", 0.8, -1.4, 0)
	B.prop("village", "Target", -(hw + 2.5), -0.04, 1.5, 0.0, 2.6)
	B.prop("village", "TargetWithArrows", hw + 2.5, -0.04, 1.5, 0.0, 2.6)
	B.prop("village", "Dummy", hw + 2.5, -0.04, 4.5, 0.0, 1.6)


static func _chapel(B: Builder, b: Dictionary, R: RandomNumberGenerator, npc: Callable) -> void:
	var hd: float = b.d / 2.0
	var z := -hd + 4.0
	while z < hd - 1.5:
		for s in [-1.0, 1.0]:
			pew(B, s * 1.9, z, 2.4)
		z += 1.5
	B.box("stone", 0, 0.5, -hd + 1.6, 2.0, 1.0, 0.9, "#e8e4dc")
	B.box("color", 0, 1.02, -hd + 1.6, 2.1, 0.03, 1.0, "#e8e0f0", false)
	B.box("color", 0, 0.7, -hd + 2.06, 0.6, 0.6, 0.02, "#c8a040", false)
	for x in [-0.8, -0.4, 0.4, 0.8]:
		candle(B, x, 1.03, -hd + 1.5)
	for s in [-1.0, 1.0]:
		B.prop("halloween", "candle_triple", s * 1.6, 0.04, -hd + 1.4, 0.0, 0.8, {"collide": false})
		banner(B, s * 2.4, 4.2, -hd + 0.3, 0, "banner_patternC_white")
	var cols := ["#ff5a5a", "#5a8aff", "#ffd84a", "#5aff8a"]
	for i in 4:
		B.box("glow", -0.6 + (i % 2) * 1.2, 2.6 + (i / 2) * 1.0, -hd + 0.14, 1.1, 0.9, 0.04, cols[i], false)
	B.box("beam", 0, 3.1, -hd + 0.13, 0.08, 2.0, 0.06, DARK, false)
	B.box("beam", 0, 3.1, -hd + 0.13, 2.4, 0.08, 0.06, DARK, false)
	rug(B, 0, 0.5, 1.4, b.d - 3.5)
	npc.call("priest", 0, -hd + 0.8, 0)


static func _house(B: Builder, b: Dictionary, R: RandomNumberGenerator) -> void:
	var hw: float = b.w / 2.0
	var hd: float = b.d / 2.0
	bed(B, -hw + 0.9, -hd + 1.4, 0)
	table(B, 1.0, 0.3, 1.2, 0.8)
	chair(B, 1.0, -0.5, 0)
	chair(B, 1.0, 1.1, PI)
	fireplace(B, hw - 1.4, -hd + 0.6, 0)
	crate(B, -hw + 0.6, hd - 1.2, 0.6)
	B.prop("dungeon", "trunk_medium_B", -hw + 0.8, 0.04, -hd + 2.8, PI / 2, 0.8)
	B.prop("dungeon", U.pick(R, ["plate_food_A", "plate_food_B"]), 1.0, 0.84, 0.3, 0.0, 0.35, {"collide": false})
	rug(B, 0, 0.5, 2, 1.6)


static func _farmhouse(B: Builder, b: Dictionary, R: RandomNumberGenerator, W: World) -> void:
	var hw: float = b.w / 2.0
	var hd: float = b.d / 2.0
	bed(B, -hw + 0.9, -hd + 1.4, 0)
	var bp := B.P(-hw + 0.9, -hd + 1.4)
	W.interactables.append({"type": "bed", "pos": Vector3(bp.x, b.floorY + 0.6, bp.z), "r": 1.8, "label": "Sleep & Save"})
	table(B, 0.8, 0.0, 1.4, 0.8)
	chair(B, 0.8, -0.8, 0)
	chair(B, 0.8, 0.8, PI)
	B.prop("dungeon", "plate_food_A", 0.8, 0.84, 0, 0.0, 0.35, {"collide": false})
	B.prop("weapons", "mug_full", 0.4, 0.84, 0.25, 0.0, 0.25, {"collide": false})
	B.prop("dungeon", "trunk_large_A", -hw + 0.9, 0.04, -hd + 3.2, PI / 2, 0.6)
	fireplace(B, hw - 1.4, -hd + 0.6, 0)
	shelf(B, -1.0, -hd + 0.35, 0, 1.4)
	crate(B, -hw + 0.6, hd - 1.2, 0.6)
	barrel(B, -hw + 0.6, hd - 2.2)
	rug(B, -0.6, 0.8, 2.2, 1.8)
	var sp := B.P(0, hd + 4.5)
	W.spawn_point = {"pos": Vector3(sp.x, b.floorY, sp.z), "yaw": b.ang}
	var bed_p := B.P(-hw + 2.0, -hd + 1.4)
	W.bed_point = {"pos": Vector3(bed_p.x, b.floorY + 0.1, bed_p.z), "yaw": b.ang}
	W.map_labels.append({"x": b.x, "z": b.z, "text": "Home"})


# ================================================================ farm field
static func _farm_field(W: World, R: RandomNumberGenerator) -> void:
	var f: Dictionary = W.farm
	var batch := MeshBatch.new()
	var ang: float = f.rot * PI / 2.0
	var B := Builder.at(W, batch, f.fx, W.plaza_y, f.fz, ang)
	var fw := 10.0
	var fd := 8.5
	for s in [-1.0, 1.0]:
		var x := -fw / 2.0
		while x <= fw / 2.0 + 0.01:
			B.box("wood", x, 0.45, s * fd / 2, 0.12, 0.9, 0.12, DARK, false)
			x += 1.25
		B.box("wood", 0, 0.65, s * fd / 2, fw, 0.08, 0.06, MID, false)
		B.box("wood", 0, 0.35, s * fd / 2, fw, 0.08, 0.06, MID, false)
		B.col_box(0, s * fd / 2, fw, 0.2, 0, 0.9)
	for s in [-1.0, 1.0]:
		var z := -fd / 2.0
		while z <= fd / 2.0 + 0.01:
			if not (s < 0 and absf(z) < 1.2):
				B.box("wood", s * fw / 2, 0.45, z, 0.12, 0.9, 0.12, DARK, false)
			z += 1.2
		if s > 0:
			B.box("wood", s * fw / 2, 0.65, 0, 0.06, 0.08, fd, MID, false)
			B.box("wood", s * fw / 2, 0.35, 0, 0.06, 0.08, fd, MID, false)
			B.col_box(s * fw / 2, 0, 0.2, fd, 0, 0.9)
		else:
			var L := fd / 2.0 - 1.2
			for zz in [-1.0, 1.0]:
				B.box("wood", s * fw / 2, 0.65, zz * (1.2 + L / 2), 0.06, 0.08, L, MID, false)
				B.box("wood", s * fw / 2, 0.35, zz * (1.2 + L / 2), 0.06, 0.08, L, MID, false)
				B.col_box(s * fw / 2, zz * (1.2 + L / 2), 0.2, L, 0, 0.9)
	W.plots = []
	var cols := 5
	var rows := 4
	var sp := 1.65
	var id := 0
	for i in cols:
		for j in rows:
			var p := B.P((i - (cols - 1) / 2.0) * sp + 0.3, (j - (rows - 1) / 2.0) * sp)
			W.plots.append({"id": id, "pos": Vector3(p.x, W.plaza_y, p.z), "state": "grass", "crop": "", "t": 0.0})
			id += 1
	var sc := B.sub(fw / 2 - 1, -fd / 2 + 1, -0.6)
	sc.box("wood", 0, 1.0, 0, 0.1, 2.0, 0.1, DARK)
	sc.box("wood", 0, 1.5, 0, 1.4, 0.08, 0.08, DARK, false)
	sc.box("color", 0, 1.35, 0, 0.45, 0.6, 0.25, "#8a3a2a", false)
	sc.geo("color", ["sphere", 0.2, 0, 0, 8], 0, 1.85, 0, 0, "#d8c090")
	sc.geo("color", ["cyl", 0.0, 0.35, 0.3, 10], 0, 2.1, 0, 0, "#d8b860")
	var hB := Builder.at(W, batch, f.x, W.plaza_y, f.z, ang)
	for hp in [Vector2(-7.5, 1.5), Vector2(-7.5, -1.2), Vector2(-8.8, 0.2)]:
		hB.prop("village", "Hay", hp.x, 0, hp.y, hp.x + hp.y, 7.5)
	hB.prop("village", "Cart", -9.5, 0, -4, 0.6, 2.3)
	hB.prop("dungeon", "barrel_small", -6, 0, 3.6, 0.0, 1.0)
	hB.box("wood", -7.5, 0.3, 4.5, 2.2, 0.6, 1.0, "#8a6038")
	hB.box("color", -7.5, 0.58, 4.5, 2.0, 0.04, 0.8, "#3a6a8a", false)
	_add(W, batch.build(W.mats), "Farm")
	W.map_labels.append({"x": f.fx, "z": f.fz, "text": "Field"})
	var fp := B.P(-fw / 2 - 1.2, 2.2)
	W.npc_spots.append({"role": "farmer", "x": fp.x, "z": fp.z, "y": W.plaza_y, "yaw": ang - PI / 2})


# ================================================================ plaza
static func _plaza(W: World, R: RandomNumberGenerator) -> void:
	var batch := MeshBatch.new()
	var y := W.plaza_y
	var B := Builder.at(W, batch, 0, y, 0, 0)
	B.geo("cobble", ["cyl", 12.5, 12.5, 0.1, 48], 0, 0.02, 0, 0, "#d8d0c4")
	B.prop("village", "Well", 0, 0.05, 0, 0.0, 2.6, {"collide": false})
	W.add_cylinder_collider(Vector3(0, y + 1.0, 0), 1.3, 3.0)
	W.interactables.append({"type": "well", "pos": Vector3(0, y + 1, 0), "r": 2.3, "label": "Drink from well"})
	W.map_labels.append({"x": 0.0, "z": -3.0, "text": "Plaza"})
	var ga: float = W.gates[0] + PI / 2.0 * 0.7
	var bp := U.polar(ga, 8.5)
	var qb := B.sub(bp.x, bp.y, ga + PI)
	qb.box("wood", 0, 1.3, 0, 2.0, 1.3, 0.12, MID)
	for s in [-1.0, 1.0]:
		qb.box("wood", s * 0.95, 1.0, 0, 0.14, 2.0, 0.14, DARK, false)
	qb.geo("shingle", ["cyl", 0.0, 1.5, 0.5, 4], 0, 2.25, 0, PI / 4, "#ffffff", Vector3(1, 1, 0.35))
	for k in 5:
		qb.box("color", -0.7 + k * 0.35 + R.randf_range(-0.05, 0.05), 1.3 + R.randf_range(-0.3, 0.3), 0.07, 0.25, 0.32, 0.01, "#f4ecd0", false)
	W.interactables.append({"type": "board", "pos": Vector3(bp.x, y + 1.3, bp.y), "r": 2.4, "label": "Quest Board"})
	for i in 3:
		var a: float = W.gates[i] + PI / 3.0 + R.randf_range(-0.25, 0.25)
		var p := U.polar(a, 10.5)
		B.prop("village", "MarketStand_1" if i % 2 else "MarketStand_2", p.x, 0.05, p.y, a + PI, 2.3)
	for i in 3:
		var a: float = W.gates[i] - PI / 3.0 + R.randf_range(-0.2, 0.2)
		var p := U.polar(a, 5.5)
		B.prop("village", "Bench_1", p.x, 0.05, p.y, a, 2.6)
	_add(W, batch.build(W.mats, false), "Plaza")


# ================================================================ fence & gates
static func _near_gate(W: World, a: float) -> bool:
	for g in W.gates:
		if absf(U.angle_diff(a, g)) < 3.2 / W.fence_r:
			return true
	return false


static func _fence(W: World, R: RandomNumberGenerator) -> void:
	var batch := MeshBatch.new()
	var FR := W.fence_r
	var B := Builder.at(W, batch, 0, 0, 0, 0)
	var step := 2.4 / FR
	var a := 0.0
	while a < TAU:
		var a2 := a + step
		var p := U.polar(a, FR)
		var q := U.polar(a2, FR)
		if not _near_gate(W, a):
			var y := W.height_at(p.x, p.y)
			B.box("wood", p.x, y + 0.7, p.y, 0.2, 1.5, 0.2, DARK, false, a)
			B.geo("wood", ["cyl", 0.0, 0.14, 0.25, 4], p.x, y + 1.55, p.y, a, DARK)
			if not _near_gate(W, a2):
				var yq := W.height_at(q.x, q.y)
				var m := (p + q) / 2.0
				var length := p.distance_to(q)
				var ry := atan2(q.x - p.x, q.y - p.y)
				var tilt := atan2(yq - y, length)
				for hh in [0.45, 1.05]:
					batch.add_box("wood", U.xf(Vector3(m.x, (y + yq) / 2 + hh, m.y), ry, Vector3(0.08, 0.14, length + 0.1), -tilt), MID)
				W.add_box_collider(U.xf(Vector3(m.x, (y + yq) / 2 + 0.8, m.y), ry), Vector3(0.3, 1.8, length))
		a = a2
	var names := ["Goblin Hills", "Old Graveyard", "Collapsed Mine"]
	for i in W.gates.size():
		var g: float = W.gates[i]
		var p := U.polar(g, FR)
		var y := W.height_at(p.x, p.y)
		var G := B.sub(p.x, p.y, g, y)
		for s in [-1.0, 1.0]:
			G.prop("village", "Watchtower", s * 4.0, -0.2, 0, 0.0, 2.3)
		G.box("log", 0, 3.9, 0, 5.2, 0.35, 0.35, "#ffffff", false)
		_sign(W, "→ " + names[i], G.P(0, 0.2, 3.2), g + PI, 2.6)
		_sign(W, "Hollowmere", G.P(0, -0.2, 3.2), g, 2.6)
		if i == 0:
			var gp := G.P(2.2, -1.5)
			W.npc_spots.append({"role": "guard", "x": gp.x, "z": gp.z, "y": y, "yaw": g + PI})
		for s in [-1.0, 1.0]:
			G.box("fire", s * 2.4, 3.3, -0.25, 0.12, 0.2, 0.12, "#ffb04a", false)
	_add(W, batch.build(W.mats), "Fence")


# ================================================================ street props
static func _street_props(W: World, R: RandomNumberGenerator) -> void:
	var batch := MeshBatch.new()
	var B := Builder.at(W, batch, 0, 0, 0, 0)
	for r in W.roads:
		if not r.main:
			continue
		var a: Vector2 = r.pts[0]
		var b: Vector2 = r.pts[1]
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var side := 1.0
		var t := 6.0
		while t < L - 3.0:
			var p := a + dir * t + Vector2(-dir.y, dir.x) * 2.4 * side
			var y := W.height_at(p.x, p.y)
			B.cyl("color", p.x, y + 1.4, p.y, 0.08, 2.8, "#2a2a2a", true, 6)
			B.box("color", p.x, y + 2.85, p.y, 0.32, 0.08, 0.32, "#2a2a2a", false)
			B.box("window", p.x, y + 2.6, p.y, 0.24, 0.4, 0.24, null, false)
			side = -side
			t += 11.0
	for bd in W.buildings:
		var S := Builder.at(W, batch, bd.x, W.plaza_y, bd.z, bd.rot * PI / 2.0)
		for k in R.randi_range(1, 3):
			var side := -1.0 if R.randf() < 0.5 else 1.0
			var x: float = side * (bd.w / 2.0 + 0.7)
			var z := R.randf_range(-bd.d / 2.0 + 0.8, bd.d / 2.0 - 0.5)
			match R.randi_range(0, 3):
				0:
					barrel(S, x, z, 0.38)
				1:
					S.prop("dungeon", U.pick(R, ["crates_stacked", "box_large", "box_small"]), x, 0, z, R.randi_range(0, 3) * PI / 2, 0.55)
				2:
					for i in 3:
						for j in 3 - i:
							S.geo("log", ["cyl", 0.14, 0.14, 1.4, 7], x, 0.15 + i * 0.26, z - 0.3 + j * 0.3 + i * 0.15, 0, "#ffffff", Vector3.ONE, 0.0, PI / 2)
					S.col_box(x, z, 1.4, 1.0, 0, 0.8)
				_:
					S.box("wood", x, 0.2, z, 0.5, 0.4, 1.4, MID)
					for i in 5:
						S.geo("color", ["sphere", 0.1, 0, 0, 5], x + R.randf_range(-0.12, 0.12), 0.48, z - 0.55 + i * 0.27, 0, U.pick(R, ["#ff5a7a", "#ffd84a", "#ffffff", "#b58aff"]))
	var cp := U.polar(W.gates[1] + PI / 3.0 + 0.35, 14.5)
	B.sub(cp.x, cp.y, 0, W.plaza_y).prop("village", "Cart", 0, 0, 0, R.randf_range(0, 6), 2.3)
	_add(W, batch.build(W.mats), "StreetProps")


# ================================================================ NPC walking graph
static func _waypoints(W: World) -> void:
	var wp: Array = []
	for i in 8:
		wp.append({"p": U.polar(i / 8.0 * TAU, 7.5), "n": [(i + 1) % 8, (i + 7) % 8]})
	var nearest_ring := func(p: Vector2) -> int:
		var best := 0
		var bd := 1e9
		for i in 8:
			var d: float = wp[i].p.distance_to(p)
			if d < bd:
				bd = d
				best = i
		return best
	var link := func(a: int, b: int) -> void:
		wp[a].n.append(b)
		wp[b].n.append(a)
	for b in W.buildings:
		var da := atan2(b.door_front.x, b.door_front.y)
		var e := U.polar(da, 12.5)
		wp.append({"p": e, "n": []})
		var ie := wp.size() - 1
		link.call(ie, nearest_ring.call(e))
		wp.append({"p": b.door_front, "n": []})
		link.call(ie, wp.size() - 1)
	for g in W.gates:
		var prev: int = nearest_ring.call(U.polar(g, 7.5))
		for r in [16.0, 30.0, 44.0, 55.0]:
			wp.append({"p": U.polar(g, r), "n": []})
			link.call(prev, wp.size() - 1)
			prev = wp.size() - 1
	W.waypoints = wp
