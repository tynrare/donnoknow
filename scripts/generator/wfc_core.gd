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
	options: Dictionary = {},
) -> Dictionary:
	var use_patterns: bool = bool(options.get("use_patterns", false))
	var pattern_propagate: bool = bool(options.get("pattern_propagate", false))
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
					var nb_gid: int = int(nb_key)
					allowed_nbs[nb_gid] = true
					var nb_rep: int = GenRules.representative_gid(rules, nb_gid)
					if nb_rep > 0:
						allowed_nbs[nb_rep] = true
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
				pass
			_sync_compat_row_dict(compat, tiles, i, d, row)

	var build_ctx := {"count": count, "compat_dirs": compat_dirs}
	_rebuild_propagator_fwd(build_ctx)
	var propagator_fwd: Array = build_ctx["propagator_fwd"]

	var patterns: Array = []
	var pattern_index: Dictionary = {}
	if use_patterns:
		patterns = GenRules.patterns_3x3_list(rules)
		if not patterns.is_empty():
			var pattern_counts: Dictionary = rules.get("pattern_counts", {})
			pattern_index = GenRules.build_pattern_index(patterns, pattern_counts)

	return {
		"tiles": tiles,
		"count": count,
		"gid_to_idx": gid_to_idx,
		"idx_to_gid": idx_to_gid,
		"all_domain": all_domain,
		"compat_dirs": compat_dirs,
		"propagator_fwd": propagator_fwd,
		"compat": compat,
		"use_patterns": use_patterns,
		"pattern_propagate": pattern_propagate,
		"patterns": patterns,
		"pattern_index": pattern_index,
	}


static func _alias_signature_members(rules: Dictionary, ctx: Dictionary) -> void:
	var gid_to_idx: Dictionary = ctx.gid_to_idx
	var members_map: Dictionary = rules.get("generatable_members", {})
	for sig in members_map:
		var members: Variant = members_map[sig]
		if members is not Array or members.is_empty():
			continue
		var rep_idx: int = -1
		for member in members:
			var mg: int = int(member)
			if gid_to_idx.has(mg):
				rep_idx = int(gid_to_idx[mg])
				break
		if rep_idx < 0:
			continue
		for member in members:
			gid_to_idx[int(member)] = rep_idx
	var sigs: Dictionary = rules.get("signatures", {})
	for sig in sigs:
		var atlas_members: Variant = sigs[sig]
		if atlas_members is not Array:
			continue
		var rep_idx := -1
		var gen: Variant = members_map.get(sig, [])
		if gen is Array:
			for member in gen:
				var mg: int = int(member)
				if gid_to_idx.has(mg):
					rep_idx = int(gid_to_idx[mg])
					break
		if rep_idx < 0:
			for member in atlas_members:
				var mg: int = int(member)
				if gid_to_idx.has(mg):
					rep_idx = int(gid_to_idx[mg])
					break
		if rep_idx < 0:
			continue
		for member in atlas_members:
			gid_to_idx[int(member)] = rep_idx


static func _is_paint_anchor(constraints: Dictionary, i: int) -> bool:
	if constraints.modes[i] != GenConstraints.Mode.FIXED:
		return false
	if not constraints.has("paint_anchor"):
		return true
	var pa: PackedByteArray = constraints.paint_anchor
	if i >= pa.size():
		return false
	return pa[i] != 0


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


static func _axis_aligned_with_last(idx: int, last_idx: int, w: int, h: int) -> int:
	if last_idx < 0:
		return 0
	var x := idx % w
	var y := idx / w
	var lx := last_idx % w
	var ly := last_idx / w
	return 1 if (x == lx or y == ly) else 0


