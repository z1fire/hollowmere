class_name U
extends RefCounted
## Small math / random helpers shared by all scripts.

static func smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func dist_to_seg(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
	var dx := bx - ax
	var dz := bz - az
	var l2 := dx * dx + dz * dz
	if l2 < 1e-6:
		l2 = 1.0
	var t := clampf(((px - ax) * dx + (pz - az) * dz) / l2, 0.0, 1.0)
	return Vector2(px - (ax + dx * t), pz - (az + dz * t)).length()


static func angle_diff(a: float, b: float) -> float:
	return wrapf(b - a, -PI, PI)


## point on a circle; angle 0 points to +Z (same convention as the original game)
static func polar(a: float, r: float) -> Vector2:
	return Vector2(sin(a) * r, cos(a) * r)


static func pick(rng: RandomNumberGenerator, arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)]


static func chance(rng: RandomNumberGenerator, p: float) -> bool:
	return rng.randf() < p


static func shuffle(rng: RandomNumberGenerator, arr: Array) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	return arr


static func make_rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


static func fmt_time(hours: float) -> String:
	var h := int(hours) % 24
	var m := int(fmod(hours, 1.0) * 60.0)
	var ap := "PM" if h >= 12 else "AM"
	var hh := 12 if h % 12 == 0 else h % 12
	return "%d:%02d %s" % [hh, m, ap]


## Transform with yaw (radians), uniform or per-axis scale, and position
static func xf(pos: Vector3, ry: float = 0.0, s: Vector3 = Vector3.ONE, rx: float = 0.0, rz: float = 0.0) -> Transform3D:
	# scale first, then rotate (matches three.js compose)
	var b := Basis.from_euler(Vector3(rx, ry, rz), EULER_ORDER_YXZ) * Basis.from_scale(s)
	return Transform3D(b, pos)
