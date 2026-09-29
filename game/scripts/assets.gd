class_name Assets
extends RefCounted
## Loads the 3D models / textures / fonts (see tools/build-assets.mjs and assets/CREDITS.txt)
## and provides helpers to extract prop meshes for batched rendering.

const BUNDLES := ["weapons", "dungeon", "furniture", "halloween", "nature", "crops", "village"]
const CHARS := ["knight", "barbarian", "mage", "rogue", "rogue_hooded", "skeleton_minion", "skeleton_warrior", "skeleton_rogue", "skeleton_mage", "wolf", "orc", "spider", "anims"]
const TEX := ["plaster", "stone", "planks", "floor", "beam", "thatch", "tiles", "cobble", "grass", "dirt", "rock", "forest"]
## per-pack scale so everything is in meters
const PACK_SCALE := {"dungeon": 0.72, "furniture": 0.62, "halloween": 0.72, "weapons": 1.0, "nature": 1.0, "crops": 1.0, "village": 1.0}

static var bundles := {}      # name -> Node3D template (never added to the tree)
static var chars := {}        # name -> PackedScene
static var tex := {}          # name -> {albedo, normal, rough}
static var kaykit_anims: AnimationLibrary
static var fonts := {}
static var loaded := false
static var _parts := {}
static var _aabbs := {}


static func load_all(host: Node, progress: Callable) -> void:
	if loaded:
		return
	var jobs: Array = []
	for b in BUNDLES:
		jobs.append(["b", b, "res://assets/props/%s.glb" % b])
	for c in CHARS:
		jobs.append(["c", c, "res://assets/chars/%s.glb" % c])
	for t in TEX:
		for suffix in ["d", "n", "r"]:
			jobs.append(["t", t + "_" + suffix, "res://assets/tex/%s_%s.jpg" % [t, suffix]])
	var done := 0
	for j in jobs:
		ResourceLoader.load_threaded_request(j[2])
	for j in jobs:
		var res = ResourceLoader.load_threaded_get(j[2])
		match j[0]:
			"b":
				bundles[j[1]] = (res as PackedScene).instantiate()
			"c":
				chars[j[1]] = res
			"t":
				var parts: PackedStringArray = j[1].rsplit("_", true, 1)
				if not tex.has(parts[0]):
					tex[parts[0]] = {}
				tex[parts[0]][{"d": "albedo", "n": "normal", "r": "rough"}[parts[1]]] = res
		done += 1
		progress.call(float(done) / jobs.size())
		await host.get_tree().process_frame
	# one shared animation library drives every KayKit character (they share a rig)
	var anim_root: Node = chars.anims.instantiate()
	var ap: AnimationPlayer = anim_root.find_child("AnimationPlayer", true, false)
	kaykit_anims = ap.get_animation_library(&"").duplicate(true)
	anim_root.free()
	for loop_name in ["Idle", "Unarmed_Idle", "Idle_Combat", "Walking_A", "Walking_B", "Walking_C", "Running_A", "Running_B", "Running_C", "Sit_Chair_Idle", "Lie_Idle"]:
		if kaykit_anims.has_animation(loop_name):
			kaykit_anims.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
	for f in ["Cinzel", "AlegreyaSans-Regular", "AlegreyaSans-Bold", "Emoji"]:
		fonts[f] = load("res://assets/fonts/%s.ttf" % f)
	loaded = true


static func node(bundle: String, name: String) -> Node3D:
	var n: Node3D = bundles[bundle].get_node_or_null(NodePath("P_" + name))
	assert(n != null, "asset %s/%s missing" % [bundle, name])
	return n


static func has_prop(bundle: String, name: String) -> bool:
	return bundles.has(bundle) and bundles[bundle].get_node_or_null(NodePath("P_" + name)) != null


## Deep copy of a prop (for things that move / change, like chests).
static func instance(bundle: String, name: String) -> Node3D:
	var root := Node3D.new()
	var copy: Node3D = node(bundle, name).duplicate()
	copy.transform = Transform3D.IDENTITY
	copy.scale = Vector3.ONE * PACK_SCALE.get(bundle, 1.0)
	root.add_child(copy)
	for m in copy.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root


## Mesh parts of a prop with their transform relative to the prop origin (pack scale included).
static func parts(bundle: String, name: String) -> Array:
	var key := bundle + "/" + name
	if _parts.has(key):
		return _parts[key]
	var root := node(bundle, name)
	var s: float = PACK_SCALE.get(bundle, 1.0)
	var out: Array = []
	_collect(root, Transform3D.IDENTITY, out)
	for p in out:
		p.xform = Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO) * p.xform
	_parts[key] = out
	return out


static func _collect(n: Node, parent_xf: Transform3D, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D:
			var xf: Transform3D = parent_xf * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				out.append({"mesh": (c as MeshInstance3D).mesh, "xform": xf})
			_collect(c, xf, out)


## Local bounding box of a prop (meters, unrotated).
static func aabb(bundle: String, name: String) -> AABB:
	var key := bundle + "/" + name
	if _aabbs.has(key):
		return _aabbs[key]
	var box := AABB()
	var first := true
	for p in parts(bundle, name):
		var b: AABB = p.xform * (p.mesh as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	_aabbs[key] = box
	return box


## A StandardMaterial3D using one of the PBR texture sets.
static func pbr(set_name: String, uv_scale: float = 1.0, extra := {}) -> StandardMaterial3D:
	var t: Dictionary = tex[set_name]
	var m := StandardMaterial3D.new()
	m.albedo_texture = t.albedo
	m.normal_enabled = true
	m.normal_texture = t.normal
	m.normal_scale = 0.8
	m.roughness_texture = t.rough
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.set_meta("uv_scale", uv_scale)
	for k in extra:
		m.set(k, extra[k])
	return m
