# agent: composer-2.5 | 2026-07-07 | chunk stitch generator | c7d8e9
extends RefCounted

const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfc := preload("res://scripts/generator/wfc.gd")


static func generate(
	rules: Dictionary,
	constraints: Dictionary,
	seed: int = 0,
	manifest: Dictionary = {},
	options: Dictionary = {},
) -> Dictionary:
	var chunk_list: Array = GenRules.chunks(rules)
	if chunk_list.is_empty():
		return {"ok": false, "error": "no chunks in rules"}

	var cs: int = int(options.get("chunk_size", GenRules.chunk_size(rules)))
	var chunk_counts: Dictionary = rules.get("chunk_counts", {})
	var chunk_compat: Dictionary = GenRules.chunk_compat(rules)
	var chunk_map := _build_chunk_map(chunk_list)
	var w: int = constraints.width
	var h: int = constraints.height
	var cw: int = ceili(float(w) / float(cs))
	var ch: int = ceili(float(h) / float(cs))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var coarse: Array = []
	coarse.resize(cw * ch)
	coarse.fill("")

	var order: Array = _coarse_order(cw, ch, constraints, cs, w, rng)
	for ci in order:
		var cx: int = ci % cw
		var cy: int = ci / cw
		var candidates := _chunk_candidates(
			chunk_list, chunk_map, chunk_compat, chunk_counts, coarse, cx, cy, cw, ch
		)
		candidates = _filter_fixed(candidates, chunk_map, constraints, cx, cy, cs, w, h)
		if candidates.is_empty():
			candidates = _all_chunk_ids(chunk_list)
			candidates = _filter_fixed(candidates, chunk_map, constraints, cx, cy, cs, w, h)
		if candidates.is_empty():
			continue
		coarse[ci] = _weighted_pick_id(candidates, chunk_counts, rng)

	var out := PackedInt32Array()
	out.resize(w * h)
	out.fill(0)
	for i in w * h:
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			out[i] = constraints.fixed_gids[i]

	for cy in ch:
		for cx in cw:
			var id: String = coarse[cy * cw + cx]
			if id.is_empty() or not chunk_map.has(id):
				continue
			_stamp_chunk(out, chunk_map[id], cx, cy, cs, w, h, constraints)

	var filled: Dictionary = GenWfc._count_filled(out, constraints)
	return {
		"ok": filled.done > 0,
		"gids": out,
		"seed": seed,
		"attempts": 1,
		"method": "chunk_stitch",
		"filled": filled.done,
		"total": filled.generatable,
	}


static func _build_chunk_map(chunk_list: Array) -> Dictionary:
	var out := {}
	for entry in chunk_list:
		if entry is Dictionary:
			out[str(entry.id)] = entry
	return out


static func _all_chunk_ids(chunk_list: Array) -> Array:
	var out: Array = []
	for entry in chunk_list:
		if entry is Dictionary:
			out.append(str(entry.id))
	return out


static func _coarse_order(
	cw: int,
	ch: int,
	constraints: Dictionary,
	cs: int,
	w: int,
	rng: RandomNumberGenerator,
) -> Array:
	var order: Array = []
	var has_fixed := false
	for i in constraints.modes.size():
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			has_fixed = true
			break

	if has_fixed:
		var scored: Array = []
		for cy in ch:
			for cx in cw:
				var dist := _coarse_dist_to_fixed(cx, cy, cs, constraints, w)
				scored.append({"ci": cy * cw + cx, "dist": dist})
		scored.sort_custom(func(a, b): return a.dist < b.dist)
		for item in scored:
			order.append(item.ci)
	else:
		for cy in ch:
			for cx in cw:
				order.append(cy * cw + cx)
		order.shuffle()
	return order


static func _coarse_dist_to_fixed(cx: int, cy: int, cs: int, constraints: Dictionary, w: int) -> int:
	var best := 999999
	for i in constraints.modes.size():
		if constraints.modes[i] != GenConstraints.Mode.FIXED:
			continue
		var fx: int = i % w
		var fy: int = i / w
		var fcx: int = fx / cs
		var fcy: int = fy / cs
		var d: int = absi(cx - fcx) + absi(cy - fcy)
		if d < best:
			best = d
	return best


