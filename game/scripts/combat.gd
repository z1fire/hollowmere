class_name Combat
extends Node3D
## Projectiles, hit resolution, particles and floating combat text.

const SCHOOL := {
	"nature": {"color": Color("#6aff5a"), "core": Color("#d8ffb0")},
	"spark": {"color": Color("#8ab8ff"), "core": Color("#ffffff")},
	"fire": {"color": Color("#ff7a1a"), "core": Color("#ffe08a")},
	"heal": {"color": Color("#7affb0"), "core": Color("#ffffff")},
}

var game
var proj: Array = []
var _pmesh := {}
var _fade: Gradient
var _arrow_mesh: Mesh
var _orb_mesh: SphereMesh


func setup(g) -> Combat:
	game = g
	_fade = Gradient.new()
	_fade.set_color(0, Color(1, 1, 1, 1))
	_fade.set_color(1, Color(1, 1, 1, 0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.012
	shaft.bottom_radius = 0.012
	shaft.height = 0.75
	shaft.radial_segments = 4
	st.append_from(shaft, 0, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO))
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.03
	tip.height = 0.1
	tip.radial_segments = 4
	st.append_from(tip, 0, Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0, -0.42)))
	_arrow_mesh = st.commit()
	var am := StandardMaterial3D.new()
	am.albedo_color = Color("#8a6a44")
	_arrow_mesh.surface_set_material(0, am)
	_orb_mesh = SphereMesh.new()
	_orb_mesh.radius = 0.14
	_orb_mesh.height = 0.28
	_orb_mesh.radial_segments = 10
	_orb_mesh.rings = 6
	return self


# ------------------------------------------------ particles
func _particle_mesh(additive: bool) -> QuadMesh:
	if _pmesh.has(additive):
		return _pmesh[additive]
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.6))
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = Color(2.2, 2.2, 2.2) if additive else Color.WHITE
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = m
	_pmesh[additive] = q
	return q


## One-shot particle burst.
func burst(pos: Vector3, color: Color, amount := 20, speed := 3.0, life := 0.6, gravity := 6.0, spread := 0.0, size := 0.18, additive := true) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.randomness = 0.4
	p.mesh = _particle_mesh(additive)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	if spread > 0.0:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = spread * 0.5
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.4
	p.color = color
	p.color_ramp = _fade
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


func heal_fx(pos: Vector3) -> void:
	burst(pos, Color("#7affb0"), 40, 1.5, 1.0, -2.5, 1.2, 0.2)


func float_text(pos: Vector3, text: String, color: Color, big := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Assets.fonts.Cinzel
	l.font_size = 72 if big else 56
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	add_child(l)
	l.global_position = pos
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "global_position", pos + Vector3(0, 1.0, 0), 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)


# ------------------------------------------------ projectiles
func _spawn(o: Dictionary) -> void:
	var node := Node3D.new()
	if o.kind == "arrow":
		var mi := MeshInstance3D.new()
		mi.mesh = _arrow_mesh
		node.add_child(mi)
	else:
		var s: Dictionary = SCHOOL[o.school]
		var mi := MeshInstance3D.new()
		mi.mesh = _orb_mesh
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = s.core * 3.0
		mi.material_override = m
		mi.scale = Vector3.ONE * (1.5 if o.school == "fire" else 1.0)
		node.add_child(mi)
		var trail := CPUParticles3D.new()
		trail.amount = 40
		trail.lifetime = 0.35
		trail.local_coords = false
		trail.mesh = _particle_mesh(true)
		trail.spread = 180.0
		trail.initial_velocity_max = 0.6
		trail.gravity = Vector3(0, 2.0 if o.school == "fire" else 0.0, 0)
		trail.scale_amount_min = 0.15
		trail.scale_amount_max = 0.4 if o.school == "fire" else 0.25
		trail.color = s.color
		trail.color_ramp = _fade
		node.add_child(trail)
		o["trail"] = trail
		var light := OmniLight3D.new()
		light.light_color = s.color
		light.light_energy = 1.5
		light.omni_range = 5.0
		node.add_child(light)
	add_child(node)
	node.global_position = o.pos
	o["node"] = node
	o["life"] = o.get("life", 3.0)
	proj.append(o)


func player_shot(item: Dictionary, dmg: float, skill: String) -> void:
	var cam: Camera3D = game.player.camera
	var dir := -cam.global_transform.basis.z
	var pos := cam.global_position + dir * 0.6 + cam.global_transform.basis.x * 0.12 - Vector3(0, 0.12, 0)
	if item.skill == "ranged":
		var vel: Vector3 = dir * item.get("speed", 40.0) + Vector3(0, 1.2, 0)
		_spawn({"kind": "arrow", "pos": pos, "vel": vel, "gravity": 9.0, "dmg": dmg, "skill": skill, "hostile": false})
	else:
		_spawn({"kind": "orb", "school": item.school, "pos": pos, "vel": dir * item.get("speed", 28.0), "gravity": 0.0, "dmg": dmg, "skill": skill, "hostile": false, "splash": item.get("splash", 0.0)})


