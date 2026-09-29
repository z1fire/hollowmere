class_name Actor
extends Node3D
## Animated character built from the KayKit (shared rig) or Quaternius models.

const KAY_ANIMS := {
	"idle": "Idle", "walk": "Walking_A", "run": "Running_A", "attack": "1H_Melee_Attack_Chop", "attack2": "1H_Melee_Attack_Slice_Diagonal",
	"stab": "1H_Melee_Attack_Stab", "heavy": "2H_Melee_Attack_Chop", "shoot": "2H_Ranged_Shoot", "cast": "Spellcast_Shoot", "hit": "Hit_A",
	"death": "Death_A", "sit": "Sit_Chair_Idle", "talk": "Interact", "cheer": "Cheer", "use": "Use_Item",
}
const SKELETON_ANIMS := {"walk": "Walking_C", "run": "Running_C", "death": "Death_C_Skeletons", "idle": "Idle_Combat"}
const KINDS := {
	"knight": {"file": "knight", "rig": "kaykit", "scale": 0.95}, "barbarian": {"file": "barbarian", "rig": "kaykit", "scale": 0.95},
	"mage": {"file": "mage", "rig": "kaykit", "scale": 0.95}, "rogue": {"file": "rogue", "rig": "kaykit", "scale": 0.95},
	"rogue_hooded": {"file": "rogue_hooded", "rig": "kaykit", "scale": 0.95},
	"skeleton_minion": {"file": "skeleton_minion", "rig": "kaykit", "scale": 0.95, "anims": SKELETON_ANIMS},
	"skeleton_warrior": {"file": "skeleton_warrior", "rig": "kaykit", "scale": 0.98, "anims": SKELETON_ANIMS},
	"skeleton_rogue": {"file": "skeleton_rogue", "rig": "kaykit", "scale": 0.95, "anims": SKELETON_ANIMS},
	"skeleton_mage": {"file": "skeleton_mage", "rig": "kaykit", "scale": 0.95, "anims": SKELETON_ANIMS},
	"orc": {"file": "orc", "rig": "orc", "scale": 0.42, "anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "Weapon", "attack2": "Punch", "hit": "HitReact", "death": "Death", "talk": "Wave", "shoot": "Weapon"}},
	"wolf": {"file": "wolf", "rig": "wolf", "scale": 0.32, "anims": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "attack": "Attack", "hit": "Idle_HitReact_Left", "death": "Death"}},
	"spider": {"file": "spider", "rig": "spider", "scale": 0.26, "anims": {"idle": "Spider_Idle", "walk": "Spider_Walk", "run": "Spider_Walk", "attack": "Spider_Attack", "death": "Spider_Death"}},
}

static var _recolor_cache := {}
static var _merged := {}

var kind := ""
var def := {}
var model: Node3D
var anim: AnimationPlayer
var materials: Array = []
var base_anim := ""
var one_shot := ""
var dead := false


## opts: show (Array of accessory mesh names), right/left (weapon prop names), hue/sat/light (clothing re-dye), scale, own_materials
func setup(p_kind: String, opts := {}) -> Actor:
	kind = p_kind
	def = KINDS[p_kind]
	model = (Assets.chars[def.file] as PackedScene).instantiate()
	model.scale = Vector3.ONE * def.scale * opts.get("scale", 1.0)
	add_child(model)
	if def.rig == "kaykit":
		_merge_body()
	var show: Array = opts.get("show", [])
	var recolor: bool = opts.has("hue") or opts.has("sat") or opts.has("light")
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if def.rig == "kaykit" and mi.get_parent() is BoneAttachment3D:
			mi.visible = mi.name in show
			if not mi.visible:
				continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat == null:
				continue
			if recolor and mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
				mat = mat.duplicate()
				mat.albedo_texture = _recolor((mat as BaseMaterial3D).albedo_texture, opts.get("hue", 0.0), opts.get("sat", 1.0), opts.get("light", 1.0))
				mi.set_surface_override_material(s, mat)
			elif opts.get("own_materials", false):
				mat = mat.duplicate()
				mi.set_surface_override_material(s, mat)
			materials.append(mat)
	for side in ["right", "left"]:
		if opts.has(side):
			var slot: Node = model.find_child("handslot_r" if side == "right" else "handslot_l", true, false)
			if slot:
				var w: Node3D = Assets.node("weapons", opts[side]).duplicate()
				w.transform = Transform3D.IDENTITY
				slot.add_child(w)
				for m in w.find_children("*", "MeshInstance3D", true, false):
					if opts.get("own_materials", false):
						var mm: Material = (m as MeshInstance3D).get_active_material(0)
						if mm:
							mm = mm.duplicate()
							(m as MeshInstance3D).set_surface_override_material(0, mm)
							materials.append(mm)
	anim = model.find_child("AnimationPlayer", true, false)
	if def.rig == "kaykit":
		if anim == null:
			anim = AnimationPlayer.new()
			model.add_child(anim)
		if not anim.has_animation_library(&""):
			anim.add_animation_library(&"", Assets.kaykit_anims)
	elif anim:
		for n in anim.get_animation_list():
			if n in ["Idle", "Walk", "Run", "Gallop", "Spider_Idle", "Spider_Walk"]:
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if anim:
		anim.animation_finished.connect(_on_finished)
	set_base("idle")
	return self


