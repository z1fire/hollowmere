class_name Player
extends CharacterBody3D
## First-person farmer-turned-hero: movement, stats, use-based skills, inventory and actions.

const STACK := ["seed", "crop", "consumable", "material"]
const EYE := 1.62

var game
var camera: Camera3D
var vm: Viewmodel
var yaw := 0.0
var pitch := 0.0
var radius := 0.35
var bob := 0.0
var cool := 0.0
var hurt_t := 99.0
var dead := false
var in_village := true

var skills := {}
var gold := 25
var inv: Array = []
var hotbar: Array = []
var sel := 0
var armor := "farm_clothes"
var hp := 1.0
var mp := 1.0
var max_hp := 1.0
var max_mp := 1.0
var def_ := 0.0
var stats := {}
var cls := {}
var class_name_ := ""


func setup(g) -> Player:
	game = g
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	camera = Camera3D.new()
	camera.position.y = EYE
	camera.near = 0.02
	camera.far = 650.0
	add_child(camera)
	vm = Viewmodel.new()
	camera.add_child(vm)
	vm.setup(self)
	reset()
	return self


func reset() -> void:
	skills = {"melee": {"lvl": 0, "xp": 0.0}, "ranged": {"lvl": 0, "xp": 0.0}, "nature": {"lvl": 0, "xp": 0.0}, "combat": {"lvl": 0, "xp": 0.0}, "farming": {"lvl": 1, "xp": 0.0}}
	gold = 25
	inv = []
	hotbar = [null, null, null, null, null, null]
	armor = "farm_clothes"
	add_item("pitchfork")
	add_item("hoe")
	add_item("wheat_seed", 8)
	add_item("bread", 2)
	add_item("farm_clothes")
	sel = 1
	recompute()
	hp = max_hp
	mp = max_mp
	class_name_ = cls.title


func serialize() -> Dictionary:
	return {"x": position.x, "y": position.y, "z": position.z, "yaw": yaw, "skills": skills, "gold": gold, "inv": inv, "hotbar": hotbar, "sel": sel, "armor": armor, "hp": hp, "mp": mp}


func load_data(d: Dictionary) -> void:
	for k in d.skills:
		skills[k] = {"lvl": int(d.skills[k].lvl), "xp": float(d.skills[k].xp)}
	gold = int(d.gold)
	inv = []
	for s in d.inv:
		inv.append({"id": s.id, "qty": int(s.qty)})
	hotbar = d.hotbar
	sel = int(d.sel)
	armor = d.armor
	position = Vector3(d.x, d.y, d.z)
	yaw = d.yaw
	recompute()
	hp = minf(d.hp, max_hp)
	mp = minf(d.mp, max_mp)
	class_name_ = cls.title
	vm.set_item(held())


# ------------------------------------------------ stats
func recompute() -> void:
	var s := skills
	var str_: float = 10.0 + s.melee.lvl * 2 + s.farming.lvl * 0.8
	var dex: float = 10.0 + s.ranged.lvl * 2 + s.farming.lvl * 0.3
	var intel: float = 10.0 + (s.nature.lvl + s.combat.lvl) * 1.6
	stats = {"str": roundi(str_), "dex": roundi(dex), "int": roundi(intel)}
	var arm: Dictionary = Data.ITEMS.get(armor, {})
	max_hp = roundf(30 + str_ * 2.2 + dex * 0.6 + intel * 0.4)
	max_mp = roundf(8 + intel * 2.4 + arm.get("mana", 0))
	def_ = arm.get("def", 0)
	cls = Data.compute_class(skills)


func gain_xp(skill: String, amt: float) -> void:
	if not skills.has(skill) or amt <= 0.0:
		return
	var s: Dictionary = skills[skill]
	s.xp += amt
	var leveled := false
	while s.xp >= Data.xp_to_next(s.lvl):
		s.xp -= Data.xp_to_next(s.lvl)
		s.lvl += 1
		leveled = true
	if leveled:
		var old := max_hp
		recompute()
		hp += maxf(0.0, max_hp - old)
		mp = minf(max_mp, mp + 10)
		var sk: Dictionary = Data.SKILLS[skill]
		game.ui.toast("%s %s increased to %d!" % [sk.icon, sk.name, s.lvl], sk.color)
		game.combat.burst(position + Vector3(0, 1, 0), sk.color, 80, 2.5, 1.4, -3.0, 1.0)
		game.audio.play("levelup")
		if cls.title != class_name_:
			class_name_ = cls.title
			game.ui.banner("You are now a " + cls.title, "Your class reflects the skills you use most")
	game.ui.dirty = true


# ------------------------------------------------ inventory
func count(id: String) -> int:
	var n := 0
	for s in inv:
		if s.id == id:
			n += s.qty
	return n


