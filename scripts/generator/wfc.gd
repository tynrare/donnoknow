# agent: composer-2.5 | 2026-07-07 | repeat_penalty pick variety | g2h3i4
extends RefCounted

const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")

const DELTA := [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]
const DIR_NAMES := ["north", "east", "south", "west"]
const OPPOSITE := {
	"north": "south",
	"east": "west",
	"south": "north",
	"west": "east",
}
const OPPOSITE_DIR_IDX := [2, 3, 0, 1]


static func generate(
	rules: Dictionary,
	constraints: Dictionary,
	seed: int = 0,
	manifest: Dictionary = {},
	max_restarts: int = 16,
	options: Dictionary = {},
) -> Dictionary:
	if max_restarts == null:
		max_restarts = 32

	var job := GenWfcJob.new(rules, constraints, manifest, seed, max_restarts, options)
	while not job.finished:
		var step: Dictionary = job.step()
		if step.get("finished", false):
			return _finalize_result(step, rules, constraints, seed, manifest, options)

	return _finalize_result(
		{"ok": false, "gids": job.out, "attempts": max_restarts, "seed": seed},
		rules,
		constraints,
		seed,
		manifest,
		options,
	)


static func _finalize_result(
	step: Dictionary,
	rules: Dictionary,
	constraints: Dictionary,
	seed: int,
	manifest: Dictionary,
	options: Dictionary,
) -> Dictionary:
	var w: int = constraints.width
	var h: int = constraints.height
	var n := w * h
	var gids: PackedInt32Array = step.get("gids", PackedInt32Array())
	if gids.size() != n:
		gids = PackedInt32Array()
		gids.resize(n)
		gids.fill(0)

	var filled := _count_filled(gids, constraints)
	var method := "wfc" if filled.done == filled.generatable else "wfc_partial"

	return {
		"ok": filled.done == filled.generatable or filled.generatable == 0,
		"gids": gids,
		"seed": int(step.get("seed", seed)),
		"attempts": int(step.get("attempts", 1)),
		"backtracks": int(step.get("backtracks", 0)),
		"method": method,
		"filled": filled.done,
		"total": filled.generatable,
		"error": step.get("error", ""),
	}


static func _count_filled(gids: PackedInt32Array, constraints: Dictionary) -> Dictionary:
	var generatable := 0
	var done := 0
	for i in gids.size():
		match constraints.modes[i]:
			GenConstraints.Mode.FORBID:
				continue
			GenConstraints.Mode.FIXED:
				generatable += 1
				done += 1
			_:
				generatable += 1
				if gids[i] > 0:
					done += 1
	return {"generatable": generatable, "done": done}


static func build_compat(rules: Dictionary, tiles: PackedInt32Array) -> Dictionary:
	return _build_context(rules, tiles).compat


static func _build_context(
	rules: Dictionary,
	tiles: PackedInt32Array,
	use_patterns: bool = false,
) -> Dictionary:
	var count := tiles.size()
	var gid_to_idx := {}
	var idx_to_gid := PackedInt32Array()
	idx_to_gid.resize(count)
	for i in count:
		gid_to_idx[tiles[i]] = i
		idx_to_gid[i] = tiles[i]

	var all_domain := PackedByteArray()
	all_domain.resize(count)
	all_domain.fill(1)

	var compat_dirs: Array = []
	for _d in 4:
		var dir_maps: Array = []
		dir_maps.resize(count)
		for i in count:
			dir_maps[i] = PackedByteArray()
			dir_maps[i].resize(count)
			dir_maps[i].fill(0)
		compat_dirs.append(dir_maps)

	var compat := {}
	for i in count:
		var gid: int = tiles[i]
		compat[gid] = {}
		for d in 4:
			var dir_name: String = DIR_NAMES[d]
			var opts: Dictionary = GenRules.adj_options(rules, gid, dir_name)
			var row: PackedByteArray = compat_dirs[d][i]
			if opts.is_empty():
				row.fill(1)
			else:
				var allowed_nbs: Dictionary = {}
				for nb_key in opts:
					if int(opts[nb_key]) <= 0:
						continue
					allowed_nbs[int(nb_key)] = true
				for j in count:
					if allowed_nbs.has(tiles[j]):
						row[j] = 1
			var allowed := {}
			for j in count:
				if row[j]:
					allowed[tiles[j]] = true
			compat[gid][dir_name] = allowed

	var patterns: Array = GenRules.patterns_3x3(rules) if use_patterns else []
	var pattern_counts: Dictionary = rules.get("pattern_counts", {}) if use_patterns else {}
	return {
		"tiles": tiles,
		"count": count,
		"gid_to_idx": gid_to_idx,
		"idx_to_gid": idx_to_gid,
		"all_domain": all_domain,
		"compat_dirs": compat_dirs,
		"compat": compat,
		"use_patterns": use_patterns,
		"patterns": patterns,
		"pattern_index": GenRules.build_pattern_index(patterns, pattern_counts) if use_patterns else {},
	}


