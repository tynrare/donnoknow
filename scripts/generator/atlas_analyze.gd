# agent: composer-2.5 | 2026-07-07 | rgb+topo edges tight alias | k6l7m8
extends RefCounted

const DIRS := ["north", "east", "south", "west"]
const OPPOSITE := {"north": "south", "east": "west", "south": "north", "west": "east"}
const DEFAULT_MAX_ALIAS_CLASS := 4


static func analyze_atlas(manifest: Dictionary) -> Dictionary:
	var adjacency: Dictionary = {}
	var tile_classes: Array = []
	var topology: Dictionary = {}
	var atlas_path: String = str(manifest.get("atlas", ""))
	if atlas_path.is_empty() or not FileAccess.file_exists(atlas_path):
		push_warning("AtlasAnalyze: missing atlas %s" % atlas_path)
		return {"adjacency": adjacency, "tile_classes": tile_classes, "topology": topology}

	var img := Image.load_from_file(ProjectSettings.globalize_path(atlas_path))
	if img == null:
		return {"adjacency": adjacency, "tile_classes": tile_classes, "topology": topology}

	var analyze: Dictionary = manifest.get("analyze", {})
	var tw: int = _tile_w(manifest)
	var th: int = _tile_h(manifest)
	var cols: int = int(manifest.get("columns", 0))
	var row_count: int = int(manifest.get("rows", 0))
	var first_gid: int = int(manifest.get("first_gid", 1))
	if cols <= 0 or row_count <= 0:
		return {"adjacency": adjacency, "tile_classes": tile_classes, "topology": topology}

	var quant_bits: int = clampi(int(analyze.get("color_quantize", 24)), 8, 32)
	var edge_quant_bits: int = clampi(int(analyze.get("edge_quantize", 32)), 8, 32)
	var edge_quant_shift: int = _quant_shift_from_bits(edge_quant_bits)
	var alias_threshold: float = clampf(float(analyze.get("alias_threshold", 0.85)), 0.5, 1.0)
	var alias_auto: bool = analyze.get("alias_auto", true)
	var alias_max_col: int = maxi(int(analyze.get("alias_max_col_distance", 1)), 1)
	var alias_max_row: int = maxi(int(analyze.get("alias_max_row_distance", 1)), 1)
	var max_class_size: int = maxi(
		int(analyze.get("alias_max_class_size", DEFAULT_MAX_ALIAS_CLASS)), 2
	)
	max_class_size = mini(max_class_size, 12)

	var tile_count: int = cols * row_count
	var descs: Array = []
	descs.resize(tile_count)

	for local in tile_count:
		var atlas := Vector2i(local % cols, local / cols)
		var rect := Rect2i(atlas.x * tw, atlas.y * th, tw, th)
		var gid: int = first_gid + local
		var north_topo := _edge_topology(img, rect, "north", tw, th)
		var east_topo := _edge_topology(img, rect, "east", tw, th)
		var south_topo := _edge_topology(img, rect, "south", tw, th)
		var west_topo := _edge_topology(img, rect, "west", tw, th)
		descs[local] = {
			"local": local,
			"gid": gid,
			"atlas_y": atlas.y,
			"atlas_x": atlas.x,
			"north_topo": north_topo,
			"east_topo": east_topo,
			"south_topo": south_topo,
			"west_topo": west_topo,
			"north_key": _edge_match_key(img, rect, "north", tw, th, edge_quant_shift, north_topo),
			"east_key": _edge_match_key(img, rect, "east", tw, th, edge_quant_shift, east_topo),
			"south_key": _edge_match_key(img, rect, "south", tw, th, edge_quant_shift, south_topo),
			"west_key": _edge_match_key(img, rect, "west", tw, th, edge_quant_shift, west_topo),
			"fill": _tile_histogram(img, rect, tw, th, quant_bits),
		}
		if analyze.get("save_topology", false):
			topology[str(gid)] = {
				"north": north_topo,
				"east": east_topo,
				"south": south_topo,
				"west": west_topo,
			}

	if alias_auto:
		tile_classes = _build_tile_classes(
			descs, cols, row_count, alias_threshold, alias_max_col, alias_max_row, max_class_size
		)
	_build_local_adjacency(adjacency, descs, tile_count)

	return {"adjacency": adjacency, "tile_classes": tile_classes, "topology": topology}


static func max_alias_class_size(rules: Dictionary) -> int:
	return maxi(int(rules.get("stats", {}).get("alias_max_class_size", DEFAULT_MAX_ALIAS_CLASS)), 2)


static func adjacency_from_edges(manifest: Dictionary) -> Dictionary:
	return analyze_atlas(manifest).adjacency


static func class_for_gid(rules: Dictionary, gid: int) -> Array:
	var cap: int = max_alias_class_size(rules)
	for class_v in rules.get("tile_classes", []):
		if class_v is not Array or class_v.size() > cap:
			continue
		for member in class_v:
			if int(member) == gid:
				return class_v
	return [gid]


