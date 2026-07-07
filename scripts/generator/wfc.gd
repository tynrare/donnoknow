extends RefCounted

const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")

const DELTA := [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]
const FROM_DIR := ["south", "west", "north", "east"]


static func generate(
	rules: Dictionary,
	constraints: Dictionary,
	seed: int = 0,
	manifest: Dictionary = {},
	_max_restarts: int = 1,
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tiles := GenRules.all_tiles(rules, manifest)
	tiles = _merge_fixed_tiles(tiles, constraints)
	if tiles.is_empty():
		return {"ok": false, "error": "no tiles in rules"}

	var compat := _build_compat(rules, tiles)
	var result := _fill(rules, constraints, tiles, compat, rng)
	if result.ok:
		result["attempts"] = 1
		result["seed"] = seed
	return result


static func _build_compat(rules: Dictionary, tiles: PackedInt32Array) -> Dictionary:
	var all := {}
	for gid in tiles:
		all[gid] = true

	var compat := {}
	for gid in tiles:
		compat[gid] = {}
		for d in GenRules.DIRS:
			var opts: Dictionary = GenRules.adj_options(rules, gid, d)
			if opts.is_empty():
				compat[gid][d] = all
				continue
			var allowed := {}
			for other in tiles:
				if opts.get(str(other), 0) > 0:
					allowed[other] = true
			compat[gid][d] = allowed if not allowed.is_empty() else all
	return compat


static func _merge_fixed_tiles(tiles: PackedInt32Array, constraints: Dictionary) -> PackedInt32Array:
	var seen := {}
	for gid in tiles:
		seen[gid] = true
	if constraints.has("fixed_gids"):
		for gid in constraints.fixed_gids:
			if gid > 0:
				seen[gid] = true
	var merged := PackedInt32Array()
	for gid in seen:
		merged.append(int(gid))
	merged.sort()
	return merged


static func _fill(
	rules: Dictionary,
	constraints: Dictionary,
	tiles: PackedInt32Array,
	compat: Dictionary,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var w: int = constraints.width
	var h: int = constraints.height
	var n := w * h
	var out := PackedInt32Array()
	out.resize(n)
	out.fill(0)

	var order: Array = []
	for i in n:
		order.append(i)
	order.shuffle()

	for i in order:
		match constraints.modes[i]:
			GenConstraints.Mode.FORBID:
				out[i] = 0
				continue
			GenConstraints.Mode.FIXED:
				out[i] = constraints.fixed_gids[i]
				continue

		var allowed := _allowed_here(i, w, h, out, compat, tiles)
		out[i] = _weighted_pick(rules, allowed, tiles, rng)

	return {"ok": true, "gids": out}


static func _allowed_here(
	idx: int,
	w: int,
	h: int,
	out: PackedInt32Array,
	compat: Dictionary,
	tiles: PackedInt32Array,
) -> Array:
	var x := idx % w
	var y := idx / w
	var allowed: Array = []
	var first := true

	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		var neighbor_gid: int = out[ni]
		if neighbor_gid <= 0:
			continue
		if not compat.has(neighbor_gid):
			continue
		var bucket: Dictionary = compat[neighbor_gid][FROM_DIR[d]]
		if first:
			for gid in tiles:
				if bucket.has(gid):
					allowed.append(gid)
			first = false
		else:
			var next: Array = []
			for gid in allowed:
				if bucket.has(gid):
					next.append(gid)
			allowed = next

	if allowed.is_empty():
		allowed = tiles.duplicate()
	return allowed


static func _weighted_pick(
	rules: Dictionary,
	options: Array,
	fallback: PackedInt32Array,
	rng: RandomNumberGenerator,
) -> int:
	if options.is_empty():
		options = fallback.duplicate()

	var total := 0.0
	for gid in options:
		total += GenRules.tile_weight(rules, gid)
	if total <= 0.0:
		return options[rng.randi_range(0, options.size() - 1)]

	var roll := rng.randf() * total
	for gid in options:
		roll -= GenRules.tile_weight(rules, gid)
		if roll <= 0.0:
			return gid
	return options.back()