static func _augment_compat_from_constraints(constraints: Dictionary, ctx: Dictionary) -> void:
	var w: int = constraints.width
	var h: int = constraints.height
	var gid_to_idx: Dictionary = ctx.gid_to_idx
	var compat_dirs: Array = ctx.compat_dirs

	for i in w * h:
		if constraints.modes[i] != GenConstraints.Mode.FIXED:
			continue
		var gid: int = constraints.fixed_gids[i]
		if gid <= 0 or not gid_to_idx.has(gid):
			continue
		var gi: int = gid_to_idx[gid]
		var x := i % w
		var y := i / w

		for d in 4:
			var np: Vector2i = Vector2i(x, y) + DELTA[d]
			if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
				continue
			var ni: int = np.y * w + np.x
			if constraints.modes[ni] != GenConstraints.Mode.FIXED:
				continue
			var neighbor_gid: int = constraints.fixed_gids[ni]
			if neighbor_gid <= 0 or not gid_to_idx.has(neighbor_gid):
				continue
			_set_compat_pair(ctx, gi, gid_to_idx[neighbor_gid], d)


static func _pick_collapse_cell(
	constraints: Dictionary,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	w: int,
	h: int,
	rng: RandomNumberGenerator,
	require_fixed_frontier: bool = true,
) -> int:
	var n := w * h
	var from_fixed := false
	if require_fixed_frontier:
		for i in n:
			if constraints.modes[i] == GenConstraints.Mode.FIXED:
				from_fixed = true
				break

	var best := -1
	var best_size := 999999
	var best_dist := 999999
	for i in n:
		if done[i]:
			continue
		if domain_counts[i] == 0:
			return -1
		if from_fixed and not _touches_done(i, done, w, h):
			continue
		var sz: int = domain_counts[i]
		var dist: int = _dist_to_fixed(i, constraints, w, h)
		if sz < best_size:
			best_size = sz
			best_dist = dist
			best = i
		elif sz == best_size and (
			dist < best_dist or (dist == best_dist and rng.randf() < 0.5)
		):
			best_dist = dist
			best = i

	if best < 0 and from_fixed:
		return _pick_collapse_cell(
			constraints, domain_counts, done, w, h, rng, false
		)
	return best


static func _touches_done(idx: int, done: PackedByteArray, w: int, h: int) -> bool:
	var x := idx % w
	var y := idx / w
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		if done[np.y * w + np.x]:
			return true
	return false


static func _dist_to_fixed(idx: int, constraints: Dictionary, w: int, h: int) -> int:
	var x := idx % w
	var y := idx / w
	var best := 999999
	for i in constraints.modes.size():
		if constraints.modes[i] != GenConstraints.Mode.FIXED:
			continue
		var fx: int = i % w
		var fy: int = i / w
		var d: int = absi(x - fx) + absi(y - fy)
		if d < best:
			best = d
	return best


static func _set_compat_pair(ctx: Dictionary, gi: int, hj: int, dir_idx: int) -> void:
	ctx.compat_dirs[dir_idx][gi][hj] = 1
	ctx.compat_dirs[OPPOSITE_DIR_IDX[dir_idx]][hj][gi] = 1
	_sync_compat_dict(ctx, gi, dir_idx)
	_sync_compat_dict(ctx, hj, OPPOSITE_DIR_IDX[dir_idx])


static func _sync_compat_dict(ctx: Dictionary, gi: int, dir_idx: int) -> void:
	var gid: int = ctx.idx_to_gid[gi]
	var allowed := {}
	var row: PackedByteArray = ctx.compat_dirs[dir_idx][gi]
	for j in ctx.count:
		if row[j]:
			allowed[ctx.idx_to_gid[j]] = true
	if not ctx.compat.has(gid):
		ctx.compat[gid] = {}
	ctx.compat[gid][DIR_NAMES[dir_idx]] = allowed


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


static func _domain_copy(src: PackedByteArray) -> PackedByteArray:
	return src.duplicate()


static func _domain_pick_indices(domain: PackedByteArray) -> Array:
	var out: Array = []
	for i in domain.size():
		if domain[i]:
			out.append(i)
	return out


