# agent: composer-2.5 | 2026-07-08 | shared wfc helpers | c3d4e5
extends RefCounted

const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")

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


static func _compat_row_any(row: PackedByteArray) -> bool:
	for v in row:
		if v:
			return true
	return false


static func _sync_compat_row_dict(
	compat: Dictionary,
	tiles: PackedInt32Array,
	gi: int,
	dir_idx: int,
	row: PackedByteArray,
) -> void:
	var gid: int = tiles[gi]
	var allowed := {}
	for j in tiles.size():
		if row[j]:
			allowed[tiles[j]] = true
	if not compat.has(gid):
		compat[gid] = {}
	compat[gid][DIR_NAMES[dir_idx]] = allowed


static func _build_context(
	rules: Dictionary,
	tiles: PackedInt32Array,
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
			if not opts.is_empty():
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

	for d in 4:
		var opp: int = OPPOSITE_DIR_IDX[d]
		var opp_rows: Array = compat_dirs[opp]
		for i in count:
			var row: PackedByteArray = compat_dirs[d][i]
			if _compat_row_any(row):
				continue
			for j in count:
				if opp_rows[j][i]:
					row[j] = 1
			if not _compat_row_any(row):
				row.fill(1)
			_sync_compat_row_dict(compat, tiles, i, d, row)

	var build_ctx := {"count": count, "compat_dirs": compat_dirs}
	_rebuild_propagator_fwd(build_ctx)
	var propagator_fwd: Array = build_ctx["propagator_fwd"]

	return {
		"tiles": tiles,
		"count": count,
		"gid_to_idx": gid_to_idx,
		"idx_to_gid": idx_to_gid,
		"all_domain": all_domain,
		"compat_dirs": compat_dirs,
		"propagator_fwd": propagator_fwd,
		"compat": compat,
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

	_rebuild_propagator_fwd(ctx)


static func _rebuild_propagator_fwd(ctx: Dictionary) -> void:
	var count: int = ctx.count
	var compat_dirs: Array = ctx.compat_dirs
	var propagator_fwd: Array = []
	for d in 4:
		var back_rows: Array = compat_dirs[OPPOSITE_DIR_IDX[d]]
		var fwd_rows: Array = compat_dirs[d]
		var dir_lists: Array = []
		dir_lists.resize(count)
		for u in count:
			var targets := PackedInt32Array()
			var fwd_row: PackedByteArray = fwd_rows[u]
			for t in count:
				if fwd_row[t] and back_rows[t][u]:
					targets.append(t)
			dir_lists[u] = targets
		propagator_fwd.append(dir_lists)
	ctx["propagator_fwd"] = propagator_fwd


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
		if from_fixed and not _touches_done(i, done, w, h):
			continue
		if domain_counts[i] == 0:
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


static func _touches_open(idx: int, done: PackedByteArray, w: int, h: int) -> bool:
	var x := idx % w
	var y := idx / w
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		if done[np.y * w + np.x] == 0:
			return true
	return false


static func _collect_propagate_seeds(
	constraints: Dictionary,
	done: PackedByteArray,
	out: PackedInt32Array,
	w: int,
	h: int,
) -> Array:
	var seeds: Array = []
	for i in w * h:
		if not done[i]:
			continue
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			seeds.append(i)
			continue
		if out[i] <= 0:
			continue
		if _touches_open(i, done, w, h):
			seeds.append(i)
	return seeds


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


static func untried_domain_count(domain: PackedByteArray, exclude: Array) -> int:
	var n := 0
	for t in domain.size():
		if domain[t] and not exclude.has(t):
			n += 1
	return n


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
	var stack_idx := {}
	for entry in stack:
		stack_idx[entry.idx] = true

	for i in w * h:
		if constraints.modes[i] == GenConstraints.Mode.FORBID:
			continue
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			continue
		if stack_idx.has(i):
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

	_propagate_one_hop(
		queue, domains, domain_counts, done, out, constraints, w, h, ctx
	)
	for i in w * h:
		if done[i]:
			continue
		if constraints.modes[i] == GenConstraints.Mode.FORBID:
			continue
		if domain_counts[i] == 0:
			domains[i] = _domain_copy(all_domain)
			domain_counts[i] = count
	return true


static func _propagate_one_hop(
	seed_queue: Array,
	domains: Array,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	out: PackedInt32Array,
	constraints: Dictionary,
	w: int,
	h: int,
	ctx: Dictionary,
) -> void:
	for raw_idx in seed_queue:
		var idx: int = int(raw_idx)
		if done[idx] == 0 or out[idx] <= 0:
			continue
		var x: int = idx % w
		var y: int = idx / w
		for d in 4:
			var np: Vector2i = Vector2i(x, y) + DELTA[d]
			if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
				continue
			var ni: int = np.y * w + np.x
			if constraints.modes[ni] == GenConstraints.Mode.FORBID:
				continue
			if done[ni]:
				continue
			_narrow(ni, idx, d, domains, domain_counts, done, out, w, h, ctx)


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
			var changed: int = _narrow(ni, idx, d, domains, domain_counts, done, out, w, h, ctx)
			if changed < 0:
				return false
			if changed > 0 and done[idx] and not in_queue[ni]:
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
	w: int,
	h: int,
	ctx: Dictionary,
) -> int:
	var count: int = ctx.count
	var compat_dirs: Array = ctx.compat_dirs
	var propagator_fwd: Array = ctx.get("propagator_fwd", [])
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
		var dir_lists: Array = propagator_fwd[dir_idx] if propagator_fwd.size() > dir_idx else []
		var allowed := PackedByteArray()
		allowed.resize(count)
		allowed.fill(0)
		for u in count:
			if not src_domain[u]:
				continue
			if dir_lists.size() > u:
				var targets: PackedInt32Array = dir_lists[u]
				for ti in targets.size():
					allowed[targets[ti]] = 1
			else:
				var fwd_row: PackedByteArray = fwd[u]
				var back_row: PackedByteArray = back[u]
				for t in count:
					if fwd_row[t] and back_row[t]:
						allowed[t] = 1
		for t in count:
			if not dst_domain[t]:
				continue
			var keep: int = 1 if allowed[t] else 0
			if dst_domain[t] != keep:
				dst_domain[t] = keep
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
		if exclude.is_empty():
			filtered = options
		else:
			return options[0]

	var total := 0.0
	var weights: Array = []
	for option_idx in filtered:
		var gid: int = idx_to_gid[option_idx]
		var weight: float = GenRules.pick_weight(rules, gid)
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
