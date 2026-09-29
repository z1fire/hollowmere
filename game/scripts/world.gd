class_name World
extends Node3D
## Procedurally generated region: terrain, village, wilds, vegetation, sky and lighting.

const SIZE := 470.0
const RES := 2.0
const N := 236  # grid vertices per side (SIZE / RES + 1)

var seed_value := 0
var quality := "med"
var rng: RandomNumberGenerator
var nz_fbm: FastNoiseLite
var nz2: FastNoiseLite
var nz3: FastNoiseLite

var heights := PackedFloat32Array()
var road_d := PackedFloat32Array()   # distance to nearest road edge per grid cell
var blocked := PackedByteArray()     # exclusion zones per grid cell
var flats: Array = []
var roads: Array = []
var excl: Array = []
var pois := {}
var gates: Array = []
var fence_r := 60.0
var water := {}
var plaza_y := 0.0
var farm := {}
var buildings: Array = []
var interactables: Array = []
var spawns: Array = []
var npc_spots: Array = []
var waypoints: Array = []
var plots: Array = []
var herbs: Array = []
var chests: Array = []
var map_labels: Array = []
var rock_spots: Array = []
var spawn_point := {}
var bed_point := {}
var animated: Array = []

var mats := {}
var props := PropField.new()
var body: StaticBody3D   # terrain
var _bodies := {}        # static colliders, split into spatial chunks (Jolt limits shapes per body)
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var interior_light: OmniLight3D
var lantern: OmniLight3D
var camp_light: OmniLight3D
var water_mat: StandardMaterial3D
var grass_mat: ShaderMaterial
var night := 0.0
var inside = null
var t := 0.0


# ================================================================ generation
func generate(p_seed: int, p_quality: String, progress: Callable) -> void:
	seed_value = p_seed
	quality = p_quality
	rng = U.make_rng(p_seed)
	nz_fbm = _noise(p_seed, true)
	nz2 = _noise(p_seed + 71, false)
	nz3 = _noise(p_seed + 913, false)
	body = StaticBody3D.new()
	body.name = "Static"
	add_child(body)
	_make_materials()
	var steps := [
		["Planning the village...", func(): plan_layout(); Village.plan(self)],
		["Shaping the land...", func(): compute_heights()],
		["Carving roads...", func(): rasterize()],
		["Growing grass...", func(): build_terrain()],
		["Raising the village...", func(): Village.build(self)],
		["Exploring the wilds...", func(): Wilds.build(self)],
		["Planting forests...", func(): scatter_vegetation()],
		["Hiding treasure...", func(): Wilds.herbs_and_chests(self)],
		["Painting the sky...", func(): build_sky(); build_lights()],
		["Placing props...", func(): props.build(self, quality)],
	]
	for i in steps.size():
		progress.call(steps[i][0], float(i) / steps.size())
		await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		steps[i][1].call()
		print("[gen] %s %d ms" % [steps[i][0], Time.get_ticks_msec() - t0])


func _noise(s: int, fbm: bool) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = 1.0
	if fbm:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n


func _make_materials() -> void:
	mats = {
		"plaster": Assets.pbr("plaster", 2.2), "stone": Assets.pbr("stone", 2.4), "log": Assets.pbr("planks", 2.2),
		"wood": Assets.pbr("floor", 2.0), "beam": Assets.pbr("beam", 1.4), "thatch": Assets.pbr("thatch", 2.6),
		"shingle": Assets.pbr("tiles", 2.2), "cobble": Assets.pbr("cobble", 3.0), "road": Assets.pbr("dirt", 3.2),
	}
	for m in mats.values():
		m.vertex_color_is_srgb = true
	var color := StandardMaterial3D.new()
	color.vertex_color_use_as_albedo = true
	color.vertex_color_is_srgb = true
	color.roughness = 0.9
	mats["color"] = color
	var metal := color.duplicate()
	metal.metallic = 0.6
	metal.roughness = 0.45
	mats["metal"] = metal
	# emissive vertex-coloured materials (bloom)
	var glow_shader := Shader.new()
	glow_shader.code = "shader_type spatial;\nrender_mode unshaded, shadows_disabled;\nuniform float strength = 2.2;\nvoid fragment(){ ALBEDO = COLOR.rgb * strength; }"
	var fire := ShaderMaterial.new()
	fire.shader = glow_shader
	mats["fire"] = fire
	var glow := ShaderMaterial.new()
	glow.shader = glow_shader
	glow.set_shader_parameter("strength", 1.6)
	mats["glow"] = glow
	var win_shader := Shader.new()
	win_shader.code = "shader_type spatial;\nrender_mode unshaded, shadows_disabled;\nuniform vec3 day_col : source_color = vec3(0.17,0.22,0.28);\nuniform vec3 night_col : source_color = vec3(1.0,0.71,0.33);\nuniform float night = 0.0;\nvoid fragment(){ ALBEDO = mix(day_col, night_col * 2.2, night); }"
	var win := ShaderMaterial.new()
	win.shader = win_shader
	mats["window"] = win
	# road ribbons sit just above the terrain
	var road: StandardMaterial3D = mats.road
	road.render_priority = 1


