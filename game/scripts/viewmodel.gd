class_name Viewmodel
extends Node3D
## First-person held item. Everything lives at 1/10 scale right in front of the camera,
## so it can never clip into walls (the camera's near plane is 2 cm).

var player
var model: Node3D
var base := [0.25, -0.4, -0.5, 0.0, 0.0, 0.0]
var anim_type := ""
var anim_t := 0.0
var anim_dur := 0.3
var t := 0.0
var sway := Vector2.ZERO
var last_yaw := 0.0
var last_pitch := 0.0
var equip_t := 0.0
var orb: Node3D
var arrow: Node3D
var kind := ""


func setup(p) -> void:
	player = p
	scale = Vector3.ONE * 0.1


func _mat(c: String, metal := 0.0, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c)
	m.metallic = metal
	m.roughness = rough
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _held(bundle: String, name: String, tint = null) -> Node3D:
	var n: Node3D = Assets.node(bundle, name).duplicate()
	n.transform = Transform3D.IDENTITY
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if tint != null:
			for s in mi.mesh.get_surface_count():
				var mat = mi.get_active_material(s)
				if mat is BaseMaterial3D:
					var mm: BaseMaterial3D = mat.duplicate()
					mm.albedo_color *= Color(tint)
					mi.set_surface_override_material(s, mm)
	return n


