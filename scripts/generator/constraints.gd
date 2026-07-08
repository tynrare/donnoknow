# agent: composer-2.5 | 2026-07-07 | paint+seed constraints | d1e2f3
extends RefCounted

enum Mode { GENERATE, FIXED, FORBID }


static func empty(width: int, height: int) -> Dictionary:
	var n := width * height
	var fixed := PackedInt32Array()
	fixed.resize(n)
	fixed.fill(0)
	return {
		"width": width,
		"height": height,
		"modes": _filled(n, Mode.GENERATE),
		"fixed_gids": fixed,
	}


static func from_gids(width: int, height: int, gids: PackedInt32Array) -> Dictionary:
	var modes: Array = _filled(width * height, Mode.GENERATE)
	var fixed := PackedInt32Array()
	fixed.resize(width * height)
	for i in gids.size():
		if gids[i] > 0:
			modes[i] = Mode.FIXED
			fixed[i] = gids[i]
	return {"width": width, "height": height, "modes": modes, "fixed_gids": fixed}


static func from_paint_and_seed(
	width: int,
	height: int,
	paint_gids: PackedInt32Array,
	seed_gids: PackedInt32Array,
	replace_inner: bool = false,
) -> Dictionary:
	var n: int = width * height
	var modes: Array = _filled(n, Mode.GENERATE)
	var fixed := PackedInt32Array()
	fixed.resize(n)
	fixed.fill(0)
	var seeds := PackedInt32Array()
	seeds.resize(n)
	seeds.fill(0)
	for i in mini(n, paint_gids.size()):
		if paint_gids[i] > 0:
			modes[i] = Mode.FIXED
			fixed[i] = paint_gids[i]
			seeds[i] = 0
		elif not replace_inner and i < seed_gids.size() and seed_gids[i] > 0:
			seeds[i] = seed_gids[i]
	return {
		"width": width,
		"height": height,
		"modes": modes,
		"fixed_gids": fixed,
		"seed_gids": seeds,
	}


static func from_paint_seed_and_halo(
	grid_w: int,
	grid_h: int,
	halo: int,
	inner_w: int,
	inner_h: int,
	paint_gids: PackedInt32Array,
	context_gids: PackedInt32Array,
	replace_inner: bool = false,
) -> Dictionary:
	if halo <= 0:
		return from_paint_and_seed(grid_w, grid_h, paint_gids, context_gids, replace_inner)

	var n: int = grid_w * grid_h
	var modes: Array = _filled(n, Mode.GENERATE)
	var fixed := PackedInt32Array()
	fixed.resize(n)
	fixed.fill(0)
	var seeds := PackedInt32Array()
	seeds.resize(n)
	seeds.fill(0)

	for y in grid_h:
		for x in grid_w:
			var i: int = y * grid_w + x
			var in_inner: bool = (
				x >= halo
				and y >= halo
				and x < halo + inner_w
				and y < halo + inner_h
			)
			var paint_gid: int = paint_gids[i] if i < paint_gids.size() else 0
			var ctx_gid: int = context_gids[i] if i < context_gids.size() else 0

			if paint_gid > 0:
				modes[i] = Mode.FIXED
				fixed[i] = paint_gid
				continue

			if not in_inner:
				if ctx_gid > 0:
					modes[i] = Mode.FIXED
					fixed[i] = ctx_gid
				else:
					modes[i] = Mode.FORBID
				continue

			modes[i] = Mode.GENERATE
			if not replace_inner and ctx_gid > 0:
				seeds[i] = ctx_gid

	return {
		"width": grid_w,
		"height": grid_h,
		"modes": modes,
		"fixed_gids": fixed,
		"seed_gids": seeds,
	}


static func set_fixed(c: Dictionary, x: int, y: int, gid: int) -> void:
	var i := _idx(c, x, y)
	c.modes[i] = Mode.FIXED
	c.fixed_gids[i] = gid


static func set_forbid(c: Dictionary, x: int, y: int) -> void:
	c.modes[_idx(c, x, y)] = Mode.FORBID


static func set_generate(c: Dictionary, x: int, y: int) -> void:
	c.modes[_idx(c, x, y)] = Mode.GENERATE


static func get_mode(c: Dictionary, x: int, y: int) -> int:
	return c.modes[_idx(c, x, y)]


static func _idx(c: Dictionary, x: int, y: int) -> int:
	return y * c.width + x


static func _filled(n: int, value: int) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(value)
	return a