static func _pick_collapse_cell(
	constraints: Dictionary,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	w: int,
	h: int,
	rng: RandomNumberGenerator,
	require_fixed_frontier: bool = true,
	bfs_wave: PackedInt32Array = PackedInt32Array(),
	last_collapsed: int = -1,
	anchor_mask: PackedByteArray = PackedByteArray(),
) -> int:
	var n := w * h
	var from_fixed := false
	if require_fixed_frontier:
		for i in n:
			if constraints.modes[i] == GenConstraints.Mode.FIXED:
				from_fixed = true
				break

	var use_wave := bfs_wave.size() == n
	var min_wave := 999999
	if use_wave:
		for i in n:
			if done[i]:
				continue
			if from_fixed and not _touches_done(i, done, w, h):
				continue
			if domain_counts[i] <= 0:
				continue
			min_wave = mini(min_wave, bfs_wave[i])
		if min_wave >= 999999:
			use_wave = false

	var heap: Array = []
	for i in n:
		if done[i]:
			continue
		if from_fixed and not _touches_done(i, done, w, h):
			continue
		var sz: int = domain_counts[i]
		if sz <= 0:
			continue
		if use_wave and bfs_wave[i] > min_wave:
			continue
		var dist_anchor: int = _dist_to_anchor(i, constraints, anchor_mask, w, h)
		var neighbors_done: int = _count_done_neighbors(i, done, w, h)
		var adjacent_last: int = 1 if _touches_idx(i, last_collapsed, w, h) else 0
		var axis_last: int = _axis_aligned_with_last(i, last_collapsed, w, h)
		_heap_push(heap, [sz, dist_anchor, adjacent_last, axis_last, neighbors_done, rng.randf(), i])

	if heap.is_empty() and from_fixed:
		return _pick_collapse_cell(
			constraints,
			domain_counts,
			done,
			w,
			h,
			rng,
			false,
			bfs_wave,
			last_collapsed,
			anchor_mask,
		)
	if heap.is_empty():
		return -1
	return _heap_pop(heap)[6]


static func _count_done_neighbors(idx: int, done: PackedByteArray, w: int, h: int) -> int:
	var x := idx % w
	var y := idx / w
	var count := 0
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		if done[np.y * w + np.x]:
			count += 1
	return count


static func _touches_idx(idx: int, other: int, w: int, h: int) -> bool:
	if other < 0:
		return false
	var x := idx % w
	var y := idx / w
	var ox := other % w
	var oy := other / w
	return absi(x - ox) + absi(y - oy) == 1


static func _heap_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	if a[2] != b[2]:
		return a[2] < b[2]
	if a[3] != b[3]:
		return a[3] < b[3]
	if a[4] != b[4]:
		return a[4] < b[4]
	return a[5] < b[5]


static func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _heap_less(entry, heap[parent]):
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = entry


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var smallest := i
		if left < heap.size() and _heap_less(heap[left], heap[smallest]):
			smallest = left
		if right < heap.size() and _heap_less(heap[right], heap[smallest]):
			smallest = right
		if smallest == i:
			break
		var tmp = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return top


static func _context_pick_key_at(
	out: PackedInt32Array,
	done: PackedByteArray,
	idx: int,
	w: int,
	h: int,
) -> String:
	var x := idx % w
	var y := idx / w
	var parts: PackedStringArray = PackedStringArray()
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			parts.append("0")
			continue
		var ni: int = np.y * w + np.x
		if done[ni] == 0 or out[ni] <= 0:
			parts.append("0")
		else:
			parts.append(str(out[ni]))
	return "|".join(parts)


static func _build_partial_3x3(
	out: PackedInt32Array,
	done: PackedByteArray,
	idx: int,
	w: int,
	h: int,
) -> PackedInt32Array:
	var cx := idx % w
	var cy := idx / w
	var partial := PackedInt32Array()
	partial.resize(9)
	partial.fill(-1)
	for dy in 3:
		for dx in 3:
			var x: int = cx + dx - 1
			var y: int = cy + dy - 1
			var slot: int = dy * 3 + dx
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var ni: int = y * w + x
			if done[ni] and out[ni] > 0:
				partial[slot] = out[ni]
	return partial


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