func set_item(item: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	orb = null
	arrow = null
	model = Node3D.new()
	add_child(model)
	kind = "fists" if item.is_empty() else item.get("vm", item.kind)
	var glove := _mat("#6a4a30", 0.0, 0.6)
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.038
	hand_mesh.height = 0.07
	var add_hand := func(p: Vector3) -> void:
		var h := _mesh(hand_mesh, glove, p)
		h.scale = Vector3(1, 0.9, 1.25)
		model.add_child(h)
	match kind:
		"sword", "axe":
			var names := {"knight_blade": "sword_2handed", "war_axe": "axe_2handed"}
			var name: String = names.get(item.id, "axe_1handed" if kind == "axe" else "sword_1handed")
			var tint = "#b89878" if item.id == "rusty_sword" else ("#ffe6a0" if item.id == "knight_blade" else null)
			var w := _held("weapons", name, tint)
			w.scale = Vector3.ONE * (0.17 if name.contains("2handed") else 0.2)
			w.rotation.x = -0.35
			model.add_child(w)
			add_hand.call(Vector3(0, 0, 0.02))
			base = [0.36, -0.38, -0.62, 0.1, 0.0, -0.3]
		"pitchfork", "hoe":
			var wood := _mat("#7a5634")
			var metal := _mat("#c8ccd0", 0.7, 0.3)
			var s := Node3D.new()
			var shaft := CylinderMesh.new()
			shaft.top_radius = 0.018
			shaft.bottom_radius = 0.018
			shaft.height = 1.7
			shaft.radial_segments = 8
			s.add_child(_mesh(shaft, wood, Vector3(0, 0.35, 0)))
			if kind == "pitchfork":
				var bar := BoxMesh.new()
				bar.size = Vector3(0.22, 0.03, 0.03)
				s.add_child(_mesh(bar, metal, Vector3(0, 1.2, 0)))
				var tine := CylinderMesh.new()
				tine.top_radius = 0.008
				tine.bottom_radius = 0.012
				tine.height = 0.3
				tine.radial_segments = 5
				for x in [-0.1, 0.0, 0.1]:
					s.add_child(_mesh(tine, metal, Vector3(x, 1.35, 0)))
			else:
				var blade := BoxMesh.new()
				blade.size = Vector3(0.14, 0.02, 0.11)
				s.add_child(_mesh(blade, _mat("#8a8a8a", 0.5, 0.5), Vector3(0, 1.2, 0.05)))
			s.rotation.x = -1.2
			model.add_child(s)
			add_hand.call(Vector3(0, 0, 0.02))
			add_hand.call(Vector3(-0.05, 0.25, -0.35))
			base = [0.3, -0.4, -0.5, 0.0, 0.15, -0.1]
		"bow":
			var w := _held("village", "Bow_Golden" if item.id == "longbow" else "Bow_Wooden", "#c8a888" if item.id == "short_bow" else null)
			w.scale = Vector3.ONE * 0.24
			w.rotation = Vector3(0, PI / 2, 0.18)
			model.add_child(w)
			arrow = _held("weapons", "arrow")
			arrow.scale = Vector3.ONE * 0.45
			arrow.rotation = Vector3(-PI / 2, 0, 0)
			arrow.position = Vector3(0, 0, -0.05)
			model.add_child(arrow)
			add_hand.call(Vector3(0, -0.02, 0.05))
			base = [0.2, -0.26, -0.6, 0.0, 0.0, 0.0]
		"tome":
			var tint: String = {"nature": "#9aff9a", "heal": "#a0ffe0", "spark": "#a8c0ff", "fire": "#ffb0a0"}[item.school]
			var glow: String = {"nature": "#8aff6a", "heal": "#8affc0", "spark": "#9ac8ff", "fire": "#ffa040"}[item.school]
			var b := _held("weapons", "spellbook_open", tint)
			b.scale = Vector3.ONE * 0.26
			b.position = Vector3(-0.34, -0.04, 0.0)
			b.rotation = Vector3(-0.5, 0.35, 0.15)
			model.add_child(b)
			var om := StandardMaterial3D.new()
			om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			om.albedo_color = Color(glow) * 2.5
			var sm := SphereMesh.new()
			sm.radius = 0.035
			sm.height = 0.07
			orb = _mesh(sm, om, Vector3(0, 0.1, -0.05))
			model.add_child(orb)
			add_hand.call(Vector3(0, 0, 0.02))
			add_hand.call(Vector3(-0.34, -0.08, 0.08))
			base = [0.26, -0.36, -0.55, 0.0, 0.0, 0.0]
		"seed", "crop", "consumable", "material":
			var m: Node3D
			var id: String = item.id
			if kind == "consumable" and id.contains("potion"):
				m = _held("village", "Potion1_Filled" if id == "hp_potion" else "Potion4_Filled")
				m.scale = Vector3.ONE * 0.16
			elif kind == "seed":
				m = _held("village", "Bag")
				m.scale = Vector3.ONE * 0.9
			elif id in ["wheat", "carrot", "pumpkin"]:
				m = _held("crops", {"wheat": "Wheat_4", "carrot": "Carrot_4", "pumpkin": "Pumpkin_4"}[id])
				m.scale = Vector3.ONE * (0.18 if id == "pumpkin" else 0.3)
			else:
				var sm := SphereMesh.new()
				sm.radius = 0.07
				sm.height = 0.14
				m = _mesh(sm, _mat("#d8b860"), Vector3.ZERO)
			m.position = Vector3(0, 0.08, -0.02)
			model.add_child(m)
			add_hand.call(Vector3(0, 0, 0.02))
			base = [0.3, -0.36, -0.5, 0.2, 0.0, 0.0]
		_:
			add_hand.call(Vector3(0, 0, 0.02))
			add_hand.call(Vector3(-0.45, -0.05, 0.05))
			base = [0.25, -0.4, -0.5, 0.0, 0.0, 0.0]
	equip_t = 0.25
	_apply()


func swing(type: String) -> void:
	anim_type = type
	anim_t = 0.0
	anim_dur = 0.35 if type in ["bow", "cast", "thrust"] else 0.32


func _apply() -> void:
	if model == null:
		return
	model.position = Vector3(base[0] + sway.x, base[1] + sway.y - equip_t * 1.2, base[2])
	model.rotation = Vector3(base[3], base[4], base[5])
	if anim_type == "":
		return
	var k := anim_t / anim_dur
	var s := sin(k * PI)
	match anim_type:
		"slash", "chop":
			if k < 0.3:
				var e := k / 0.3
				model.rotation.x += 0.5 * e
				model.rotation.z += 0.4 * e
			else:
				var e := (k - 0.3) / 0.7
				model.rotation.x += -1.4 * sin(e * PI * 0.9)
				model.rotation.z += 1.1 * sin(e * PI * 0.8)
				model.position.x -= 0.25 * sin(e * PI)
		"thrust":
			model.position.z -= s * 0.45
			model.position.y += s * 0.06
		"bow":
			model.position.z += s * 0.06
			model.rotation.x += s * 0.12
			if arrow:
				arrow.visible = k > 0.6
		"cast":
			model.position.z -= s * 0.2
			model.position.y += s * 0.05
			if orb:
				orb.scale = Vector3.ONE * (1.0 + s * 1.2)
		"toss":
			model.position.y += s * 0.1
			model.rotation.x -= s * 0.6


func update(dt: float, moving: float) -> void:
	t += dt
	var dyaw: float = player.yaw - last_yaw
	var dpitch: float = player.pitch - last_pitch
	last_yaw = player.yaw
	last_pitch = player.pitch
	var mv := minf(1.0, moving / 3.0)
	var target := Vector2(clampf(dyaw * 0.6, -0.06, 0.06) + sin(player.bob) * 0.012 * mv,
		clampf(-dpitch * 0.6, -0.05, 0.05) + absf(cos(player.bob)) * 0.012 * mv + sin(t * 1.6) * 0.004)
	sway = sway.lerp(target, minf(1.0, dt * 10.0))
	equip_t = maxf(0.0, equip_t - dt)
	if anim_type != "":
		anim_t += dt
		if anim_t >= anim_dur:
			anim_type = ""
	if orb and anim_type != "cast":
		orb.scale = Vector3.ONE * (1.0 + sin(t * 5.0) * 0.1)
	_apply()