func enemy_arrow(from: Vector3, to: Vector3, def: Dictionary, enemy) -> void:
	var d := from.distance_to(to)
	var speed := 26.0
	var t := d / speed
	var vel := (to - from) / t
	vel.y += 0.5 * 9.0 * t
	vel.x += randf_range(-0.6, 0.6)
	vel.z += randf_range(-0.6, 0.6)
	_spawn({"kind": "arrow", "pos": from, "vel": vel, "gravity": 9.0, "dmg": randf_range(def.dmg[0], def.dmg[1]), "hostile": true, "source": enemy})


func hit_enemy(e, dmg: float, skill: String, src) -> void:
	var P = game.player
	var crit: bool = randf() < 0.08 + P.stats.dex * 0.002
	if crit:
		dmg *= 1.8
	var amount := roundi(dmg)
	var killed: bool = e.damage(amount, src)
	var c: Vector3 = e.center()
	var blood := Color("#e8e4d0") if e.def.model == "skeleton" else (Color("#4a8a2a") if e.def.model == "goblin" else Color("#a01a1a"))
	burst(c, blood, 10, 3.0, 0.6, 9.0, 0.0, 0.12, false)
	float_text(c, ("%d!" % amount) if crit else str(amount), Color("#ffd23a") if crit else Color.WHITE, crit)
	P.gain_xp(skill, amount * 0.55)
	game.audio.play("hit_bone" if e.def.model == "skeleton" else "hit")
	if killed:
		game.on_kill(e, skill)


func _physics_process(dt: float) -> void:
	if game == null:
		return
	var P = game.player
	var space := get_world_3d().direct_space_state
	for i in range(proj.size() - 1, -1, -1):
		var p: Dictionary = proj[i]
		p.life -= dt
		p.vel.y -= p.gravity * dt
		var node: Node3D = p.node
		var from := node.global_position
		var to: Vector3 = from + p.vel * dt
		var done := false
		# creatures
		for s in 3:
			var q := from.lerp(to, (s + 1) / 3.0)
			if p.hostile:
				if not P.dead and Vector2(q.x - P.position.x, q.z - P.position.z).length() < 0.5 and q.y > P.position.y and q.y < P.position.y + 1.9:
					P.hurt(p.dmg, p.source)
					done = true
					break
			else:
				for e in game.enemies:
					if e.dead:
						continue
					if Vector2(q.x - e.position.x, q.z - e.position.z).length() < e.radius + 0.25 and q.y > e.position.y - 0.1 and q.y < e.position.y + e.height + 0.2:
						if p.get("splash", 0.0) > 0.0:
							_explode(q, p)
						else:
							hit_enemy(e, p.dmg, p.skill, q)
						done = true
						break
			if done:
				to = q
				break
		# world
		if not done:
			var rq := PhysicsRayQueryParameters3D.create(from, to, 1)
			var hit := space.intersect_ray(rq)
			if hit:
				to = hit.position
				done = true
				if p.get("splash", 0.0) > 0.0:
					_explode(to, p)
				elif p.kind == "orb":
					burst(to, SCHOOL[p.school].color, 12, 2.0, 0.4, 0.0, 0.0, 0.2)
				else:
					burst(to, Color("#8a7a5a"), 4, 1.5, 0.4, 6.0, 0.0, 0.08, false)
		node.global_position = to
		if p.kind == "arrow" and p.vel.length() > 0.1:
			node.look_at(to + p.vel, Vector3.UP if absf(p.vel.normalized().y) < 0.99 else Vector3.FORWARD)
		if done or p.life <= 0.0:
			if done and p.kind == "orb" and p.get("splash", 0.0) <= 0.0:
				burst(to, SCHOOL[p.school].color, 14, 3.0, 0.4, 0.0, 0.0, 0.2)
			if p.has("trail"):
				(p.trail as CPUParticles3D).emitting = false
			node.queue_free()
			proj.remove_at(i)


func _explode(pos: Vector3, p: Dictionary) -> void:
	burst(pos, Color("#ff7a1a"), 60, 7.0, 0.7, -1.0, 0.5, 0.5)
	burst(pos, Color("#ffe08a"), 30, 3.0, 0.5, -2.0, 0.3, 0.4)
	burst(pos, Color("#3a3a3a"), 20, 2.0, 1.2, -1.5, 0.5, 0.5, false)
	game.audio.play("boom")
	for e in game.enemies:
		if e.dead:
			continue
		var d: float = e.center().distance_to(pos)
		var rr: float = p.splash + e.radius
		if d < rr:
			hit_enemy(e, p.dmg * (1.0 - 0.5 * d / rr), p.skill, pos)