# ================================================================ height
func base_height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var h := nz_fbm.get_noise_2d(x * 0.007, z * 0.007) * 16.0 + nz2.get_noise_2d(x * 0.045, z * 0.045) * 1.0
	h = lerpf(nz2.get_noise_2d(x * 0.02, z * 0.02) * 0.5, h, U.smoothstep(60.0, 90.0, r))
	var m := U.smoothstep(150.0, 195.0, r)
	h += m * m * 50.0 * (0.75 + 0.35 * nz3.get_noise_2d(x * 0.02, z * 0.02))
	return h


func _flat_height(x: float, z: float, h: float) -> float:
	for f in flats:
		var dx: float = x - f.x
		var dz: float = z - f.z
		var lim: float = f.r + f.fall
		if dx > lim or dx < -lim or dz > lim or dz < -lim:
			continue
		var d := sqrt(dx * dx + dz * dz)
		if d < lim:
			var fh: float = f.h
			if f.get("bowl", 0.0) > 0.0:
				var k: float = d / f.r
				fh = f.h - f.bowl * maxf(0.0, 1.0 - k * k)
			h = lerpf(fh, h, U.smoothstep(f.r, lim, d))
	return h


func compute_heights() -> void:
	heights.resize(N * N)
	var half := SIZE / 2.0
	for j in N:
		var z := -half + j * RES
		for i in N:
			var x := -half + i * RES
			heights[j * N + i] = _flat_height(x, z, base_height(x, z))


## terrain height (bilinear from the grid, matches the rendered mesh)
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + SIZE / 2.0) / RES, 0.0, N - 1.001)
	var fz := clampf((z + SIZE / 2.0) / RES, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * N + i]
	var b := heights[j * N + i + 1]
	var c := heights[(j + 1) * N + i]
	var d := heights[(j + 1) * N + i + 1]
	# match the triangle split used by the mesh
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


## ground including floors / props below `from_y` (physics ray)
func ground_at(x: float, z: float, from_y := 400.0) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -200, z), 1)
	var hit := space.intersect_ray(q)
	return hit.position.y if hit else height_at(x, z)


func _cell(x: float, z: float) -> int:
	var i := clampi(int((x + SIZE / 2.0) / RES + 0.5), 0, N - 1)
	var j := clampi(int((z + SIZE / 2.0) / RES + 0.5), 0, N - 1)
	return j * N + i


func road_edge(x: float, z: float) -> float:
	return road_d[_cell(x, z)]


func is_clear(x: float, z: float, road_pad := 2.0) -> bool:
	var c := _cell(x, z)
	if road_d[c] < road_pad or blocked[c] != 0:
		return false
	var r := sqrt(x * x + z * z)
	return not (r > fence_r - 2.0 and r < fence_r + 2.0)


# ================================================================ layout
func plan_layout() -> void:
	var base := rng.randf_range(0, TAU)
	gates = []
	for i in 3:
		gates.append(base + i * TAU / 3.0 + rng.randf_range(-0.22, 0.22))
	var camp := U.polar(gates[0] + rng.randf_range(-0.3, 0.3), 128.0)
	var grave := U.polar(gates[1] + rng.randf_range(-0.3, 0.3), 108.0)
	var mine := U.polar(gates[2] + rng.randf_range(-0.15, 0.15), 158.0)
	var pond := U.polar(gates[2] + PI / 3.0 + rng.randf_range(-0.15, 0.15), rng.randf_range(88.0, 100.0))
	pois = {"camp": camp, "grave": grave, "mine": mine, "pond": pond}
	flats.append({"x": 0.0, "z": 0.0, "r": 13.0, "fall": 8.0, "h": base_height(0, 0)})
	flats.append({"x": camp.x, "z": camp.y, "r": 18.0, "fall": 12.0, "h": base_height(camp.x, camp.y)})
	flats.append({"x": grave.x, "z": grave.y, "r": 19.0, "fall": 12.0, "h": base_height(grave.x, grave.y)})
	flats.append({"x": mine.x, "z": mine.y, "r": 10.0, "fall": 10.0, "h": base_height(mine.x, mine.y)})
	var ph := base_height(pond.x, pond.y)
	flats.append({"x": pond.x, "z": pond.y, "r": 14.0, "fall": 9.0, "h": ph, "bowl": 2.6})
	water = {"x": pond.x, "z": pond.y, "r": 14.0, "y": ph - 0.35}
	plaza_y = flats[0].h
	excl.append_array([{"t": "c", "x": 0.0, "z": 0.0, "r": 14.0}, {"t": "c", "x": camp.x, "z": camp.y, "r": 21.0}, {"t": "c", "x": grave.x, "z": grave.y, "r": 22.0},
		{"t": "c", "x": mine.x, "z": mine.y, "r": 12.0}, {"t": "c", "x": pond.x, "z": pond.y, "r": 16.0}])
	var targets := [camp, grave, mine]
	for i in 3:
		var g: float = gates[i]
		var tg: Vector2 = targets[i]
		var tr := tg.length()
		var ta := atan2(tg.x, tg.y)
		var pts := [U.polar(g, 12.0), U.polar(g, fence_r), U.polar(g + U.angle_diff(g, ta) * 0.5 + rng.randf_range(-0.06, 0.06), (fence_r + tr) / 2.0), U.polar(ta, tr - (6.0 if i == 2 else 15.0))]
		roads.append({"pts": pts, "w": 2.8, "main": true, "gate": i})


