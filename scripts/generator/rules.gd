# agent: composer-2.5 | 2026-07-07 | cap adj gap-fill anti-repeat | f1a2b3
extends RefCounted

const GenTmx := preload("res://scripts/generator/tmx.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")

const DIRS := GenTmx.DIRS
const CTX_UNK := 0
const DEFAULT_CHUNK_SIZE := 8
const DEFAULT_EDGE_GAP_MAX := 8
const TILED_GID_MASK := 0x1FFFFFFF
const OPPOSITE := {
	"north": "south",
	"east": "west",
	"south": "north",
	"west": "east",
}


static func analyze_maps(
	maps: Array,
	min_adj_count: int = 1,
	manifest: Dictionary = {},
	chunk_size: int = DEFAULT_CHUNK_SIZE,
) -> Dictionary:
	var map_data: Array = []
	for map_path in maps:
		var map := GenTmx.read_map(map_path)
		if not map.is_empty():
			map_data.append(map)
	return analyze_map_data(map_data, min_adj_count, manifest, chunk_size, maps)


# agent: composer-2.5 | 2026-07-10 | analyze map data refactor | 86a5f0
static func analyze_map_data(
	map_data: Array,
	min_adj_count: int = 1,
	manifest: Dictionary = {},
	chunk_size: int = DEFAULT_CHUNK_SIZE,
	map_sources: Array = [],
) -> Dictionary:
	var tile_counts: Dictionary = {}
	var adjacency: Dictionary = {}
	var context_weights: Dictionary = {}
	var patterns_3x3: Array = []
	var pattern_counts: Dictionary = {}
	var chunks: Array = []
	var chunk_set := {}
	var chunk_counts: Dictionary = {}
	var chunk_compat: Dictionary = {}
	var total := 0
	var analyze: Dictionary = manifest.get("analyze", {})
	var use_maps: bool = analyze.get("maps", true)
	var use_chunks: bool = analyze.get("chunks", false)
	var use_tileset_edges: bool = analyze.get("tileset_edges", false)
	var edge_weight_raw: float = float(analyze.get("tileset_edges_weight", 0.35))
	var edge_weight: int = maxi(int(round(edge_weight_raw * 10.0)), 1) if edge_weight_raw > 0.0 else 0
	var min_adj: int = maxi(int(analyze.get("min_adj_count", min_adj_count)), 1)
	var tile_classes: Array = []
	var topology: Dictionary = {}
	var sources := {
		"maps": use_maps,
		"tileset_edges": use_tileset_edges,
		"min_adj_count": min_adj,
		"color_quantize": int(analyze.get("color_quantize", 24)),
		"edge_quantize": int(analyze.get("edge_quantize", 32)),
		"edge_match": str(analyze.get("edge_match", "exact")),
		"alias_threshold": float(analyze.get("alias_threshold", 0.85)),
	}

	var atlas_result: Dictionary = GenAtlasAnalyze.analyze_atlas(manifest)
	tile_classes = atlas_result.get("tile_classes", [])
	topology = atlas_result.get("topology", {})

	if use_maps:
		for map in map_data:
			if map is not Dictionary or map.is_empty():
				continue
			_scan_map(map, tile_counts, adjacency, manifest)
			_scan_context(map, context_weights, manifest)
			_scan_patterns_3x3(map, patterns_3x3, pattern_counts, manifest)
			if use_chunks:
				_scan_chunks(map, chunks, chunk_set, chunk_counts, chunk_compat, manifest, chunk_size)
			total += int(map.width) * int(map.height)

	_filter_adjacency(adjacency, min_adj)
	_symmetrize_adjacency(adjacency)

	if use_tileset_edges and edge_weight > 0:
		var active: Dictionary = _active_gid_set(tile_counts, tile_classes)
		var edge_adj: Dictionary = _restrict_adjacency(
			atlas_result.get("adjacency", {}), active
		)
		var edge_gap_max: int = maxi(
			int(analyze.get("edge_gap_max_neighbors", DEFAULT_EDGE_GAP_MAX)), 1
		)
		_merge_edge_gap_fill(adjacency, edge_adj, edge_weight, active, edge_gap_max)
		_symmetrize_adjacency(adjacency)

	if analyze.get("trim_self_adj", true):
		var bg_gid: int = int(manifest.get("background_gid", 1))
		_trim_self_adjacency(adjacency, bg_gid)

	var context_counts: Dictionary = _copy_context_counts(context_weights)
	_normalize_context_weights(context_weights, 3)

	var tile_weights := {}
	var pick_weights := {}
	var log_total := 0.0
	for gid in tile_counts:
		log_total += log(float(tile_counts[gid]) + 1.0)
	var tile_total := 0
	for gid in tile_counts:
		tile_total += tile_counts[gid]
	for gid in tile_counts:
		tile_weights[str(gid)] = float(tile_counts[gid]) / float(maxi(tile_total, 1))
		pick_weights[str(gid)] = log(float(tile_counts[gid]) + 1.0) / maxf(log_total, 0.001)

	return {
		"version": 3,
		"tile_weights": tile_weights,
		"pick_weights": pick_weights,
		"pick_weight_mode": "log",
		"adjacency": adjacency,
		"context_weights": context_weights,
		"context_counts": context_counts,
		"patterns_3x3": patterns_3x3,
		"pattern_counts": pattern_counts,
		"chunks": chunks,
		"chunk_counts": chunk_counts,
		"chunk_compat": chunk_compat,
		"chunk_size": chunk_size,
		"tile_classes": tile_classes,
		"maps": map_sources,
		"sources": sources,
		"grid": {
			"columns": int(manifest.get("columns", 0)),
			"rows": int(manifest.get("rows", 0)),
			"first_gid": int(manifest.get("first_gid", 1)),
			"tile_count": int(manifest.get("tile_count", 0)),
			"map_width": int(manifest.get("map_width", 0)),
			"map_height": int(manifest.get("map_height", 0)),
		},
		"stats": {
			"cells": total,
			"unique_tiles": tile_counts.size(),
			"patterns_3x3": patterns_3x3.size(),
			"context_keys": context_weights.size(),
			"chunks": chunks.size(),
			"tile_classes": tile_classes.size(),
			"alias_max_class_size": int(analyze.get("alias_max_class_size", 4)),
		},
	}


