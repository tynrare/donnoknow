# agent: composer-2.5 | 2026-07-09 | RGB-quad signatures + atlas neighbor edges | s3g4h5
extends RefCounted

const DIRS := ["north", "east", "south", "west"]
const OPPOSITE := {"north": "south", "east": "west", "south": "north", "west": "east"}


static func analyze_atlas(manifest: Dictionary) -> Dictionary:
	var empty := {
		"signatures": {},
		"gid_to_sig": {},
		"palette": [],
		"sig_adjacency": {},
		"tile_descs": {},
	}
	var atlas_path: String = str(manifest.get("atlas", ""))
	if atlas_path.is_empty() or not FileAccess.file_exists(atlas_path):
		push_warning("AtlasAnalyze: missing atlas %s" % atlas_path)
		return empty

	var img := Image.load_from_file(ProjectSettings.globalize_path(atlas_path))
	if img == null:
		return empty

	var analyze: Dictionary = manifest.get("analyze", {})
	var tw: int = _tile_w(manifest)
	var th: int = _tile_h(manifest)
	var cols: int = int(manifest.get("columns", 0))
	var row_count: int = int(manifest.get("rows", 0))
	var first_gid: int = int(manifest.get("first_gid", 1))
	if cols <= 0 or row_count <= 0:
		return empty

	var grid: int = maxi(int(analyze.get("visual_grid", 2)), 2)
	var alpha_cutoff: int = clampi(int(analyze.get("transparent_alpha", 128)), 1, 255)
	var color_quantize: int = maxi(int(analyze.get("color_quantize", 0)), 0)

	var palette: Array = [{"r": 0, "g": 0, "b": 0, "a": 0}]
	var color_to_id: Dictionary = {"0,0,0": 0}
	var tile_count: int = cols * row_count
	var gid_to_sig: Dictionary = {}
	var signatures: Dictionary = {}
	var descs: Dictionary = {}

	for local in tile_count:
		var atlas := Vector2i(local % cols, local / cols)
		var rect := Rect2i(atlas.x * tw, atlas.y * th, tw, th)
		var gid: int = first_gid + local
		var cells: Array = _downsample_rgb_grid(
			img, rect, tw, th, grid, alpha_cutoff, color_quantize
		)
		if cells.size() != grid * grid:
			continue
		var sig: String = _rgb_cells_to_sig(cells)
		var edges: Dictionary = _edges_from_cells(cells, grid)

		for cell in cells:
			_register_palette_rgb(cell, palette, color_to_id)

		if signatures.has(sig) and not signatures[sig].is_empty():
			var rep_gid: int = int(signatures[sig][0])
			var rep_cells: Array = descs[str(rep_gid)].cells
			if not _cells_equal(cells, rep_cells):
				push_warning(
					"AtlasAnalyze: signature hash collision gid=%d sig=%s" % [gid, sig]
				)

		gid_to_sig[str(gid)] = sig
		if not signatures.has(sig):
			signatures[sig] = []
		if not signatures[sig].has(gid):
			signatures[sig].append(gid)
		descs[str(gid)] = {
			"sig": sig,
			"edges": edges,
			"cells": cells,
			"local": local,
		}

	for sig in signatures:
		signatures[sig].sort()

	var sig_adjacency: Dictionary = _build_sig_adjacency_from_descs(
		descs, gid_to_sig, cols, row_count, first_gid
	)

	return {
		"signatures": signatures,
		"gid_to_sig": gid_to_sig,
		"palette": _palette_to_hex(palette),
		"sig_adjacency": sig_adjacency,
		"tile_descs": descs,
	}


static func sig_for_gid(rules: Dictionary, gid: int) -> String:
	return str(rules.get("gid_to_sig", {}).get(str(gid), ""))


static func signature_members(rules: Dictionary, sig: String) -> Array:
	var node: Variant = rules.get("signatures", {}).get(sig, [])
	return node if node is Array else []


static func generatable_members(rules: Dictionary, sig: String) -> Array:
	var node: Variant = rules.get("generatable_members", {}).get(sig, [])
	if node is Array and not node.is_empty():
		return node
	return signature_members(rules, sig)


static func cells_equal(cells_a: Array, cells_b: Array) -> bool:
	return _cells_equal(cells_a, cells_b)


static func remap_gid_for_analyze(rules: Dictionary, gid: int) -> int:
	var gid_to_sig: Dictionary = rules.get("gid_to_sig", {})
	if gid_to_sig.is_empty():
		return gid
	var sig: String = str(gid_to_sig.get(str(gid), ""))
	if sig.is_empty():
		return gid
	var bg_sig: String = str(rules.get("background_sig", ""))
	var bg_gid: int = int(rules.get("background_gid", 0))
	if sig == bg_sig and gid != bg_gid and bg_gid > 0:
		return bg_gid
	return gid


