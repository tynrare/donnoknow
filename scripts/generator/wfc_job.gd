# agent: composer-2.5 | 2026-07-07 | seed resume propagate | e2f3a4
extends RefCounted

const GenWfc := preload("res://scripts/generator/wfc.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenDebugLog := preload("res://scripts/generator/debug_log.gd")

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
var attempt: int = 0
var max_restarts: int = 32
var ready := false

var collapse_stack: Array = []
var tried_picks: Dictionary = {}
var backtrack_depth: int = 8
var backtracks_used: int = 0
var use_patterns: bool = false
var tile_bias: Dictionary = {}
var repeat_penalty: float = 1.0
var _initial_seed: PackedInt32Array = PackedInt32Array()
var _retry_cell: int = -1
var _exhausted_cells := {}


func _init(
	p_rules: Dictionary,
	p_constraints: Dictionary,
	p_manifest: Dictionary,
	p_seed: int = 0,
	p_max_restarts: int = 32,
	p_options: Dictionary = {},
) -> void:
	rules = p_rules
	constraints = p_constraints
	base_seed = p_seed
	max_restarts = p_max_restarts if p_max_restarts != null else 32
	options = p_options
	backtrack_depth = int(options.get("backtrack_depth", 8))
	use_patterns = bool(options.get("use_patterns", false))
	tile_bias = options.get("tile_bias", {})
	repeat_penalty = clampf(float(options.get("repeat_penalty", 1.0)), 0.0, 1.0)
	var opt_restarts: Variant = options.get("max_restarts", null)
	if opt_restarts != null:
		max_restarts = int(opt_restarts)

	var tiles := GenRules.generatable_tiles(rules, p_manifest)
	tiles = GenWfc._merge_fixed_tiles(tiles, constraints)
	if tiles.is_empty():
		finished = true
		return

	ctx = GenWfc._build_context(rules, tiles, use_patterns)
	GenWfc._augment_compat_from_constraints(constraints, ctx)
	w = constraints.width
	h = constraints.height
	n = w * h
	_initial_seed = _read_seed_gids(constraints)
	attempt = 0
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
		best = GenWfc._pick_collapse_cell(constraints, domain_counts, done, w, h, rng)

	if best < 0:
		return _finish_now(true, false)

	if not GenWfc._apply_pattern_filter(
		domains[best], domain_counts, best, out, done, w, h, ctx
	):
		return _skip_cell(best)

	var count: int = ctx.count
	var idx_to_gid: PackedInt32Array = ctx.idx_to_gid
	var exclude: Array = tried_picks.get(best, [])
	if GenWfc.untried_domain_count(domains[best], exclude) == 0:
		return _skip_cell(best)

	var picked_idx: int = GenWfc._weighted_pick_idx(
		rules,
		domains[best],
		idx_to_gid,
		rng,
		out,
		done,
		best,
		w,
		h,
		tile_bias,
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
	if not GenWfc._propagate(queue, domains, domain_counts, done, out, constraints, w, h, ctx):
		done[best] = 0
		out[best] = 0
		domains[best] = prev_domain
		domain_counts[best] = prev_count
		_record_tried(best, picked_idx)
		if not GenWfc.repropagate(
			domains, domain_counts, done, out, constraints, w, h, ctx, collapse_stack
		):
			return _skip_cell(best)
		_apply_exhausted_cells(count)
		var tried: Array = tried_picks.get(best, [])
		var remaining: int = GenWfc.untried_domain_count(prev_domain, tried)
		#region agent log
		if remaining <= 0 or attempt <= 2:
			GenDebugLog.write(
				"H5",
				"wfc_job.gd:step",
				"propagate_fail",
				{
					"attempt": attempt,
					"cell": best,
					"picked_gid": idx_to_gid[picked_idx],
					"domain_size": prev_count,
					"tried": tried.size(),
					"remaining": remaining,
				},
			)
		#endregion
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
	var filled: Dictionary = GenWfc._count_filled(gids, constraints)
	var method := "wfc"
	if filled.done < filled.generatable:
		method = "wfc_partial"
	var success: bool = (not was_cancelled) and (ok or int(filled.done) > 0)
	#region agent log
	GenDebugLog.write(
		"H4",
		"wfc_job.gd:_finish_now",
		"job_finished",
		{
			"ok_param": ok,
			"success": success,
			"filled": filled.done,
			"total": filled.generatable,
			"attempts": attempt,
			"backtracks": backtracks_used,
			"method": method,
			"reason": reason,
		},
	)
	#endregion
	return {
		"finished": true,
		"ok": success,
		"cancelled": was_cancelled,
		"gids": gids,
		"seed": base_seed + attempt - 1,
		"attempts": attempt,
		"backtracks": backtracks_used,
		"method": method,
		"filled": filled.done,
		"total": filled.generatable,
		"error": reason,
	}


func _start_attempt() -> void:
	attempt += 1
	rng = RandomNumberGenerator.new()
	rng.seed = base_seed + attempt - 1
	collapse_stack.clear()
	tried_picks.clear()
	backtracks_used = 0
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
					domains[i] = GenWfc._domain_copy(all_domain)
					domain_counts[i] = count
					done[i] = 0

	var seeds: Array = []
	for i in n:
		if done[i] and out[i] > 0:
			seeds.append(i)
	var init_mode := "none"
	var repaired := 0
	if not seeds.is_empty():
		init_mode = "propagate"
		if not GenWfc._propagate(
			seeds, domains, domain_counts, done, out, constraints, w, h, ctx
		):
			init_mode = "propagate_repaired"
		for i in n:
			if done[i]:
				continue
			if domain_counts[i] == 0:
				domains[i] = GenWfc._domain_copy(all_domain)
				domain_counts[i] = count
				repaired += 1
	ready = true
	#region agent log
	var avg_domain := 0.0
	var open_cells := 0
	var zero_domains := 0
	for i in n:
		if done[i]:
			continue
		open_cells += 1
		if domain_counts[i] == 0:
			zero_domains += 1
		avg_domain += float(domain_counts[i])
	if open_cells > 0:
		avg_domain /= float(open_cells)
	GenDebugLog.write(
		"H3",
		"wfc_job.gd:_start_attempt",
		"init_domains",
		{
			"attempt": attempt,
			"tile_count": count,
			"open_cells": open_cells,
			"zero_domains": zero_domains,
			"avg_domain": avg_domain,
			"init_propagate": init_mode,
			"seed_cells": seeds.size(),
			"repaired": repaired,
		},
	)
	#endregion
