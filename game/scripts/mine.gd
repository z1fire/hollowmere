class_name Mine
extends RefCounted
## The old silver mine: a cave level carved procedurally beneath the mine entrance -
## caverns joined by tunnels, timber supports, rails, torches, silver veins, chests,
## cave spiders, restless miners and the Hollow Foreman.
##
## The cave is a 2D signed field on a 1 m grid (S > 0 = open). Floor and ceiling are
## height-fields over the open cells; walls are marching-squares contours of S extruded
## upwards and roughened with 3D noise.

const Y := -70.0        # floor height of the entrance cavern
const HALF := 48.0      # the level spans its centre +- HALF metres (x and z)
const G := 97           # field grid points per side (1 m spacing)
const ROWS := 4         # vertical subdivisions of the cave walls
const WALL_AO := [0.45, 0.8, 1.0, 0.85, 0.55]

const AREA_NAMES := {"entry": "Mine Entrance", "workings": "Old Workings", "spider": "Spider Nest", "ore": "Silver Vein", "camp": "Miners' Camp", "cache": "Prospector's Cache", "boss": "Foreman's Hall", "cavein": "Cave-in"}

# marching squares: corner bits a=1 b=2 c=4 d=8 -> edge pairs (e0 bottom, e1 right, e2 top, e3 left)
const CASES := {1: [[3, 0]], 2: [[0, 1]], 3: [[3, 1]], 4: [[1, 2]], 6: [[0, 2]], 7: [[3, 2]], 8: [[2, 3]], 9: [[0, 2]], 11: [[1, 2]], 12: [[3, 1]], 13: [[0, 1]], 14: [[3, 0]]}

static var _web_tex: ImageTexture


class Acc extends RefCounted:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()  # collision triangles

	func vert(p: Vector3, col: Color) -> int:
		v.append(p)
		n.append(Vector3.ZERO)
		c.append(col)
		return v.size() - 1

	## Front faces are clockwise in Godot: order the triangle so it faces `want`.
	func tri(a: int, b: int, d: int, want: Vector3, collide: bool) -> void:
		var fn := (v[b] - v[a]).cross(v[d] - v[a])
		if fn.dot(want) > 0.0:
			var t := b
			b = d
			d = t
			fn = -fn
		idx.append_array([a, b, d])
		n[a] -= fn
		n[b] -= fn
		n[d] -= fn
		if collide:
			faces.append_array([v[a], v[b], v[d]])


# ================================================================ build
static func build(W: World) -> void:
	var R := U.make_rng(W.seed_value + 61)
	var am := atan2(W.pois.mine.x, W.pois.mine.y)
	var C := U.polar(am, 112.0)
	var fwd := Vector2(sin(am), cos(am))  # towards the surface entrance
	var root := Node3D.new()
	root.name = "Mine"
	root.visible = false
	W.add_child(root)
	var M := {"root": root, "x0": C.x - HALF, "z0": C.y - HALF, "size": HALF * 2.0, "rooms": [], "tunnels": [], "labels": [],
		"torches": [], "lights": [], "icons": [], "wallpts": [], "lit": [], "light_t": 0.0, "reveal_t": 0.0, "reveal_new": []}
	W.mine = M
	var nf := FastNoiseLite.new()
	nf.seed = W.seed_value + 62
	nf.frequency = 0.5
	var nc := FastNoiseLite.new()
	nc.seed = W.seed_value + 63
	nc.frequency = 0.22
	var n3 := FastNoiseLite.new()
	n3.seed = W.seed_value + 64
	n3.frequency = 0.38
	M.nf = nf
	M.nc = nc
	M.n3 = n3
	_plan(M, R, C, fwd)
	_field(M, W.seed_value)
	_cave_mesh(M)
	_dress(W, M, R)
	var cells := (G - 1) * (G - 1)
	var rev := PackedByteArray()
	rev.resize(cells)
	M.revealed = rev


# ---------------------------------------------------------------- layout
static func _plan(M: Dictionary, R: RandomNumberGenerator, C: Vector2, fwd: Vector2) -> void:
	var rooms: Array = M.rooms
	var fits := func(p: Vector2, r: float) -> bool:
		var lim := HALF - r * 1.3 - 3.5
		if absf(p.x - C.x) > lim or absf(p.y - C.y) > lim:
			return false
		for o in rooms:
			if p.distance_to(o.c) < r + o.r + 4.0:
				return false
		return true
	rooms.append({"c": C + fwd * 33.0, "r": 5.5, "y": 0.0, "type": "entry"})
	# the main path winds away from the entrance and down, ending in the Foreman's hall
	for type in ["workings", "spider", "ore", "workings", "boss"]:
		var prev: Dictionary = rooms[rooms.size() - 1]
		var r := 9.5 if type == "boss" else R.randf_range(5.0, 7.0)
		var best = null
		var best_score := -1e9
		for k in 120:
			var a := R.randf_range(0, TAU)
			var p: Vector2 = prev.c + Vector2(sin(a), cos(a)) * (prev.r + r + R.randf_range(7.0, 12.0))
			if not fits.call(p, r):
				continue
			var score := -(p - C).dot(fwd) + R.randf() * 8.0
			if score > best_score:
				best_score = score
				best = p
		if best == null:
			if type != "boss":
				continue
			# no room left for the hall: turn the last cavern into it
			prev.type = "boss"
			break
		rooms.append({"c": best, "r": r, "y": prev.y - R.randf_range(0.8, 1.5), "type": type})
		_tunnel(M, R, rooms.size() - 2, rooms.size() - 1, 1.7, true)
	var main_count := rooms.size()
	var boss_i := main_count - 1
	# side caverns branch off the main path
	for type in U.shuffle(R, ["cache", "camp", "spider", "ore"]):
		for k in 120:
			var pi := R.randi_range(1, maxi(1, main_count - 2))
			var par: Dictionary = rooms[pi]
			var r := R.randf_range(4.5, 6.0)
			var a := R.randf_range(0, TAU)
			var p: Vector2 = par.c + Vector2(sin(a), cos(a)) * (par.r + r + R.randf_range(6.0, 10.0))
			if fits.call(p, r):
				rooms.append({"c": p, "r": r, "y": par.y + R.randf_range(-0.6, 0.3), "type": type})
				_tunnel(M, R, pi, rooms.size() - 1, 1.35, false)
				break
	# a dead-end tunnel past the hall, blocked by a fresh cave-in (the way deeper, for a future update)
	var boss: Dictionary = rooms[boss_i]
	for k in 60:
		var a := R.randf_range(0, TAU)
		var p: Vector2 = boss.c + Vector2(sin(a), cos(a)) * (boss.r + 9.0)
		if fits.call(p, 2.2):
			rooms.append({"c": p, "r": 2.2, "y": boss.y - 0.6, "type": "cavein"})
			_tunnel(M, R, boss_i, rooms.size() - 1, 1.4, false)
			break


