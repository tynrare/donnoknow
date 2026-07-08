# agent: composer-2.5 | 2026-07-08 | preload wfc_core breaks cycle | e5f6a7
extends RefCounted

const Core := preload("res://scripts/generator/wfc_core.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")

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
var repeat_penalty: float = 1.0
var _initial_seed: PackedInt32Array = PackedInt32Array()
var _retry_cell: int = -1
var _exhausted_cells := {}


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
	options = p_options
	repeat_penalty = clampf(float(options.get("repeat_penalty", 1.0)), 0.0, 1.0)

	var tiles := GenRules.generatable_tiles(rules, p_manifest)
	tiles = Core._merge_fixed_tiles(tiles, constraints)
	if tiles.is_empty():
		finished = true
		return

	ctx = Core._build_context(rules, tiles)
	Core._augment_compat_from_constraints(constraints, ctx)
	w = constraints.width
	h = constraints.height
	n = w * h
	_initial_seed = _read_seed_gids(constraints)
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
		best = Core._pick_collapse_cell(constraints, domain_counts, done, w, h, rng)

	if best < 0:
		return _finish_now(true, false)

	var count: int = ctx.count
	var idx_to_gid: PackedInt32Array = ctx.idx_to_gid
	var exclude: Array = tried_picks.get(best, [])
	if Core.untried_domain_count(domains[best], exclude) == 0:
		return _skip_cell(best)

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
		repeat_penalty,
	)

	var prev_domain: PackedByteArray = domains[best].duplicate()
	var prev_count: int = domain_counts[best]
	var picked_domain := PackedByteArray()
	picked_domain.resize(count)
	picked_domain[picked_idx] = 1
	domains[best] = picked_domain
	domain_counts[best] = 1
	done[best] = 1
	out[best] = idx_to_gid[picked_idx]

	var queue: Array = [best]
	if not Core._propagate(queue, domains, domain_counts, done, out, constraints, w, h, ctx):
		done[best] = 0
		out[best] = 0
		domains[best] = prev_domain
		domain_counts[best] = prev_count
		_record_tried(best, picked_idx)
		if not Core.repropagate(
			domains, domain_counts, done, out, constraints, w, h, ctx, collapse_stack
		):
			return _skip_cell(best)
		_apply_exhausted_cells(count)
		var tried: Array = tried_picks.get(best, [])
		var remaining: int = Core.untried_domain_count(prev_domain, tried)
		if remaining > 0:
			_retry_cell = best
			return {"finished": false, "retry": true, "idx": best}
		return _skip_cell(best)

	collapse_stack.append({
		"idx": best,
		"domain": prev_domain,
		"count": prev_count,
		"gid": out[best],
		"tile_idx": picked_idx,
	})
	tried_picks.erase(best)
	_retry_cell = -1

	return {
		"finished": false,
		"idx": best,
		"gid": out[best],
	}


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
		"error": reason,
	}


func _start_attempt() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = base_seed
	collapse_stack.clear()
	tried_picks.clear()
	_retry_cell = -1
	_exhausted_cells.clear()

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
		Core._propagate_one_hop(
			seeds, domains, domain_counts, done, out, constraints, w, h, ctx
		)
		for i in n:
			if done[i]:
				continue
			if domain_counts[i] == 0:
				domains[i] = Core._domain_copy(all_domain)
				domain_counts[i] = count
	ready = true
