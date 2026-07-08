extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const Core := preload("res://scripts/generator/wfc_core.gd")

const RULES_PATH := "res://resources/generator/adve.rules.json"
const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(RULES_PATH)

	_check("10x10 center", _job_empty(rules, manifest, 10, 10, 5, 5))
	_check(
		"48x29 halo paint",
		_job_halo(manifest, rules, Vector2i(48, 29), 1, 24, 14)
	)
	_check(
		"48x29 halo paint + continue",
		_job_halo_continue(manifest, rules, Vector2i(48, 29), 1, 24, 14)
	)
	print("PASS fixed ring tests")
	quit(0)


func _check(label: String, data: Dictionary) -> void:
	var job: GenWfcJob = data.job
	var fx: int = data.fx
	var fy: int = data.fy
	var w: int = data.w
	var fi: int = fy * w + fx
	var zero_ring := 0
	var open_ring := 0
	for d in 4:
		var np: Vector2i = Vector2i(fx, fy) + Core.DELTA[d]
		if np.x < 0 or np.y < 0 or np.x >= w or np.y >= w:
			continue
		var ni: int = np.y * w + np.x
		if job.done[ni]:
			continue
		open_ring += 1
		if job.domain_counts[ni] <= 0:
			zero_ring += 1

	var steps := 0
	var still_open := open_ring
	while not job.finished and steps < 50000 and still_open > 0:
		job.step()
		steps += 1
		still_open = 0
		for d in 4:
			var np: Vector2i = Vector2i(fx, fy) + Core.DELTA[d]
			if np.x < 0 or np.y < 0 or np.x >= w or np.y >= w:
				continue
			var ni: int = np.y * w + np.x
			if job.done[ni]:
				continue
			still_open += 1

	if still_open > 0 and steps >= 500:
		push_error("FAIL %s: ring not filled within 500 steps (%d still open)" % [label, still_open])
		quit(1)

	print(
		"%s: init_zero_ring=%d/%d still_open=%d steps=%d"
		% [label, zero_ring, open_ring, still_open, steps]
	)
	if open_ring > 0 and zero_ring > 0:
		push_error("FAIL %s: %d/%d ring neighbors have zero domain at init" % [label, zero_ring, open_ring])
		quit(1)
	if open_ring > 0 and still_open > 0:
		push_error("FAIL %s: %d/%d ring neighbors still empty" % [label, still_open, open_ring])
		quit(1)


func _job_empty(rules: Dictionary, manifest: Dictionary, w: int, h: int, fx: int, fy: int) -> Dictionary:
	var c := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(c, fx, fy, 27)
	var job := GenWfcJob.new(rules, c, manifest, 42, GenService.default_options())
	return {"job": job, "fx": fx, "fy": fy, "w": w}


func _job_halo(
	manifest: Dictionary,
	rules: Dictionary,
	inner: Vector2i,
	halo: int,
	fx: int,
	fy: int,
) -> Dictionary:
	var gw := inner.x + halo * 2
	var gh := inner.y + halo * 2
	var n := gw * gh
	var paint := PackedInt32Array()
	paint.resize(n)
	paint.fill(0)
	var ctx := PackedInt32Array()
	ctx.resize(n)
	ctx.fill(0)
	paint[(halo + fy) * gw + (halo + fx)] = 27
	var c := GenConstraints.from_paint_seed_and_halo(
		gw, gh, halo, inner.x, inner.y, paint, ctx, false
	)
	var job := GenWfcJob.new(rules, c, manifest, 42, GenService.default_options())
	return {"job": job, "fx": halo + fx, "fy": halo + fy, "w": gw}


func _job_halo_continue(
	manifest: Dictionary,
	rules: Dictionary,
	inner: Vector2i,
	halo: int,
	fx: int,
	fy: int,
) -> Dictionary:
	var gw := inner.x + halo * 2
	var gh := inner.y + halo * 2
	var n := gw * gh
	var bg := int(manifest.get("background_gid", 1))
	var paint := PackedInt32Array()
	paint.resize(n)
	paint.fill(0)
	var ctx := PackedInt32Array()
	ctx.resize(n)
	ctx.fill(0)
	paint[(halo + fy) * gw + (halo + fx)] = 27
	for y in gh:
		for x in gw:
			var in_inner := x >= halo and y >= halo and x < halo + inner.x and y < halo + inner.y
			if in_inner and (x + y) % 4 != 0:
				ctx[y * gw + x] = bg
	var c := GenConstraints.from_paint_seed_and_halo(
		gw, gh, halo, inner.x, inner.y, paint, ctx, false
	)
	var job := GenWfcJob.new(rules, c, manifest, 42, GenService.default_options())
	return {"job": job, "fx": halo + fx, "fy": halo + fy, "w": gw}