# agent: composer-2.5 | 2026-07-10 | train region merge rules | d09bda
static func train_from_region(
	base: Dictionary,
	gids: PackedInt32Array,
	width: int,
	height: int,
	manifest: Dictionary = {},
	chunk_size: int = DEFAULT_CHUNK_SIZE,
) -> Dictionary:
	var map := {"width": width, "height": height, "gids": gids}
	var tile_counts: Dictionary = {}
	var adjacency: Dictionary = {}
	var context_weights: Dictionary = {}
	var patterns_3x3: Array = []
	var pattern_counts: Dictionary = {}
	var chunks: Array = []
	var chunk_set := {}
	var chunk_counts: Dictionary = {}
	var chunk_compat: Dictionary = {}

	var analyze: Dictionary = manifest.get("analyze", {})
	var use_chunks: bool = analyze.get("chunks", false)

	_scan_map(map, tile_counts, adjacency, manifest)
	_scan_context(map, context_weights, manifest)
	_scan_patterns_3x3(map, patterns_3x3, pattern_counts, manifest)
	if use_chunks:
		_scan_chunks(map, chunks, chunk_set, chunk_counts, chunk_compat, manifest, chunk_size)

	_filter_adjacency(adjacency, 1)
	_symmetrize_adjacency(adjacency)

	return _merge_into_rules(
		base,
		{
			"tile_counts": tile_counts,
			"adjacency": adjacency,
			"context_counts": _copy_context_counts(context_weights),
			"patterns_3x3": patterns_3x3,
			"pattern_counts": pattern_counts,
			"chunks": chunks,
			"chunk_counts": chunk_counts,
			"chunk_compat": chunk_compat,
			"cells": _count_filled_gids(gids),
		},
		manifest,
		chunk_size,
	)


static func save(path: String, rules: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(rules, "\t"))
	return OK