static func _is_propagate_seed_fixed(constraints: Dictionary, i: int) -> bool:
	if constraints.modes[i] != GenConstraints.Mode.FIXED:
		return false
	if constraints.has("paint_anchor"):
		var pa: PackedByteArray = constraints.paint_anchor
		if i < pa.size():
			return pa[i] != 0
	return true


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
			if _is_propagate_seed_fixed(constraints, i):
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


static func _dist_to_anchor(
	idx: int,
	constraints: Dictionary,
	anchor_mask: PackedByteArray,
	w: int,
	h: int,
) -> int:
	if anchor_mask.size() == constraints.modes.size():
		var x := idx % w
		var y := idx / w
		var best := 999999
		for i in anchor_mask.size():
			if anchor_mask[i] == 0:
				continue
			var ax: int = i % w
			var ay: int = i / w
			var d: int = absi(x - ax) + absi(y - ay)
			if d < best:
				best = d
		if best < 999999:
			return best
	return _dist_to_fixed(idx, constraints, w, h)


static func bfs_wave_from_anchors(
	constraints: Dictionary,
	anchor_mask: PackedByteArray,
	w: int,
	h: int,
) -> PackedInt32Array:
	var n := w * h
	var wave := PackedInt32Array()
	wave.resize(n)
	wave.fill(999999)
	var queue: Array = []
	for i in n:
		if anchor_mask.size() != n or anchor_mask[i] == 0:
			continue
		wave[i] = 0
		queue.append(i)
	var head := 0
	while head < queue.size():
		var idx: int = int(queue[head])
		head += 1
		var base: int = wave[idx]
		var x := idx % w
		var y := idx / w
		for d in 4:
			var np: Vector2i = Vector2i(x, y) + DELTA[d]
			if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
				continue
			var ni: int = np.y * w + np.x
			if constraints.modes[ni] == GenConstraints.Mode.FORBID:
				continue
			if wave[ni] <= base + 1:
				continue
			wave[ni] = base + 1
			queue.append(ni)
	return wave


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
	return _packed_from_seen(seen)


static func merge_runtime_tiles(
	rules: Dictionary,
	tiles: PackedInt32Array,
	constraints: Dictionary,
	initial_seed: PackedInt32Array,
) -> PackedInt32Array:
	var seen := {}
	for gid in tiles:
		seen[int(gid)] = true
	if constraints.has("fixed_gids"):
		for gid in constraints.fixed_gids:
			if gid > 0:
				seen[int(gid)] = true
	for i in initial_seed.size():
		var seed_gid: int = initial_seed[i]
		if seed_gid > 0:
			seen[seed_gid] = true
			var rep: int = GenRules.representative_gid(rules, seed_gid)
			if rep > 0:
				seen[rep] = true
	return _packed_from_seen(seen)


static func _packed_from_seen(seen: Dictionary) -> PackedInt32Array:
	var merged := PackedInt32Array()
	for gid in seen:
		merged.append(int(gid))
	merged.sort()
	return merged


static func _domain_copy(src: PackedByteArray) -> PackedByteArray:
	return src.duplicate()


static func _uncollapse_cell(
	idx: int,
	domains: Array,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	out: PackedInt32Array,
	all_domain: PackedByteArray,
	count: int,
) -> void:
	done[idx] = 0
	out[idx] = 0
	domains[idx] = _domain_copy(all_domain)
	domain_counts[idx] = count


static func repair_continue_conflicts_at(
	idx: int,
	initial_seed: PackedInt32Array,
	constraints: Dictionary,
	domains: Array,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	out: PackedInt32Array,
	w: int,
	h: int,
	ctx: Dictionary,
) -> bool:
	var count: int = ctx.count
	var all_domain: PackedByteArray = ctx.all_domain
	var x := idx % w
	var y := idx / w
	var removed := false
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done[ni] == 0 or out[ni] <= 0:
			continue
		if not _is_removable_seed(constraints, ni, initial_seed):
			continue
		if _mutual_compat(ctx, out[idx], d, out[ni]):
			continue
		_uncollapse_cell(ni, domains, domain_counts, done, out, all_domain, count)
		removed = true
	if not removed:
		return true
	var seeds: Array = [idx]
	for i in w * h:
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			if _is_propagate_seed_fixed(constraints, i):
				seeds.append(i)
	return _propagate_ac4(
		seeds, domains, domain_counts, done, out, constraints, w, h, ctx
	)