static func repropagate(
	domains: Array,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	out: PackedInt32Array,
	constraints: Dictionary,
	w: int,
	h: int,
	ctx: Dictionary,
	stack: Array,
) -> bool:
	var count: int = ctx.count
	var all_domain: PackedByteArray = ctx.all_domain

	for i in w * h:
		if constraints.modes[i] == GenConstraints.Mode.FORBID:
			continue
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			continue
		domains[i] = _domain_copy(all_domain)
		domain_counts[i] = count
		done[i] = 0
		out[i] = 0

	for entry in stack:
		var idx: int = entry.idx
		domains[idx] = entry.domain.duplicate()
		domain_counts[idx] = entry.count
		done[idx] = 1
		out[idx] = entry.gid

	var queue: Array = []
	for i in w * h:
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			queue.append(i)
	for entry in stack:
		queue.append(entry.idx)

	return _propagate(queue, domains, domain_counts, done, out, constraints, w, h, ctx)


static func _propagate(
	seed_queue: Array,
	domains: Array,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	out: PackedInt32Array,
	constraints: Dictionary,
	w: int,
	h: int,
	ctx: Dictionary,
) -> bool:
	var queue: Array = seed_queue.duplicate()
	var in_queue := PackedByteArray()
	in_queue.resize(w * h)
	for idx in seed_queue:
		in_queue[idx] = 1

	var head := 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		in_queue[idx] = 0

		var x := idx % w
		var y := idx / w
		for d in 4:
			var np: Vector2i = Vector2i(x, y) + DELTA[d]
			if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
				continue
			var ni: int = np.y * w + np.x
			if constraints.modes[ni] == GenConstraints.Mode.FORBID:
				continue
			if done[ni]:
				continue
			var changed: int = _narrow(ni, idx, d, domains, domain_counts, done, out, ctx)
			if changed < 0:
				return false
			if changed > 0 and not in_queue[ni]:
				queue.append(ni)
				in_queue[ni] = 1

	return true


static func _narrow(
	dst: int,
	src: int,
	dir_idx: int,
	domains: Array,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	out: PackedInt32Array,
	ctx: Dictionary,
) -> int:
	var count: int = ctx.count
	var compat_dirs: Array = ctx.compat_dirs
	var gid_to_idx: Dictionary = ctx.gid_to_idx
	var fwd: Array = compat_dirs[dir_idx]
	var back: Array = compat_dirs[OPPOSITE_DIR_IDX[dir_idx]]
	var dst_domain: PackedByteArray = domains[dst]
	var new_count: int = 0
	var changed: int = 0
	var src_collapsed := done[src] == 1

	if src_collapsed:
		var src_gid: int = out[src]
		if src_gid <= 0 or not gid_to_idx.has(src_gid):
			return 0
		var src_idx: int = gid_to_idx[src_gid]
		var allow: PackedByteArray = fwd[src_idx]
		for t in count:
			var keep: int = 1 if (dst_domain[t] and allow[t] and back[t][src_idx]) else 0
			if dst_domain[t] != keep:
				dst_domain[t] = keep
				changed = 1
			new_count += keep
	else:
		var src_domain: PackedByteArray = domains[src]
		for t in count:
			if not dst_domain[t]:
				continue
			var keep := 0
			for u in count:
				if not src_domain[u]:
					continue
				if fwd[u][t] and back[t][u]:
					keep = 1
					break
			if keep == 0:
				dst_domain[t] = 0
				changed = 1
			new_count += keep

	if changed == 0:
		return 0
	if new_count == 0:
		domain_counts[dst] = 0
		return -1
	domain_counts[dst] = new_count
	return 1


static func _weighted_pick_idx(
	rules: Dictionary,
	domain: PackedByteArray,
	idx_to_gid: PackedInt32Array,
	rng: RandomNumberGenerator,
	out: PackedInt32Array,
	done: PackedByteArray,
	idx: int,
	w: int,
	h: int,
	tile_bias: Dictionary = {},
	exclude: Array = [],
	repeat_penalty: float = 1.0,
) -> int:
	var options: Array = _domain_pick_indices(domain)
	if options.is_empty():
		return 0

	var filtered: Array = []
	for option_idx in options:
		if exclude.has(option_idx):
			continue
		filtered.append(option_idx)
	if filtered.is_empty():
		filtered = options

	var ctx_arr: PackedInt32Array = GenRules.build_context_at(out, done, idx, w, h)
	var total := 0.0
	var weights: Array = []
	for option_idx in filtered:
		var gid: int = idx_to_gid[option_idx]
		var ctx_w: float = GenRules.context_weight(rules, gid, ctx_arr)
		var weight: float
		if ctx_w > 0.0:
			weight = ctx_w * 8.0 + GenRules.pick_weight(rules, gid, tile_bias) * 0.25
		else:
			weight = GenRules.pick_weight(rules, gid, tile_bias)
		weight *= _repeat_penalty_factor(rules, out, done, idx, w, h, gid, repeat_penalty)
		weights.append(weight)
		total += weight

	if total <= 0.0:
		return filtered[rng.randi_range(0, filtered.size() - 1)]

	var roll := rng.randf() * total
	for i in filtered.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return filtered[i]
	return filtered.back()


