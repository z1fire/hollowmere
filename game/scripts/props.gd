class_name PropField
extends RefCounted
## Collects static prop placements and renders them as spatially-chunked MultiMeshes
## (few draw calls, per-chunk culling + distance fade, Godot's automatic mesh LODs).

const CHUNK := 96.0
var items := {}
static var _tinted := {}


func add(bundle: String, name: String, xf: Transform3D, tint = null) -> void:
	var key := bundle + "/" + name
	if not items.has(key):
		items[key] = []
	items[key].append({"xf": xf, "tint": tint})


func _tinted_mesh(mesh: Mesh) -> Mesh:
	if _tinted.has(mesh):
		return _tinted[mesh]
	var m: Mesh = mesh.duplicate()
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		if mat is BaseMaterial3D:
			var mm: BaseMaterial3D = mat.duplicate()
			mm.vertex_color_use_as_albedo = true
			m.surface_set_material(s, mm)
	_tinted[mesh] = m
	return m


func build(parent: Node3D, quality: String) -> void:
	var far_mul := 1.0 if quality == "high" else (0.8 if quality == "med" else 0.6)
	var merged := {}
	for key in items:
		var bn: PackedStringArray = key.split("/")
		var parts := Assets.parts(bn[0], bn[1])
		var size := Assets.aabb(bn[0], bn[1]).size.length()
		var chunks := {}
		for it in items[key]:
			var o: Vector3 = it.xf.origin
			var ck := Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK))
			if not chunks.has(ck):
				chunks[ck] = []
			chunks[ck].append(it)
		for ck in chunks:
			var list: Array = chunks[ck]
			# props placed only a few times per area are merged into one mesh per material (see below)
			var is_tree: bool = bn[1].contains("Tree") or bn[1].begins_with("Willow")
			if list.size() < 8 and not is_tree:
				if not merged.has(ck):
					merged[ck] = {"batch": MeshBatch.new(), "mats": {}}
				var mb: Dictionary = merged[ck]
				for it in list:
					for p in parts:
						var mesh: Mesh = p.mesh
						for si in mesh.get_surface_count():
							var mat := mesh.surface_get_material(si)
							var mkey := str(mat.get_instance_id()) if mat else "none"
							mb.mats[mkey] = mat if mat else StandardMaterial3D.new()
							mb.batch.add_arrays(mkey, mesh.surface_get_arrays(si), it.xf * p.xform, Color.WHITE)
				continue
			var tinted: bool = list.any(func(i): return i.tint != null)
			var inst_scale: float = (list[0].xf as Transform3D).basis.get_scale().x
			var world_size := size * inst_scale
			for p in parts:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = tinted
				mm.mesh = _tinted_mesh(p.mesh) if tinted else p.mesh
				mm.instance_count = list.size()
				for i in list.size():
					mm.set_instance_transform(i, list[i].xf * p.xform)
					if tinted:
						mm.set_instance_color(i, list[i].tint if list[i].tint != null else Color.WHITE)
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				# small things fade out at a distance; big things (trees, houses) stay visible into the fog
				if world_size < 1.5:
					mmi.visibility_range_end = 55.0 * far_mul
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				elif world_size < 4.0:
					mmi.visibility_range_end = 110.0 * far_mul
				mmi.visibility_range_end_margin = 8.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if quality != "low" else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				parent.add_child(mmi)
	for ck in merged:
		var mi: MeshInstance3D = merged[ck].batch.build(merged[ck].mats)
		mi.visibility_range_end = 150.0 * far_mul
		if quality != "high":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end_margin = 10.0
		parent.add_child(mi)
	items.clear()