func clip(n: String) -> String:
	var map: Dictionary = def.get("anims", {})
	var name: String = map.get(n, KAY_ANIMS.get(n, n) if def.rig == "kaykit" else n)
	return name if anim and anim.has_animation(name) else ""


func set_base(n: String, speed := 1.0) -> void:
	var c := clip(n)
	if c == "":
		c = clip("idle")
	if c == "":
		return
	anim.speed_scale = speed if one_shot == "" else anim.speed_scale
	if c == base_anim:
		return
	base_anim = c
	if one_shot == "" and not dead:
		anim.play(c, 0.25)


## locomotion from speed in m/s
func move(speed: float) -> void:
	if dead or one_shot != "":
		return
	if speed < 0.2:
		set_base("idle")
	elif speed < 3.2:
		set_base("walk")
		anim.speed_scale = maxf(0.6, speed / 1.8)
	else:
		set_base("run")
		anim.speed_scale = maxf(0.7, speed / 5.0)


func play(n: String, speed := 1.0) -> float:
	var c := clip(n)
	if c == "":
		return 0.0
	one_shot = c
	anim.play(c, 0.1)
	anim.seek(0.0, true)
	anim.speed_scale = speed
	return anim.get_animation(c).length / speed


func _on_finished(n: StringName) -> void:
	if String(n) == one_shot:
		one_shot = ""
		if not dead and base_anim != "":
			anim.speed_scale = 1.0
			anim.play(base_anim, 0.2)


func die() -> void:
	dead = true
	play("death")


func revive() -> void:
	dead = false
	one_shot = ""
	base_anim = ""
	set_base("idle")


func flash(v: float) -> void:
	for m in materials:
		if m is BaseMaterial3D:
			(m as BaseMaterial3D).emission_enabled = v > 0.0
			(m as BaseMaterial3D).emission = Color(v, v * 0.15, v * 0.1)


## KayKit characters are 6+ skinned parts sharing one skin and texture: merge them into a single
## mesh (one draw call per character instead of 6-8, which matters a lot on phones).
func _merge_body() -> void:
	var skel: Skeleton3D = model.find_child("Skeleton3D", true, false)
	if skel == null:
		return
	var parts: Array = []
	for c in skel.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).skin != null:
			parts.append(c)
	if parts.size() < 2:
		return
	var skin: Skin = parts[0].skin
	for p in parts:
		if p.skin != skin:
			return
	var mesh: ArrayMesh = _merged.get(def.file)
	if mesh == null:
		var groups := {}
		var mats := {}
		for p in parts:
			var m: Mesh = p.mesh
			for si in m.get_surface_count():
				var mat: Material = p.get_active_material(si)
				var key := mat.get_instance_id() if mat else 0
				mats[key] = mat
				var a: Array = m.surface_get_arrays(si)
				if not groups.has(key):
					groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()}
				var g: Dictionary = groups[key]
				var base: int = g.v.size()
				g.v.append_array(a[Mesh.ARRAY_VERTEX])
				g.n.append_array(a[Mesh.ARRAY_NORMAL])
				g.uv.append_array(a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array())
				g.b.append_array(a[Mesh.ARRAY_BONES])
				g.w.append_array(a[Mesh.ARRAY_WEIGHTS])
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				for k in idx.size():
					g.i.append(idx[k] + base)
		mesh = ArrayMesh.new()
		for key in groups:
			var g: Dictionary = groups[key]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = g.v
			arr[Mesh.ARRAY_NORMAL] = g.n
			if g.uv.size() == g.v.size():
				arr[Mesh.ARRAY_TEX_UV] = g.uv
			arr[Mesh.ARRAY_BONES] = g.b
			arr[Mesh.ARRAY_WEIGHTS] = g.w
			arr[Mesh.ARRAY_INDEX] = g.i
			var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if g.w.size() == g.v.size() * 8 else 0
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[key])
		_merged[def.file] = mesh
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.skin = skin
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	for p in parts:
		skel.remove_child(p)
		p.queue_free()


## Re-dye clothing (keeps skin, hair, leather and greys) for villager variety.
static func _recolor(tex: Texture2D, hue: float, sat: float, light: float) -> Texture2D:
	var key := "%d|%s|%s|%s" % [tex.get_instance_id(), hue, sat, light]
	if _recolor_cache.has(key):
		return _recolor_cache[key]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(mini(256, img.get_width()), mini(256, img.get_height()), Image.INTERPOLATE_NEAREST)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var s := c.s
			var h := c.h
			if s < 0.12 or ((h < 0.15 or h > 0.97) and s < 0.9):
				continue
			img.set_pixel(x, y, Color.from_hsv(fposmod(h + hue, 1.0), clampf(s * sat, 0, 1), clampf(c.v * light, 0, 1), c.a))
	var t := ImageTexture.create_from_image(img)
	_recolor_cache[key] = t
	return t
