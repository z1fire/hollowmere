class_name Enemy
extends CharacterBody3D
## Wolves, goblins and skeletons: idle wander -> chase -> attack -> return to spawn.

static var _bar_shader: Shader

var game
var spawn := {}
var type := ""
var def := {}
var actor: Actor
var radius := 0.4
var height := 1.8
var hp := 1.0
var max_hp := 1.0
var state := "idle"
var cool := 0.0
var wait := 0.0
var target = null
var yaw := 0.0
var dead := false
var dead_t := 0.0
var respawn_t := 0.0
var flash := 0.0
var last_hit := 0.0
var bar: MeshInstance3D
var bar_mat: ShaderMaterial
var spawn_pos := Vector3.ZERO


func setup(g, s: Dictionary) -> Enemy:
	game = g
	spawn = s
	type = s.type
	def = Data.ENEMIES[type]
	collision_layer = 4
	collision_mask = 1
	actor = Actor.new()
	add_child(actor)
	match type:
		"wolf":
			actor.setup("wolf", {"own_materials": true})
		"goblin":
			actor.setup("orc", {"own_materials": true})
		"goblin_archer":
			actor.setup("orc", {"own_materials": true, "scale": 0.9})
		"goblin_chief":
			actor.setup("orc", {"own_materials": true, "scale": 1.75})
			for m in actor.materials:
				if m is BaseMaterial3D:
					(m as BaseMaterial3D).albedo_color *= Color("#ff9a7a")
		"skeleton":
			if randf() < 0.5:
				actor.setup("skeleton_minion", {"own_materials": true, "right": "sword_1handed"})
			else:
				actor.setup("skeleton_warrior", {"own_materials": true, "right": "axe_1handed", "left": "shield_round"})
		"skeleton_archer":
			actor.setup("skeleton_rogue", {"own_materials": true, "right": "crossbow_2handed", "show": ["Skeleton_Rogue_Hood"]})
	radius = 0.5 if def.model == "wolf" else def.get("scale", 1.0) * 0.42
	height = 0.95 if def.model == "wolf" else (1.3 * def.get("scale", 1.0) if def.model == "goblin" else 1.8)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0 + 0.05)
	cs.shape = cap
	cs.position.y = cap.height / 2.0
	add_child(cs)
	# health bar (billboarded quad)
	if _bar_shader == null:
		_bar_shader = Shader.new()
		_bar_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float fill = 1.0;
