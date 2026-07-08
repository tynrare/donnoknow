# agent: composer-2.5 | 2026-07-08 | 2x2 palette signatures + downscaled edges | s1g2h3
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
	var palette_max: int = clampi(int(analyze.get("palette_max", 64)), 8, 256)
	var alpha_cutoff: int = clampi(int(analyze.get("transparent_alpha", 128)), 1, 255)

	var palette: Array = [{"r": 0, "g": 0, "b": 0, "a": 0}]
	var color_to_id: Dictionary = {"0,0,0,0": 0}
	var tile_count: int = cols * row_count
	var gid_to_sig: Dictionary = {}
	var signatures: Dictionary = {}
	var descs: Dictionary = {}

	for local in tile_count:
		var atlas := Vector2i(local % cols, local / cols)
		var rect := Rect2i(atlas.x * tw, atlas.y * th, tw, th)
		var gid: int = first_gid + local
		var cells: PackedInt32Array = _downsample_grid(img, rect, tw, th, grid, palette, color_to_id, palette_max, alpha_cutoff)
		if cells.size() != grid * grid:
			continue
		var sig: String = _cells_to_sig(cells)
		var edges: Dictionary
		if grid == 2:
			edges = {
				"north": int(cells[0]),
				"east": int(cells[1]),
				"south": int(cells[2]),
				"west": int(cells[0]),
			}
		else:
			edges = {
				"north": int(cells[0]),
				"east": int(cells[grid - 1]),
				"south": int(cells[(grid - 1) * grid]),
				"west": int(cells[0]),
			}

		gid_to_sig[str(gid)] = sig
		if not signatures.has(sig):
			signatures[sig] = []
		if not signatures[sig].has(gid):
			signatures[sig].append(gid)
		descs[str(gid)] = {"sig": sig, "edges": edges, "cells": cells}

	for sig in signatures:
		signatures[sig].sort()

	var sig_adjacency: Dictionary = _build_sig_adjacency_from_descs(descs, gid_to_sig)

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


static func _build_sig_adjacency_from_descs(descs: Dictionary, gid_to_sig: Dictionary) -> Dictionary:
	var south_match_north: Dictionary = {}
	var north_match_south: Dictionary = {}
	var west_match_east: Dictionary = {}
	var east_match_west: Dictionary = {}

	for gid_key in descs:
		var d: Dictionary = descs[gid_key]
		var edges: Dictionary = d.edges
		var gid: int = int(gid_key)
		_bucket_append(south_match_north, str(edges.north), gid)
		_bucket_append(north_match_south, str(edges.south), gid)
		_bucket_append(west_match_east, str(edges.east), gid)
		_bucket_append(east_match_west, str(edges.west), gid)

	var sig_adj: Dictionary = {}
	for gid_key in descs:
		var d: Dictionary = descs[gid_key]
		var sig_a: String = str(d.sig)
		var edges: Dictionary = d.edges
		_ensure_sig_adj(sig_adj, sig_a)
		for nb in south_match_north.get(str(edges.north), []):
			var sig_b: String = str(gid_to_sig.get(str(int(nb)), ""))
			if sig_b.is_empty() or sig_b == sig_a:
				continue
			_add_sig_pair(sig_adj, sig_a, sig_b, "north")
		for nb in east_match_west.get(str(edges.east), []):
			var sig_b2: String = str(gid_to_sig.get(str(int(nb)), ""))
			if sig_b2.is_empty() or sig_b2 == sig_a:
				continue
			_add_sig_pair(sig_adj, sig_a, sig_b2, "east")
		for nb in north_match_south.get(str(edges.south), []):
			var sig_b3: String = str(gid_to_sig.get(str(int(nb)), ""))
			if sig_b3.is_empty() or sig_b3 == sig_a:
				continue
			_add_sig_pair(sig_adj, sig_a, sig_b3, "south")
		for nb in west_match_east.get(str(edges.west), []):
			var sig_b4: String = str(gid_to_sig.get(str(int(nb)), ""))
			if sig_b4.is_empty() or sig_b4 == sig_a:
				continue
			_add_sig_pair(sig_adj, sig_a, sig_b4, "west")
	return sig_adj


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


static func _downsample_grid(
	img: Image,
	rect: Rect2i,
	tw: int,
	th: int,
	grid: int,
	palette: Array,
	color_to_id: Dictionary,
	palette_max: int,
	alpha_cutoff: int,
) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(grid * grid)
	var cell_w: int = maxi(tw / grid, 1)
	var cell_h: int = maxi(th / grid, 1)
	for gy in grid:
		for gx in grid:
			var r_sum := 0.0
			var g_sum := 0.0
			var b_sum := 0.0
			var a_sum := 0.0
			var n := 0
			for py in cell_h:
				for px in cell_w:
					var x: int = rect.position.x + gx * cell_w + px
					var y: int = rect.position.y + gy * cell_h + py
					if x >= rect.position.x + tw or y >= rect.position.y + th:
						continue
					var c: Color = img.get_pixel(x, y)
					r_sum += c.r
					g_sum += c.g
					b_sum += c.b
					a_sum += c.a
					n += 1
			var idx: int = gy * grid + gx
			if n <= 0 or a_sum / float(n) < float(alpha_cutoff) / 255.0:
				out[idx] = 0
				continue
			var avg := Color(r_sum / n, g_sum / n, b_sum / n, a_sum / n)
			out[idx] = _palette_index(avg, palette, color_to_id, palette_max, alpha_cutoff)
	return out


static func _palette_index(
	color: Color,
	palette: Array,
	color_to_id: Dictionary,
	palette_max: int,
	alpha_cutoff: int,
) -> int:
	if color.a8 < alpha_cutoff:
		return 0
	var qr: int = int(color.r8)
	var qg: int = int(color.g8)
	var qb: int = int(color.b8)
	var key := "%d,%d,%d,%d" % [qr, qg, qb, 255]
	if color_to_id.has(key):
		return int(color_to_id[key])
	if palette.size() >= palette_max:
		return _nearest_palette_id(color, palette, alpha_cutoff)
	var id: int = palette.size()
	palette.append({"r": qr, "g": qg, "b": qb, "a": 255})
	color_to_id[key] = id
	return id


static func _nearest_palette_id(color: Color, palette: Array, alpha_cutoff: int) -> int:
	if color.a8 < alpha_cutoff:
		return 0
	var best_id := 1
	var best_dist := 999999.0
	for i in range(1, palette.size()):
		var p: Dictionary = palette[i]
		var dr: float = float(color.r8) - float(p.r)
		var dg: float = float(color.g8) - float(p.g)
		var db: float = float(color.b8) - float(p.b)
		var dist: float = dr * dr + dg * dg + db * db
		if dist < best_dist:
			best_dist = dist
			best_id = i
	return best_id


static func _cells_to_sig(cells: PackedInt32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for c in cells:
		parts.append(str(c))
	return "-".join(parts)


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
