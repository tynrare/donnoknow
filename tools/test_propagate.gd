extends SceneTree

const GenWfc := preload("res://scripts/generator/wfc.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenService := preload("res://scripts/generator/service.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const DEADLINE_MS := 60_000


func _init() -> void:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(manifest.get("rules", ""))
	var tiles := GenRules.generatable_tiles(rules, manifest)
	tiles = GenWfc._merge_fixed_tiles(tiles, GenConstraints.empty(1, 1))
	var ctx := GenWfc._build_context(rules, tiles, false)

	_test_one_hop_narrows_neighbors(ctx, rules, deadline)
	_test_full_propagate_from_fixed(ctx, rules, deadline)
	_test_pick_ignores_distant_zero_domains(ctx, rules, deadline)
	_test_untried_domain_count(deadline)
	_test_halo_context_constraints(deadline)

	print("PASS propagation tests ms=%d" % (DEADLINE_MS - (deadline - Time.get_ticks_msec())))
	quit(0)


func _check_deadline(deadline: int, name: String) -> void:
	if Time.get_ticks_msec() > deadline:
		_fail("%s exceeded 60s budget" % name)


func _fail(msg: String) -> void:
	push_error("FAIL: %s" % msg)
	quit(1)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _setup_fixed_grid(
	ctx: Dictionary,
	rules: Dictionary,
	w: int,
	h: int,
	fx: int,
	fy: int,
	fgid: int,
) -> Dictionary:
	var constraints := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(constraints, fx, fy, fgid)
	GenWfc._augment_compat_from_constraints(constraints, ctx)

	var n := w * h
	var count: int = ctx.count
	var all_domain: PackedByteArray = ctx.all_domain
	var gid_to_idx: Dictionary = ctx.gid_to_idx

	var domains: Array = []
	domains.resize(n)
	var domain_counts := PackedInt32Array()
	domain_counts.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	var out := PackedInt32Array()
	out.resize(n)
	out.fill(0)

	for i in n:
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			var gid: int = constraints.fixed_gids[i]
			var fixed_domain := PackedByteArray()
			fixed_domain.resize(count)
			fixed_domain[gid_to_idx[gid]] = 1
			domains[i] = fixed_domain
			domain_counts[i] = 1
			done[i] = 1
			out[i] = gid
		else:
			domains[i] = GenWfc._domain_copy(all_domain)
			domain_counts[i] = count
			done[i] = 0

	var fixed_idx := fy * w + fx
	return {
		"constraints": constraints,
		"w": w,
		"h": h,
		"domains": domains,
		"domain_counts": domain_counts,
		"done": done,
		"out": out,
		"fixed_idx": fixed_idx,
	}


func _test_one_hop_narrows_neighbors(ctx: Dictionary, _rules: Dictionary, deadline: int) -> void:
	_check_deadline(deadline, "one_hop")
	var st := _setup_fixed_grid(ctx, _rules, 5, 5, 2, 2, 27)
	var w: int = st.w
	var h: int = st.h

	GenWfc._propagate_one_hop(
		[st.fixed_idx],
		st.domains,
		st.domain_counts,
		st.done,
		st.out,
		st.constraints,
		w,
		h,
		ctx,
	)

	var neighbors := [Vector2i(2, 1), Vector2i(3, 2), Vector2i(2, 3), Vector2i(1, 2)]
	for p in neighbors:
		var ni: int = p.y * w + p.x
		_assert(st.domain_counts[ni] > 0, "one_hop zeroed neighbor (%d,%d)" % [p.x, p.y])
		_assert(st.domain_counts[ni] < ctx.count, "one_hop did not narrow neighbor (%d,%d)" % [p.x, p.y])

	print("PASS one_hop fixed GID 27 narrows 4 neighbors")


func _test_full_propagate_from_fixed(ctx: Dictionary, _rules: Dictionary, deadline: int) -> void:
	_check_deadline(deadline, "full_propagate")
	var st := _setup_fixed_grid(ctx, _rules, 5, 5, 2, 2, 27)
	var w: int = st.w
	var h: int = st.h

	GenWfc._propagate_one_hop(
		[st.fixed_idx],
		st.domains,
		st.domain_counts,
		st.done,
		st.out,
		st.constraints,
		w,
		h,
		ctx,
	)

	var east: int = 2 + 3 * w
	var domain: PackedByteArray = st.domains[east]
	var placed := false
	for t in ctx.count:
		if not domain[t]:
			continue
		st.done[east] = 1
		st.out[east] = ctx.idx_to_gid[t]
		st.domains[east] = PackedByteArray()
		st.domains[east].resize(ctx.count)
		st.domains[east][t] = 1
		st.domain_counts[east] = 1
		var ok := GenWfc._propagate(
			[st.fixed_idx, east],
			st.domains,
			st.domain_counts,
			st.done,
			st.out,
			st.constraints,
			w,
			h,
			ctx,
		)
		if ok:
			placed = true
			break
		st.done[east] = 0
		st.out[east] = 0
		st.domains[east] = domain.duplicate()
		st.domain_counts[east] = GenWfc._domain_pick_indices(domain).size()

	_assert(placed, "no compatible east neighbor tile propagated from fixed GID 27")

	var rng := RandomNumberGenerator.new()
	var pick := GenWfc._pick_collapse_cell(
		st.constraints, st.domain_counts, st.done, w, h, rng, true
	)
	_assert(pick >= 0, "pick_collapse_cell found no frontier after propagate")

	print("PASS full propagate from fixed GID 27 + collapsed neighbor")


func _test_pick_ignores_distant_zero_domains(ctx: Dictionary, _rules: Dictionary, deadline: int) -> void:
	_check_deadline(deadline, "pick_skip_zero")
	var st := _setup_fixed_grid(ctx, _rules, 5, 5, 2, 2, 27)
	var w: int = st.w

	GenWfc._propagate_one_hop(
		[st.fixed_idx],
		st.domains,
		st.domain_counts,
		st.done,
		st.out,
		st.constraints,
		w,
		st.h,
		ctx,
	)

	var corner: int = 0
	st.domain_counts[corner] = 0
	for t in ctx.count:
		st.domains[corner][t] = 0

	var rng := RandomNumberGenerator.new()
	var pick := GenWfc._pick_collapse_cell(
		st.constraints, st.domain_counts, st.done, w, st.h, rng, true
	)
	_assert(pick >= 0, "pick aborted on distant zero-domain cell")
	_assert(st.domain_counts[pick] > 0, "picked cell has empty domain")

	print("PASS pick_collapse_cell skips distant zero-domain cells")


func _test_untried_domain_count(deadline: int) -> void:
	_check_deadline(deadline, "untried_count")
	var domain := PackedByteArray()
	domain.resize(5)
	domain[0] = 1
	domain[2] = 1
	domain[4] = 1
	_assert(GenWfc.untried_domain_count(domain, [2]) == 2, "untried_domain_count wrong")
	print("PASS untried_domain_count")


func _test_halo_context_constraints(deadline: int) -> void:
	_check_deadline(deadline, "halo_constraints")
	var paint := PackedInt32Array()
	paint.resize(25)
	paint.fill(0)
	var context := paint.duplicate()
	context[2 * 5 + 0] = 42

	var c := GenConstraints.from_paint_seed_and_halo(5, 5, 1, 3, 3, paint, context)
	var halo_idx: int = 2 * 5 + 0
	var inner_idx: int = 2 * 5 + 2

	_assert(c.modes[halo_idx] == GenConstraints.Mode.FIXED, "halo tile should be FIXED")
	_assert(c.fixed_gids[halo_idx] == 42, "halo tile gid")
	_assert(c.modes[inner_idx] == GenConstraints.Mode.GENERATE, "empty inner cell GENERATE")
	_assert(c.modes[0] == GenConstraints.Mode.FORBID, "empty halo cell FORBID")

	context[2 * 5 + 2] = 99
	var c2 := GenConstraints.from_paint_seed_and_halo(5, 5, 1, 3, 3, paint, context)
	_assert(c2.modes[inner_idx] != GenConstraints.Mode.FIXED, "inner generated tile is seed not fixed")
	_assert(c2.get("seed_gids", PackedInt32Array())[inner_idx] == 99, "inner seed gid")

	var c0 := GenConstraints.from_paint_seed_and_halo(3, 3, 0, 3, 3, paint, context)
	_assert(c0.has("seed_gids"), "halo=0 delegates to paint+seed")

	print("PASS halo context constraints")
