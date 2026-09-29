class_name Farm
extends Node3D
## Tilling, planting and harvesting on the family field.

var game
var soil_mat: StandardMaterial3D
var glow_mat: StandardMaterial3D
var nodes := {}


func setup(g) -> Farm:
	game = g
	soil_mat = Assets.pbr("dirt", 1.4)
	soil_mat.albedo_color = Color("#b08a60")
	glow_mat = StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_color = Color(1.0, 0.88, 0.54, 0.45)
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color.WHITE)
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	glow_mat.albedo_texture = gt
	for p in game.world.plots:
		var n := Node3D.new()
		n.position = p.pos
		add_child(n)
		nodes[p.id] = n
		refresh(p)
	return self


func progress(p: Dictionary) -> float:
	return clampf(p.t / Data.CROPS[p.crop].grow, 0.0, 1.0)


func ripe(p: Dictionary) -> bool:
	return p.state == "planted" and p.t >= Data.CROPS[p.crop].grow


func stage(p: Dictionary) -> int:
	if p.state != "planted":
		return -1
	return 3 if ripe(p) else mini(2, int(progress(p) * 3.0))


## merge several model parts into one mesh (one draw call per plot)
func _plot_mesh(parts: Array) -> MeshInstance3D:
	var batch := MeshBatch.new()
	var mats := {}
	for pt in parts:
		var xf := U.xf(Vector3(pt[2], 0.08, pt[3]), pt[4], Vector3.ONE * pt[5])
		for part in Assets.parts(pt[0], pt[1]):
			var mesh: Mesh = part.mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s)
				var key := str(mat.get_instance_id()) if mat else "none"
				mats[key] = mat if mat else StandardMaterial3D.new()
				batch.add_arrays(key, mesh.surface_get_arrays(s), xf * part.xform, Color.WHITE)
	return batch.build(mats)


func refresh(p: Dictionary) -> void:
	var n: Node3D = nodes[p.id]
	for c in n.get_children():
		c.queue_free()
	p["shown"] = stage(p)
	var rnd := func(i: int) -> float: return fposmod(sin(p.id * 91.7 + i * 13.3) * 43758.5, 1.0)
	if p.state == "grass":
		var parts: Array = []
		for i in 7:
			parts.append(["nature", "Grass" if rnd.call(i) < 0.6 else "Grass_Short", (rnd.call(i + 20) - 0.5) * 1.2, (rnd.call(i + 40) - 0.5) * 1.2, rnd.call(i + 60) * 6.0, 0.45 + rnd.call(i + 80) * 0.3])
		n.add_child(_plot_mesh(parts))
		return
	var batch := MeshBatch.new()
	batch.add_box("soil", U.xf(Vector3(0, 0.03, 0), 0.0, Vector3(1.4, 0.1, 1.4)), Color.WHITE)
	for i in [-1, 0, 1]:
		batch.add_box("soil", U.xf(Vector3(0, 0.09, i * 0.42), 0.0, Vector3(1.3, 0.07, 0.2)), Color.WHITE)
	n.add_child(batch.build({"soil": soil_mat}, false))
	if p.state != "planted":
		return
	var st: int = p.shown
	var name: String = {"wheat": "Wheat", "carrot": "Carrot", "pumpkin": "Pumpkin"}[p.crop] + "_" + str(st + 1)
	var parts: Array = []
	if p.crop == "pumpkin":
		parts.append(["crops", name, 0.0, 0.0, rnd.call(1) * 6.0, 0.85])
	else:
		for i in 9:
			var x: float = ((i % 3) - 1) * 0.42 + (rnd.call(i) - 0.5) * 0.08
			var z: float = (i / 3 - 1) * 0.42 + (rnd.call(i + 9) - 0.5) * 0.08
			if p.crop == "wheat":
				for k in 3:
					parts.append(["crops", name, x + (k - 1) * 0.08, z + (rnd.call(i * 3 + k) - 0.5) * 0.1, rnd.call(i + k) * 6.0, 0.9 + rnd.call(k + i) * 0.25])
			else:
				parts.append(["crops", name, x, z, rnd.call(i) * 6.0, 0.5])
	n.add_child(_plot_mesh(parts))
	if st == 3:
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.6)
		var g := MeshInstance3D.new()
		g.mesh = q
		g.material_override = glow_mat
		g.position.y = 0.9
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(g)


func till(p: Dictionary) -> void:
	p.state = "tilled"
	refresh(p)
	game.audio.play("till")
	game.player.gain_xp("farming", 4)
	game.combat.burst(p.pos + Vector3(0, 0.2, 0), Color("#6a4a2a"), 14, 2.0, 0.6, 8.0, 0.0, 0.12, false)


func plant(p: Dictionary, seed_id: String) -> void:
	var P = game.player
	if P.count(seed_id) <= 0:
		return
	p.state = "planted"
	p.crop = Data.ITEMS[seed_id].crop
	p.t = 0.0
	P.remove_item(seed_id, 1)
	P.gain_xp("farming", 3)
	refresh(p)
	game.audio.play("pickup")


func harvest(p: Dictionary) -> void:
	var c: Dictionary = Data.CROPS[p.crop]
	var P = game.player
	var n: int = randi_range(c.yield[0], c.yield[1])
	if randf() < P.skills.farming.lvl * 0.04:
		n += 1
	P.add_item(p.crop, n)
	if randf() < 0.35 + P.skills.farming.lvl * 0.02:
		P.add_item(p.crop + "_seed", 1)
	P.gain_xp("farming", c.xp)
	game.ui.toast("Harvested %d %s" % [n, Data.ITEMS[p.crop].name], Color("#d9b050"))
	game.audio.play("pickup")
	game.combat.burst(p.pos + Vector3(0, 0.5, 0), Color("#e2c35a"), 60, 2.5, 1.2, -3.0, 1.0)
	p.state = "tilled"
	p.crop = ""
	p.t = 0.0
	refresh(p)
	game.check_collect_quests()


func _process(dt: float) -> void:
	if game == null or not game.running:
		return
	var lvl: int = game.player.skills.farming.lvl
	for p in game.world.plots:
		if p.state != "planted":
			continue
		p.t += dt * (1.0 + lvl * 0.04)
		if stage(p) != p.shown:
			refresh(p)