static func load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func all_tiles(rules: Dictionary, manifest: Dictionary = {}) -> PackedInt32Array:
	return generatable_tiles(rules, manifest)


static func generatable_tiles(rules: Dictionary, manifest: Dictionary = {}) -> PackedInt32Array:
	var seen: Dictionary = {}
	var bg: int = int(manifest.get("background_gid", 1))
	if bg > 0 and (manifest.is_empty() or _is_valid_gid(manifest, bg)):
		seen[bg] = true
	for k in rules.get("tile_weights", {}):
		var gid := int(k)
		if manifest.is_empty() or _is_valid_gid(manifest, gid):
			seen[gid] = true
	var packed := PackedInt32Array()
	for gid in seen:
		packed.append(gid)
	packed.sort()
	return packed


static func adj_options(rules: Dictionary, gid: int, dir: String) -> Dictionary:
	var node: Variant = rules.get("adjacency", {}).get(str(gid), {})
	if node is Dictionary:
		return node.get(dir, {})
	return {}


static func class_mates(rules: Dictionary, gid: int) -> Array:
	var cap: int = GenAtlasAnalyze.max_alias_class_size(rules)
	for class_v in rules.get("tile_classes", []):
		if class_v is not Array or class_v.size() > cap:
			continue
		for member in class_v:
			if int(member) == gid:
				return class_v
	return [gid]


static func tile_weight(rules: Dictionary, gid: int) -> float:
	return float(rules.get("tile_weights", {}).get(str(gid), 0.001))


static func pick_weight(rules: Dictionary, gid: int, tile_bias: Dictionary = {}) -> float:
	var base := float(rules.get("pick_weights", {}).get(str(gid), 0.0))
	if base <= 0.0:
		base = tile_weight(rules, gid)
	var bias_key := str(gid)
	if tile_bias.has(bias_key):
		base *= float(tile_bias[bias_key])
	elif tile_bias.has(gid):
		base *= float(tile_bias[gid])
	return maxf(base, 0.0001)


static func context_weight(rules: Dictionary, gid: int, ctx: PackedInt32Array) -> float:
	var bucket: Variant = rules.get("context_weights", {}).get(_ctx_key(ctx), {})
	if bucket is Dictionary:
		return float(bucket.get(str(gid), 0.0))
	return 0.0


static func patterns_3x3(rules: Dictionary) -> Array:
	var raw: Variant = rules.get("patterns_3x3", [])
	return raw if raw is Array else []


static func chunks(rules: Dictionary) -> Array:
	var raw: Variant = rules.get("chunks", [])
	return raw if raw is Array else []


static func chunk_size(rules: Dictionary) -> int:
	return int(rules.get("chunk_size", DEFAULT_CHUNK_SIZE))


static func chunk_compat(rules: Dictionary) -> Dictionary:
	var raw: Variant = rules.get("chunk_compat", {})
	return raw if raw is Dictionary else {}


static func chunk_count_for(rules: Dictionary, chunk_id: String) -> int:
	return int(rules.get("chunk_counts", {}).get(chunk_id, 1))


static func build_pattern_index(patterns: Array, pattern_counts: Dictionary = {}) -> Dictionary:
	var index := {}
	for pat_v in patterns:
		var pat: PackedInt32Array = _coerce_pattern(pat_v)
		if pat.size() != 9:
			continue
		var freq: float = 1.0
		var key := _pattern_key(pat)
		if pattern_counts.has(key):
			freq = float(pattern_counts[key])
		var neighbor_mask := 0
		for i in 9:
			if i != 4 and pat[i] > 0:
				neighbor_mask |= 1 << i
		var mask: int = neighbor_mask
		while mask > 0:
			var partial_key := _partial_pattern_key(pat, mask)
			if not index.has(partial_key):
				index[partial_key] = {}
			var center: int = pat[4]
			index[partial_key][center] = index[partial_key].get(center, 0.0) + freq
			mask = (mask - 1) & neighbor_mask
	return index