static func _tunnel(M: Dictionary, R: RandomNumberGenerator, ia: int, ib: int, hw: float, main: bool) -> void:
	var a: Dictionary = M.rooms[ia]
	var b: Dictionary = M.rooms[ib]
	var ab: Vector2 = b.c - a.c
	var mid: Vector2 = a.c + ab * 0.5 + Vector2(ab.y, -ab.x).normalized() * R.randf_range(-3.5, 3.5)
	M.tunnels.append({"a": ia, "b": ib, "hw": hw, "main": main, "pts": [a.c, mid, b.c], "lv": [a.y, (a.y + b.y) / 2.0, b.y]})


# ---------------------------------------------------------------- field
static func _field(M: Dictionary, seed_value: int) -> void:
	var n1 := FastNoiseLite.new()
	n1.seed = seed_value + 65
	n1.frequency = 1.0
	var n2 := FastNoiseLite.new()
	n2.seed = seed_value + 66
	n2.frequency = 0.2
	n2.fractal_type = FastNoiseLite.FRACTAL_FBM
	n2.fractal_octaves = 3
	var N := G * G
	var best := PackedFloat32Array()
	var ws := PackedFloat32Array()
	var ls := PackedFloat32Array()
	var hs := PackedFloat32Array()
	best.resize(N)
	best.fill(-1e9)
	ws.resize(N)
	ls.resize(N)
	hs.resize(N)
	var x0: float = M.x0
	var z0: float = M.z0
	# each feature only touches the grid cells around it
	var feats: Array = []
	for ri in M.rooms.size():
		var rm: Dictionary = M.rooms[ri]
		feats.append({"room": rm, "ri": ri, "lo": rm.c - Vector2.ONE * (rm.r * 1.3 + 3.5), "hi": rm.c + Vector2.ONE * (rm.r * 1.3 + 3.5)})
	for t in M.tunnels:
		for k in 2:
			var a: Vector2 = t.pts[k]
			var b: Vector2 = t.pts[k + 1]
			var pad: float = t.hw * 1.4 + 3.5
			feats.append({"a": a, "b": b, "ya": t.lv[k], "yb": t.lv[k + 1], "hw": t.hw, "lo": Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * pad, "hi": Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * pad})
	for f in feats:
		var i0 := clampi(floori(f.lo.x - x0), 0, G - 1)
		var i1 := clampi(ceili(f.hi.x - x0), 0, G - 1)
		var j0 := clampi(floori(f.lo.y - z0), 0, G - 1)
		var j1 := clampi(ceili(f.hi.y - z0), 0, G - 1)
		var is_room: bool = f.has("room")
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := Vector2(x0 + i, z0 + j)
				var s := 0.0
				var lv := 0.0
				var ht := 0.0
				if is_room:
					var rm: Dictionary = f.room
					var a := atan2(p.y - rm.c.y, p.x - rm.c.x)
					var rr: float = rm.r * (1.0 + 0.26 * n1.get_noise_2d(cos(a) * 1.4 + f.ri * 9.1, sin(a) * 1.4))
					s = rr - p.distance_to(rm.c)
					lv = rm.y
					ht = 4.2 + rm.r * 0.3
				else:
					var ab: Vector2 = f.b - f.a
					var t := clampf((p - f.a).dot(ab) / ab.length_squared(), 0.0, 1.0)
					s = f.hw * (1.0 + 0.3 * n2.get_noise_2d(p.x * 1.6, p.y * 1.6)) - p.distance_to(f.a + ab * t)
					lv = lerpf(f.ya, f.yb, t)
					ht = 3.4
				var k := j * G + i
				if s > best[k]:
					best[k] = s
				var w := maxf(0.0, s + 3.0)
				w *= w
				ws[k] += w
				ls[k] += w * lv
				hs[k] += w * ht
	var S := PackedFloat32Array()
	var LV := PackedFloat32Array()
	var HT := PackedFloat32Array()
	S.resize(N)
	LV.resize(N)
	HT.resize(N)
	for j in G:
		for i in G:
			var k := j * G + i
			var s := best[k] + n2.get_noise_2d(x0 + i, z0 + j) * 0.6
			if i == 0 or j == 0 or i == G - 1 or j == G - 1:
				s = minf(s, -1.0)  # always closed at the grid border
			S[k] = s
			LV[k] = ls[k] / ws[k] if ws[k] > 0.0 else 0.0
			HT[k] = hs[k] / ws[k] if ws[k] > 0.0 else 4.0
	M.S = S
	M.LV = LV
	M.HT = HT


