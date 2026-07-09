# agent: composer-2.5 | 2026-07-08 | sync generate via preloaded job | d4e5f6
extends RefCounted

const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const Core := preload("res://scripts/generator/wfc_core.gd")


static func generate(
	rules: Dictionary,
	constraints: Dictionary,
	seed: int = 0,
	manifest: Dictionary = {},
	options: Dictionary = {},
) -> Dictionary:
	var max_restarts: int = maxi(int(options.get("max_restarts", 2)), 1)
	var last_step: Dictionary = {"ok": false, "gids": PackedInt32Array(), "seed": seed}
	for attempt in max_restarts:
		var attempt_seed: int = seed + attempt
		var job = GenWfcJob.new(rules, constraints, manifest, attempt_seed, options)
		while not job.finished:
			var step: Dictionary = job.step()
			if step.get("finished", false):
				last_step = step
				break
		if _attempt_acceptable(last_step):
			last_step["seed"] = attempt_seed
			last_step["attempts"] = attempt + 1
			return _finalize_result(
				last_step, rules, constraints, attempt_seed, manifest, options
			)

	last_step["attempts"] = max_restarts
	return _finalize_result(last_step, rules, constraints, seed, manifest, options)


static func _attempt_acceptable(step: Dictionary) -> bool:
	if step.get("cancelled", false):
		return true
	if not step.get("ok", false):
		return false
	var filled: int = int(step.get("filled", 0))
	var total: int = int(step.get("total", 0))
	if total > 0 and filled < total:
		return false
	if int(step.get("bad_adj", 0)) > 0:
		return false
	return true


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

	var filled := Core._count_filled(gids, constraints)
	var method := "wfc" if filled.done == filled.generatable else "wfc_partial"

	return {
		"ok": filled.done > 0 or filled.done == filled.generatable or filled.generatable == 0,
		"gids": gids,
		"seed": int(step.get("seed", seed)),
		"attempts": int(step.get("attempts", 1)),
		"method": method,
		"filled": filled.done,
		"total": filled.generatable,
		"bad_adj": int(step.get("bad_adj", 0)),
		"backtracks": int(step.get("backtracks", 0)),
		"error": step.get("error", ""),
	}
