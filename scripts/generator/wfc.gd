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
	var job = GenWfcJob.new(rules, constraints, manifest, seed, options)
	while not job.finished:
		var step: Dictionary = job.step()
		if step.get("finished", false):
			return _finalize_result(step, rules, constraints, seed, manifest, options)

	return _finalize_result(
		{"ok": false, "gids": job.out, "seed": seed},
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

	var filled := Core._count_filled(gids, constraints)
	var method := "wfc" if filled.done == filled.generatable else "wfc_partial"

	return {
		"ok": filled.done > 0 or filled.done == filled.generatable or filled.generatable == 0,
		"gids": gids,
		"seed": int(step.get("seed", seed)),
		"method": method,
		"filled": filled.done,
		"total": filled.generatable,
		"error": step.get("error", ""),
	}