static func _mutual_compat(
	ctx: Dictionary,
	gid_a: int,
	dir_idx: int,
	gid_b: int,
) -> bool:
	var gid_to_idx: Dictionary = ctx.gid_to_idx
	if not gid_to_idx.has(gid_a) or not gid_to_idx.has(gid_b):
		return false
	var gi: int = gid_to_idx[gid_a]
	var hj: int = gid_to_idx[gid_b]
	var compat_dirs: Array = ctx.compat_dirs
	if not compat_dirs[dir_idx][gi][hj]:
		return false
	if not compat_dirs[OPPOSITE_DIR_IDX[dir_idx]][hj][gi]:
		return false
	return true


static func cell_has_bad_adjacency(
	idx: int,
	out: PackedInt32Array,
	done: PackedByteArray,
	w: int,
	h: int,
	ctx: Dictionary,
) -> bool:
	var gid: int = out[idx]
	if gid <= 0:
		return false
	var x := idx % w
	var y := idx / w
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done[ni] == 0 or out[ni] <= 0:
			continue
		if not _mutual_compat(ctx, gid, d, out[ni]):
			return true
	return false


static func count_bad_adjacency(
	out: PackedInt32Array,
	w: int,
	h: int,
	ctx: Dictionary,
) -> int:
	var bad := 0
	for y in h:
		for x in w:
			var a: int = out[y * w + x]
			if a <= 0:
				continue
			for d in 4:
				var np: Vector2i = Vector2i(x, y) + DELTA[d]
				if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
					continue
				var b: int = out[np.y * w + np.x]
				if b <= 0:
					continue
				if not _mutual_compat(ctx, a, d, b):
					bad += 1
	return bad


static func _done_cell_valid(
	idx: int,
	out: PackedInt32Array,
	done: PackedByteArray,
	domains: Array,
	w: int,
	h: int,
	ctx: Dictionary,
) -> bool:
	var gid: int = out[idx]
	if gid <= 0:
		return false
	var gid_to_idx: Dictionary = ctx.gid_to_idx
	if not gid_to_idx.has(gid):
		return false
	if not domains[idx][gid_to_idx[gid]]:
		return false
	var x := idx % w
	var y := idx / w
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done[ni] == 0 or out[ni] <= 0:
			continue
		if not _mutual_compat(ctx, gid, d, out[ni]):
			return false
	return true


static func _is_removable_seed(constraints: Dictionary, idx: int, initial_seed: PackedInt32Array) -> bool:
	if constraints.modes[idx] == GenConstraints.Mode.FIXED:
		return false
	if idx >= initial_seed.size() or initial_seed[idx] <= 0:
		return false
	return true


static func _adjacent_to_paint_anchor(
	idx: int,
	constraints: Dictionary,
	done: PackedByteArray,
	w: int,
	h: int,
) -> bool:
	if not constraints.has("paint_anchor"):
		return false
	var pa: PackedByteArray = constraints.paint_anchor
	if pa.size() != constraints.modes.size():
		return false
	var x := idx % w
	var y := idx / w
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done[ni] and pa[ni]:
			return true
	return false