## roads, exclusion zones and fence ring rasterised onto the grid
func rasterize() -> void:
	road_d.resize(N * N)
	road_d.fill(99.0)
	blocked.resize(N * N)
	blocked.fill(0)
	var half := SIZE / 2.0
	for r in roads:
		for k in r.pts.size() - 1:
			var a: Vector2 = r.pts[k]
			var b: Vector2 = r.pts[k + 1]
			var pad: float = r.w / 2.0 + 6.0
			var i0 := clampi(int((minf(a.x, b.x) - pad + half) / RES), 0, N - 1)
			var i1 := clampi(int((maxf(a.x, b.x) + pad + half) / RES) + 1, 0, N - 1)
			var j0 := clampi(int((minf(a.y, b.y) - pad + half) / RES), 0, N - 1)
			var j1 := clampi(int((maxf(a.y, b.y) + pad + half) / RES) + 1, 0, N - 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var d: float = U.dist_to_seg(-half + i * RES, -half + j * RES, a.x, a.y, b.x, b.y) - r.w / 2.0
					var c := j * N + i
					if d < road_d[c]:
						road_d[c] = d
	for e in excl:
		var minx: float
		var maxx: float
		var minz: float
		var maxz: float
		if e.t == "c":
			minx = e.x - e.r
			maxx = e.x + e.r
			minz = e.z - e.r
			maxz = e.z + e.r
		else:
			minx = e.minX
			maxx = e.maxX
			minz = e.minZ
			maxz = e.maxZ
		for j in range(clampi(int((minz + half) / RES), 0, N - 1), clampi(int((maxz + half) / RES) + 1, 0, N - 1) + 1):
			for i in range(clampi(int((minx + half) / RES), 0, N - 1), clampi(int((maxx + half) / RES) + 1, 0, N - 1) + 1):
				var x := -half + i * RES
				var z := -half + j * RES
				if e.t == "r" or Vector2(x - e.x, z - e.z).length() < e.r:
					blocked[j * N + i] = 1


# ================================================================ terrain
func build_terrain() -> void:
	var half := SIZE / 2.0
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var tint := PackedFloat32Array()
	verts.resize(N * N)
	norms.resize(N * N)
	uvs.resize(N * N)
	cols.resize(N * N)
	tans.resize(N * N * 4)
	tint.resize(N * N * 4)
	var cA := Color("#58872f").srgb_to_linear()
	var cB := Color("#7fa845").srgb_to_linear()
	var cDry := Color("#a09f55").srgb_to_linear()
	var cDark := Color("#40652a").srgb_to_linear()
	var W := water
	var camp: Vector2 = pois.camp
	var grave: Vector2 = pois.grave
	for j in N:
		for i in N:
			var k := j * N + i
			var x := -half + i * RES
			var z := -half + j * RES
			var h := heights[k]
			verts[k] = Vector3(x, h, z)
			var hl := heights[j * N + maxi(i - 1, 0)]
			var hr := heights[j * N + mini(i + 1, N - 1)]
			var hd := heights[maxi(j - 1, 0) * N + i]
			var hu := heights[mini(j + 1, N - 1) * N + i]
			var n := Vector3(hl - hr, 2.0 * RES, hd - hu).normalized()
			norms[k] = n
			var tg := Vector3(1, 0, 0) - n * n.x
			tg = tg.normalized()
			tans[k * 4] = tg.x
			tans[k * 4 + 1] = tg.y
			tans[k * 4 + 2] = tg.z
			tans[k * 4 + 3] = 1.0
			uvs[k] = Vector2(x / 3.0, z / 3.0)
			var r := sqrt(x * x + z * z)
			var nn := nz2.get_noise_2d(x * 0.05, z * 0.05)
			var n2 := nz3.get_noise_2d(x * 0.012, z * 0.012)
			var c := cA.lerp(cB, clampf(nn * 0.8 + 0.5, 0.0, 1.0))
			c = c.lerp(cDry, U.smoothstep(0.15, 0.55, n2) * 0.55)
			c = c.lerp(cDark, U.smoothstep(0.0, -0.4, n2) * 0.55 * U.smoothstep(60.0, 90.0, r))
			tint[k * 4] = c.r
			tint[k * 4 + 1] = c.g
			tint[k * 4 + 2] = c.b
			tint[k * 4 + 3] = 1.0
			# texture weights: grass, dirt, rock, forest floor
			var sl := (absf(hr - hl) + absf(hu - hd)) / (2.0 * RES) * 2.0
			var wr := maxf(U.smoothstep(0.9, 1.8, sl), U.smoothstep(13.0, 24.0, h))
			var wd := maxf(1.0 - U.smoothstep(-0.8, 1.4, road_d[k]), 1.0 - U.smoothstep(W.r * 0.8, W.r + 3.0, Vector2(x - W.x, z - W.z).length()))
			wd = maxf(wd, (1.0 - U.smoothstep(8.0, 18.0, Vector2(x - camp.x, z - camp.y).length())) * 0.8)
			wd = maxf(wd, U.smoothstep(0.35, 0.6, nz3.get_noise_2d(x * 0.05 + 7.0, z * 0.05)) * 0.35)
			var wf := U.smoothstep(0.0, -0.35, n2) * U.smoothstep(64.0, 90.0, r) + (1.0 - U.smoothstep(14.0, 24.0, Vector2(x - grave.x, z - grave.y).length())) * 0.6
			wd = minf(1.0, wd)
			wr = minf(1.0, wr)
			wf = minf(1.0, wf) * (1.0 - wd) * (1.0 - wr)
			var wg := maxf(0.0, 1.0 - wd - wr - wf)
			var sum := wg + wd + wr + wf
			if sum <= 0.0:
				sum = 1.0
			cols[k] = Color(wg / sum, wd / sum, wr / sum, wf / sum)
	var idx := PackedInt32Array()
	idx.resize((N - 1) * (N - 1) * 6)
	var q := 0
	for j in N - 1:
		for i in N - 1:
			var a := j * N + i
			var b := a + 1
			var c2 := a + N
			var d := c2 + 1
			# clockwise front faces, split a-d diagonal to match height_at()
			idx[q] = a; idx[q + 1] = b; idx[q + 2] = c2
			idx[q + 3] = b; idx[q + 4] = d; idx[q + 5] = c2
			q += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tans
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_CUSTOM0] = tint
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, _terrain_material())
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	_build_roads()
	_build_water()


