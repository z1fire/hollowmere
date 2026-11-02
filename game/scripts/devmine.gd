extends SceneTree
## Dev harness (not shipped): plan the mine for many seeds and check every layout is complete.
## godot --headless --path game -s res://scripts/devmine.gd


func _initialize() -> void:
	var bad := 0
	var types := {}
	for seed_value in 200:
		var R := U.make_rng(seed_value + 61)
		var am := R.randf_range(0, TAU)
		var C := U.polar(am, 112.0)
		var M := {"x0": C.x - Mine.HALF, "z0": C.y - Mine.HALF, "size": Mine.HALF * 2.0, "rooms": [], "tunnels": []}
		Mine._plan(M, R, C, Vector2(sin(am), cos(am)))
		Mine._field(M, seed_value)
		var kinds: Array = M.rooms.map(func(r): return r.type)
		var ok: bool = kinds.has("entry") and kinds.has("boss") and kinds.size() >= 7
		for rm in M.rooms:
			if Mine.open_at(M, rm.c.x, rm.c.y) <= 0.5:
				ok = false
		for k in kinds:
			types[k] = types.get(k, 0) + 1
		if not ok:
			bad += 1
			print("seed %d: %s" % [seed_value, kinds])
	print("[mine] %d/200 layouts incomplete; room counts %s" % [bad, types])
	quit()
