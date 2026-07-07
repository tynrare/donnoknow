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