static func _edges_from_cells(cells: Array, grid: int) -> Dictionary:
	if grid == 2:
		return {
			"north": _rgb_key(cells[0]),
			"east": _rgb_key(cells[1]),
			"south": _rgb_key(cells[2]),
			"west": _rgb_key(cells[0]),
		}
	return {
		"north": _rgb_key(cells[0]),
		"east": _rgb_key(cells[grid - 1]),
		"south": _rgb_key(cells[(grid - 1) * grid]),
		"west": _rgb_key(cells[0]),
	}


static func _build_sig_adjacency_from_descs(
	descs: Dictionary,
	gid_to_sig: Dictionary,
	cols: int,
	row_count: int,
	first_gid: int,
) -> Dictionary:
	var sig_adj: Dictionary = {}
	var tile_count: int = cols * row_count

	for gid_key in descs:
		var d: Dictionary = descs[gid_key]
		var gid: int = int(gid_key)
		var local: int = int(d.local)
		var sig_a: String = str(d.sig)
		var edges: Dictionary = d.edges
		_ensure_sig_adj(sig_adj, sig_a)

		var north_local: int = local - cols
		if north_local >= 0:
			var nb_gid: int = first_gid + north_local
			if descs.has(str(nb_gid)):
				var nb: Dictionary = descs[str(nb_gid)]
				if str(edges.north) == str(nb.edges.south):
					var sig_b: String = str(nb.sig)
					if not sig_b.is_empty():
						_add_sig_pair(sig_adj, sig_a, sig_b, "north")

		var south_local: int = local + cols
		if south_local < tile_count:
			var nb_gid_s: int = first_gid + south_local
			if descs.has(str(nb_gid_s)):
				var nb_s: Dictionary = descs[str(nb_gid_s)]
				if str(edges.south) == str(nb_s.edges.north):
					var sig_b2: String = str(nb_s.sig)
					if not sig_b2.is_empty():
						_add_sig_pair(sig_adj, sig_a, sig_b2, "south")

		var ax: int = local % cols
		var east_local: int = local + 1
		if ax + 1 < cols:
			var nb_gid_e: int = first_gid + east_local
			if descs.has(str(nb_gid_e)):
				var nb_e: Dictionary = descs[str(nb_gid_e)]
				if str(edges.east) == str(nb_e.edges.west):
					var sig_b3: String = str(nb_e.sig)
					if not sig_b3.is_empty():
						_add_sig_pair(sig_adj, sig_a, sig_b3, "east")

		var west_local: int = local - 1
		if ax > 0:
			var nb_gid_w: int = first_gid + west_local
			if descs.has(str(nb_gid_w)):
				var nb_w: Dictionary = descs[str(nb_gid_w)]
				if str(edges.west) == str(nb_w.edges.east):
					var sig_b4: String = str(nb_w.sig)
					if not sig_b4.is_empty():
						_add_sig_pair(sig_adj, sig_a, sig_b4, "west")

	apply_same_sig_vertical_adj(sig_adj, descs, 2)
	return sig_adj


static func apply_same_sig_vertical_adj(
	sig_adj: Dictionary,
	descs: Dictionary,
	min_count: int = 2,
) -> void:
	var by_sig: Dictionary = {}
	for gid_key in descs:
		var sig: String = str(descs[gid_key].sig)
		if not by_sig.has(sig):
			by_sig[sig] = []
		by_sig[sig].append(int(gid_key))

	for sig in by_sig:
		var gids: Array = by_sig[sig]
		if gids.size() < 2:
			continue
		var rep_cells: Array = descs[str(gids[0])].cells
		# Only alias/interchange when every member shares the same full 2x2 tile.
		var all_same_full := true
		for gid in gids:
			if not _cells_equal(descs[str(gid)].cells, rep_cells):
				all_same_full = false
				break
		if not all_same_full:
			continue
		_ensure_sig_adj(sig_adj, sig)
		var need: int = maxi(min_count, 2)
		sig_adj[sig]["north"][sig] = maxi(int(sig_adj[sig]["north"].get(sig, 0)), need)
		sig_adj[sig]["south"][sig] = maxi(int(sig_adj[sig]["south"].get(sig, 0)), need)