static func _build_local_adjacency(adjacency: Dictionary, descs: Array, tile_count: int) -> void:
	var north_match_south: Dictionary = {}
	var east_match_west: Dictionary = {}
	var south_match_north: Dictionary = {}
	var west_match_east: Dictionary = {}

	for local in tile_count:
		var d: Dictionary = descs[local]
		if not _is_meaningful_tile(d):
			continue
		var gid: int = d.gid
		_bucket_append(north_match_south, d.north_key, gid)
		_bucket_append(east_match_west, d.east_key, gid)
		_bucket_append(south_match_north, d.south_key, gid)
		_bucket_append(west_match_east, d.west_key, gid)

	for local in tile_count:
		var da: Dictionary = descs[local]
		if not _is_meaningful_tile(da):
			continue
		var gid_a: int = da.gid
		_ensure_adj(adjacency, gid_a)
		for nb in north_match_south.get(da.north_key, []):
			if int(nb) != gid_a:
				_add_pair(adjacency, gid_a, int(nb), "north")
		for nb in east_match_west.get(da.east_key, []):
			if int(nb) != gid_a:
				_add_pair(adjacency, gid_a, int(nb), "east")
		for nb in south_match_north.get(da.south_key, []):
			if int(nb) != gid_a:
				_add_pair(adjacency, gid_a, int(nb), "south")
		for nb in west_match_east.get(da.west_key, []):
			if int(nb) != gid_a:
				_add_pair(adjacency, gid_a, int(nb), "west")


static func _build_tile_classes(
	descs: Array,
	cols: int,
	row_count: int,
	alias_threshold: float,
	alias_max_col: int,
	alias_max_row: int,
	max_class_size: int,
) -> Array:
	var n: int = descs.size()
	var visited: Dictionary = {}
	var classes: Array = []

	for i in n:
		if visited.has(i):
			continue
		if not _is_meaningful_tile(descs[i]):
			continue

		var group_locals: Array = [i]
		visited[i] = true
		var queue: Array = [i]
		var head := 0
		while head < queue.size() and group_locals.size() < max_class_size:
			var cur: int = queue[head]
			head += 1
			for nj in _atlas_neighbors(cur, cols, row_count):
				if visited.has(nj):
					continue
				if not _should_alias(descs[cur], descs[nj], alias_threshold, alias_max_col, alias_max_row):
					continue
				visited[nj] = true
				group_locals.append(nj)
				queue.append(nj)

		if group_locals.size() < 2:
			continue
		var gids: Array = []
		for local in group_locals:
			gids.append(descs[local].gid)
		gids.sort()
		classes.append(gids)

	classes.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	return classes


static func _atlas_neighbors(local: int, cols: int, row_count: int) -> Array:
	var ax: int = local % cols
	var ay: int = local / cols
	var out: Array = []
	for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = ax + delta.x
		var ny: int = ay + delta.y
		if nx < 0 or ny < 0 or nx >= cols or ny >= row_count:
			continue
		out.append(ny * cols + nx)
	return out


static func _should_alias(
	a: Dictionary,
	b: Dictionary,
	alias_threshold: float,
	alias_max_col: int,
	alias_max_row: int,
) -> bool:
	if not _is_meaningful_tile(a) or not _is_meaningful_tile(b):
		return false
	if _hist_similarity(a.fill, b.fill) < alias_threshold:
		return false

	if a.atlas_y == b.atlas_y and absi(a.atlas_x - b.atlas_x) <= alias_max_col:
		if a.north_topo == b.north_topo and a.south_topo == b.south_topo:
			return true
	if a.atlas_x == b.atlas_x and absi(a.atlas_y - b.atlas_y) <= alias_max_row:
		if a.east_topo == b.east_topo and a.west_topo == b.west_topo:
			return true
	return false


static func _edge_match_key(
	img: Image,
	rect: Rect2i,
	side: String,
	tw: int,
	th: int,
	quant_shift: int,
	topo: String,
) -> String:
	return "%s|%s" % [topo, _edge_rgb_key(img, rect, side, tw, th, quant_shift)]


static func _edge_rgb_key(img: Image, rect: Rect2i, side: String, tw: int, th: int, quant_shift: int) -> String:
	var parts: PackedStringArray = []
	match side:
		"north":
			for x in tw:
				parts.append(_edge_rgb_char(img.get_pixel(rect.position.x + x, rect.position.y), quant_shift))
		"south":
			for x in tw:
				parts.append(
					_edge_rgb_char(
						img.get_pixel(rect.position.x + x, rect.position.y + th - 1), quant_shift
					)
				)
		"west":
			for y in th:
				parts.append(_edge_rgb_char(img.get_pixel(rect.position.x, rect.position.y + y), quant_shift))
		"east":
			for y in th:
				parts.append(
					_edge_rgb_char(
						img.get_pixel(rect.position.x + tw - 1, rect.position.y + y), quant_shift
					)
				)
	return ",".join(parts)