static func _bilin(M: Dictionary, arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf(x - M.x0, 0.0, G - 1.001)
	var fz := clampf(z - M.z0, 0.0, G - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * G + i
	return lerpf(lerpf(arr[k], arr[k + 1], tx), lerpf(arr[k + G], arr[k + G + 1], tx), tz)


## how far inside open cave a point is (metres, negative inside rock)
static func open_at(M: Dictionary, x: float, z: float) -> float:
	return _bilin(M, M.S, x, z)


static func floor_y(M: Dictionary, x: float, z: float) -> float:
	return Y + _bilin(M, M.LV, x, z) + (M.nf as FastNoiseLite).get_noise_2d(x, z) * 0.08


static func ceil_y(M: Dictionary, x: float, z: float) -> float:
	return Y + _bilin(M, M.LV, x, z) + _bilin(M, M.HT, x, z) + (M.nc as FastNoiseLite).get_noise_2d(x, z) * 0.45


static func contains(M: Dictionary, p: Vector3) -> bool:
	return p.y < Y + 20.0 and p.x > M.x0 and p.z > M.z0 and p.x < M.x0 + M.size and p.z < M.z0 + M.size


# ---------------------------------------------------------------- cave mesh
static func _cave_mesh(M: Dictionary) -> void:
	var S: PackedFloat32Array = M.S
	var x0: float = M.x0
	var z0: float = M.z0
	var acc := Acc.new()
	# floor and ceiling height-fields
	var fidx := PackedInt32Array()
	var cidx := PackedInt32Array()
	fidx.resize(G * G)
	cidx.resize(G * G)
	fidx.fill(-1)
	cidx.fill(-1)
	for j in G:
		for i in G:
			var k := j * G + i
			if S[k] > -2.4:
				var x := x0 + i
				var z := z0 + j
				var near := U.smoothstep(-0.6, 2.2, S[k])
				fidx[k] = acc.vert(Vector3(x, floor_y(M, x, z), z), Color.WHITE * (0.5 + 0.5 * near))
				cidx[k] = acc.vert(Vector3(x, ceil_y(M, x, z), z), Color.WHITE * (0.42 + 0.2 * near))
	for j in G - 1:
		for i in G - 1:
			var k := j * G + i
			var q := [k, k + 1, k + G + 1, k + G]
			if fidx[q[0]] < 0 or fidx[q[1]] < 0 or fidx[q[2]] < 0 or fidx[q[3]] < 0:
				continue
			acc.tri(fidx[q[0]], fidx[q[1]], fidx[q[2]], Vector3.UP, true)
			acc.tri(fidx[q[0]], fidx[q[2]], fidx[q[3]], Vector3.UP, true)
			acc.tri(cidx[q[0]], cidx[q[1]], cidx[q[2]], Vector3.DOWN, false)
			acc.tri(cidx[q[0]], cidx[q[2]], cidx[q[3]], Vector3.DOWN, false)
	# walls along the S = 0 contour
	var edge_cache := {}
	for j in G - 1:
		for i in G - 1:
			var k := j * G + i
			var sa := S[k]
			var sb := S[k + 1]
			var sc := S[k + G + 1]
			var sd := S[k + G]
			var code := (1 if sa > 0.0 else 0) | (2 if sb > 0.0 else 0) | (4 if sc > 0.0 else 0) | (8 if sd > 0.0 else 0)
			if code == 0 or code == 15:
				continue
			var pairs: Array
			if code == 5 or code == 10:
				var centre_open := (sa + sb + sc + sd) > 0.0
				pairs = [[0, 1], [2, 3]] if centre_open == (code == 5) else [[3, 0], [1, 2]]
			else:
				pairs = CASES[code]
			for pr in pairs:
				var A: Array = _edge_vertex(acc, M, edge_cache, i, j, pr[0])
				var B: Array = _edge_vertex(acc, M, edge_cache, i, j, pr[1])
				var want: Vector3 = (A[1] + B[1]).normalized()
				var a0: int = A[0]
				var b0: int = B[0]
				for r in ROWS:
					acc.tri(a0 + r, b0 + r, b0 + r + 1, want, true)
					acc.tri(a0 + r, b0 + r + 1, a0 + r + 1, want, true)
	for i in acc.n.size():
		acc.n[i] = acc.n[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = acc.v
	arrays[Mesh.ARRAY_NORMAL] = acc.n
	arrays[Mesh.ARRAY_COLOR] = acc.c
	arrays[Mesh.ARRAY_INDEX] = acc.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _rock_material())
	var mi := MeshInstance3D.new()
	mi.name = "Cave"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(M.root as Node3D).add_child(mi)
	var body := StaticBody3D.new()
	body.name = "CaveBody"
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(acc.faces)
	cs.shape = shape
	body.add_child(cs)
	(M.root as Node3D).add_child(body)


## One wall column (ROWS+1 vertices) where the contour crosses a grid edge; shared by neighbouring cells.
## Returns [first vertex index, normal pointing into the open cave].
static func _edge_vertex(acc: Acc, M: Dictionary, cache: Dictionary, i: int, j: int, e: int) -> Array:
	var p0: Vector2i
	var p1: Vector2i
	var id: int
	match e:
		0:
			p0 = Vector2i(i, j)
			p1 = Vector2i(i + 1, j)
			id = (j * G + i) * 2
		1:
			p0 = Vector2i(i + 1, j)
			p1 = Vector2i(i + 1, j + 1)
			id = (j * G + i + 1) * 2 + 1
		2:
			p0 = Vector2i(i, j + 1)
			p1 = Vector2i(i + 1, j + 1)
			id = ((j + 1) * G + i) * 2
		_:
			p0 = Vector2i(i, j)
			p1 = Vector2i(i, j + 1)
			id = (j * G + i) * 2 + 1
	if cache.has(id):
		return cache[id]
	var S: PackedFloat32Array = M.S
	var s0 := S[p0.y * G + p0.x]
	var s1 := S[p1.y * G + p1.x]
	var t := clampf(s0 / (s0 - s1), 0.0, 1.0)
	var g := _grad(S, p0).lerp(_grad(S, p1), t)
	var n := g.normalized() if g.length() > 0.0001 else Vector2(1, 0)
	var x: float = M.x0 + lerpf(p0.x, p1.x, t)
	var z: float = M.z0 + lerpf(p0.y, p1.y, t)
	var fy := floor_y(M, x, z) - 0.8
	var cy := ceil_y(M, x, z) + 1.0
	var n3: FastNoiseLite = M.n3
	var first := -1
	for r in ROWS + 1:
		var y := lerpf(fy, cy, float(r) / ROWS)
		var d := n3.get_noise_3d(x, y, z) * 0.85
		var vi := acc.vert(Vector3(x - n.x * d, y, z - n.y * d), Color.WHITE * WALL_AO[r])
		if r == 0:
			first = vi
	var res := [first, Vector3(n.x, 0, n.y)]
	cache[id] = res
	(M.wallpts as Array).append({"p": Vector2(x, z), "n": n})
	return res


static func _grad(S: PackedFloat32Array, p: Vector2i) -> Vector2:
	var i0 := maxi(p.x - 1, 0)
	var i1 := mini(p.x + 1, G - 1)
	var j0 := maxi(p.y - 1, 0)
	var j1 := mini(p.y + 1, G - 1)
	return Vector2((S[p.y * G + i1] - S[p.y * G + i0]) / float(i1 - i0), (S[j1 * G + p.x] - S[j0 * G + p.x]) / float(j1 - j0))


static func _rock_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D t_rock : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_dirt : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = VERTEX;
	wn = NORMAL;
}
void fragment() {
	vec3 b = pow(abs(normalize(wn)), vec3(4.0));
	b /= b.x + b.y + b.z;
	vec3 rock = texture(t_rock, wp.zy * 0.3).rgb * b.x + texture(t_rock, wp.xz * 0.3).rgb * b.y + texture(t_rock, wp.xy * 0.3).rgb * b.z;
	rock = mix(rock, texture(t_rock, wp.xy * 0.07 + wp.zz * 0.05).rgb, 0.3) * vec3(0.95, 0.88, 0.8);
	vec3 dirt = mix(texture(t_dirt, wp.xz * 0.35).rgb, texture(t_dirt, wp.xz * 0.09).rgb, 0.4) * vec3(1.0, 0.88, 0.72);
	float fl = smoothstep(0.62, 0.9, normalize(wn).y);
	ALBEDO = mix(rock, dirt, fl) * COLOR.rgb;
	ROUGHNESS = mix(0.82, 0.95, fl);
	SPECULAR = 0.35;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("t_rock", Assets.tex.rock.albedo)
	m.set_shader_parameter("t_dirt", Assets.tex.dirt.albedo)
	return m


# ================================================================ dressing
static func _dress(W: World, M: Dictionary, R: RandomNumberGenerator) -> void:
	var batch := MeshBatch.new()
	var B := Builder.at(W, batch, 0, 0, 0, 0)
	var root: Node3D = M.root
	var rooms: Array = M.rooms
	for t in M.tunnels:
		_supports(W, M, batch, t)
		if t.main and t.a <= 1:
			_rails(M, batch, t)
	var ore_mat := StandardMaterial3D.new()
	ore_mat.albedo_color = Color("#c4d2e2")
	ore_mat.metallic = 0.85
	ore_mat.roughness = 0.22
	ore_mat.emission_enabled = true
	ore_mat.emission = Color("#5ab8ff")
	ore_mat.emission_energy_multiplier = 0.45
	var gem_mat := StandardMaterial3D.new()
	gem_mat.albedo_color = Color("#a070ff")
	gem_mat.roughness = 0.2
	gem_mat.emission_enabled = true
	gem_mat.emission = Color("#8a4aff")
	gem_mat.emission_energy_multiplier = 1.1
	var web_mat := StandardMaterial3D.new()
	web_mat.albedo_texture = _web_texture()
	web_mat.albedo_color = Color(0.92, 0.92, 0.96, 0.75)
	web_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	web_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	web_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	web_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for rm in rooms:
		var c: Vector2 = rm.c
		M.labels.append({"x": c.x, "z": c.y, "text": AREA_NAMES[rm.type]})
		var walls := _walls_near(M, rm)
		match rm.type:
			"entry":
				_entry(W, M, B, batch, rm)
				_torches(M, batch, walls, 2, R)
				_scatter(M, B, R, rm, ["barrel_large", "crates_stacked", "box_large", "barrel_small_stack"], 4)
			"workings":
				_torches(M, batch, walls, 3, R)
				_scatter(M, B, R, rm, ["barrel_large", "box_stacked", "crates_stacked", "box_small", "rubble_half", "rubble_half", "keg"], 6)
				_spawn(W, M, R, rm, "miner", 2)
				_spawn(W, M, R, rm, "cave_spider", 1)
			"spider":
				_webs(M, batch, walls, 10, R)
				_scatter(M, B, R, rm, ["bone_A", "bone_B", "skull", "ribcage", "bone_A", "skull"], 7, "halloween")
				_spawn(W, M, R, rm, "cave_spider", 4)
			"ore":
				_torches(M, batch, walls, 2, R)
				_ores(W, M, walls, 4, ore_mat, R)
				_gems(M, batch, walls, 3, R)
				_spawn(W, M, R, rm, "miner", 2)
			"camp":
				_torches(M, batch, walls, 2, R)
				_camp(W, M, B, R, rm)
				_spawn(W, M, R, rm, "miner", 1)
			"cache":
				_webs(M, batch, walls, 4, R)
				var p := _spot(M, R, rm, 0.4, 1.8)
				_chest(W, M, p, R.randf_range(0, TAU), 1.1, ["hp_potion", "mp_potion", "old_coin", "chainmail", "longbow", "tome_fireball", "war_axe", "silver_ore"], [40, 95])
				_scatter(M, B, R, rm, ["box_small", "barrel_small", "box_large"], 3)
				_spawn(W, M, R, rm, "cave_spider", 2)
			"boss":
				_torches(M, batch, walls, 4, R)
				_gems(M, batch, walls, 4, R)
				_hall(W, M, B, R, rm)
				var sp := _spot(M, R, rm, 0.3, 3.0)
				W.spawns.append({"type": "foreman", "x": sp.x, "z": sp.y, "y": floor_y(M, sp.x, sp.y) + 0.2, "leash": 16.0, "under": true})
				_spawn(W, M, R, rm, "miner", 2)
			"cavein":
				B.prop("dungeon", "rubble_large", c.x, floor_y(M, c.x, c.y) - 0.1, c.y, R.randf_range(0, TAU), 0.75)
				B.prop("dungeon", "rubble_half", c.x + 1.2, floor_y(M, c.x, c.y), c.y - 0.8, R.randf_range(0, TAU), 0.8, {"collide": false})
				var it := {"type": "cave_in", "pos": Vector3(c.x, floor_y(M, c.x, c.y) + 1.0, c.y), "r": 3.0, "label": "Examine the cave-in"}
				W.interactables.append(it)
				M.icons.append({"t": "cavein", "p": c})
	# torches along the tunnels
	for t in M.tunnels:
		var near: Array = []
		for w in M.wallpts:
			var d := _seg_dist(w.p, t.pts)
			if d < t.hw + 1.6 and (w.p as Vector2).distance_to(rooms[t.a].c) > rooms[t.a].r + 1.5 and (w.p as Vector2).distance_to(rooms[t.b].c) > rooms[t.b].r + 1.5:
				near.append(w)
		var length: float = (t.pts[0] as Vector2).distance_to(t.pts[1]) + (t.pts[1] as Vector2).distance_to(t.pts[2])
		_torches(M, batch, near, int(length / 11.0), R)
	var mats: Dictionary = W.mats.duplicate()
	mats["ore"] = ore_mat
	mats["gem"] = gem_mat
	mats["web"] = web_mat
	var mi := batch.build(mats, false)
	mi.name = "MineDecor"
	root.add_child(mi)
	W.props.build(root, W.quality)
	# a pool of torch lights follows the player from torch to torch
	var n_lights := 6 if W.quality == "high" else (5 if W.quality == "med" else 3)
	for i in n_lights:
		var l := OmniLight3D.new()
		l.light_color = Color("#ff9a4a")
		l.omni_range = 10.0
		l.omni_attenuation = 1.3
		l.light_energy = 0.0
		root.add_child(l)
		M.lights.append(l)


static func _seg_dist(p: Vector2, pts: Array) -> float:
	var best := 1e9
	for k in pts.size() - 1:
		best = minf(best, U.dist_to_seg(p.x, p.y, pts[k].x, pts[k].y, pts[k + 1].x, pts[k + 1].y))
	return best


static func _walls_near(M: Dictionary, rm: Dictionary) -> Array:
	var out: Array = []
	for w in M.wallpts:
		if (w.p as Vector2).distance_to(rm.c) < rm.r * 1.45:
			out.append(w)
	return out


## random open floor point inside a cavern
static func _spot(M: Dictionary, R: RandomNumberGenerator, rm: Dictionary, frac: float, clear: float) -> Vector2:
	for k in 50:
		var a := R.randf_range(0, TAU)
		var p: Vector2 = rm.c + Vector2(sin(a), cos(a)) * sqrt(R.randf()) * rm.r * frac
		if open_at(M, p.x, p.y) > clear:
			return p
	return rm.c


## a spot on the cave wall at height `h` above the floor: [surface point, normal into the cave]
static func _wall_at(M: Dictionary, w: Dictionary, h: float) -> Array:
	var p: Vector2 = w.p
	var n: Vector2 = w.n
	var y := floor_y(M, p.x, p.y) + h
	var d := (M.n3 as FastNoiseLite).get_noise_3d(p.x, y, p.y) * 0.85
	return [Vector3(p.x - n.x * d, y, p.y - n.y * d), Vector3(n.x, 0, n.y)]


static func _spawn(W: World, M: Dictionary, R: RandomNumberGenerator, rm: Dictionary, type: String, count: int) -> void:
	for i in count:
		var p := _spot(M, R, rm, 0.6, 1.4)
		W.spawns.append({"type": type, "x": p.x, "z": p.y, "y": floor_y(M, p.x, p.y) + 0.2, "leash": 12.0, "under": true})


static func _scatter(M: Dictionary, B: Builder, R: RandomNumberGenerator, rm: Dictionary, names: Array, count: int, bundle := "dungeon") -> void:
	var walls := _walls_near(M, rm)
	for i in count:
		var name: String = U.pick(R, names)
		var small := name.begins_with("bone") or name in ["skull", "ribcage", "box_small", "rubble_half"]
		var p: Vector2
		if walls.size() > 0 and not small:
			# bigger things sit against the walls, out of the way
			var w: Dictionary = U.pick(R, walls)
			p = (w.p as Vector2) + (w.n as Vector2) * R.randf_range(1.1, 1.6)
			if open_at(M, p.x, p.y) < 0.8:
				continue
		else:
			p = _spot(M, R, rm, 0.85, 0.6)
		B.prop(bundle, name, p.x, floor_y(M, p.x, p.y), p.y, R.randf_range(0, TAU), R.randf_range(0.9, 1.15), {"collide": not small})


static func _torches(M: Dictionary, batch: MeshBatch, walls: Array, count: int, R: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 12 and walls.size() > 0:
		tries += 1
		var w: Dictionary = U.pick(R, walls)
		var ok := true
		for t in M.torches:
			if Vector2(t.x, t.z).distance_to(w.p) < 6.0:
				ok = false
				break
		if not ok:
			continue
		var wa := _wall_at(M, w, 1.9)
		var bp: Vector3 = wa[0]
		var n: Vector3 = wa[1]
		var up := Vector3.UP
		batch.add_box("metal", _xf_along(bp + n * 0.05, n, Vector3(0.16, 0.22, 0.1)), "#3a3330")
		var stick_dir := (n * 0.6 + up).normalized()
		batch.add_arrays("log", MeshBatch.prim("cyl", 0.03, 0.04, 0.55, 6), Transform3D(Basis(Quaternion(Vector3.UP, stick_dir)), bp + n * 0.2 + stick_dir * 0.1), "#6a4a2a")
		var flame := bp + n * 0.2 + stick_dir * 0.42
		batch.add_arrays("fire", MeshBatch.prim("cyl", 0.0, 0.08, 0.26, 6), U.xf(flame + Vector3(0, 0.1, 0)), "#ff7a1a")
		batch.add_arrays("fire", MeshBatch.prim("cyl", 0.0, 0.045, 0.16, 5), U.xf(flame + Vector3(0, 0.07, 0)), "#ffd35a")
		M.torches.append(flame)
		M.icons.append({"t": "torch", "p": Vector2(flame.x, flame.z)})
		placed += 1


## transform for a box facing along horizontal normal n
static func _xf_along(pos: Vector3, n: Vector3, size: Vector3) -> Transform3D:
	var z := n.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x * size.x, Vector3.UP * size.y, z * size.z), pos)


static func _supports(W: World, M: Dictionary, batch: MeshBatch, t: Dictionary) -> void:
	var pts: Array = t.pts
	var ra: Dictionary = M.rooms[t.a]
	var rb: Dictionary = M.rooms[t.b]
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var s := 2.0
		while s < L - 1.0:
			var p := a + dir * s
			s += 4.5
			if p.distance_to(ra.c) < ra.r + 1.0 or p.distance_to(rb.c) < rb.r + 1.0:
				continue
			var nrm := Vector2(dir.y, -dir.x)
			var off: float = t.hw - 0.3
			while off > 0.6 and (open_at(M, p.x + nrm.x * off, p.y + nrm.y * off) < 0.2 or open_at(M, p.x - nrm.x * off, p.y - nrm.y * off) < 0.2):
				off -= 0.15
			var fy := floor_y(M, p.x, p.y)
			var h := minf(ceil_y(M, p.x, p.y) - fy - 0.15, 3.1)
			var n3 := Vector3(nrm.x, 0, nrm.y)
			var t3 := Vector3(dir.x, 0, dir.y)
			for side in [-1.0, 1.0]:
				var q: Vector3 = Vector3(p.x, fy + h / 2.0, p.y) + n3 * off * side
				batch.add_box("beam", Transform3D(Basis(n3 * 0.24, Vector3.UP * h, t3 * 0.24), q), "#9a7a58")
				W.add_box_collider(Transform3D(Basis(n3, Vector3.UP, t3), q), Vector3(0.24, h, 0.24))
			batch.add_box("beam", Transform3D(Basis(n3 * (off * 2.0 + 0.5), Vector3.UP * 0.26, t3 * 0.28), Vector3(p.x, fy + h - 0.13, p.y)), "#8a6a48")


static func _rails(M: Dictionary, batch: MeshBatch, t: Dictionary) -> void:
	var pts: Array = t.pts
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var n3 := Vector3(dir.y, 0, -dir.x)
		var t3 := Vector3(dir.x, 0, dir.y)
		var s := 0.0
		while s < L:
			var p := a + dir * s
			s += 0.7
			if open_at(M, p.x, p.y) < 0.9:
				continue
			var fy := floor_y(M, p.x, p.y)
			batch.add_box("log", Transform3D(Basis(n3 * 1.15, Vector3.UP * 0.07, t3 * 0.2), Vector3(p.x, fy + 0.03, p.y)), "#5a4028")
			var q := p + dir * 0.35
			var y2 := floor_y(M, q.x, q.y)
			for side in [-1.0, 1.0]:
				batch.add_box("metal", Transform3D(Basis(n3 * 0.06, Vector3.UP * 0.07, t3 * 0.72), Vector3(q.x, y2 + 0.1, q.y) + n3 * 0.42 * side), "#6a6460")


static func _entry(W: World, M: Dictionary, B: Builder, batch: MeshBatch, rm: Dictionary) -> void:
	var c: Vector2 = rm.c
	# head towards the first tunnel
	var nxt: Vector2 = c
	for t in M.tunnels:
		if t.a == 0:
			nxt = t.pts[1]
			break
	var dir := (nxt - c).normalized()
	var lad: Vector2 = c - dir * (rm.r * 0.45)
	while open_at(M, lad.x, lad.y) < 1.2 and lad.distance_to(c) > 0.5:
		lad = lad.lerp(c, 0.2)
	var fy := floor_y(M, lad.x, lad.y)
	var top := ceil_y(M, lad.x, lad.y) + 2.0
	var h := top - fy
	var n3 := Vector3(dir.x, 0, dir.y)
	var side := Vector3(dir.y, 0, -dir.x)
	for s in [-1.0, 1.0]:
		batch.add_box("log", Transform3D(Basis(side * 0.08, Vector3.UP * h, n3 * 0.08), Vector3(lad.x, fy + h / 2.0, lad.y) + side * 0.3 * s), "#7a5a3a")
	var ry := 0.35
	while ry < h:
		batch.add_box("log", Transform3D(Basis(side * 0.62, Vector3.UP * 0.05, n3 * 0.06), Vector3(lad.x, fy + ry, lad.y)), "#8a6a48")
		ry += 0.38
	W.add_box_collider(Transform3D(Basis.IDENTITY, Vector3(lad.x, fy + 1.5, lad.y)), Vector3(0.8, 3.0, 0.3))
	# a shaft of daylight from above
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 1.7
	cm.height = h
	cm.radial_segments = 12
	cm.cap_top = false
	cm.cap_bottom = false
	var beam := StandardMaterial3D.new()
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.albedo_color = Color(1.0, 0.95, 0.78, 0.07)
	cm.material = beam
	var bm := MeshInstance3D.new()
	bm.mesh = cm
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bm.position = Vector3(lad.x, fy + h / 2.0, lad.y)
	(M.root as Node3D).add_child(bm)
	var day := OmniLight3D.new()
	day.light_color = Color("#d8e4ff")
	day.light_energy = 1.3
	day.omni_range = 10.0
	day.position = Vector3(lad.x, fy + 3.2, lad.y)
	(M.root as Node3D).add_child(day)
	W.interactables.append({"type": "mine_exit", "pos": Vector3(lad.x, fy + 1.2, lad.y), "r": 2.6, "label": "Climb out of the mine"})
	M.icons.append({"t": "exit", "p": lad})
	M.exit_pos = Vector2(lad.x, lad.y)
	var start := c + dir * 1.5
	M.entry_pos = Vector3(start.x, floor_y(M, start.x, start.y) + 0.3, start.y)
	M.entry_yaw = atan2(-dir.x, -dir.y)
	# an old mine cart on the rails
	var cp: Vector2 = c + dir * (rm.r * 0.6)
	var cy := floor_y(M, cp.x, cp.y)
	var cb := B.sub(cp.x, cp.y, atan2(dir.x, dir.y), cy)
	cb.box("metal", 0, 0.62, 0, 0.95, 0.6, 1.35, "#5a5048", true)
	cb.box("color", 0, 0.94, 0, 0.82, 0.08, 1.2, "#4a4a4a", false)
	for s in [-1.0, 1.0]:
		for zz in [-0.45, 0.45]:
			cb.geo("metal", ["cyl", 0.16, 0.16, 0.08, 8], s * 0.5, 0.18, zz, 0.0, "#2a2622", Vector3.ONE, 0.0, PI / 2.0)
	B.prop("halloween", "lantern_standing", lad.x + side.x * 1.4, fy, lad.y + side.z * 1.4, 0.0, 1.0)


static func _camp(W: World, M: Dictionary, B: Builder, R: RandomNumberGenerator, rm: Dictionary) -> void:
	var c := _spot(M, R, rm, 0.25, 2.2)
	var fy := floor_y(M, c.x, c.y)
	var a := R.randf_range(0, TAU)
	B.prop("dungeon", "table_medium", c.x, fy, c.y, a, 1.0)
	B.prop("dungeon", "candle_lit", c.x, fy + 0.78, c.y, 0.0, 1.0, {"collide": false})
	for k in 3:
		var sa := a + k * 2.1
		B.prop("dungeon", "stool", c.x + sin(sa) * 1.1, fy, c.y + cos(sa) * 1.1, sa, 1.0, {"collide": false})
	_scatter(M, B, R, rm, ["bed_frame", "barrel_large", "crates_stacked", "keg", "box_stacked"], 4)
	var p := _spot(M, R, rm, 0.7, 1.6)
	_chest(W, M, p, R.randf_range(0, TAU), 1.1, ["hp_potion", "stew", "bread", "silver_ore", "old_coin", "hunting_bow", "leather", "tome_sparks"], [25, 60])


static func _hall(W: World, M: Dictionary, B: Builder, R: RandomNumberGenerator, rm: Dictionary) -> void:
	var c: Vector2 = rm.c
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var p: Vector2 = c + Vector2(sin(a), cos(a)) * rm.r * 0.55
		if open_at(M, p.x, p.y) > 1.0:
			B.prop("dungeon", "column", p.x, floor_y(M, p.x, p.y), p.y, a, 1.3)
	# the foreman's hoard against the far wall
	var walls := _walls_near(M, rm)
	var w: Dictionary = walls[R.randi_range(0, walls.size() - 1)] if walls.size() > 0 else {"p": c, "n": Vector2(1, 0)}
	var hp: Vector2 = (w.p as Vector2) + (w.n as Vector2) * 2.2
	if open_at(M, hp.x, hp.y) < 1.0:
		hp = c
	var face := atan2((w.n as Vector2).x, (w.n as Vector2).y)
	_chest(W, M, hp, face, 1.45, ["plate", "longbow", "tome_fireball", "war_axe", "knight_blade", "mage_robe"], [120, 200])
	for k in 3:
		var p := hp + Vector2(R.randf_range(-1.6, 1.6), R.randf_range(-1.6, 1.6))
		if open_at(M, p.x, p.y) > 0.6:
			B.prop("dungeon", "coin_stack_large", p.x, floor_y(M, p.x, p.y), p.y, R.randf_range(0, TAU), 1.0, {"collide": false})
	_scatter(M, B, R, rm, ["skull", "bone_A", "bone_B", "ribcage", "candle_triple", "skull_candle"], 9, "halloween")
	_scatter(M, B, R, rm, ["rubble_half", "rubble_large", "barrel_large"], 3)


static func _chest(W: World, M: Dictionary, p: Vector2, ry: float, scale: float, pool: Array, gold: Array) -> void:
	var y := floor_y(M, p.x, p.y)
	var g := Node3D.new()
	g.position = Vector3(p.x, y, p.y)
	g.rotation.y = ry
	var closed := Assets.instance("village", "Chest_Closed")
	var opened := Assets.instance("village", "Chest_Open")
	closed.scale = Vector3.ONE * scale
	opened.scale = Vector3.ONE * scale
	opened.visible = false
	g.add_child(closed)
	g.add_child(opened)
	(M.root as Node3D).add_child(g)
	W.add_cylinder_collider(Vector3(p.x, y + 0.4, p.y), 0.5 * scale, 0.8)
	var it := {"type": "chest", "id": W.chests.size(), "pos": Vector3(p.x, y + 0.4, p.y), "r": 2.0, "label": "Open Chest", "closed": closed, "opened": opened, "opened_day": -1, "pool": pool, "gold": gold}
	W.chests.append(it)
	W.interactables.append(it)
	M.icons.append({"t": "chest", "p": p, "ref": it})


static func _ores(W: World, M: Dictionary, walls: Array, count: int, mat: Material, R: RandomNumberGenerator) -> void:
	var used: Array = []
	for i in count:
		for tries in 20:
			var w: Dictionary = U.pick(R, walls)
			if used.any(func(u: Vector2) -> bool: return u.distance_to(w.p) < 3.0):
				continue
			used.append(w.p)
			var wa := _wall_at(M, w, R.randf_range(0.5, 1.3))
			var base: Vector3 = wa[0]
			var n: Vector3 = wa[1]
			var batch := MeshBatch.new()
			_shards(batch, "ore", base, n, 10, 0.09, 0.2, 0.4, 1.05, R)
			var mi := batch.build({"ore": mat}, false)
			(M.root as Node3D).add_child(mi)
			var it := {"type": "ore", "pos": base + n * 0.6, "r": 2.4, "label": "Mine Silver Ore", "node": mi, "respawn": 0.0}
			W.ores.append(it)
			W.interactables.append(it)
			M.icons.append({"t": "ore", "p": Vector2(base.x, base.z), "ref": it})
			break


static func _gems(M: Dictionary, batch: MeshBatch, walls: Array, count: int, R: RandomNumberGenerator) -> void:
	for i in mini(count, walls.size()):
		var w: Dictionary = U.pick(R, walls)
		var wa := _wall_at(M, w, R.randf_range(0.2, 2.6))
		_shards(batch, "gem", wa[0], wa[1], 5, 0.05, 0.1, 0.2, 0.5, R)


## a cluster of tapered crystal shards growing out of the wall along n
static func _shards(batch: MeshBatch, key: String, base: Vector3, n: Vector3, count: int, r0: float, r1: float, h0: float, h1: float, R: RandomNumberGenerator) -> void:
	for k in count:
		var dir := (n + Vector3(R.randf_range(-0.7, 0.7), R.randf_range(-0.4, 0.8), R.randf_range(-0.7, 0.7))).normalized()
		var h := R.randf_range(h0, h1)
		var r := R.randf_range(r0, r1)
		var at := base + Vector3(R.randf_range(-0.25, 0.25), R.randf_range(-0.2, 0.2), R.randf_range(-0.25, 0.25)) + dir * h * 0.35
		batch.add_arrays(key, MeshBatch.prim("cyl", 0.0, r, h, 5), Transform3D(Basis(Quaternion(Vector3.UP, dir)), at), Color.WHITE)


static func _webs(M: Dictionary, batch: MeshBatch, walls: Array, count: int, R: RandomNumberGenerator) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var arr := quad.get_mesh_arrays()
	for i in mini(count, walls.size()):
		var w: Dictionary = U.pick(R, walls)
		var p: Vector2 = w.p
		var top := ceil_y(M, p.x, p.y) - floor_y(M, p.x, p.y)
		var wa := _wall_at(M, w, top - R.randf_range(0.6, 1.4))
		var n: Vector3 = wa[1]
		var s := R.randf_range(1.4, 2.6)
		var basis := Basis(Quaternion(Vector3.BACK, (n + Vector3.UP * R.randf_range(-0.6, 0.6)).normalized())).rotated(n, R.randf_range(0, TAU))
		batch.add_arrays("web", arr, Transform3D(basis.scaled(Vector3.ONE * s), (wa[0] as Vector3) + n * 0.3), Color.WHITE)


static func _web_texture() -> ImageTexture:
	if _web_tex:
		return _web_tex
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var c := Vector2(S / 2.0, S / 2.0)
	var spokes := 11
	var line := func(a: Vector2, b: Vector2, alpha: float) -> void:
		var steps := int(a.distance_to(b) * 1.5) + 1
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			if p.x >= 0 and p.y >= 0 and p.x < S and p.y < S:
				var old := img.get_pixel(int(p.x), int(p.y))
				img.set_pixel(int(p.x), int(p.y), Color(1, 1, 1, maxf(old.a, alpha)))
	var ends: Array = []
	for k in spokes:
		var a := k * TAU / spokes + sin(k * 3.7) * 0.15
		ends.append(Vector2(cos(a), sin(a)))
		line.call(c, c + ends[k] * 62.0, 0.85)
	var r := 7.0
	while r < 60.0:
		for k in spokes:
			var a: Vector2 = c + ends[k] * r
			var b: Vector2 = c + ends[(k + 1) % spokes] * r
			line.call(a, (a + b) / 2.0 + (c - (a + b) / 2.0).normalized() * r * 0.06, 0.7)
			line.call((a + b) / 2.0 + (c - (a + b) / 2.0).normalized() * r * 0.06, b, 0.7)
		r *= 1.32
	img.generate_mipmaps()
	_web_tex = ImageTexture.create_from_image(img)
	return _web_tex


# ================================================================ per frame
static func update(W: World, dt: float, pp: Vector3) -> void:
	var M: Dictionary = W.mine
	M.light_t -= dt
	if M.light_t <= 0.0:
		M.light_t = 0.25
		var ts: Array = M.torches.duplicate()
		ts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(pp) < b.distance_squared_to(pp))
		M.lit = ts.slice(0, (M.lights as Array).size())
	var lit: Array = M.lit
	for i in (M.lights as Array).size():
		var l: OmniLight3D = M.lights[i]
		if i < lit.size() and (lit[i] as Vector3).distance_to(pp) < 24.0:
			l.position = lit[i] + Vector3(0, 0.2, 0)
			l.light_energy = 2.6 + sin(W.t * 11.0 + i * 1.7) * 0.22 + sin(W.t * 6.3 + i) * 0.18
		else:
			l.light_energy = 0.0
	# reveal the map around the player
	M.reveal_t -= dt
	if M.reveal_t <= 0.0:
		M.reveal_t = 0.2
		reveal(M, pp.x, pp.z, 8.0)


static func reveal(M: Dictionary, x: float, z: float, radius: float) -> void:
	var rev: PackedByteArray = M.revealed
	var n := G - 1
	var ci := int(x - M.x0)
	var cj := int(z - M.z0)
	var ri := int(radius) + 1
	var fresh: Array = M.reveal_new
	var changed := false
	for j in range(maxi(0, cj - ri), mini(n, cj + ri + 1)):
		for i in range(maxi(0, ci - ri), mini(n, ci + ri + 1)):
			var k := j * n + i
			if rev[k] == 0 and Vector2(i - ci, j - cj).length() <= radius:
				rev[k] = 1
				fresh.append(k)
				changed = true
	if changed:
		M.revealed = rev


static func is_revealed(M: Dictionary, p: Vector2) -> bool:
	var n := G - 1
	var i := int(p.x - M.x0)
	var j := int(p.y - M.z0)
	if i < 0 or j < 0 or i >= n or j >= n:
		return false
	return (M.revealed as PackedByteArray)[j * n + i] != 0