static func _partial_pattern_key(pat: PackedInt32Array, mask: int) -> String:
	var parts: Array = []
	for i in 9:
		if i == 4:
			parts.append("_")
		elif mask & (1 << i):
			parts.append(str(pat[i]))
		else:
			parts.append("*")
	return ",".join(parts)


static func _coerce_pattern(pat_v: Variant) -> PackedInt32Array:
	if pat_v is PackedInt32Array:
		return pat_v
	if pat_v is Array:
		var pat := PackedInt32Array()
		for gid in pat_v:
			pat.append(int(gid))
		return pat
	return PackedInt32Array()


static func _ctx_key(ctx: PackedInt32Array) -> String:
	return "%d,%d,%d,%d" % [ctx[0], ctx[1], ctx[2], ctx[3]]


static func build_context_at(
	out: PackedInt32Array,
	done: PackedByteArray,
	idx: int,
	w: int,
	h: int,
) -> PackedInt32Array:
	var x := idx % w
	var y := idx / w
	var ctx := PackedInt32Array()
	ctx.resize(4)
	ctx.fill(CTX_UNK)

	var north := Vector2i(x, y - 1)
	if north.y >= 0:
		var ni: int = north.y * w + north.x
		if done[ni] and out[ni] > 0:
			ctx[0] = out[ni]

	var east := Vector2i(x + 1, y)
	if east.x < w:
		var ni: int = east.y * w + east.x
		if done[ni] and out[ni] > 0:
			ctx[1] = out[ni]

	var south := Vector2i(x, y + 1)
	if south.y < h:
		var ni: int = south.y * w + south.x
		if done[ni] and out[ni] > 0:
			ctx[2] = out[ni]

	var west := Vector2i(x - 1, y)
	if west.x >= 0:
		var ni: int = west.y * w + west.x
		if done[ni] and out[ni] > 0:
			ctx[3] = out[ni]

	return ctx


static func _merge_edge_gap_fill(
	into: Dictionary,
	from: Dictionary,
	weight: int,
	active: Dictionary,
	max_neighbors: int = DEFAULT_EDGE_GAP_MAX,
) -> void:
	for gid_key in from:
		var gid: int = int(gid_key)
		if not active.has(gid):
			continue
		_ensure_adj(into, gid)
		for d in DIRS:
			var map_bucket: Dictionary = into[str(gid)][d]
			if not map_bucket.is_empty():
				continue
			var edge_bucket: Variant = from[gid_key].get(d, {})
			if edge_bucket is not Dictionary or edge_bucket.is_empty():
				continue
			var ranked: Array = []
			for nb_key in edge_bucket:
				var nb: int = int(nb_key)
				if not active.has(nb):
					continue
				ranked.append({"key": nb_key, "count": int(edge_bucket[nb_key])})
			ranked.sort_custom(func(a, b): return a.count > b.count)
			var limit: int = mini(maxi(max_neighbors, 1), ranked.size())
			for i in limit:
				var entry: Dictionary = ranked[i]
				var nb_key: String = str(entry.key)
				into[str(gid)][d][nb_key] = (
					into[str(gid)][d].get(nb_key, 0) + int(entry.count) * weight
				)


static func _trim_self_adjacency(adjacency: Dictionary, except_gid: int = 0) -> void:
	for gid_key in adjacency:
		var gid: int = int(gid_key)
		if gid == except_gid:
			continue
		for d in DIRS:
			var bucket: Dictionary = adjacency[gid_key][d]
			if bucket.has(gid_key):
				bucket.erase(gid_key)