static func _recover_local_frontier_domains(
	domains: Array,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	out: PackedInt32Array,
	constraints: Dictionary,
	w: int,
	h: int,
	ctx: Dictionary,
	exhausted: Dictionary = {},
) -> void:
	var n: int = w * h
	var count: int = ctx.count
	var idx_to_gid: PackedInt32Array = ctx.idx_to_gid
	var pa: PackedByteArray = constraints.get("paint_anchor", PackedByteArray())
	var has_paint_anchor := pa.size() == n
	for i in n:
		if exhausted.has(i):
			continue
		if constraints.modes[i] == GenConstraints.Mode.FORBID:
			continue
		if done[i]:
			continue
		if not _touches_done(i, done, w, h):
			continue
		var paint_only := has_paint_anchor and _adjacent_to_paint_anchor(
			i, constraints, done, w, h
		)
		var new_domain := PackedByteArray()
		new_domain.resize(count)
		var new_count := 0
		if paint_only:
			for t in count:
				var gid: int = idx_to_gid[t]
				if not _compatible_with_paint_neighbors(
					i, gid, out, done, w, h, ctx, pa
				):
					continue
				new_domain[t] = 1
				new_count += 1
		else:
			for t in count:
				var gid: int = idx_to_gid[t]
				if not _compatible_with_done_neighbors(i, gid, out, done, w, h, ctx):
					continue
				new_domain[t] = 1
				new_count += 1
		if new_count <= 0:
			continue
		domains[i] = new_domain
		domain_counts[i] = new_count


static func _compatible_with_paint_neighbors(
	idx: int,
	gid: int,
	out: PackedInt32Array,
	done: PackedByteArray,
	w: int,
	h: int,
	ctx: Dictionary,
	paint_anchor: PackedByteArray,
) -> bool:
	var x := idx % w
	var y := idx / w
	var touched := false
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done[ni] == 0 or out[ni] <= 0:
			continue
		if paint_anchor[ni] == 0:
			continue
		touched = true
		if not _mutual_compat(ctx, gid, d, out[ni]):
			return false
	return touched


static func finalize_init_domains(
	constraints: Dictionary,
	initial_seed: PackedInt32Array,
	domains: Array,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	out: PackedInt32Array,
	w: int,
	h: int,
	ctx: Dictionary,
) -> bool:
	var n: int = w * h
	var count: int = ctx.count
	var all_domain: PackedByteArray = ctx.all_domain

	for _pass in 8:
		var changed := false
		for i in n:
			if not done[i]:
				continue
			if not _is_removable_seed(constraints, i, initial_seed):
				continue
			if _done_cell_valid(i, out, done, domains, w, h, ctx):
				continue
			_uncollapse_cell(i, domains, domain_counts, done, out, all_domain, count)
			changed = true

		var seeds: Array = _collect_propagate_seeds(constraints, done, out, w, h)
		if seeds.is_empty():
			return true
		if not _propagate_ac4(
			seeds, domains, domain_counts, done, out, constraints, w, h, ctx
		):
			var removed := false
			for i in n:
				if not done[i]:
					continue
				if not _is_removable_seed(constraints, i, initial_seed):
					continue
				_uncollapse_cell(i, domains, domain_counts, done, out, all_domain, count)
				removed = true
				changed = true
				break
			if not removed:
				break
		if not changed:
			break

	_recover_local_frontier_domains(
		domains, domain_counts, done, out, constraints, w, h, ctx
	)
	return true


static func _compatible_with_done_neighbors(
	idx: int,
	gid: int,
	out: PackedInt32Array,
	done: PackedByteArray,
	w: int,
	h: int,
	ctx: Dictionary,
) -> bool:
	var x := idx % w
	var y := idx / w
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done[ni] == 0 or out[ni] <= 0:
			continue
		if not _mutual_compat(ctx, gid, d, out[ni]):
			return false
	return true


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

	_propagate_ac4(
		queue, domains, domain_counts, done, out, constraints, w, h, ctx
	)
	return not _has_open_contradiction(constraints, domain_counts, done, w, h)


static func _has_open_contradiction(
	constraints: Dictionary,
	domain_counts: PackedInt32Array,
	done: PackedByteArray,
	w: int,
	h: int,
) -> bool:
	for i in w * h:
		if constraints.modes[i] == GenConstraints.Mode.FORBID:
			continue
		if done[i]:
			continue
		if domain_counts[i] == 0:
			return true
	return false


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
	return _propagate_ac4(
		seed_queue, domains, domain_counts, done, out, constraints, w, h, ctx
	)


