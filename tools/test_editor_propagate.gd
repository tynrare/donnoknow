extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfc := preload("res://scripts/generator/wfc.gd")

const DEADLINE_MS := 60_000


func _init() -> void:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	var manifest := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var rules := GenRules.load(manifest.get("rules", ""))
	var tiles := GenRules.generatable_tiles(rules, manifest)
	var ctx := GenWfc._build_context(rules, tiles, true)

	_test_first_ring_expands(ctx, rules, deadline)
	print("PASS editor propagation expands from fixed GID 27 on 54x35")
	quit(0)


func _fail(msg: String) -> void:
	push_error("FAIL: %s" % msg)
	quit(1)


func _test_first_ring_expands(ctx: Dictionary, _rules: Dictionary, deadline: int) -> void:
	if Time.get_ticks_msec() > deadline:
		_fail("timeout before first ring test")

	var w := 54
	var h := 35
	var constraints := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(constraints, 15, 5, 27)
	GenWfc._augment_compat_from_constraints(constraints, ctx)

	var st := _setup(constraints, ctx, w, h, 15, 5, 27)
	GenWfc._propagate_one_hop(
		[st.fixed_idx], st.domains, st.domain_counts, st.done, st.out, constraints, w, h, ctx
	)

	var neighbors := [Vector2i(14, 5), Vector2i(16, 5), Vector2i(15, 4), Vector2i(15, 6)]
	var placed := 0
	for p in neighbors:
		if Time.get_ticks_msec() > deadline:
			_fail("timeout during neighbor placement")
		var ni: int = p.y * w + p.x
		var domain: PackedByteArray = st.domains[ni].duplicate()
		for t in ctx.count:
			if not domain[t]:
				continue
			st.done[ni] = 1
			st.out[ni] = ctx.idx_to_gid[t]
			st.domains[ni] = PackedByteArray()
			st.domains[ni].resize(ctx.count)
			st.domains[ni][t] = 1
			st.domain_counts[ni] = 1
			if GenWfc._propagate(
				[st.fixed_idx, ni],
				st.domains,
				st.domain_counts,
				st.done,
				st.out,
				constraints,
				w,
				h,
				ctx,
			):
				placed += 1
				break
			st.done[ni] = 0
			st.out[ni] = 0
			st.domains[ni] = domain.duplicate()
			st.domain_counts[ni] = GenWfc._domain_pick_indices(domain).size()

	if placed < 2:
		_fail("first ring placed %d/4 neighbors (expected >=2)" % placed)
	print("PASS first ring %d/4 neighbors propagate from fixed tile on 54x35" % placed)


func _setup(
	constraints: Dictionary,
	ctx: Dictionary,
	w: int,
	h: int,
	fx: int,
	fy: int,
	fgid: int,
) -> Dictionary:
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

	return {
		"fixed_idx": fy * w + fx,
		"domains": domains,
		"domain_counts": domain_counts,
		"done": done,
		"out": out,
	}