func add_item(id: String, qty := 1) -> void:
	var it: Dictionary = Data.ITEMS.get(id, {})
	if it.is_empty():
		return
	if it.kind in STACK:
		var found := false
		for s in inv:
			if s.id == id:
				s.qty += qty
				found = true
				break
		if not found:
			inv.append({"id": id, "qty": qty})
	else:
		for i in qty:
			inv.append({"id": id, "qty": 1})
	if it.kind in ["weapon", "tool", "seed", "consumable"] and not hotbar.has(id):
		var free := hotbar.find(null)
		if free >= 0:
			hotbar[free] = id
	if game and game.ui:
		game.ui.dirty = true


func remove_item(id: String, qty := 1) -> void:
	for i in range(inv.size() - 1, -1, -1):
		if qty <= 0:
			break
		var s: Dictionary = inv[i]
		if s.id != id:
			continue
		var take: int = mini(qty, s.qty)
		s.qty -= take
		qty -= take
		if s.qty <= 0:
			inv.remove_at(i)
	if count(id) == 0:
		var h := hotbar.find(id)
		if h >= 0:
			hotbar[h] = null
			if h == sel:
				vm.set_item(held())
		if armor == id:
			equip_armor("farm_clothes")
	game.ui.dirty = true


func held() -> Dictionary:
	var id = hotbar[sel]
	if id == null or count(id) <= 0:
		return {}
	var d: Dictionary = Data.ITEMS[id].duplicate()
	d["id"] = id
	return d


func select(i: int) -> void:
	if i == sel or i < 0 or i >= hotbar.size():
		return
	sel = i
	vm.set_item(held())
	cool = maxf(cool, 0.2)
	game.ui.dirty = true
	game.audio.play("click")


func equip_armor(id: String) -> void:
	armor = id
	recompute()
	hp = minf(hp, max_hp)
	mp = minf(mp, max_mp)
	game.ui.dirty = true


func consume(id: String) -> void:
	var it: Dictionary = Data.ITEMS.get(id, {})
	if it.is_empty() or count(id) <= 0:
		return
	if it.has("heal"):
		hp = minf(max_hp, hp + it.heal)
		game.combat.heal_fx(position + Vector3(0, 1, 0))
	if it.has("mana"):
		mp = minf(max_mp, mp + it.mana)
	remove_item(id, 1)
	game.audio.play("drink")
	game.ui.toast("Used " + it.name)


# ------------------------------------------------ frame
func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _physics_process(dt: float) -> void:
	if game == null or not game.running:
		return
	var inp = game.input
	var frozen: bool = game.ui.modal_open
	var W: World = game.world
	cool -= dt
	hurt_t += dt
	if dead:
		_update_camera(0.0)
		velocity = Vector3(0, velocity.y - 18.0 * dt, 0)
		move_and_slide()
		return
	if hurt_t > 5.0:
		hp = minf(max_hp, hp + max_hp * 0.012 * dt)
	mp = minf(max_mp, mp + (1.0 + stats.int * 0.03) * dt)
	if not frozen:
		yaw -= inp.look.x
		pitch = clampf(pitch - inp.look.y, -1.45, 1.45)
	inp.look = Vector2.ZERO
	var mv: Vector2 = Vector2.ZERO if frozen else inp.move
	if mv.length() > 1.0:
		mv = mv.normalized()
	var in_water: bool = Vector2(position.x - W.water.x, position.z - W.water.z).length() < W.water.r * 0.95 and position.y < W.water.y
	var sprint: bool = inp.sprint or (mv.length() > 0.95 and inp.touch)
	var speed := 4.3 * (1.55 if sprint else 1.0) * (0.55 if in_water else 1.0)
	var f := forward()
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var v := (f * mv.y + right * mv.x) * speed
	velocity.x = v.x
	velocity.z = v.z
	if is_on_floor():
		if velocity.y < -10.0:
			hurt((-velocity.y - 10.0) * 3.0, null, true)
		velocity.y = 0.0
		if inp.jump and not frozen:
			velocity.y = 5.6
			game.audio.play("jump")
	else:
		velocity.y -= 18.0 * dt
	inp.jump = false
	move_and_slide()
	# world boundary
	var r := Vector2(position.x, position.z).length()
	if r > 186.0:
		position.x *= 186.0 / r
		position.z *= 186.0 / r
	var moving := Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0
	if moving > 0.5:
		var pb := bob
		bob += dt * moving * 1.9
		if floori(pb / PI) != floori(bob / PI):
			game.audio.play("step_wood" if W.inside else ("step_water" if in_water else "step"))
	in_village = r < W.fence_r - 0.5
	_update_camera(moving)
	if not frozen and inp.attack:
		primary()
	vm.update(dt, moving)