static func _chunk_candidates(
	chunk_list: Array,
	chunk_map: Dictionary,
	chunk_compat: Dictionary,
	chunk_counts: Dictionary,
	coarse: Array,
	cx: int,
	cy: int,
	cw: int,
	ch: int,
) -> Array:
	var all := _all_chunk_ids(chunk_list)
	if cx == 0 and cy == 0:
		return all

	var out: Array = []
	for id in all:
		if not _edges_match(id, cx, cy, cw, ch, coarse, chunk_map, chunk_compat):
			continue
		out.append(id)
	return out if not out.is_empty() else all


static func _edges_match(
	id: String,
	cx: int,
	cy: int,
	cw: int,
	ch: int,
	coarse: Array,
	chunk_map: Dictionary,
	chunk_compat: Dictionary,
) -> bool:
	if not chunk_compat.has(id):
		return true
	var compat: Dictionary = chunk_compat[id]

	if cy > 0:
		var north_id: String = coarse[(cy - 1) * cw + cx]
		if not north_id.is_empty() and chunk_compat.has(north_id):
			if not _rows_equal(compat.get("north", []), chunk_compat[north_id].get("south", [])):
				return false

	if cx > 0:
		var west_id: String = coarse[cy * cw + cx - 1]
		if not west_id.is_empty() and chunk_compat.has(west_id):
			if not _rows_equal(compat.get("west", []), chunk_compat[west_id].get("east", [])):
				return false

	return true


static func _rows_equal(a: Array, b: Array) -> bool:
	if a.is_empty() or b.is_empty():
		return true
	if a.size() != b.size():
		return false
	for i in a.size():
		var av: int = int(a[i])
		var bv: int = int(b[i])
		if av <= 0 or bv <= 0:
			continue
		if av != bv:
			return false
	return true


static func _filter_fixed(
	candidates: Array,
	chunk_map: Dictionary,
	constraints: Dictionary,
	cx: int,
	cy: int,
	cs: int,
	w: int,
	h: int,
) -> Array:
	var out: Array = []
	for id in candidates:
		if _chunk_matches_fixed(id, chunk_map, constraints, cx, cy, cs, w, h):
			out.append(id)
	return out


static func _chunk_matches_fixed(
	id: String,
	chunk_map: Dictionary,
	constraints: Dictionary,
	cx: int,
	cy: int,
	cs: int,
	w: int,
	h: int,
) -> bool:
	if not chunk_map.has(id):
		return false
	var tiles: Array = chunk_map[id].get("tiles", [])
	for dy in cs:
		for dx in cs:
			var tx: int = cx * cs + dx
			var ty: int = cy * cs + dy
			if tx >= w or ty >= h:
				continue
			var idx: int = ty * w + tx
			if constraints.modes[idx] != GenConstraints.Mode.FIXED:
				continue
			var expected: int = constraints.fixed_gids[idx]
			var got: int = int(tiles[dy * cs + dx])
			if got != expected:
				return false
	return true


static func _weighted_pick_id(candidates: Array, chunk_counts: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id in candidates:
		total += float(chunk_counts.get(id, 1))
	if total <= 0.0:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var roll := rng.randf() * total
	for id in candidates:
		roll -= float(chunk_counts.get(id, 1))
		if roll <= 0.0:
			return id
	return candidates.back()


static func _stamp_chunk(
	out: PackedInt32Array,
	entry: Dictionary,
	cx: int,
	cy: int,
	cs: int,
	w: int,
	h: int,
	constraints: Dictionary,
) -> void:
	var tiles: Array = entry.get("tiles", [])
	for dy in cs:
		for dx in cs:
			var tx: int = cx * cs + dx
			var ty: int = cy * cs + dy
			if tx >= w or ty >= h:
				continue
			var idx: int = ty * w + tx
			if constraints.modes[idx] == GenConstraints.Mode.FIXED:
				continue
			if constraints.modes[idx] == GenConstraints.Mode.FORBID:
				out[idx] = 0
				continue
			var gid: int = int(tiles[dy * cs + dx])
			if gid > 0:
				out[idx] = gid
