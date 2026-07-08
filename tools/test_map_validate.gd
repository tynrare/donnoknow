extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const RULES_PATH := "res://resources/generator/adve.rules.json"
const DEADLINE_MS := 90_000


func _init() -> void:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	_run_case("10x10", Vector2i(10, 10), 5, 5, deadline)
	_run_case("48x29", Vector2i(48, 29), 24, 14, deadline)
	_run_case("54x35", Vector2i(54, 35), 27, 17, deadline)
	print("PASS map validate suite")
	quit(0)


func _run_case(label: String, size: Vector2i, fx: int, fy: int, deadline: int) -> void:
	if Time.get_ticks_msec() > deadline:
		push_error("FAIL: timeout before %s" % label)
		quit(1)
		return

	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(RULES_PATH)
	var c := GenConstraints.empty(size.x, size.y)
	GenConstraints.set_fixed(c, fx, fy, 27)

	var t0 := Time.get_ticks_msec()
	var job := GenWfcJob.new(rules, c, manifest, 42, GenService.default_options())
	var init_ms := Time.get_ticks_msec() - t0
	if not job.ready:
		push_error("FAIL %s: job not ready" % label)
		quit(1)
		return
	if init_ms > 2000:
		push_error("FAIL %s: init too slow (%d ms)" % [label, init_ms])
		quit(1)
		return

	var steps := 0
	while not job.finished:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL %s: generation timeout at step %d" % [label, steps])
			quit(1)
			return
		job.step()
		steps += 1

	var run_ms := Time.get_ticks_msec() - t0 - init_ms
	var bad := _count_bad_adjacency(job.out, size.x, size.y, rules)
	var unique := _unique_tiles(job.out)
	var filled := 0
	for g in job.out:
		if g > 0:
			filled += 1

	print(
		"%s init=%dms run=%dms steps=%d filled=%d unique=%d bad_adj=%d"
		% [label, init_ms, run_ms, steps, filled, unique, bad]
	)
	if bad > 0:
		push_error("FAIL %s: %d invalid adjacency pairs" % [label, bad])
		quit(1)
	if unique < 6:
		push_error("FAIL %s: low variety (%d unique)" % [label, unique])
		quit(1)


func _count_bad_adjacency(gids: PackedInt32Array, w: int, h: int, rules: Dictionary) -> int:
	var adj: Dictionary = rules.get("adjacency", {})
	var op := {"north": "south", "east": "west", "south": "north", "west": "east"}
	var delta := {
		"north": Vector2i(0, -1),
		"east": Vector2i(1, 0),
		"south": Vector2i(0, 1),
		"west": Vector2i(-1, 0),
	}
	var bad := 0
	for y in h:
		for x in w:
			var a: int = gids[y * w + x]
			if a <= 0:
				continue
			for d in ["north", "east", "south", "west"]:
				var np: Vector2i = Vector2i(x, y) + delta[d]
				if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
					continue
				var b: int = gids[np.y * w + np.x]
				if b <= 0:
					continue
				var ok: int = int(adj.get(str(a), {}).get(d, {}).get(str(b), 0))
				var ok2: int = int(adj.get(str(b), {}).get(op[d], {}).get(str(a), 0))
				if ok <= 0 or ok2 <= 0:
					bad += 1
	return bad


func _unique_tiles(gids: PackedInt32Array) -> int:
	var seen := {}
	for g in gids:
		if g > 0:
			seen[g] = true
	return seen.size()