static func _edge_rgb_char(color: Color, quant_shift: int) -> String:
	if color.a8 < 128:
		return "T"
	return str(_quantize_color(color, quant_shift))


static func _bucket_append(into: Dictionary, key: String, gid: int) -> void:
	if key.is_empty():
		return
	if not into.has(key):
		into[key] = []
	into[key].append(gid)


static func _edge_topology(img: Image, rect: Rect2i, side: String, tw: int, th: int) -> String:
	var parts: PackedStringArray = []
	match side:
		"north":
			for x in tw:
				parts.append(_topo_char(img.get_pixel(rect.position.x + x, rect.position.y)))
		"south":
			for x in tw:
				parts.append(_topo_char(img.get_pixel(rect.position.x + x, rect.position.y + th - 1)))
		"west":
			for y in th:
				parts.append(_topo_char(img.get_pixel(rect.position.x, rect.position.y + y)))
		"east":
			for y in th:
				parts.append(_topo_char(img.get_pixel(rect.position.x + tw - 1, rect.position.y + y)))
	return "".join(parts)


static func _topo_char(color: Color) -> String:
	return "S" if color.a8 >= 128 else "T"


static func _tile_w(manifest: Dictionary) -> int:
	var tile_size: Array = manifest.get("tile_size", [8, 8])
	return int(tile_size[0]) if tile_size.size() > 0 else 8


static func _tile_h(manifest: Dictionary) -> int:
	var tile_size: Array = manifest.get("tile_size", [8, 8])
	return int(tile_size[1]) if tile_size.size() > 1 else 8


static func _quant_shift_from_bits(bits: int) -> int:
	if bits >= 32:
		return 0
	return clampi(8 - bits / 3, 1, 7)


static func _quantize_color(color: Color, quant_shift: int) -> int:
	if color.a8 < 128:
		return -1
	if quant_shift <= 0:
		return (int(color.r8) << 16) | (int(color.g8) << 8) | int(color.b8)
	var r: int = int(color.r8) >> quant_shift
	var g: int = int(color.g8) >> quant_shift
	var b: int = int(color.b8) >> quant_shift
	return (r << 10) | (g << 5) | b


static func _tile_histogram(
	img: Image, rect: Rect2i, tw: int, th: int, quant_bits: int
) -> String:
	var quant_shift: int = _quant_shift_from_bits(quant_bits)
	var hist: Dictionary = {}
	for y in th:
		for x in tw:
			var q: int = _quantize_color(img.get_pixel(rect.position.x + x, rect.position.y + y), quant_shift)
			if q < 0:
				continue
			var key := str(q)
			hist[key] = int(hist.get(key, 0)) + 1
	return _hist_to_key(hist)


static func _hist_to_key(hist: Dictionary) -> String:
	if hist.is_empty():
		return ""
	var keys: Array = hist.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		parts.append("%s:%d" % [key, int(hist[key])])
	return ",".join(parts)


static func _hist_similarity(a: String, b: String) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	if a == b:
		return 1.0
	var ha: Dictionary = _parse_hist_key(a)
	var hb: Dictionary = _parse_hist_key(b)
	var keys: Dictionary = {}
	for k in ha:
		keys[k] = true
	for k in hb:
		keys[k] = true
	var dot := 0.0
	var na := 0.0
	var nb := 0.0
	for k in keys:
		var va: float = float(ha.get(k, 0))
		var vb: float = float(hb.get(k, 0))
		dot += va * vb
		na += va * va
		nb += vb * vb
	if na <= 0.0 or nb <= 0.0:
		return 0.0
	return dot / (sqrt(na) * sqrt(nb))


static func _parse_hist_key(key: String) -> Dictionary:
	var out: Dictionary = {}
	if key.is_empty():
		return out
	for part in key.split(","):
		if part.is_empty():
			continue
		var bits: PackedStringArray = part.split(":")
		if bits.size() < 2:
			continue
		out[bits[0]] = bits[1].to_int()
	return out


static func _is_meaningful_tile(desc: Dictionary) -> bool:
	for key in ["north_topo", "south_topo", "east_topo", "west_topo"]:
		var topo: String = desc.get(key, "")
		if topo.is_empty() or not topo.contains("S"):
			return false
	if desc.fill.is_empty():
		return false
	return true


static func _ensure_adj(adjacency: Dictionary, gid: int) -> void:
	var key := str(gid)
	if adjacency.has(key):
		return
	adjacency[key] = {"north": {}, "east": {}, "south": {}, "west": {}}


static func _add_pair(adjacency: Dictionary, a: int, b: int, dir: String) -> void:
	var ak := str(a)
	var bk := str(b)
	adjacency[ak][dir][bk] = adjacency[ak][dir].get(bk, 0) + 1