static func _propagate_ac4(
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
	var queue: Array = []
	var in_arc := {}

	for raw_idx in seed_queue:
		_enqueue_revise_arcs(int(raw_idx), w, h, queue, in_arc)

	var head := 0
	while head < queue.size():
		var arc: Array = queue[head]
		head += 1
		var dst: int = int(arc[0])
		var src: int = int(arc[1])
		var dir_idx: int = int(arc[2])
		var arc_key: String = "%d:%d:%d" % [dst, src, dir_idx]
		in_arc.erase(arc_key)

		if constraints.modes[dst] == GenConstraints.Mode.FORBID:
			continue
		if done[dst]:
			continue

		var changed: int = _narrow(
			dst, src, dir_idx, domains, domain_counts, done, out, w, h, ctx
		)
		if changed < 0:
			return false
		if changed > 0:
			_enqueue_revise_arcs(dst, w, h, queue, in_arc)

	return true


static func _enqueue_revise_arcs(
	src: int,
	w: int,
	h: int,
	queue: Array,
	in_arc: Dictionary,
) -> void:
	var x := src % w
	var y := src / w
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		var arc_key: String = "%d:%d:%d" % [ni, src, d]
		if in_arc.has(arc_key):
			continue
		in_arc[arc_key] = true
		queue.append([ni, src, d])


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

	if not done[dst] and ctx.get("pattern_propagate", false):
		if not _apply_pattern_filter(
			domains[dst], domain_counts, dst, out, done, w, h, ctx
		):
			domain_counts[dst] = 0
			return -1
		if domain_counts[dst] == 0:
			return -1

	return 1


static func _apply_pattern_filter(
	domain: PackedByteArray,
	domain_counts: PackedInt32Array,
	idx: int,
	out: PackedInt32Array,
	done: PackedByteArray,
	w: int,
	h: int,
	ctx: Dictionary,
) -> bool:
	var rules: Dictionary = ctx.get("rules", {})
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

	var allowed: Variant = _pattern_allowed_centers(out, done, idx, w, h, ctx)
	if allowed == null:
		return true

	var allowed_map: Dictionary = allowed
	var count: int = ctx.count
	var idx_to_gid: PackedInt32Array = ctx.idx_to_gid
	var backup := domain.duplicate()
	var new_count := 0
	for t in count:
		if not domain[t]:
			continue
		var gid: int = idx_to_gid[t]
		if GenRules.pattern_center_allowed(rules, gid, allowed_map):
			new_count += 1
		else:
			domain[t] = 0

	if new_count == 0:
		for t in count:
			domain[t] = backup[t]
		return true

	domain_counts[idx] = new_count
	return true


static func _pattern_allowed_centers(
	out: PackedInt32Array,
	done: PackedByteArray,
	idx: int,
	w: int,
	h: int,
	ctx: Dictionary,
):
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

	return null


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


static func _directional_context_factor(
	rules: Dictionary,
	out: PackedInt32Array,
	done: PackedByteArray,
	idx: int,
	w: int,
	h: int,
	gid: int,
	boost: float = 1.0,
) -> float:
	var x := idx % w
	var y := idx / w
	var log_sum := 0.0
	var n := 0
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done[ni] == 0 or out[ni] <= 0:
			continue
		var factor: float = GenRules.dir_context_pick_factor(
			rules, DIR_NAMES[d], out[ni], gid
		)
		if is_equal_approx(factor, 1.0):
			continue
		log_sum += log(maxf(factor * maxf(boost, 1.0), 0.0001))
		n += 1
	if n == 0:
		return 1.0
	return exp(log_sum / float(n))


static func _adj_pick_boost(
	rules: Dictionary,
	out: PackedInt32Array,
	done: PackedByteArray,
	idx: int,
	w: int,
	h: int,
	gid: int,
) -> float:
	var x := idx % w
	var y := idx / w
	var boost := 1.0
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done[ni] == 0 or out[ni] <= 0:
			continue
		var nb_gid: int = out[ni]
		var opp_dir: String = DIR_NAMES[OPPOSITE_DIR_IDX[d]]
		var opts: Dictionary = GenRules.adj_options(rules, nb_gid, opp_dir)
		var count: int = int(opts.get(str(gid), 0))
		if count > 0:
			boost = maxf(boost, sqrt(float(count)))
	return boost


static func _anchor_gid_penalty(
	constraints: Dictionary,
	idx: int,
	gid: int,
) -> float:
	if not constraints.has("paint_anchor"):
		return 1.0
	var pa: PackedByteArray = constraints.paint_anchor
	if idx < pa.size() and pa[idx]:
		return 1.0
	for i in mini(constraints.fixed_gids.size(), pa.size()):
		if pa[i] and constraints.fixed_gids[i] == gid:
			return 0.08
	return 1.0


static func _background_penalty(rules: Dictionary, gid: int, option_count: int) -> float:
	if option_count < 2:
		return 1.0
	var bg: int = int(rules.get("sources", {}).get("background_gid", 1))
	if bg <= 0:
		bg = int(rules.get("background_gid", 1))
	if bg > 0 and gid == bg:
		return 0.12 if option_count >= 4 else 0.35
	return 1.0


static func _pick_jitter(rng: RandomNumberGenerator, amount: float) -> float:
	if amount <= 0.0:
		return 1.0
	return 1.0 + (rng.randf() * 2.0 - 1.0) * amount


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
	constraints: Dictionary = {},
	ctx: Dictionary = {},
	options: Dictionary = {},
) -> int:
	var pick_indices: Array = _domain_pick_indices(domain)
	if pick_indices.is_empty():
		return 0

	var filtered: Array = []
	var paint_only := false
	var pa: PackedByteArray = PackedByteArray()
	if not constraints.is_empty() and constraints.has("paint_anchor"):
		pa = constraints.paint_anchor
		paint_only = _adjacent_to_paint_anchor(idx, constraints, done, w, h)
	for option_idx in pick_indices:
		if exclude.has(option_idx):
			continue
		var gid: int = idx_to_gid[option_idx]
		var ok := false
		if paint_only:
			ok = _compatible_with_paint_neighbors(idx, gid, out, done, w, h, ctx, pa)
		else:
			ok = _compatible_with_done_neighbors(idx, gid, out, done, w, h, ctx)
		if not ok:
			continue
		filtered.append(option_idx)
	if filtered.is_empty():
		return -1

	var ctx_key: String = _context_pick_key_at(out, done, idx, w, h)
	var partial_3x3 := _build_partial_3x3(out, done, idx, w, h)
	var context_boost: float = float(options.get("context_boost", 4.0))
	var use_pattern_pick: bool = bool(options.get("use_pattern_pick", true))
	var use_bg_penalty: bool = bool(options.get("background_penalty", true))
	var pick_jitter: float = float(options.get("pick_jitter", 0.12))

	var total := 0.0
	var weights: Array = []
	for option_idx in filtered:
		var gid: int = idx_to_gid[option_idx]
		var weight: float = GenRules.pick_weight(rules, gid)
		weight *= _directional_context_factor(
			rules, out, done, idx, w, h, gid, context_boost
		)
		if use_pattern_pick:
			weight *= GenRules.pattern_pick_factor(rules, partial_3x3, gid)
		weight *= _adj_pick_boost(rules, out, done, idx, w, h, gid)
		weight *= _anchor_gid_penalty(constraints, idx, gid)
		weight *= GenRules.context_weight_boosted(rules, ctx_key, gid, context_boost)
		if use_bg_penalty:
			weight *= _background_penalty(rules, gid, filtered.size())
		weight *= _pick_jitter(rng, pick_jitter)
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