static func _merge_into_rules(
	base: Dictionary,
	region: Dictionary,
	manifest: Dictionary,
	chunk_size: int,
) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	var tile_counts: Dictionary = _tile_counts_from_rules(out)
	for gid in region.tile_counts:
		tile_counts[gid] = int(tile_counts.get(gid, 0)) + int(region.tile_counts[gid])

	if not out.has("adjacency"):
		out["adjacency"] = {}
	_merge_adjacency(out.adjacency, region.adjacency, 1)

	var context_counts: Dictionary = _context_counts_from_rules(out)
	_merge_context_counts(context_counts, region.context_counts)
	var ctx_norm: Dictionary = _copy_context_counts(context_counts)
	_normalize_context_weights(ctx_norm, 3)
	out["context_counts"] = context_counts
	out["context_weights"] = ctx_norm

	_merge_patterns(out, region.patterns_3x3, region.pattern_counts)
	_merge_chunks(out, region.chunks, region.chunk_counts, region.chunk_compat)

	var weights: Dictionary = _recompute_tile_weights(tile_counts)
	out["tile_weights"] = weights.tile_weights
	out["pick_weights"] = weights.pick_weights
	out["pick_weight_mode"] = "log"

	var stats: Dictionary = out.get("stats", {}).duplicate()
	stats["cells"] = int(stats.get("cells", 0)) + int(region.cells)
	stats["unique_tiles"] = tile_counts.size()
	stats["patterns_3x3"] = out.get("patterns_3x3", []).size()
	stats["context_keys"] = context_counts.size()
	stats["chunks"] = out.get("chunks", []).size()
	out["stats"] = stats
	out["chunk_size"] = chunk_size
	return out


static func _count_filled_gids(gids: PackedInt32Array) -> int:
	var n := 0
	for gid in gids:
		if gid > 0:
			n += 1
	return n