uniform vec4 col : source_color = vec4(0.88, 0.23, 0.16, 1.0);
void vertex() { MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]); }
void fragment() { ALBEDO = UV.x < fill ? col.rgb : vec3(0.12, 0.02, 0.02); ALPHA = 0.9; }
"""
	bar_mat = ShaderMaterial.new()
	bar_mat.shader = _bar_shader
	if def.get("boss", false):
		bar_mat.set_shader_parameter("col", Color("#ff9a2a"))
	var q := QuadMesh.new()
	q.size = Vector2(1.4 if def.get("boss", false) else 0.9, 0.09)
	bar = MeshInstance3D.new()
	bar.mesh = q
	bar.material_override = bar_mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.visible = false
	bar.position.y = height + 0.35
	add_child(bar)
	return self


func respawn() -> void:
	var W: World = game.world
	spawn_pos = Vector3(spawn.x, W.height_at(spawn.x, spawn.z) + 0.2, spawn.z)
	position = spawn_pos
	hp = def.hp
	max_hp = def.hp
	state = "idle"
	cool = 0.0
	wait = randf() * 3.0
	target = null
	yaw = randf() * TAU
	dead = false
	dead_t = 0.0
	flash = 0.0
	velocity = Vector3.ZERO
	visible = true
	actor.position.y = 0.0
	actor.revive()
	actor.flash(0.0)
	bar.visible = false
	collision_layer = 4


func center() -> Vector3:
	return position + Vector3(0, height * 0.55, 0)


func damage(amount: float, source) -> bool:
	if dead:
		return false
	hp -= amount
	flash = 0.15
	last_hit = 0.0
	state = "chase"
	if source != null:
		var away := Vector2(position.x - source.x, position.z - source.z).normalized()
		var k := 0.15 if def.get("boss", false) else 0.5
		position += Vector3(away.x, 0, away.y) * k
	if hp <= 0.0:
		die()
		return true
	if actor.one_shot == "":
		actor.play("hit", 1.4)
	return false


func die() -> void:
	dead = true
	dead_t = 0.0
	hp = 0.0
	bar.visible = false
	collision_layer = 0
	actor.die()
	actor.flash(0.0)
	respawn_t = def.get("respawn", 75.0 + randf() * 45.0)


func _physics_process(dt: float) -> void:
	var P = game.player
	if dead:
		dead_t += dt
		if dead_t > 3.0:
			actor.position.y = -(dead_t - 3.0) * 0.5
		if dead_t > 5.0:
			visible = false
		respawn_t -= dt
		if respawn_t <= 0.0:
			if P.global_position.distance_to(Vector3(spawn.x, P.global_position.y, spawn.z)) > 30.0:
				respawn()
			else:
				respawn_t = 5.0
		return
	var p: Vector3 = P.global_position
	var to := Vector2(p.x - position.x, p.z - position.z)
	var dist := to.length()
	var far := dist > 110.0
	visible = not far
	actor.anim.active = dist < 70.0
	if far and state == "idle":
		return
	var home_d := Vector2(position.x - spawn.x, position.z - spawn.z).length()
	cool -= dt
	last_hit += dt
	var aggro: float = def.aggro * (1.25 if game.world.night > 0.6 else 1.0) * (0.4 if P.in_village else 1.0)
	var speed := 0.0
	if P.dead:
		state = "return"
	match state:
		"idle":
			if dist < aggro and not P.dead and absf(p.y - position.y) < 6.0:
				state = "chase"
				game.audio.growl(def.model)
			elif target == null:
				wait -= dt
				if wait < 0.0:
					var a := randf() * TAU
					var r := randf() * 8.0
					target = Vector2(spawn.x + sin(a) * r, spawn.z + cos(a) * r)
			else:
				var tt: Vector2 = target - Vector2(position.x, position.z)
				if tt.length() < 0.7:
					target = null
					wait = 2.0 + randf() * 5.0
				else:
					_face(tt, dt)
					speed = def.speed * 0.3
		"chase":
			if home_d > spawn.leash + 8.0 or (dist > aggro * 2.2 and last_hit > 5.0) or (P.in_village and dist > 6.0):
				state = "return"
			else:
				_face(to, dt)
				var rng_: float = def.range + (0.0 if def.get("ranged", false) else P.radius)
				if def.get("ranged", false):
					var clear: bool = dist < rng_ and game.line_clear(position + Vector3(0, height * 0.75, 0), p + Vector3(0, 1.2, 0))
					if clear:
						if cool <= 0.0:
							_attack(P)
						if dist < 6.0:
							speed = -def.speed * 0.6
					else:
						speed = def.speed
				elif dist > rng_:
					speed = def.speed
				elif cool <= 0.0:
					_attack(P)
		"return":
			var tt := Vector2(spawn.x - position.x, spawn.z - position.z)
			if tt.length() < 1.5:
				state = "idle"
				hp = minf(max_hp, hp + max_hp * 0.5)
			else:
				_face(tt, dt)
				speed = def.speed * 0.9
				hp = minf(max_hp, hp + max_hp * 0.1 * dt)
				if dist < aggro * 0.6 and home_d < spawn.leash and not P.dead and not P.in_village:
					state = "chase"
	if flash > 0.0:
		speed *= 0.3
	var v := Vector3(sin(yaw), 0, cos(yaw)) * speed
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 18.0 * dt
	move_and_slide()
	# stay out of the village
	var r := Vector2(position.x, position.z).length()
	var fr: float = game.world.fence_r + 1.5
	if r < fr:
		position.x *= fr / r
		position.z *= fr / r
	rotation.y = yaw
	if actor.one_shot == "":
		actor.move(absf(speed))
	if flash > 0.0:
		flash -= dt
		actor.flash(0.6 if flash > 0.0 else 0.0)
	var show := hp < max_hp and dist < 35.0
	bar.visible = show
	if show:
		bar_mat.set_shader_parameter("fill", clampf(hp / max_hp, 0.0, 1.0))


func _face(dir: Vector2, dt: float) -> void:
	yaw += U.angle_diff(yaw, atan2(dir.x, dir.y)) * minf(1.0, dt * 7.0)


func _attack(P) -> void:
	cool = def.rate * randf_range(0.85, 1.15)
	var ranged: bool = def.get("ranged", false)
	actor.play("shoot" if ranged else ("attack" if randf() < 0.5 or actor.clip("attack2") == "" else "attack2"), 1.3)
	if ranged:
		var from := position + Vector3(0, height * 0.75, 0)
		game.combat.enemy_arrow(from, P.global_position + Vector3(0, 1.2, 0), def, self)
		game.audio.play("bow")
	else:
		get_tree().create_timer(0.38).timeout.connect(func():
			if dead:
				return
			var d := Vector2(P.global_position.x - position.x, P.global_position.z - position.z).length()
			if d < def.range + P.radius + 0.4:
				P.hurt(randf_range(def.dmg[0], def.dmg[1]), self))
		game.audio.play("bite" if def.model == "wolf" else "swing")
