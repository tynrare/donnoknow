# agent: composer-2.5 | 2026-07-08 | moderated seam backtracking | f7a8b9
extends RefCounted

const Core := preload("res://scripts/generator/wfc_core.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenService := preload("res://scripts/generator/service.gd")

const _DELTA := [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

var cancelled := false
var finished := false

var rules: Dictionary = {}
var constraints: Dictionary = {}
var ctx: Dictionary = {}
var rng: RandomNumberGenerator
var options: Dictionary = {}

var domains: Array = []
var domain_counts: PackedInt32Array
var done: PackedByteArray
var out: PackedInt32Array

var w: int = 0
var h: int = 0
var n: int = 0
var base_seed: int = 0
var ready := false

var collapse_stack: Array = []
var tried_picks: Dictionary = {}
var _initial_seed: PackedInt32Array = PackedInt32Array()
var _retry_cell: int = -1
var _exhausted_cells := {}
var _bfs_wave: PackedInt32Array = PackedInt32Array()
var _last_collapsed: int = -1
var _anchor_mask: PackedByteArray = PackedByteArray()
var _wave_source_mask: PackedByteArray = PackedByteArray()
var _backtrack_incidents: int = 0
var _backtrack_pops: int = 0


func _init(
	p_rules: Dictionary,
	p_constraints: Dictionary,
	p_manifest: Dictionary,
	p_seed: int = 0,
	p_options: Dictionary = {},
) -> void:
	rules = p_rules
	constraints = p_constraints
	base_seed = p_seed
	options = GenService.default_options()
	for key in p_options:
		options[key] = p_options[key]

	w = constraints.width
	h = constraints.height
	n = w * h
	_initial_seed = _read_seed_gids(constraints)

	var tiles := GenRules.generatable_tiles(rules, p_manifest)
	tiles = Core.merge_runtime_tiles(rules, tiles, constraints, _initial_seed)
	if tiles.is_empty():
		finished = true
		return

	ctx = Core._build_context(rules, tiles)
	Core._alias_signature_members(rules, ctx)
	Core._augment_compat_from_constraints(constraints, ctx)
	_start_attempt()


static func _read_seed_gids(constraints: Dictionary) -> PackedInt32Array:
	var n: int = constraints.width * constraints.height
	var seeds: Variant = constraints.get("seed_gids", PackedInt32Array())
	if seeds is not PackedInt32Array or seeds.size() != n:
		var out := PackedInt32Array()
		out.resize(n)
		out.fill(0)
		return out
	return seeds.duplicate()


func cancel() -> void:
	cancelled = true


func step() -> Dictionary:
	if finished:
		return {"finished": true, "ok": false, "error": "already finished"}
	if cancelled:
		finished = true
		return _finish_now(false, true)

	if not ready:
		return _finish_now(false, false, "fixed tile contradiction")

	var best: int = _retry_cell
	if best >= 0:
		if done[best] or domain_counts[best] == 0:
			_retry_cell = -1
			best = -1
	if best < 0:
		best = _pick_next_cell()
	if best < 0:
		return _finish_now(true, false, "no collapsible cells")

	var count: int = ctx.count
	var idx_to_gid: PackedInt32Array = ctx.idx_to_gid
	var exclude: Array = tried_picks.get(best, [])
	if Core.untried_domain_count(domains[best], exclude) == 0:
		return _handle_skip(best)

	var picked_idx: int = Core._weighted_pick_idx(
		rules,
		domains[best],
		idx_to_gid,
		rng,
		out,
		done,
		best,
		w,
		h,
		exclude,
		constraints,
		ctx,
	)
	if picked_idx < 0:
		return _handle_skip(best)

	var prev_domain: PackedByteArray = domains[best].duplicate()
	var prev_count: int = domain_counts[best]
	var picked_domain := PackedByteArray()
	picked_domain.resize(count)
	picked_domain[picked_idx] = 1
	domains[best] = picked_domain
	domain_counts[best] = 1
	done[best] = 1
	var rep_gid: int = idx_to_gid[picked_idx]
	out[best] = rep_gid

	var queue: Array = [best]
	if not Core._propagate(queue, domains, domain_counts, done, out, constraints, w, h, ctx):
		return _handle_collapse_failure(best, prev_domain, prev_count, picked_idx)

	if not Core.repair_continue_conflicts_at(
		best,
		_initial_seed,
		constraints,
		domains,
		domain_counts,
		done,
		out,
		w,
		h,
		ctx,
	):
		return _handle_collapse_failure(best, prev_domain, prev_count, picked_idx)

	if Core.cell_has_bad_adjacency(best, out, done, w, h, ctx):
		_undo_open_collapse(best, prev_domain, prev_count)
		_record_tried(best, picked_idx)
		if not Core.repropagate(
			domains, domain_counts, done, out, constraints, w, h, ctx, collapse_stack
		):
			return _handle_skip(best)
		return _handle_failure_after_tried(best, prev_domain)

	out[best] = GenRules.resolve_generatable_gid(rules, rep_gid, rng)

	collapse_stack.append({
		"idx": best,
		"domain": prev_domain,
		"count": prev_count,
		"gid": out[best],
		"tile_idx": picked_idx,
	})
	tried_picks.erase(best)
	_retry_cell = -1
	_last_collapsed = best
	_bfs_update_wave(best)

	return {
		"finished": false,
		"idx": best,
		"gid": out[best],
	}


func _pick_next_cell() -> int:
	var best := Core._pick_collapse_cell(
		constraints,
		domain_counts,
		done,
		w,
		h,
		rng,
		true,
		_bfs_wave,
		_last_collapsed,
		_anchor_mask,
	)
	if best >= 0:
		return best
	Core._recover_local_frontier_domains(
		domains, domain_counts, done, out, constraints, w, h, ctx, _exhausted_cells
	)
	return Core._pick_collapse_cell(
		constraints,
		domain_counts,
		done,
		w,
		h,
		rng,
		true,
		_bfs_wave,
		_last_collapsed,
		_anchor_mask,
	)


func _undo_open_collapse(idx: int, prev_domain: PackedByteArray, prev_count: int) -> void:
	done[idx] = 0
	out[idx] = 0
	domains[idx] = prev_domain
	domain_counts[idx] = prev_count


func _handle_collapse_failure(
	idx: int,
	prev_domain: PackedByteArray,
	prev_count: int,
	picked_idx: int,
) -> Dictionary:
	_undo_open_collapse(idx, prev_domain, prev_count)
	_record_tried(idx, picked_idx)
	if not Core.repropagate(
		domains, domain_counts, done, out, constraints, w, h, ctx, collapse_stack
	):
		return _handle_skip(idx)
	return _handle_failure_after_tried(idx, prev_domain)


func _handle_failure_after_tried(idx: int, prev_domain: PackedByteArray) -> Dictionary:
	var tried: Array = tried_picks.get(idx, [])
	var remaining: int = Core.untried_domain_count(prev_domain, tried)
	if remaining > 0:
		_retry_cell = idx
		return {"finished": false, "retry": true, "idx": idx}
	if _try_backtrack(idx):
		return {"finished": false, "backtrack": true, "idx": _retry_cell}
	return _handle_skip(idx)


func _handle_skip(idx: int) -> Dictionary:
	if Core._touches_done(idx, done, w, h) and _try_backtrack(idx):
		return {"finished": false, "backtrack": true, "idx": _retry_cell}
	return _skip_cell(idx)


func _try_backtrack(retry_idx: int) -> bool:
	if not _backtrack_budget_ok():
		return false
	if collapse_stack.is_empty():
		return false

	_backtrack_incidents += 1
	var depth_limit: int = int(options.get("backtrack_depth", 5))
	var target_idx := retry_idx
	var pops := 0

	while pops < depth_limit and not collapse_stack.is_empty():
		var entry: Dictionary = collapse_stack.pop_back()
		pops += 1
		_backtrack_pops += 1
		_exhausted_cells.erase(int(entry.idx))
		if entry.has("tile_idx"):
			_record_tried(int(entry.idx), int(entry.tile_idx))
		target_idx = int(entry.idx)
		if constraints.modes[target_idx] == GenConstraints.Mode.GENERATE:
			break

	if pops <= 0:
		return false

	if not Core.repropagate(
		domains, domain_counts, done, out, constraints, w, h, ctx, collapse_stack
	):
		return false

	_exhausted_cells.clear()
	_last_collapsed = collapse_stack.back().idx if not collapse_stack.is_empty() else -1
	_retry_cell = target_idx
	return true


func _backtrack_budget_ok() -> bool:
	if _backtrack_incidents >= int(options.get("backtrack_incidents", 20)):
		return false
	if _backtrack_pops >= int(options.get("backtrack_cells", 50)):
		return false
	return true


func _skip_cell(idx: int) -> Dictionary:
	var count: int = ctx.count
	_retry_cell = -1
	_exhausted_cells[idx] = true
	tried_picks.erase(idx)
	if done[idx]:
		done[idx] = 0
		out[idx] = 0
	domain_counts[idx] = 0
	for t in count:
		domains[idx][t] = 0
	_apply_exhausted_cells(count)
	return {"finished": false, "skipped": idx}


func _record_tried(idx: int, tile_idx: int) -> void:
	if not tried_picks.has(idx):
		tried_picks[idx] = []
	tried_picks[idx].append(tile_idx)


func _apply_exhausted_cells(count: int) -> void:
	for idx in _exhausted_cells:
		domain_counts[idx] = 0
		for t in count:
			domains[idx][t] = 0


func _finish_now(ok: bool, was_cancelled: bool, reason: String = "") -> Dictionary:
	finished = true
	var gids := PackedInt32Array()
	gids.resize(n)
	for i in n:
		gids[i] = out[i]
	var filled: Dictionary = Core._count_filled(gids, constraints)
	var method := "wfc"
	if filled.done < filled.generatable:
		method = "wfc_partial"
	var bad_adj: int = Core.count_bad_adjacency(gids, w, h, ctx)
	var success: bool = (not was_cancelled) and (ok or int(filled.done) > 0)
	return {
		"finished": true,
		"ok": success,
		"cancelled": was_cancelled,
		"gids": gids,
		"seed": base_seed,
		"method": method,
		"filled": filled.done,
		"total": filled.generatable,
		"bad_adj": bad_adj,
		"backtracks": _backtrack_incidents,
		"error": reason,
	}


func _start_attempt() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = base_seed
	collapse_stack.clear()
	tried_picks.clear()
	_retry_cell = -1
	_exhausted_cells.clear()
	_last_collapsed = -1
	_backtrack_incidents = 0
	_backtrack_pops = 0

	var count: int = ctx.count
	var all_domain: PackedByteArray = ctx.all_domain
	var gid_to_idx: Dictionary = ctx.gid_to_idx

	domains = []
	domains.resize(n)
	domain_counts = PackedInt32Array()
	domain_counts.resize(n)
	done = PackedByteArray()
	done.resize(n)
	out = PackedInt32Array()
	out.resize(n)
	out.fill(0)

	for i in n:
		match constraints.modes[i]:
			GenConstraints.Mode.FORBID:
				domains[i] = PackedByteArray()
				domains[i].resize(count)
				domain_counts[i] = 0
				done[i] = 1
				out[i] = 0
			GenConstraints.Mode.FIXED:
				var gid: int = constraints.fixed_gids[i]
				if not gid_to_idx.has(gid):
					ready = false
					return
				var fixed_domain := PackedByteArray()
				fixed_domain.resize(count)
				fixed_domain[gid_to_idx[gid]] = 1
				domains[i] = fixed_domain
				domain_counts[i] = 1
				done[i] = 1
				out[i] = gid
			_:
				var seed_gid: int = _initial_seed[i] if i < _initial_seed.size() else 0
				if seed_gid > 0 and gid_to_idx.has(seed_gid):
					var seed_domain := PackedByteArray()
					seed_domain.resize(count)
					seed_domain[gid_to_idx[seed_gid]] = 1
					domains[i] = seed_domain
					domain_counts[i] = 1
					done[i] = 1
					out[i] = seed_gid
				else:
					domains[i] = Core._domain_copy(all_domain)
					domain_counts[i] = count
					done[i] = 0

	var seeds: Array = Core._collect_propagate_seeds(constraints, done, out, w, h)
	if not seeds.is_empty():
		Core.finalize_init_domains(
			constraints,
			_initial_seed,
			domains,
			domain_counts,
			done,
			out,
			w,
			h,
			ctx,
		)
	_bfs_init_waves()
	ready = true


func _build_anchor_mask() -> void:
	_anchor_mask = PackedByteArray()
	_anchor_mask.resize(n)
	_anchor_mask.fill(0)
	var has_paint := false
	if constraints.has("paint_anchor"):
		var pa: PackedByteArray = constraints.paint_anchor
		for i in mini(n, pa.size()):
			if pa[i]:
				_anchor_mask[i] = 1
				has_paint = true
	for i in n:
		if _initial_seed[i] > 0 and done[i]:
			_anchor_mask[i] = 1
			has_paint = true
	if not has_paint:
		for i in n:
			if constraints.modes[i] == GenConstraints.Mode.FIXED:
				_anchor_mask[i] = 1


func _build_wave_source_mask() -> void:
	_build_anchor_mask()
	_wave_source_mask = _anchor_mask.duplicate()
	for i in n:
		if constraints.modes[i] != GenConstraints.Mode.FIXED:
			continue
		if _anchor_mask[i]:
			continue
		_wave_source_mask[i] = 1


func _bfs_init_waves() -> void:
	_build_wave_source_mask()
	_bfs_wave = Core.bfs_wave_from_anchors(constraints, _wave_source_mask, w, h)


func _bfs_update_wave(collapsed_idx: int) -> void:
	var base: int = _bfs_wave[collapsed_idx]
	var x := collapsed_idx % w
	var y := collapsed_idx / w
	for d in 4:
		var np: Vector2i = Vector2i(x, y) + _DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
			continue
		var ni: int = np.y * w + np.x
		if done[ni]:
			continue
		_bfs_wave[ni] = mini(_bfs_wave[ni], base + 1)