func _terrain_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D t_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_forest : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_grass : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_dirt : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_rock : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec4 splat;
varying vec3 tint;
varying vec2 wuv;
void vertex() {
	splat = COLOR;
	tint = CUSTOM0.rgb;
	wuv = VERTEX.xz / 3.0;
}
void fragment() {
	vec3 gt = mix(texture(t_grass, wuv).rgb, texture(t_grass, wuv * 0.21 + 0.37).rgb, 0.45);
	vec3 cg = tint * (0.35 + dot(gt, vec3(0.3, 0.59, 0.11)) * 2.6);
	vec3 cd = mix(texture(t_dirt, wuv * 0.8).rgb, texture(t_dirt, wuv * 0.19).rgb, 0.35);
	vec3 cr = mix(texture(t_rock, wuv * 0.5).rgb, texture(t_rock, wuv * 0.13).rgb, 0.4);
	vec3 cf = texture(t_forest, wuv * 0.9).rgb;
	ALBEDO = cg * splat.r + cd * splat.g + cr * splat.b + cf * splat.a;
	NORMAL_MAP = texture(n_grass, wuv).rgb * splat.r + texture(n_dirt, wuv * 0.8).rgb * (splat.g + splat.a) + texture(n_rock, wuv * 0.5).rgb * splat.b;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.95;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("t_grass", Assets.tex.grass.albedo)
	m.set_shader_parameter("t_dirt", Assets.tex.dirt.albedo)
	m.set_shader_parameter("t_rock", Assets.tex.rock.albedo)
	m.set_shader_parameter("t_forest", Assets.tex.forest.albedo)
	m.set_shader_parameter("n_grass", Assets.tex.grass.normal)
	m.set_shader_parameter("n_dirt", Assets.tex.dirt.normal)
	m.set_shader_parameter("n_rock", Assets.tex.rock.normal)
	return m


func _build_roads() -> void:
	var batch := MeshBatch.new()
	var g := batch._g("road")
	for r in roads:
		var samples: Array = []
		for k in r.pts.size() - 1:
			var a: Vector2 = r.pts[k]
			var b: Vector2 = r.pts[k + 1]
			var n := maxi(1, ceili(a.distance_to(b) / 1.2))
			for s in n:
				samples.append(a.lerp(b, float(s) / n))
		samples.append(r.pts[r.pts.size() - 1])
		var col := Color("#f0e4d0") if r.main else Color("#e4d6c0")
		var base: int = g.v.size()
		for k in samples.size():
			var p: Vector2 = samples[k]
			var nxt: Vector2 = samples[mini(k + 1, samples.size() - 1)]
			var prv: Vector2 = samples[maxi(k - 1, 0)]
			var tg := (nxt - prv).normalized()
			var nrm: Vector2 = Vector2(-tg.y, tg.x) * r.w / 2.0
			var wob := nz2.get_noise_2d(p.x * 0.3, p.y * 0.3) * 0.25
			for s in [-1.0, 1.0]:
				var q: Vector2 = p + nrm * (s + wob * s)
				g.v.append(Vector3(q.x, height_at(q.x, q.y) + 0.07, q.y))
				g.n.append(Vector3.UP)
				g.uv.append(Vector2.ZERO)
				g.c.append(col)
			if k > 0:
				var b0: int = base + (k - 1) * 2
				# pick the winding that faces up
				g.i.append_array([b0, b0 + 1, b0 + 2, b0 + 1, b0 + 3, b0 + 2])
		# ensure the first triangle faces up (clockwise from above)
		if samples.size() > 1:
			var v0: Vector3 = g.v[base]
			var v1: Vector3 = g.v[base + 1]
			var v2: Vector3 = g.v[base + 2]
			if (v1 - v0).cross(v2 - v0).y > 0.0:
				var start: int = g.i.size() - (samples.size() - 1) * 6
				for q2 in range(start, g.i.size(), 3):
					var tmp: int = g.i[q2 + 1]
					g.i[q2 + 1] = g.i[q2 + 2]
					g.i[q2 + 2] = tmp
	var mi := batch.build(mats, false)
	mi.name = "Roads"
	add_child(mi)


func _build_water() -> void:
	var W := water
	var cm := CylinderMesh.new()
	cm.top_radius = W.r * 1.02
	cm.bottom_radius = W.r * 1.02
	cm.height = 0.02
	cm.radial_segments = 48
	cm.rings = 1
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 4.0
	water_mat = StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.12, 0.29, 0.35, 0.86)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.05
	water_mat.metallic = 0.1
	water_mat.normal_enabled = true
	water_mat.normal_texture = nt
	water_mat.normal_scale = 0.35
	water_mat.uv1_scale = Vector3(4, 4, 4)
	cm.material = water_mat
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.position = Vector3(W.x, W.y, W.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# deep water is off-limits
	add_cylinder_collider(Vector3(W.x, W.y, W.z), W.r * 0.62, 6.0)


# ================================================================ colliders
func _body_for(p: Vector3) -> StaticBody3D:
	var k := Vector2i(floori(p.x / 32.0), floori(p.z / 32.0))
	if not _bodies.has(k):
		var b := StaticBody3D.new()
		b.name = "Static_%d_%d" % [k.x, k.y]
		add_child(b)
		_bodies[k] = b
	return _bodies[k]


func add_box_collider(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size.abs().max(Vector3(0.05, 0.05, 0.05))
	cs.shape = bs
	cs.transform = xf.orthonormalized()
	_body_for(xf.origin).add_child(cs)


func add_cylinder_collider(pos: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	cs.shape = s
	cs.position = pos
	_body_for(pos).add_child(cs)


# ================================================================ vegetation
func scatter_vegetation() -> void:
	var R := U.make_rng(seed_value + 5)
	var trees := {
		"common": ["CommonTree_1", "CommonTree_2", "CommonTree_5", "CommonTree_3"], "pine": ["PineTree_1", "PineTree_2", "PineTree_3", "PineTree_4"],
		"birch": ["BirchTree_1", "BirchTree_2", "BirchTree_3"], "willow": ["Willow_1", "Willow_2"], "dead": ["CommonTree_Dead_1", "CommonTree_Dead_2"],
	}
	var step := 8.0 if quality == "low" else (6.8 if quality == "med" else 5.8)
	var x := -192.0
	while x < 192.0:
		var z := -192.0
		while z < 192.0:
			var px := x + R.randf_range(-2.2, 2.2)
			var pz := z + R.randf_range(-2.2, 2.2)
			z += step
			var r := sqrt(px * px + pz * pz)
			if r > 192.0:
				continue
			var dens := nz3.get_noise_2d(px * 0.013 + 3.0, pz * 0.013)
			var p: float
			if r < fence_r - 3.0:
				p = 0.05 if r > 16.0 else 0.0
			elif r < 72.0:
				p = 0.14
			else:
				p = 0.22 + 0.62 * U.smoothstep(-0.25, 0.35, dens)
			if r > 178.0:
				p *= 0.5
			if R.randf() >= p or not is_clear(px, pz, 3.0):
				continue
			var near_grave := Vector2(px, pz).distance_to(pois.grave) < 42.0
			var near_water := Vector2(px, pz).distance_to(Vector2(water.x, water.z)) < 30.0
			var kind := "common"
			if near_grave and R.randf() < 0.65:
				kind = "dead"
			elif near_water and R.randf() < 0.5:
				kind = "willow"
			elif r > 150.0 or nz2.get_noise_2d(px * 0.02, pz * 0.02) > 0.15:
				kind = "pine"
			elif R.randf() < 0.22:
				kind = "birch"
			var s := R.randf_range(2.3, 3.3)
			var tint := Color.from_hsv(R.randf_range(0.2, 0.32), R.randf_range(0.0, 0.25), R.randf_range(0.85, 1.05))
			props.add("nature", U.pick(R, trees[kind]), U.xf(Vector3(px, height_at(px, pz) - 0.15, pz), R.randf_range(0, TAU), Vector3(s, s * R.randf_range(0.9, 1.15), s)), tint)
			add_cylinder_collider(Vector3(px, height_at(px, pz) + 2.0, pz), 0.14 * s, 5.0)
		x += step
	# rocks
	for i in 300:
		var a := R.randf_range(0, TAU)
		var r := sqrt(R.randf()) * 120.0 + 68.0
		var px := sin(a) * r
		var pz := cos(a) * r
		if r > 190.0 or not is_clear(px, pz, 1.5):
			continue
		var big := r > 160.0 or R.randf() < 0.18
		var s := R.randf_range(2.2, 4.5) if big else R.randf_range(0.7, 1.6)
		var y := height_at(px, pz)
		props.add("nature", U.pick(R, ["Rock_Moss_1", "Rock_Moss_2", "Rock_Moss_3", "Rock_Moss_4", "Rock_Moss_5", "Rock_2", "Rock_3"]), U.xf(Vector3(px, y - 0.1 * s, pz), R.randf_range(0, 6), Vector3(s, s * R.randf_range(0.8, 1.2), s)))
		if s > 1.2:
			add_cylinder_collider(Vector3(px, y + s * 0.3, pz), s * 0.36, s * 0.8)
		rock_spots.append(Vector3(px, y, pz))
	# bushes, plants, flowers, logs
	var small := [["Bush_1", 1.1, 1.8], ["Bush_2", 1.1, 1.8], ["BushBerries_1", 1.0, 1.5], ["Plant_1", 1.0, 1.6], ["Plant_3", 0.9, 1.5], ["Plant_2", 0.7, 1.1]]
	for i in (350 if quality == "low" else 800):
		var a := R.randf_range(0, TAU)
		var r := R.randf_range(15.0, 182.0)
		var px := sin(a) * r
		var pz := cos(a) * r
		if not is_clear(px, pz, 1.0):
			continue
		var it: Array = U.pick(R, small)
		props.add("nature", it[0], U.xf(Vector3(px, height_at(px, pz) - 0.05, pz), R.randf_range(0, TAU), Vector3.ONE * R.randf_range(it[1], it[2])))
	for i in 70:
		var a := R.randf_range(0, TAU)
		var r := R.randf_range(70.0, 180.0)
		var px := sin(a) * r
		var pz := cos(a) * r
		if not is_clear(px, pz, 2.0):
			continue
		var log_ := R.randf() < 0.5
		var s := R.randf_range(1.4, 2.0)
		var y := height_at(px, pz)
		props.add("nature", "WoodLog_Moss" if log_ else "TreeStump_Moss", U.xf(Vector3(px, y - 0.05, pz), R.randf_range(0, TAU), Vector3.ONE * s))
		add_cylinder_collider(Vector3(px, y + 0.4, pz), 0.8 if log_ else 0.6, 0.9)
	for i in (250 if quality == "low" else 600):
		var a := R.randf_range(0, TAU)
		var r := R.randf_range(14.0, 110.0)
		var px := sin(a) * r
		var pz := cos(a) * r
		if not is_clear(px, pz, 0.5) or nz3.get_noise_2d(px * 0.05, pz * 0.05) < 0.05:
			continue
		props.add("nature", "Flowers", U.xf(Vector3(px, height_at(px, pz) - 0.03, pz), R.randf_range(0, TAU), Vector3.ONE * R.randf_range(0.7, 1.1)))
	_build_grass(R)


func _build_grass(R: RandomNumberGenerator) -> void:
	# one clump = 4 crossed blades, lit from above on both sides
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a := i / 4.0 * PI + R.randf_range(-0.2, 0.2)
		var o := Vector3(R.randf_range(-0.12, 0.12), 0, R.randf_range(-0.12, 0.12))
		var h := R.randf_range(0.35, 0.6)
		var w := Vector3(cos(a), 0, sin(a)) * 0.06
		var lean := R.randf_range(-0.08, 0.08)
		var p0 := o - w
		var p1 := o + w
		var p2 := o + Vector3(lean, h, lean)
		for tri in [[p0, p1, p2], [p1, p0, p2]]:
			for v in tri:
				var top: bool = v.y > 0.01
				st.set_color(Color(0.6, 0.82, 0.28) if top else Color(0.26, 0.44, 0.12))
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var blade := st.commit()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float wind_time = 0.0;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = sin(wind_time * 1.8 + wp.x * 0.3 + wp.z * 0.22) * 0.14 + sin(wind_time * 3.3 + wp.x * 0.9 + wp.z * 0.5) * 0.05;
	VERTEX.x += w * VERTEX.y * 1.6;
	VERTEX.z += w * VERTEX.y;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25, 0.35, 0.1);
}
"""
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = sh
	blade.surface_set_material(0, grass_mat)
	var count := 6000 if quality == "low" else (14000 if quality == "med" else 26000)
	var chunks := {}
	var tries := 0
	var placed := 0
	while placed < count and tries < count * 4:
		tries += 1
		var a := R.randf_range(0, TAU)
		var r := sqrt(R.randf()) * 125.0
		var px := sin(a) * r
		var pz := cos(a) * r
		if not is_clear(px, pz, 0.4) and not (Vector2(px, pz).distance_to(pois.grave) < 22.0 and R.randf() < 0.5):
			continue
		if Vector2(px, pz).distance_to(Vector2(water.x, water.z)) < water.r:
			continue
		if nz2.get_noise_2d(px * 0.08, pz * 0.08) < -0.35:
			continue
		var s := R.randf_range(0.7, 1.35)
		var ck := Vector2i(floori(px / 40.0), floori(pz / 40.0))
		if not chunks.has(ck):
			chunks[ck] = []
		chunks[ck].append({"xf": U.xf(Vector3(px, height_at(px, pz) - 0.02, pz), R.randf_range(0, TAU), Vector3(s, s * R.randf_range(0.8, 1.3), s)),
			"c": Color.from_hsv(R.randf_range(0.2, 0.28), R.randf_range(0.0, 0.3), R.randf_range(0.75, 1.1))})
		placed += 1
	var far := 45.0 if quality == "low" else (60.0 if quality == "med" else 80.0)
	for ck in chunks:
		var list: Array = chunks[ck]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = blade
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i].xf)
			mm.set_instance_color(i, list[i].c)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = far
		mmi.visibility_range_end_margin = 10.0
		add_child(mmi)


# ================================================================ sky & lights
func build_sky() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type sky;
uniform vec3 top_col : source_color;
uniform vec3 hor_col : source_color;
uniform vec3 sun_col : source_color;
uniform float stars = 0.0;
uniform float time = 0.0;
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453); }
float vnoise(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 1.0)), b = hash(vec3(i + vec2(1, 0), 1.0)), c = hash(vec3(i + vec2(0, 1), 1.0)), d = hash(vec3(i + vec2(1, 1), 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y); }
void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 col = y > 0.0 ? mix(hor_col, top_col, pow(clamp(y, 0.0, 1.0), 0.55)) : hor_col * mix(1.0, 0.55, clamp(-y * 3.0, 0.0, 1.0));
	vec3 sd = LIGHT0_DIRECTION;
	if (LIGHT0_ENABLED) {
		float s = max(dot(d, sd), 0.0);
		col += sun_col * (pow(s, 900.0) * 6.0 + pow(s, 14.0) * 0.35 + pow(s, 3.0) * 0.08);
		float m = max(dot(d, -sd), 0.0);
		col += vec3(0.8, 0.85, 1.0) * smoothstep(0.9993, 0.9996, m) * stars * 1.5;
	}
	if (!AT_CUBEMAP_PASS) {
		float h = hash(floor(d * 260.0));
		col += vec3(step(0.9972, h)) * stars * smoothstep(0.0, 0.2, y) * (0.6 + 0.4 * sin(time * 3.0 + h * 100.0));
	}
	if (y > 0.02) {
		vec2 cp = d.xz / (y + 0.15) * 1.6 + vec2(time * 0.01, 0.0);
		float c = vnoise(cp) * 0.6 + vnoise(cp * 2.3) * 0.3 + vnoise(cp * 5.1) * 0.1;
		c = smoothstep(0.55, 0.85, c) * smoothstep(0.02, 0.25, y);
		col = mix(col, mix(hor_col, vec3(1.0), 0.6 * (1.0 - stars)), c * 0.75);
	}
	COLOR = col;
}
"""
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 240.0
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	env.glow_enabled = quality != "low"
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	env.ssao_enabled = quality == "high"
	env.ssao_intensity = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = quality != "low"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0 if quality == "med" else 80.0
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.5
	add_child(sun)
	interior_light = _omni(Color("#ffc47a"), 14.0)
	lantern = _omni(Color("#ffb866"), 16.0)
	camp_light = _omni(Color("#ff8a3a"), 22.0)
	var cp: Vector2 = pois.camp
	camp_light.position = Vector3(cp.x, height_at(cp.x, cp.y) + 1.5, cp.y)


func _omni(c: Color, rng_: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = rng_
	l.omni_attenuation = 1.2
	l.light_energy = 0.0
	l.shadow_enabled = false
	add_child(l)
	return l


func building_at(x: float, z: float):
	for b in buildings:
		var inr: Dictionary = b.inner
		if x > inr.minX and x < inr.maxX and z > inr.minZ and z < inr.maxZ:
			return b
	return null


# ================================================================ per frame
func update(dt: float, hours: float, player_pos: Vector3) -> void:
	t += dt
	var a := (hours - 6.0) / 24.0 * TAU
	var sd := Vector3(cos(a) * 0.9, sin(a), 0.42).normalized()
	var day := U.smoothstep(-0.15, 0.25, sd.y)
	var dusk := maxf(0.0, 1.0 - absf(sd.y) * 4.5) * U.smoothstep(-0.25, 0.0, sd.y)
	var top := Color("#070b1c").lerp(Color("#3d7bd0"), day)
	var hor := Color("#121a30").lerp(Color("#b9d6ef"), day).lerp(Color("#ff9a5c"), dusk * 0.75)
	sky_mat.set_shader_parameter("top_col", top)
	sky_mat.set_shader_parameter("hor_col", hor)
	sky_mat.set_shader_parameter("sun_col", Color("#fff3d6").lerp(Color("#ff8a40"), dusk))
	sky_mat.set_shader_parameter("stars", 1.0 - U.smoothstep(-0.2, 0.05, sd.y))
	sky_mat.set_shader_parameter("time", t)
	env.fog_light_color = hor
	var is_day := sd.y > -0.05
	var L := sd if is_day else -sd
	L.y = maxf(0.15, L.y)
	sun.look_at_from_position(Vector3.ZERO, -L, Vector3.UP if absf(L.normalized().y) < 0.99 else Vector3.FORWARD)
	sun.light_energy = (1.35 * U.smoothstep(-0.05, 0.25, sd.y)) if is_day else (0.18 * U.smoothstep(-0.05, -0.3, sd.y))
	sun.light_color = (Color("#fff0d8") if is_day else Color("#9fb4ff")).lerp(Color("#ffa060"), dusk if is_day else 0.0)
	env.ambient_light_energy = 0.35 + 0.65 * day
	env.background_energy_multiplier = 1.0
	night = 1.0 - day
	mats.window.set_shader_parameter("night", U.smoothstep(0.35, 0.8, night))
	var b = building_at(player_pos.x, player_pos.z)
	if b:
		interior_light.position = b.light_pos
		interior_light.light_energy = 1.4 + sin(t * 9.0) * 0.08
		interior_light.omni_range = maxf(b.w, b.d) * 1.4
	else:
		interior_light.light_energy = 0.0
	inside = b
	lantern.position = player_pos + Vector3(0, 1.9, 0)
	lantern.light_energy = 0.0 if b else 1.2 * U.smoothstep(0.4, 0.8, night)
	camp_light.light_energy = 2.2 + sin(t * 11.0) * 0.35 + sin(t * 7.3) * 0.3
	if grass_mat:
		grass_mat.set_shader_parameter("wind_time", t)
	if water_mat:
		water_mat.uv1_offset = Vector3(t * 0.02, t * 0.013, 0)
	for f in animated:
		f.call(dt, t)
