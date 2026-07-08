extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const RULES_PATH := "res://resources/generator/adve.rules.json"
const SIZE := 10
const FIXED_GID := 27
const FIXED_X := 5
const FIXED_Y := 5
const SEED := 42


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(RULES_PATH)
	var c := GenConstraints.empty(SIZE, SIZE)
	GenConstraints.set_fixed(c, FIXED_X, FIXED_Y, FIXED_GID)

	var job := GenWfcJob.new(rules, c, manifest, SEED, GenService.default_options())
	if not job.ready:
		push_error("FAIL: job not ready")
		quit(1)
		return

	var order: Array = []
	while not job.finished:
		var step: Dictionary = job.step()
		if step.get("finished", false):
			break
		if step.has("idx"):
			order.append(int(step.idx))

	var gids: PackedInt32Array = job.out
	_print_grid(gids, SIZE)
	_print_stats(gids, SIZE, order, rules)
	quit(0)


func _print_grid(gids: PackedInt32Array, w: int) -> void:
	print("Grid (local atlas index = gid - first_gid):")
	for y in w:
		var row := ""
		for x in w:
			var g: int = gids[y * w + x]
			if g <= 0:
				row += ".. "
			else:
				row += "%02d " % (g - 1)
		print(row)


func _print_stats(gids: PackedInt32Array, w: int, order: Array, rules: Dictionary) -> void:
	var counts: Dictionary = {}
	for g in gids:
		if g <= 0:
			continue
		counts[g] = int(counts.get(g, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	print("Unique tiles: %d" % keys.size())
	for k in keys:
		print("  gid %d: %d cells" % [int(k), counts[k]])

	var max_run := 1
	var run := 1
	for i in range(1, order.size()):
		var a: Vector2i = _idx_to_xy(order[i - 1], w)
		var b: Vector2i = _idx_to_xy(order[i], w)
		if absi(a.x - b.x) + absi(a.y - b.y) == 1:
			run += 1
			max_run = maxi(max_run, run)
		else:
			run = 1
	print("Max adjacent collapse run (snake metric): %d / %d steps" % [max_run, order.size()])

	var same_as_prev := 0
	for i in range(1, order.size()):
		if gids[order[i]] == gids[order[i - 1]]:
			same_as_prev += 1
	print("Same gid as previous collapse: %d" % same_as_prev)
	var bad := _validate_adjacency(gids, w, rules)
	if bad > 0:
		push_error("FAIL: invalid adjacency")
		quit(1)
	if keys.size() < 8:
		push_error("FAIL: low variety (%d unique tiles)" % keys.size())
		quit(1)
	if same_as_prev > 45:
		push_error("FAIL: too repetitive (%d same-as-prev)" % same_as_prev)
		quit(1)
	print("PASS 10x10 fixed-27 variety/adjacency")


func _validate_adjacency(gids: PackedInt32Array, w: int, rules: Dictionary) -> int:
	var adj: Dictionary = rules.get("adjacency", {})
	var OP := {"north": "south", "east": "west", "south": "north", "west": "east"}
	var bad := 0
	for y in w:
		for x in w:
			var i := y * w + x
			var a: int = gids[i]
			if a <= 0:
				continue
			for d in ["north", "east", "south", "west"]:
				var np := Vector2i(x, y) + _delta(d)
				if np.x < 0 or np.y < 0 or np.x >= w or np.y >= w:
					continue
				var b: int = gids[np.y * w + np.x]
				if b <= 0:
					continue
				var ok: int = int(adj.get(str(a), {}).get(d, {}).get(str(b), 0))
				var ok2: int = int(adj.get(str(b), {}).get(OP[d], {}).get(str(a), 0))
				if ok <= 0 or ok2 <= 0:
					bad += 1
	print("Invalid adjacency pairs: %d" % bad)
	return bad


func _delta(d: String) -> Vector2i:
	match d:
		"north":
			return Vector2i(0, -1)
		"east":
			return Vector2i(1, 0)
		"south":
			return Vector2i(0, 1)
		_:
			return Vector2i(-1, 0)


func _idx_to_xy(idx: int, w: int) -> Vector2i:
	return Vector2i(idx % w, idx / w)