static func _apply_pattern_filter(
	domain: PackedByteArray,
	domain_counts: PackedInt32Array,
	idx: int,
	out: PackedInt32Array,
	done: PackedByteArray,
	w: int,
	h: int,
	ctx: Dictionary,
	strict: bool = false,
) -> bool:
	var patterns: Array = ctx.get("patterns", [])
	if not ctx.get("use_patterns", false) or patterns.is_empty():
		return true

	var x := idx % w
	var y := idx / w
	var collapsed := 0
	for dy in 3:
		for dx in 3:
			if dx == 1 and dy == 1:
				continue
			var cx: int = x + dx - 1
			var cy: int = y + dy - 1
			if cx < 0 or cy < 0 or cx >= w or cy >= h:
				continue
			var ni: int = cy * w + cx
			if done[ni] and out[ni] > 0:
				collapsed += 1

	if collapsed == 0:
		return true

	var allowed: Dictionary = _pattern_allowed_centers(out, done, idx, w, h, ctx)
	var count: int = ctx.count
	var idx_to_gid: PackedInt32Array = ctx.idx_to_gid
	var backup := domain.duplicate()
	var new_count := 0
	for t in count:
		if not domain[t]:
			continue
		if allowed.has(idx_to_gid[t]):
			new_count += 1
		else:
			domain[t] = 0

	if new_count == 0:
		for t in count:
			domain[t] = backup[t]
		return not strict

	domain_counts[idx] = new_count
	return true


static func _pattern_allowed_centers(
	out: PackedInt32Array,
	done: PackedByteArray,
	idx: int,
	w: int,
	h: int,
	ctx: Dictionary,
) -> Dictionary:
	var window := PackedInt32Array()
	window.resize(9)
	window.fill(0)
	var x := idx % w
	var y := idx / w
	for dy in 3:
		for dx in 3:
			var cx: int = x + dx - 1
			var cy: int = y + dy - 1
			if cx < 0 or cy < 0 or cx >= w or cy >= h:
				continue
			var ni: int = cy * w + cx
			if done[ni] and out[ni] > 0:
				window[dy * 3 + dx] = out[ni]

	var index: Dictionary = ctx.get("pattern_index", {})
	if not index.is_empty():
		var merged := {}
		var neighbor_mask := 0
		for i in 9:
			if i != 4 and window[i] > 0:
				neighbor_mask |= 1 << i
		var mask: int = neighbor_mask
		while mask > 0:
			var key := _window_mask_key(window, mask)
			if index.has(key):
				for gid in index[key]:
					merged[gid] = true
			mask = (mask - 1) & neighbor_mask
		if not merged.is_empty():
			return merged

	return {}


static func _window_mask_key(window: PackedInt32Array, mask: int) -> String:
	var parts: Array = []
	for i in 9:
		if i == 4:
			parts.append("_")
		elif mask & (1 << i) and window[i] > 0:
			parts.append(str(window[i]))
		else:
			parts.append("*")
	return ",".join(parts)


static func _coerce_pattern(pat_v: Variant) -> PackedInt32Array:
	if pat_v is PackedInt32Array:
		return pat_v
	if pat_v is Array:
		var pat := PackedInt32Array()
		for gid in pat_v:
			pat.append(int(gid))
		return pat
	return PackedInt32Array()


static func _pattern_matches(pat: PackedInt32Array, window: PackedInt32Array) -> bool:
	for i in 9:
		if window[i] <= 0:
			continue
		if pat[i] != window[i]:
			return false
	return true


static func _repeat_penalty_factor(
	rules: Dictionary,
	out: PackedInt32Array,
	done: PackedByteArray,
	idx: int,
	w: int,
	h: int,
	gid: int,
	penalty: float,
) -> float:
	if penalty >= 1.0 or penalty <= 0.0:
		return 1.0

	var mates := {}
	for mate in GenRules.class_mates(rules, gid):
		mates[int(mate)] = true

	var x := idx % w
	var y := idx / w
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done.size() > ni and done[ni] == 0:
			continue
		var neighbor_gid: int = out[ni]
		if neighbor_gid <= 0:
			continue
		if neighbor_gid == gid or mates.has(neighbor_gid):
			return penalty

	return 1.0
