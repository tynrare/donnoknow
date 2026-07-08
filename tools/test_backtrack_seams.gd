extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const Core := preload("res://scripts/generator/wfc_core.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const RULES_PATH := "res://resources/generator/adve.rules.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(RULES_PATH)

	_run_two_anchors("48x29 dual paint", manifest, rules, Vector2i(48, 29), 24, 14, 8, 22)
	_run_two_anchors(
		"48x29 dual paint low budget",
		manifest,
		rules,
		Vector2i(48, 29),
		24,
		14,
		8,
		22,
		{"backtrack_depth": 1, "backtrack_incidents": 2, "backtrack_cells": 3},
	)
	print("PASS backtrack seam tests")
	quit(0)


func _run_two_anchors(
	label: String,
	manifest: Dictionary,
	rules: Dictionary,
	size: Vector2i,
	ax: int,
	ay: int,
	bx: int,
	by: int,
	opts: Dictionary = {},
) -> void:
	var c := GenConstraints.empty(size.x, size.y)
	GenConstraints.set_fixed(c, ax, ay, 27)
	GenConstraints.set_fixed(c, bx, by, 27)

	var job := GenWfcJob.new(rules, c, manifest, 42, opts)
	if not job.ready:
		push_error("FAIL %s: not ready" % label)
		quit(1)
		return

	var steps := 0
	while not job.finished and steps < 50000:
		job.step()
		steps += 1

	var bad := Core.count_bad_adjacency(job.out, size.x, size.y, job.ctx)
	var filled := 0
	for g in job.out:
		if g > 0:
			filled += 1

	print(
		"%s: steps=%d filled=%d bad_adj=%d backtracks=%d"
		% [label, steps, filled, bad, job._backtrack_incidents]
	)
	if bad > 0:
		push_error("FAIL %s: %d bad adjacency pairs" % [label, bad])
		quit(1)
