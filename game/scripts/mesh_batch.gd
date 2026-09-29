class_name MeshBatch
extends RefCounted
## Collects boxes / primitive meshes per material into a single ArrayMesh (one draw call per material).
## Textured materials get world-space box-projected UVs so textures tile evenly at any size.

var groups := {}
static var _prim_cache := {}

const _FACES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]


func _g(key: String) -> Dictionary:
	if not groups.has(key):
		groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	return groups[key]


static func col(c) -> Color:
	if c is Color:
		return c
	if c == null:
		return Color.WHITE
	return Color(c)


## unit box (1x1x1, centred) transformed by xf
func add_box(key: String, xf: Transform3D, color) -> void:
	var g := _g(key)
	var c := col(color)
	var nb := xf.basis.inverse().transposed()
	for f in _FACES:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var base: int = g.v.size()
		var wn := (nb * n).normalized()
		for k in 4:
			var su := -0.5 if (k == 0 or k == 3) else 0.5
			var sv := -0.5 if k < 2 else 0.5
			g.v.append(xf * (n * 0.5 + u * su + v * sv))
			g.n.append(wn)
			g.uv.append(Vector2(su + 0.5, 0.5 - sv))
			g.c.append(c)
		g.i.append_array([base, base + 2, base + 1, base, base + 3, base + 2])  # clockwise = front in Godot


## any mesh arrays (from a PrimitiveMesh etc.)
func add_arrays(key: String, arrays: Array, xf: Transform3D, color) -> void:
	var g := _g(key)
	var c := col(color)
	var nb := xf.basis.inverse().transposed()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var base: int = g.v.size()
	for k in verts.size():
		g.v.append(xf * verts[k])
		g.n.append((nb * norms[k]).normalized())
		g.uv.append(uvs[k] if uvs != null and k < uvs.size() else Vector2.ZERO)
		g.c.append(c)
	if idx == null or idx.size() == 0:
		for k in verts.size():
			g.i.append(base + k)
	else:
		# Godot primitives use clockwise front faces; keep their winding as-is
		for k in idx.size():
			g.i.append(base + idx[k])


## cached PrimitiveMesh arrays: kind = "cyl" | "sphere" | "prism"
static func prim(kind: String, a: float = 1.0, b: float = 1.0, h: float = 1.0, seg: int = 10) -> Array:
	var key := "%s|%s|%s|%s|%s" % [kind, a, b, h, seg]
	if _prim_cache.has(key):
		return _prim_cache[key]
	var m: PrimitiveMesh
	match kind:
		"cyl":
			var cm := CylinderMesh.new()
			cm.top_radius = a
			cm.bottom_radius = b
			cm.height = h
			cm.radial_segments = seg
			cm.rings = 1
			m = cm
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = a
			sm.height = a * 2.0
			sm.radial_segments = seg
			sm.rings = maxi(3, seg / 2)
			m = sm
		"prism":
			var pm := PrismMesh.new()
			pm.size = Vector3(a, h, b)
			m = pm
	var arr := m.get_mesh_arrays()
	_prim_cache[key] = arr
	return arr


func build(materials: Dictionary, cast_shadows := true) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var mat_list: Array = []
	for key in groups:
		var g: Dictionary = groups[key]
		if g.v.size() == 0:
			continue
		var mat: Material = materials[key]
		var uvs: PackedVector2Array = g.uv
		if mat.has_meta("uv_scale"):
			var s: float = mat.get_meta("uv_scale")
			uvs = PackedVector2Array()
			uvs.resize(g.v.size())
			for k in g.v.size():
				var p: Vector3 = g.v[k]
				var n: Vector3 = g.n[k]
				var ax := absf(n.x)
				var ay := absf(n.y)
				var az := absf(n.z)
				if ay >= ax and ay >= az:
					uvs[k] = Vector2(p.x / s, p.z / s)
				elif ax >= az:
					uvs[k] = Vector2(p.z / s, -p.y / s)
				else:
					uvs[k] = Vector2(p.x / s, -p.y / s)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = g.c
		arrays[Mesh.ARRAY_INDEX] = g.i
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).normal_enabled:
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays)
			st.generate_tangents()
			arrays = st.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	groups.clear()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
