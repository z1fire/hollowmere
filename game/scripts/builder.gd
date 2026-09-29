class_name Builder
extends RefCounted
## Places geometry in a local frame (building / furniture space) and registers colliders.

var w: World
var b: MeshBatch
var t: Transform3D


func _init(world: World, batch: MeshBatch, xf: Transform3D) -> void:
	w = world
	b = batch
	t = xf


static func at(world: World, batch: MeshBatch, x: float, y: float, z: float, ang := 0.0) -> Builder:
	return Builder.new(world, batch, Transform3D(Basis(Vector3.UP, ang), Vector3(x, y, z)))


func sub(x: float, z: float, ry := 0.0, y := 0.0) -> Builder:
	return Builder.new(w, b, t * Transform3D(Basis(Vector3.UP, ry), Vector3(x, y, z)))


func P(lx: float, lz: float, ly := 0.0) -> Vector3:
	return t * Vector3(lx, ly, lz)


var y: float:
	get:
		return t.origin.y


var ang: float:
	get:
		var zb := t.basis.z
		return atan2(zb.x, zb.z)


func box(key: String, lx: float, ly: float, lz: float, sx: float, sy: float, sz: float, color = null, col := true, ry := 0.0) -> void:
	b.add_box(key, t * U.xf(Vector3(lx, ly, lz), ry, Vector3(sx, sy, sz)), color)
	if col:
		col_box(lx, lz, sx, sz, ly - sy / 2.0, ly + sy / 2.0, ry)


func col_box(lx: float, lz: float, sx: float, sz: float, y0: float, y1: float, ry := 0.0) -> void:
	w.add_box_collider(t * U.xf(Vector3(lx, (y0 + y1) / 2.0, lz), ry), Vector3(sx, y1 - y0, sz))


func cyl(key: String, lx: float, ly: float, lz: float, r: float, h: float, color = null, col := true, seg := 10, rt := -1.0) -> void:
	b.add_arrays(key, MeshBatch.prim("cyl", rt if rt >= 0.0 else r, r, h, seg), t * U.xf(Vector3(lx, ly, lz)), color)
	if col:
		w.add_cylinder_collider(t * Vector3(lx, ly, lz), maxf(r, rt), h)


## primitive: ["cyl", top_r, bottom_r, h, seg] | ["sphere", r, 0, 0, seg] | ["prism", width, depth, h]
func geo(key: String, prim: Array, lx: float, ly: float, lz: float, ry := 0.0, color = null, s := Vector3.ONE, rx := 0.0, rz := 0.0) -> void:
	var arr := MeshBatch.prim(prim[0], prim[1], prim[2] if prim.size() > 2 else 1.0, prim[3] if prim.size() > 3 else 1.0, prim[4] if prim.size() > 4 else 10)
	b.add_arrays(key, arr, t * U.xf(Vector3(lx, ly, lz), ry, s, rx, rz), color)


## place a model prop in this local frame, with a collider from its bounding box
func prop(bundle: String, name: String, lx: float, ly: float, lz: float, ry := 0.0, s := 1.0, opts := {}) -> void:
	var sc := Vector3(opts.get("sx", s), opts.get("sy", s), opts.get("sz", s))
	var xf := t * U.xf(Vector3(lx, ly, lz), ry, sc)
	w.props.add(bundle, name, xf, opts.get("tint", null))
	if opts.get("collide", true):
		var box := Assets.aabb(bundle, name)
		var size := box.size * sc
		var centre := box.get_center() * sc
		var shrink: float = opts.get("shrink", 0.9)
		var cxf := xf.orthonormalized() * Transform3D(Basis.IDENTITY, centre)
		w.add_box_collider(cxf, Vector3(size.x * shrink, maxf(0.3, size.y), size.z * shrink))
