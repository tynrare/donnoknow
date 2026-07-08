extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const RULES_PATH := "res://resources/generator/adve.rules.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(RULES_PATH)
	var inner := Vector2i(48, 29)
	var halo := 1
	var gw := inner.x + halo * 2
	var gh := inner.y + halo * 2
	var n := gw * gh
	var bg := int(manifest.get("background_gid", 1))

	var paint := PackedInt32Array()
	paint.resize(n)
	paint.fill(0)
	paint[(halo + 14) * gw + (halo + 24)] = 27

	var ctx := PackedInt32Array()
	ctx.resize(n)
	ctx.fill(0)
	for y in gh:
		for x in gw:
			var in_inner := x >= halo and y >= halo and x < halo + inner.x and y < halo + inner.y
			if in_inner:
				ctx[y * gw + x] = 29 if (x + y) % 3 == 0 else bg
			elif (x + y) % 2 == 0:
				ctx[y * gw + x] = bg

	var c := GenConstraints.from_paint_seed_and_halo(
		gw, gh, halo, inner.x, inner.y, paint, ctx, false
	)

	var t0 := Time.get_ticks_msec()
	var job := GenWfcJob.new(rules, c, manifest, 42, GenService.default_options())
	print("halo48 init=", Time.get_ticks_msec() - t0, "ms ready=", job.ready)
	if not job.ready:
		push_error("FAIL not ready")
		quit(1)
		return

	var steps := 0
	while not job.finished and steps < 50000:
		job.step()
		steps += 1

	var bad := _count_bad(job.out, gw, gh, rules)
	print("steps=", steps, " bad_adj=", bad, " unique=", _unique(job.out))
	if bad > 0:
		push_error("FAIL halo continue: %d bad pairs" % bad)
		quit(1)
		return
	if steps <= 1:
		push_error("FAIL halo continue: finished without expanding (%d steps)" % steps)
		quit(1)
		return
	print("PASS halo continue 48x29")
	quit(0)


func _count_bad(gids: PackedInt32Array, w: int, h: int, rules: Dictionary) -> int:
	var delta := [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]
	var dirs := ["north", "east", "south", "west"]
	var bad := 0
	for y in h:
		for x in w:
			var a: int = gids[y * w + x]
			if a <= 0:
				continue
			for d in 4:
				var np: Vector2i = Vector2i(x, y) + delta[d]
				if np.x < 0 or np.y < 0 or np.x >= w or np.y >= h:
					continue
				var b: int = gids[np.y * w + np.x]
				if b <= 0:
					continue
				if int(GenRules.adj_options(rules, a, dirs[d]).get(str(b), 0)) <= 0:
					bad += 1
	return bad


func _unique(gids: PackedInt32Array) -> int:
	var s := {}
	for g in gids:
		if g > 0:
			s[g] = true
	return s.size()
