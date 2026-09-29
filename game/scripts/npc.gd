class_name NPC
extends CharacterBody3D
## Villager / shopkeeper / quest giver.

const LOOKS := {
	"mayor": {"kind": "mage", "show": ["Mage_Cape", "Spellbook"], "hue": 0.25, "sat": 1.1},
	"smith": {"kind": "barbarian", "show": ["1H_Axe"], "light": 0.8},
	"innkeeper": {"kind": "barbarian", "show": ["Mug"], "hue": 0.45},
	"merchant": {"kind": "rogue", "show": ["Rogue_Cape"], "hue": 0.15},
	"herbalist": {"kind": "rogue_hooded", "show": ["Rogue_Cape"], "hue": -0.05, "sat": 0.8},
	"mage": {"kind": "mage", "show": ["Mage_Hat", "Mage_Cape", "2H_Staff"]},
	"hunter": {"kind": "rogue_hooded", "show": ["2H_Crossbow", "Rogue_Cape"]},
	"priest": {"kind": "mage", "show": ["Spellbook"], "sat": 0.12, "light": 1.6},
	"farmer": {"kind": "barbarian", "show": ["Barbarian_Hat"], "hue": 0.1, "sat": 0.6},
	"guard": {"kind": "knight", "show": ["Knight_Helmet", "1H_Sword", "Round_Shield", "Knight_Cape"]},
}
const VILLAGER_KINDS := [{"kind": "knight"}, {"kind": "barbarian"}, {"kind": "rogue"}, {"kind": "mage", "show": ["Mage_Cape"]}, {"kind": "rogue_hooded"}]

var game
var role := ""
var def := {}
var npc_name := ""
var actor: Actor
var home_yaw := 0.0
var yaw := 0.0
var wander := false
var target = null
var wait := 0.0
var rng: RandomNumberGenerator
var wp_index := 0
var talking := false
var was_talking := false
var interact := {}
var marker: Label3D
var marker_state := ""
var stuck := 0.0


func setup(g, spot: Dictionary, r: RandomNumberGenerator, p_name: String) -> NPC:
	game = g
	rng = r
	role = spot.role
	def = Data.ROLES[role]
	npc_name = p_name
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	var look: Dictionary = LOOKS.get(role, {})
	if look.is_empty():
		look = (U.pick(rng, VILLAGER_KINDS) as Dictionary).duplicate()
		look.merge({"hue": rng.randf_range(-0.5, 0.5), "sat": rng.randf_range(0.6, 1.2), "light": rng.randf_range(0.8, 1.15)})
	if role == "patron":
		look = {"kind": U.pick(rng, ["barbarian", "rogue"]), "show": ["Mug"], "hue": rng.randf_range(-0.5, 0.5)}
	actor = Actor.new()
	add_child(actor)
	actor.setup(look.kind, look)
	position = Vector3(spot.x, spot.get("y", 0.0), spot.z)
	home_yaw = spot.get("yaw", 0.0)
	yaw = home_yaw
	rotation.y = yaw
	wander = spot.get("wander", false)
	wp_index = spot.get("wp", 0)
	wait = rng.randf_range(1, 5)
	interact = {"type": "npc", "npc": self, "pos": position + Vector3(0, 1.2, 0), "r": 2.6, "label": "Talk to " + npc_name}
	game.world.interactables.append(interact)
	if def.has("quest"):
		marker = Label3D.new()
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.font = Assets.fonts.Cinzel
		marker.font_size = 128
		marker.pixel_size = 0.004
		marker.outline_size = 24
		marker.outline_modulate = Color("#2a1a00")
		marker.modulate = Color("#ffd23a")
		marker.position.y = 2.45
		marker.visible = false
		add_child(marker)
	return self


func set_marker(state: String) -> void:
	if marker == null or state == marker_state:
		return
	marker_state = state
	marker.text = state
	marker.visible = state != ""


func _physics_process(dt: float) -> void:
	var P: Vector3 = game.player.global_position
	var dp := Vector2(P.x - position.x, P.z - position.z).length()
	var far := dp > 90.0
	visible = not far
	actor.anim.active = dp < 60.0
	if far and not wander:
		return
	var moving := 0.0
	var v := Vector3.ZERO
	if wander and not talking:
		if target == null:
			wait -= dt
			if wait <= 0.0:
				var wp: Array = game.world.waypoints
				wp_index = U.pick(rng, wp[wp_index].n)
				var p: Vector2 = wp[wp_index].p
				target = p + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		else:
			var to: Vector2 = target - Vector2(position.x, position.z)
			if to.length() < 0.6:
				target = null
				wait = rng.randf_range(2, 8)
			elif dp > 1.4:
				yaw += U.angle_diff(yaw, atan2(to.x, to.y)) * minf(1.0, dt * 5.0)
				v = Vector3(sin(yaw), 0, cos(yaw)) * 1.4
				moving = 1.4
				var before := position
				stuck += dt if position.distance_to(before) < 0.001 and get_real_velocity().length() < 0.2 else 0.0
				if stuck > 3.0:
					target = null
					stuck = 0.0
					wait = 1.0
	if dp < 4.5 and moving == 0.0:
		yaw += U.angle_diff(yaw, atan2(P.x - position.x, P.z - position.z)) * minf(1.0, dt * 4.0)
	elif not wander:
		yaw += U.angle_diff(yaw, home_yaw) * minf(1.0, dt * 2.0)
	rotation.y = yaw
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 18.0 * dt
	move_and_slide()
	if moving > 0.0 and get_real_velocity().length() < 0.3:
		stuck += dt
	if talking and not was_talking:
		actor.play("talk")
	was_talking = talking
	actor.move(moving)
	interact.pos = position + Vector3(0, 1.2, 0)