static func expand_sig_adjacency_to_gids(
	sig_adjacency: Dictionary,
	signatures: Dictionary,
) -> Dictionary:
	var adjacency: Dictionary = {}
	for sig_a in sig_adjacency:
		var gids_a: Array = signatures.get(sig_a, [])
		if gids_a.is_empty():
			continue
		var node: Variant = sig_adjacency[sig_a]
		if node is not Dictionary:
			continue
		for dir_name in DIRS:
			var bucket: Variant = node.get(dir_name, {})
			if bucket is not Dictionary:
				continue
			for sig_b in bucket:
				var gids_b: Array = signatures.get(str(sig_b), [])
				if gids_b.is_empty():
					continue
				var count: int = int(bucket[sig_b])
				for gid_a in gids_a:
					for gid_b in gids_b:
						if int(gid_a) == int(gid_b):
							continue
						_ensure_adj(adjacency, int(gid_a))
						var ak := str(gid_a)
						var bk := str(gid_b)
						adjacency[ak][dir_name][bk] = adjacency[ak][dir_name].get(bk, 0) + count
	return adjacency


static func _downsample_rgb_grid(
	img: Image,
	rect: Rect2i,
	tw: int,
	th: int,
	grid: int,
	alpha_cutoff: int,
	color_quantize: int = 0,
) -> Array:
	var out: Array = []
	var cell_w: int = maxi(tw / grid, 1)
	var cell_h: int = maxi(th / grid, 1)
	for gy in grid:
		for gx in grid:
			var r_sum := 0
			var g_sum := 0
			var b_sum := 0
			var a_sum := 0
			var n := 0
			for py in cell_h:
				for px in cell_w:
					var x: int = rect.position.x + gx * cell_w + px
					var y: int = rect.position.y + gy * cell_h + py
					if x >= rect.position.x + tw or y >= rect.position.y + th:
						continue
					var c: Color = img.get_pixel(x, y)
					r_sum += c.r8
					g_sum += c.g8
					b_sum += c.b8
					a_sum += c.a8
					n += 1
			if n <= 0 or a_sum / n < alpha_cutoff:
				out.append(Vector3i.ZERO)
				continue
			out.append(
				Vector3i(
					_quantize_channel(int(r_sum / n), color_quantize),
					_quantize_channel(int(g_sum / n), color_quantize),
					_quantize_channel(int(b_sum / n), color_quantize),
				)
			)
	return out


static func _cells_equal(cells_a: Array, cells_b: Array) -> bool:
	if cells_a.size() != cells_b.size():
		return false
	for i in cells_a.size():
		var a: Vector3i = cells_a[i]
		var b: Vector3i = cells_b[i]
		if a != b:
			return false
	return true


static func _rgb_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


static func _rgb_cells_to_sig(cells: Array) -> String:
	var packed := PackedByteArray()
	packed.resize(cells.size() * 3)
	for i in cells.size():
		var cell: Vector3i = cells[i]
		packed[i * 3] = cell.x
		packed[i * 3 + 1] = cell.y
		packed[i * 3 + 2] = cell.z
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(packed)
	var digest: PackedByteArray = ctx.finish()
	return digest.hex_encode().substr(0, 8)


static func _register_palette_rgb(
	cell: Vector3i,
	palette: Array,
	color_to_id: Dictionary,
) -> void:
	var key := _rgb_key(cell)
	if color_to_id.has(key):
		return
	var id: int = palette.size()
	color_to_id[key] = id
	palette.append({"r": cell.x, "g": cell.y, "b": cell.z, "a": 255 if cell != Vector3i.ZERO else 0})


static func _quantize_channel(value: int, step: int) -> int:
	if step <= 1:
		return value
	return mini(value - (value % step), 255)


static func _palette_to_hex(palette: Array) -> Array:
	var out: Array = []
	for p in palette:
		if p is Dictionary:
			out.append("#%02x%02x%02x" % [int(p.r), int(p.g), int(p.b)])
		else:
			out.append("#000000")
	return out


static func _tile_w(manifest: Dictionary) -> int:
	var tile_size: Array = manifest.get("tile_size", [8, 8])
	return int(tile_size[0]) if tile_size.size() > 0 else 8


static func _tile_h(manifest: Dictionary) -> int:
	var tile_size: Array = manifest.get("tile_size", [8, 8])
	return int(tile_size[1]) if tile_size.size() > 1 else 8


static func _bucket_append(into: Dictionary, key: String, gid: int) -> void:
	if key.is_empty():
		return
	if not into.has(key):
		into[key] = []
	if not into[key].has(gid):
		into[key].append(gid)


static func _ensure_sig_adj(into: Dictionary, sig: String) -> void:
	if into.has(sig):
		return
	into[sig] = {}
	for d in DIRS:
		into[sig][d] = {}


static func _add_sig_pair(into: Dictionary, sig_a: String, sig_b: String, dir: String) -> void:
	_ensure_sig_adj(into, sig_a)
	into[sig_a][dir][sig_b] = into[sig_a][dir].get(sig_b, 0) + 1


static func _ensure_adj(adjacency: Dictionary, gid: int) -> void:
	var key := str(gid)
	if adjacency.has(key):
		return
	adjacency[key] = {}
	for d in DIRS:
		adjacency[key][d] = {}