static func _copy_context_counts(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in src:
		var bucket: Variant = src[key]
		if bucket is not Dictionary:
			continue
		out[key] = bucket.duplicate()
	return out


static func _tile_counts_from_rules(rules: Dictionary) -> Dictionary:
	if rules.has("tile_counts") and rules.tile_counts is Dictionary:
		return rules.tile_counts.duplicate()
	var counts: Dictionary = {}
	var cells: int = int(rules.get("stats", {}).get("cells", 0))
	for k in rules.get("tile_weights", {}):
		var gid: int = int(k)
		var weight: float = float(rules.tile_weights[k])
		counts[gid] = maxi(int(round(weight * float(maxi(cells, 1)))), 1) if cells > 0 else 1
	return counts


static func _context_counts_from_rules(rules: Dictionary) -> Dictionary:
	if rules.has("context_counts") and rules.context_counts is Dictionary:
		return _copy_context_counts(rules.context_counts)
	return {}


static func _merge_context_counts(into: Dictionary, from: Dictionary) -> void:
	for key in from:
		if not into.has(key):
			into[key] = {}
		var bucket: Dictionary = into[key]
		for gid_key in from[key]:
			bucket[gid_key] = int(bucket.get(gid_key, 0)) + int(from[key][gid_key])


static func _merge_patterns(out: Dictionary, patterns: Array, pattern_counts: Dictionary) -> void:
	var existing: Array = out.get("patterns_3x3", [])
	if existing is not Array:
		existing = []
	var merged_counts: Dictionary = out.get("pattern_counts", {}).duplicate()
	if merged_counts is not Dictionary:
		merged_counts = {}
	var seen: Dictionary = {}
	for pat_v in existing:
		var pat: PackedInt32Array = _coerce_pattern(pat_v)
		if pat.size() == 9:
			seen[_pattern_key(pat)] = true
	for pat_v in patterns:
		var pat: PackedInt32Array = _coerce_pattern(pat_v)
		if pat.size() != 9:
			continue
		var key := _pattern_key(pat)
		merged_counts[key] = int(merged_counts.get(key, 0)) + int(pattern_counts.get(key, 1))
		if seen.has(key):
			continue
		seen[key] = true
		var saved: Array = []
		for gid in pat:
			saved.append(gid)
		existing.append(saved)
	out["patterns_3x3"] = existing
	out["pattern_counts"] = merged_counts


static func _merge_chunks(
	out: Dictionary,
	chunks: Array,
	chunk_counts: Dictionary,
	chunk_compat: Dictionary,
) -> void:
	var existing: Array = out.get("chunks", [])
	if existing is not Array:
		existing = []
	var merged_counts: Dictionary = out.get("chunk_counts", {}).duplicate()
	if merged_counts is not Dictionary:
		merged_counts = {}
	var merged_compat: Dictionary = out.get("chunk_compat", {}).duplicate()
	if merged_compat is not Dictionary:
		merged_compat = {}
	var seen: Dictionary = {}
	for chunk_v in existing:
		if chunk_v is Dictionary and chunk_v.has("id"):
			seen[str(chunk_v.id)] = true
	for chunk_v in chunks:
		if chunk_v is not Dictionary or not chunk_v.has("id"):
			continue
		var id: String = str(chunk_v.id)
		merged_counts[id] = int(merged_counts.get(id, 0)) + int(chunk_counts.get(id, 1))
		if seen.has(id):
			continue
		seen[id] = true
		existing.append(chunk_v)
		if chunk_compat.has(id):
			merged_compat[id] = chunk_compat[id]
	out["chunks"] = existing
	out["chunk_counts"] = merged_counts
	out["chunk_compat"] = merged_compat


static func _recompute_tile_weights(tile_counts: Dictionary) -> Dictionary:
	var tile_weights := {}
	var pick_weights := {}
	var log_total := 0.0
	for gid in tile_counts:
		log_total += log(float(tile_counts[gid]) + 1.0)
	var tile_total := 0
	for gid in tile_counts:
		tile_total += tile_counts[gid]
	for gid in tile_counts:
		tile_weights[str(gid)] = float(tile_counts[gid]) / float(maxi(tile_total, 1))
		pick_weights[str(gid)] = log(float(tile_counts[gid]) + 1.0) / maxf(log_total, 0.001)
	return {"tile_weights": tile_weights, "pick_weights": pick_weights}


static func _merge_adjacency(into: Dictionary, from: Dictionary, weight: int = 1) -> void:
	for gid_key in from:
		var gid: int = int(gid_key)
		_ensure_adj(into, gid)
		var src: Variant = from[gid_key]
		if src is not Dictionary:
			continue
		for d in DIRS:
			var bucket: Variant = src.get(d, {})
			if bucket is not Dictionary:
				continue
			for nb_key in bucket:
				into[str(gid)][d][nb_key] = into[str(gid)][d].get(nb_key, 0) + int(bucket[nb_key]) * weight


static func _active_gid_set(tile_counts: Dictionary, tile_classes: Array) -> Dictionary:
	var active: Dictionary = {}
	for gid in tile_counts:
		active[gid] = true
	for class_v in tile_classes:
		if class_v is not Array or class_v.size() > 12:
			continue
		for member in class_v:
			active[int(member)] = true
	return active


static func _restrict_adjacency(src: Dictionary, active: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for gid_key in src:
		var gid: int = int(gid_key)
		if not active.has(gid):
			continue
		_ensure_adj(out, gid)
		for d in DIRS:
			var bucket: Variant = src[gid_key].get(d, {})
			if bucket is not Dictionary:
				continue
			for nb_key in bucket:
				var nb: int = int(nb_key)
				if not active.has(nb):
					continue
				out[str(gid)][d][nb_key] = int(bucket[nb_key])
	return out


static func _scan_map(map: Dictionary, tile_counts: Dictionary, adjacency: Dictionary, manifest: Dictionary) -> void:
	var w: int = map.width
	var h: int = map.height
	var gids: PackedInt32Array = map.gids

	for y in h:
		for x in w:
			var a := _cell_gid(gids[y * w + x], manifest)
			if a <= 0:
				continue
			tile_counts[a] = tile_counts.get(a, 0) + 1
			_ensure_adj(adjacency, a)

			if y > 0:
				var b := _cell_gid(gids[(y - 1) * w + x], manifest)
				if b > 0:
					adjacency[str(a)]["north"][str(b)] = adjacency[str(a)]["north"].get(str(b), 0) + 1
			if x < w - 1:
				var b_e := _cell_gid(gids[y * w + x + 1], manifest)
				if b_e > 0:
					adjacency[str(a)]["east"][str(b_e)] = adjacency[str(a)]["east"].get(str(b_e), 0) + 1
			if y < h - 1:
				var b_s := _cell_gid(gids[(y + 1) * w + x], manifest)
				if b_s > 0:
					adjacency[str(a)]["south"][str(b_s)] = adjacency[str(a)]["south"].get(str(b_s), 0) + 1
			if x > 0:
				var b_w := _cell_gid(gids[y * w + x - 1], manifest)
				if b_w > 0:
					adjacency[str(a)]["west"][str(b_w)] = adjacency[str(a)]["west"].get(str(b_w), 0) + 1


static func _scan_context(map: Dictionary, context_weights: Dictionary, manifest: Dictionary) -> void:
	var w: int = map.width
	var h: int = map.height
	var gids: PackedInt32Array = map.gids

	for y in h:
		for x in w:
			var center := _cell_gid(gids[y * w + x], manifest)
			if center <= 0:
				continue
			var neighbors := PackedInt32Array()
			neighbors.resize(4)
			neighbors[0] = _neighbor_gid(gids, w, h, x, y - 1, manifest)
			neighbors[1] = _neighbor_gid(gids, w, h, x + 1, y, manifest)
			neighbors[2] = _neighbor_gid(gids, w, h, x, y + 1, manifest)
			neighbors[3] = _neighbor_gid(gids, w, h, x - 1, y, manifest)

			for mask in 16:
				var ctx := PackedInt32Array()
				ctx.resize(4)
				ctx.fill(CTX_UNK)
				if mask & 1:
					ctx[0] = neighbors[0]
				if mask & 2:
					ctx[1] = neighbors[1]
				if mask & 4:
					ctx[2] = neighbors[2]
				if mask & 8:
					ctx[3] = neighbors[3]
				_add_context(context_weights, ctx, center)


static func _scan_patterns_3x3(
	map: Dictionary,
	patterns: Array,
	pattern_counts: Dictionary,
	manifest: Dictionary,
) -> void:
	var w: int = map.width
	var h: int = map.height
	var gids: PackedInt32Array = map.gids
	var seen := {}

	for y in h - 2:
		for x in w - 2:
			var pat := PackedInt32Array()
			pat.resize(9)
			var valid := true
			for dy in 3:
				for dx in 3:
					var gid := _cell_gid(gids[(y + dy) * w + (x + dx)], manifest)
					if gid <= 0:
						valid = false
						break
					pat[dy * 3 + dx] = gid
				if not valid:
					break
			if not valid:
				continue
			var key := _pattern_key(pat)
			pattern_counts[key] = int(pattern_counts.get(key, 0)) + 1
			if seen.has(key):
				continue
			seen[key] = true
			var saved: Array = []
			for gid in pat:
				saved.append(gid)
			patterns.append(saved)


static func _scan_chunks(
	map: Dictionary,
	chunks: Array,
	chunk_set: Dictionary,
	chunk_counts: Dictionary,
	chunk_compat: Dictionary,
	manifest: Dictionary,
	chunk_size: int,
) -> void:
	var w: int = map.width
	var h: int = map.height
	var gids: PackedInt32Array = map.gids
	var cs: int = maxi(chunk_size, 1)

	for cy in ceili(float(h) / float(cs)):
		for cx in ceili(float(w) / float(cs)):
			var tiles := PackedInt32Array()
			tiles.resize(cs * cs)
			tiles.fill(0)
			var any := false
			for dy in cs:
				for dx in cs:
					var x: int = cx * cs + dx
					var y: int = cy * cs + dy
					if x >= w or y >= h:
						continue
					var gid := _cell_gid(gids[y * w + x], manifest)
					tiles[dy * cs + dx] = gid
					if gid > 0:
						any = true
			if not any:
				continue
			var id := _chunk_id(tiles)
			chunk_counts[id] = int(chunk_counts.get(id, 0)) + 1
			if not chunk_set.has(id):
				chunk_set[id] = true
				chunks.append({"id": id, "size": cs, "tiles": _packed_to_array(tiles)})
				chunk_compat[id] = {
					"north": _chunk_edge(tiles, cs, "north"),
					"east": _chunk_edge(tiles, cs, "east"),
					"south": _chunk_edge(tiles, cs, "south"),
					"west": _chunk_edge(tiles, cs, "west"),
				}


static func _chunk_id(tiles: PackedInt32Array) -> String:
	var parts: Array = []
	for gid in tiles:
		parts.append(str(gid))
	return ",".join(parts)


static func _chunk_edge(tiles: PackedInt32Array, cs: int, edge: String) -> Array:
	var row: Array = []
	match edge:
		"north":
			for x in cs:
				row.append(tiles[x])
		"south":
			for x in cs:
				row.append(tiles[(cs - 1) * cs + x])
		"west":
			for y in cs:
				row.append(tiles[y * cs])
		"east":
			for y in cs:
				row.append(tiles[y * cs + cs - 1])
	return row


static func _packed_to_array(tiles: PackedInt32Array) -> Array:
	var out: Array = []
	for gid in tiles:
		out.append(gid)
	return out


static func _pattern_key(pat: PackedInt32Array) -> String:
	var parts: Array = []
	for gid in pat:
		parts.append(str(gid))
	return ",".join(parts)


static func _neighbor_gid(
	gids: PackedInt32Array,
	w: int,
	h: int,
	x: int,
	y: int,
	manifest: Dictionary,
) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return CTX_UNK
	return _cell_gid(gids[y * w + x], manifest)


static func _add_context(context_weights: Dictionary, ctx: PackedInt32Array, center: int) -> void:
	var key := _ctx_key(ctx)
	if not context_weights.has(key):
		context_weights[key] = {}
	var bucket: Dictionary = context_weights[key]
	bucket[str(center)] = int(bucket.get(str(center), 0)) + 1


static func _normalize_context_weights(context_weights: Dictionary, min_total: int) -> void:
	var erase_keys: Array = []
	for key in context_weights:
		var bucket: Dictionary = context_weights[key]
		var total := 0
		for gid_key in bucket:
			total += int(bucket[gid_key])
		if total < min_total:
			erase_keys.append(key)
			continue
		for gid_key in bucket:
			bucket[gid_key] = float(bucket[gid_key]) / float(total)
	for key in erase_keys:
		context_weights.erase(key)


static func _cell_gid(raw: int, manifest: Dictionary) -> int:
	if raw <= 0:
		return 0
	var gid := _normalize_gid(raw)
	if not manifest.is_empty() and not _is_valid_gid(manifest, gid):
		return 0
	return gid


static func _normalize_gid(raw: int) -> int:
	return raw & TILED_GID_MASK


static func _tile_count(manifest: Dictionary) -> int:
	if manifest.has("tile_count"):
		return int(manifest.tile_count)
	var cols: int = int(manifest.get("columns", 0))
	var row_count: int = int(manifest.get("rows", 0))
	if cols > 0 and row_count > 0:
		return cols * row_count
	return 0


static func _is_valid_gid(manifest: Dictionary, gid: int) -> bool:
	var local := _normalize_gid(gid) - int(manifest.get("first_gid", 1))
	return local >= 0 and local < _tile_count(manifest)


static func _ensure_adj(adjacency: Dictionary, gid: int) -> void:
	var key := str(gid)
	if adjacency.has(key):
		return
	adjacency[key] = {}
	for d in DIRS:
		adjacency[key][d] = {}


static func _filter_adjacency(adjacency: Dictionary, min_count: int) -> void:
	for gid_key in adjacency:
		for d in DIRS:
			var bucket: Dictionary = adjacency[gid_key][d]
			for other in bucket.keys():
				if bucket[other] < min_count:
					bucket.erase(other)


static func _symmetrize_adjacency(adjacency: Dictionary) -> void:
	var pairs: Array = []
	for gid_key in adjacency:
		for d in DIRS:
			var bucket: Dictionary = adjacency[gid_key][d]
			for other in bucket:
				pairs.append([other, OPPOSITE[d], gid_key, bucket[other]])

	for pair in pairs:
		var other_key: String = pair[0]
		var opp_dir: String = pair[1]
		var back_key: String = pair[2]
		var count: int = pair[3]
		_ensure_adj(adjacency, int(other_key))
		var back_bucket: Dictionary = adjacency[other_key][opp_dir]
		back_bucket[back_key] = maxi(int(back_bucket.get(back_key, 0)), count)
