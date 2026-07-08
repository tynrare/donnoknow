extends SceneTree

const GenWfc := preload("res://scripts/generator/wfc.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenService := preload("res://scripts/generator/service.gd")


func _init() -> void:
	var manifest := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var rules := GenRules.load(manifest.get("rules", ""))
	var w := 11
	var h := 11
	var fx := 5
	var fy := 5
	var constraints := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(constraints, fx, fy, 27)

	var tiles := GenRules.generatable_tiles(rules, manifest)
	tiles = GenWfc._merge_fixed_tiles(tiles, constraints)
	var ctx := GenWfc._build_context(rules, tiles, false)
	GenWfc._augment_compat_from_constraints(constraints, ctx)

	if not ctx.gid_to_idx.has(27):
		push_error("FAIL: GID 27 not in tile context")
		quit(1)
		return

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
	var ok := GenWfc._propagate([fixed_idx], domains, domain_counts, done, out, constraints, w, h, ctx)
	print("propagate ok=%s" % ok)

	var neighbors := [
		Vector2i(fx, fy - 1),
		Vector2i(fx + 1, fy),
		Vector2i(fx, fy + 1),
		Vector2i(fx - 1, fy),
	]
	for p in neighbors:
		var ni: int = p.y * w + p.x
		print(
			"neighbor (%d,%d) domain=%d zero=%s"
			% [p.x, p.y, domain_counts[ni], str(domain_counts[ni] == 0)]
		)

	if domain_counts[neighbors[0].y * w + neighbors[0].x] == 0:
		push_error("FAIL: north neighbor zero domain after propagate from 27")
		quit(1)
		return

	print("PASS fixed27 neighbor propagate")
	quit(0)