func _update_camera(moving: float) -> void:
	var bob_y := sin(bob * 2.0) * 0.045 * minf(1.0, moving / 4.0)
	camera.position.y = (0.35 if dead else EYE) + bob_y
	rotation = Vector3(0, yaw, 0)
	camera.rotation = Vector3(pitch, 0, 0.6 if dead else 0.0)


# ------------------------------------------------ actions
func target_plot():
	var f := forward()
	var p := position + f * 1.3
	var best = null
	var bd := 1.1
	for pl in game.world.plots:
		var d := Vector2(pl.pos.x - p.x, pl.pos.z - p.z).length()
		if d < bd:
			bd = d
			best = pl
	return best


func damage_roll(it: Dictionary) -> float:
	var stat: float = stats.str if it.skill == "melee" else (stats.dex if it.skill == "ranged" else stats.int)
	var lvl: int = skills[it.skill].lvl if skills.has(it.skill) else 0
	return randf_range(it.dmg[0], it.dmg[1]) * (1.0 + (stat - 10.0) * 0.03) + lvl * 0.35


func primary() -> void:
	if cool > 0.0 or dead:
		return
	var it := held()
	if it.is_empty():
		it = {"id": "", "name": "Fists", "kind": "weapon", "skill": "melee", "dmg": [1, 3], "rate": 0.5, "range": 1.8, "vm": "fists"}
	if it.kind == "tool" and it.id == "hoe":
		var p = target_plot()
		if p and p.state == "grass":
			cool = 0.6
			vm.swing("chop")
			game.farm.till(p)
			return
	if it.kind == "seed":
		cool = 0.4
		var p = target_plot()
		if p == null:
			game.ui.toast("Face a plot in your field to plant")
		elif p.state == "tilled":
			vm.swing("toss")
			game.farm.plant(p, it.id)
		elif p.state == "grass":
			game.ui.toast("Till the soil with your hoe first")
		else:
			game.ui.toast("Something is already growing there")
		return
	if it.kind == "consumable" or (it.kind == "crop" and it.has("heal")):
		cool = 0.8
		consume(it.id)
		return
	if it.kind in ["crop", "material", "armor"]:
		cool = 0.4
		return
	cool = it.rate
	if it.skill == "melee":
		vm.swing("thrust" if it.get("vm", "") == "pitchfork" else "slash")
		game.audio.play("swing")
		get_tree().create_timer(0.13).timeout.connect(func(): _melee_hit(it))
	elif it.skill == "ranged":
		vm.swing("bow")
		game.audio.play("bow")
		game.combat.player_shot(it, damage_roll(it), "ranged")
	else:
		if mp < it.mana:
			game.ui.toast("Not enough mana", Color("#7aa8ff"))
			cool = 0.3
			game.audio.play("fizzle")
			return
		mp -= it.mana
		vm.swing("cast")
		if it.school == "heal":
			var amt: float = it.heal * (1.0 + (stats.int - 10.0) * 0.03) + skills.nature.lvl
			var gained := minf(max_hp - hp, amt)
			hp += gained
			game.combat.heal_fx(position + Vector3(0, 1, 0))
			game.audio.play("heal")
			gain_xp("nature", maxf(2.0, gained * 0.5))
			game.combat.float_text(position + Vector3(0, 1.4, 0) + forward() * 1.2, "+%d" % roundi(gained), Color("#7affb0"))
		else:
			game.combat.player_shot(it, damage_roll(it), it.skill)
			game.audio.play("spell_" + it.school)


func _melee_hit(it: Dictionary) -> void:
	if dead:
		return
	var f := forward()
	var hit_any := false
	for e in game.enemies:
		if e.dead:
			continue
		var to := Vector2(e.position.x - position.x, e.position.z - position.z)
		var d := to.length()
		if d > it.get("range", 2.0) + e.radius or absf(e.position.y - position.y) > 2.5:
			continue
		if to.normalized().dot(Vector2(f.x, f.z)) < 0.45 and d > 0.9:
			continue
		game.combat.hit_enemy(e, damage_roll(it), "melee", position)
		hit_any = true
	if not hit_any and it.id == "hoe":
		var p = target_plot()
		if p and p.state == "grass":
			game.farm.till(p)


func hurt(dmg: float, src, fall := false) -> void:
	if dead:
		return
	var d := dmg if fall else maxf(1.0, dmg - def_ * 0.6)
	hp -= d
	hurt_t = 0.0
	game.ui.hurt_flash()
	game.audio.play("hurt")
	if src != null and not fall:
		var away := Vector2(position.x - src.position.x, position.z - src.position.z).normalized()
		position += Vector3(away.x, 0, away.y) * 0.25
	if hp <= 0.0:
		hp = 0.0
		dead = true
		game.on_death()
