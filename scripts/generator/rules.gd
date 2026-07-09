# agent: composer-2.5 | 2026-07-08 | context weights map-primary tiles | g7h8i9
extends RefCounted

const GenTmx := preload("res://scripts/generator/tmx.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")

const DIRS := GenTmx.DIRS
const DEFAULT_EDGE_GAP_MAX := 4
const DEFAULT_MAX_ADJ_MATES := 16
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
) -> Dictionary:
	var tile_counts: Dictionary = {}
	var map_adjacency: Dictionary = {}
	var total := 0
	var analyze: Dictionary = manifest.get("analyze", {})
	var use_maps: bool = analyze.get("maps", true)
	var use_tileset_edges: bool = analyze.get("tileset_edges", false)
	var edge_weight_raw: float = float(analyze.get("tileset_edges_weight", 0.15))
	var edge_weight: int = maxi(int(round(edge_weight_raw * 10.0)), 1) if edge_weight_raw > 0.0 else 0
	var min_adj: int = maxi(int(analyze.get("min_adj_count", min_adj_count)), 1)
	var max_adj_mates: int = maxi(int(analyze.get("max_adj_mates", DEFAULT_MAX_ADJ_MATES)), 1)
	var min_generatable: int = maxi(int(analyze.get("min_generatable_count", 2)), 1)
	var min_context: int = maxi(int(analyze.get("min_context_count", 3)), 2)
	var min_pattern: int = maxi(int(analyze.get("min_pattern_count", 2)), 2)
	var context_weights_raw: Dictionary = {}
	var dir_context_weights_raw: Dictionary = {}
	var patterns_3x3_raw: Dictionary = {}
	var sources := {
		"maps": use_maps,
		"tileset_edges": use_tileset_edges,
		"min_adj_count": min_adj,
		"max_adj_mates": max_adj_mates,
		"min_generatable_count": min_generatable,
		"min_context_count": min_context,
		"visual_grid": int(analyze.get("visual_grid", 2)),
		"palette_max": int(analyze.get("palette_max", 64)),
	}

	var atlas_result: Dictionary = GenAtlasAnalyze.analyze_atlas(manifest)
	var signatures: Dictionary = atlas_result.get("signatures", {})
	var gid_to_sig: Dictionary = atlas_result.get("gid_to_sig", {})
	var palette: Array = atlas_result.get("palette", [])
	var atlas_sig_adj: Dictionary = atlas_result.get("sig_adjacency", {})
	var tile_edges: Dictionary = GenAtlasAnalyze.tile_edges_index(
		atlas_result.get("tile_descs", {})
	)
	var bg_gid: int = int(manifest.get("background_gid", 1))
	var bg_sig: String = str(gid_to_sig.get(str(bg_gid), ""))

	if use_maps:
		for map_path in maps:
			var map := GenTmx.read_map(map_path)
			if map.is_empty():
				continue
			_scan_map(map, tile_counts, map_adjacency, manifest, gid_to_sig, bg_gid, bg_sig)
			_scan_context(map, context_weights_raw, dir_context_weights_raw, manifest)
			_scan_patterns_3x3(map, patterns_3x3_raw, manifest)
			total += map.width * map.height

	var sig_counts: Dictionary = {}
	var sig_adjacency: Dictionary = {}
	for gid in tile_counts:
		var sig: String = str(gid_to_sig.get(str(gid), ""))
		if sig.is_empty():
			continue
		sig_counts[sig] = int(sig_counts.get(sig, 0)) + int(tile_counts[gid])

	if use_maps:
		sig_adjacency = _clone_sig_adjacency(_map_adjacency_to_sig(map_adjacency, gid_to_sig))
	elif not atlas_sig_adj.is_empty():
		sig_adjacency = _clone_sig_adjacency(atlas_sig_adj)

	if use_tileset_edges and edge_weight > 0 and not atlas_sig_adj.is_empty():
		if sig_adjacency.is_empty():
			sig_adjacency = _clone_sig_adjacency(atlas_sig_adj)
		else:
			_merge_sig_adjacency(sig_adjacency, atlas_sig_adj, edge_weight)

	_filter_sig_adjacency(sig_adjacency, min_adj)
	_symmetrize_sig_adjacency(sig_adjacency)
	_cap_sig_adjacency(sig_adjacency, max_adj_mates)
	_symmetrize_sig_adjacency(sig_adjacency)

	if use_tileset_edges and edge_weight > 0 and not atlas_sig_adj.is_empty():
		var edge_gap_max: int = maxi(
			int(analyze.get("edge_gap_max_neighbors", DEFAULT_EDGE_GAP_MAX)), 1
		)
		_merge_sig_edge_gap_fill(sig_adjacency, atlas_sig_adj, edge_weight, sig_counts, edge_gap_max)
		_symmetrize_sig_adjacency(sig_adjacency)
		_cap_sig_adjacency(sig_adjacency, max_adj_mates)
		_symmetrize_sig_adjacency(sig_adjacency)

	GenAtlasAnalyze.apply_same_sig_vertical_adj(
		sig_adjacency,
		atlas_result.get("tile_descs", {}),
		min_adj,
	)
	_symmetrize_sig_adjacency(sig_adjacency)

	var generatable_members: Dictionary = _build_generatable_members(
		signatures, sig_counts, gid_to_sig, bg_gid, bg_sig, min_generatable
	)

	var adjacency: Dictionary = {}
	if use_maps:
		adjacency = _clone_adjacency(map_adjacency)
		_filter_gid_adjacency_by_edges(adjacency, tile_edges)
		if analyze.get("trim_self_adj", true):
			_trim_self_adjacency(adjacency, bg_gid)

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

	var map_tile_counts := {}
	for gid in tile_counts:
		map_tile_counts[str(gid)] = int(tile_counts[gid])

	var context_weights := _normalize_context_weights(context_weights_raw, min_context)
	var dir_context_weights := _normalize_dir_context_weights(
		dir_context_weights_raw, min_context
	)
	var patterns_3x3 := _normalize_patterns_3x3(patterns_3x3_raw, min_pattern)

	return {
		"version": 8,
		"tile_weights": tile_weights,
		"pick_weights": pick_weights,
		"pick_weight_mode": "log",
		"map_tile_counts": map_tile_counts,
		"context_weights": context_weights,
		"dir_context_weights": dir_context_weights,
		"patterns_3x3": patterns_3x3,
		"adjacency": adjacency,
		"sig_adjacency": sig_adjacency,
		"signatures": signatures,
		"gid_to_sig": gid_to_sig,
		"tile_edges": tile_edges,
		"generatable_members": generatable_members,
		"palette": palette,
		"background_gid": bg_gid,
		"background_sig": bg_sig,
		"maps": maps,
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
			"unique_signatures": signatures.size(),
			"context_keys": context_weights.size(),
			"dir_context_buckets": _dir_context_bucket_count(dir_context_weights),
			"pattern_centers": patterns_3x3.size(),
			"generatable_signatures": generatable_members.size(),
			"max_adj_mates": max_adj_mates,
		},
	}


static func save(path: String, rules: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(rules))
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
	var min_count: int = maxi(
		int(rules.get("sources", {}).get("min_generatable_count", 2)), 1
	)
	var map_counts: Dictionary = rules.get("map_tile_counts", {})
	var legacy: bool = map_counts.is_empty()
	if legacy:
		map_counts = rules.get("tile_weights", {})
	var bg: int = int(rules.get("background_gid", manifest.get("background_gid", 1)))
	var members_map: Dictionary = rules.get("generatable_members", {})

	if not members_map.is_empty():
		for sig in members_map:
			var members: Variant = members_map[sig]
			if members is not Array or members.is_empty():
				continue
			var rep: int = int(members[0])
			if not manifest.is_empty() and not _is_valid_gid(manifest, rep):
				continue
			seen[rep] = true
		var packed := PackedInt32Array()
		for gid in seen:
			packed.append(gid)
		packed.sort()
		return packed

	var bg_sig: String = str(rules.get("background_sig", ""))
	var gid_to_sig: Dictionary = rules.get("gid_to_sig", {})
	if bg > 0 and (manifest.is_empty() or _is_valid_gid(manifest, bg)):
		seen[bg] = true
	for k in map_counts:
		var gid := int(k)
		if not manifest.is_empty() and not _is_valid_gid(manifest, gid):
			continue
		if not bg_sig.is_empty():
			var sig: String = str(gid_to_sig.get(str(gid), ""))
			if sig == bg_sig and gid != bg:
				continue
		if legacy or gid == bg:
			seen[gid] = true
			continue
		var count: int = int(map_counts[k])
		if count >= min_count:
			seen[gid] = true
	var packed_legacy := PackedInt32Array()
	for gid in seen:
		packed_legacy.append(gid)
	packed_legacy.sort()
	return packed_legacy


static func adj_options(rules: Dictionary, gid: int, dir: String) -> Dictionary:
	var sig_adj: Dictionary = rules.get("sig_adjacency", {})
	if not sig_adj.is_empty():
		return _adj_options_from_sig(rules, gid, dir)
	var node: Variant = rules.get("adjacency", {}).get(str(gid), {})
	if node is Dictionary:
		return node.get(dir, {})
	return {}


static func _adj_options_from_sig(rules: Dictionary, gid: int, dir: String) -> Dictionary:
	var gid_to_sig: Dictionary = rules.get("gid_to_sig", {})
	var sig: String = str(gid_to_sig.get(str(gid), ""))
	if sig.is_empty():
		return {}
	var node: Variant = rules.get("sig_adjacency", {}).get(sig, {})
	if node is not Dictionary:
		return {}
	var bucket: Variant = node.get(dir, {})
	if bucket is not Dictionary:
		return {}
	var out: Dictionary = {}
	for sig_b in bucket:
		var count: int = int(bucket[sig_b])
		for member in GenAtlasAnalyze.generatable_members(rules, str(sig_b)):
			var member_s := str(int(member))
			out[member_s] = maxi(int(out.get(member_s, 0)), count)
	return out


static func class_mates(rules: Dictionary, gid: int) -> Array:
	var sig: String = GenAtlasAnalyze.sig_for_gid(rules, gid)
	if sig.is_empty():
		return [gid]
	var members: Array = GenAtlasAnalyze.generatable_members(rules, sig)
	if members.is_empty():
		return [gid]
	return members


static func pick_member_gid(rules: Dictionary, gid: int, _rng: RandomNumberGenerator) -> int:
	return resolve_generatable_gid(rules, gid, _rng)


static func _best_weighted_member(rules: Dictionary, pool: Array) -> int:
	var best_gid := int(pool[0])
	var best_w := pick_weight(rules, best_gid)
	for i in range(1, pool.size()):
		var mg: int = int(pool[i])
		var w: float = pick_weight(rules, mg)
		if w > best_w or (is_equal_approx(w, best_w) and mg < best_gid):
			best_w = w
			best_gid = mg
	return best_gid


static func representative_gid(rules: Dictionary, gid: int) -> int:
	var sig: String = GenAtlasAnalyze.sig_for_gid(rules, gid)
	if sig.is_empty():
		return gid
	var members: Array = GenAtlasAnalyze.generatable_members(rules, sig)
	if members.is_empty():
		return gid
	return int(members[0])


static func resolve_generatable_gid(
	rules: Dictionary,
	gid: int,
	_rng: RandomNumberGenerator,
	allowed: Dictionary = {},
) -> int:
	var sig: String = GenAtlasAnalyze.sig_for_gid(rules, gid)
	if sig.is_empty():
		return gid
	var bg_sig: String = str(rules.get("background_sig", ""))
	var bg_gid: int = int(rules.get("background_gid", 0))
	if sig == bg_sig and bg_gid > 0:
		return bg_gid
	var members: Array = GenAtlasAnalyze.generatable_members(rules, sig)
	if members.is_empty():
		return gid
	var pool: Array = []
	for member in members:
		var mg: int = int(member)
		if allowed.is_empty() or allowed.has(mg):
			pool.append(mg)
	if pool.is_empty():
		return gid
	if pool.size() == 1:
		return int(pool[0])
	return _best_weighted_member(rules, pool)


static func tile_weight(rules: Dictionary, gid: int) -> float:
	return float(rules.get("tile_weights", {}).get(str(gid), 0.001))


static func pick_weight(rules: Dictionary, gid: int) -> float:
	var base := float(rules.get("pick_weights", {}).get(str(gid), 0.0))
	if base <= 0.0:
		base = tile_weight(rules, gid)
	return maxf(base, 0.0001)


static func _mate_pick_prob(rules: Dictionary, bucket: Dictionary, gid: int) -> float:
	var best := 0.0
	for mate in class_mates(rules, gid):
		best = maxf(best, float(bucket.get(str(int(mate)), 0.0)))
	return best


static func context_pick_factor(rules: Dictionary, ctx_key: String, gid: int) -> float:
	var buckets: Dictionary = rules.get("context_weights", {})
	if not buckets.has(ctx_key):
		return 1.0
	var bucket: Variant = buckets[ctx_key]
	if bucket is not Dictionary:
		return 1.0
	var prob: float = _mate_pick_prob(rules, bucket, gid)
	if prob <= 0.0:
		return 0.05
	return maxf(prob, 0.0001)


static func _neighbor_context_bucket(
	rules: Dictionary,
	by_dir: Dictionary,
	neighbor_gid: int,
) -> Dictionary:
	var merged := {}
	for mate in class_mates(rules, neighbor_gid):
		var sub: Variant = by_dir.get(str(int(mate)))
		if sub is not Dictionary:
			continue
		for gid_key in sub:
			var prob: float = float(sub[gid_key])
			merged[gid_key] = maxf(float(merged.get(gid_key, 0.0)), prob)
	return merged


static func dir_context_pick_factor(
	rules: Dictionary,
	dir: String,
	neighbor_gid: int,
	gid: int,
) -> float:
	var dirs: Dictionary = rules.get("dir_context_weights", {})
	if not dirs.has(dir):
		return 1.0
	var by_dir: Variant = dirs[dir]
	if by_dir is not Dictionary:
		return 1.0
	var bucket: Dictionary = _neighbor_context_bucket(rules, by_dir, neighbor_gid)
	if bucket.is_empty():
		return 1.0
	var prob: float = _mate_pick_prob(rules, bucket, gid)
	if prob <= 0.0:
		return 0.05
	return maxf(prob, 0.0001)


static func opposing_edges_compatible(
	rules: Dictionary,
	gid_a: int,
	dir: String,
	gid_b: int,
) -> bool:
	var tile_edges: Dictionary = rules.get("tile_edges", {})
	var edges_a: Variant = tile_edges.get(str(gid_a))
	var edges_b: Variant = tile_edges.get(str(gid_b))
	if edges_a is not Dictionary or edges_b is not Dictionary:
		return true
	return GenAtlasAnalyze.opposing_edges_match(edges_a, edges_b, dir)


static func _filter_gid_adjacency_by_edges(
	adjacency: Dictionary,
	tile_edges: Dictionary,
) -> void:
	if tile_edges.is_empty():
		return
	for gid_key in adjacency:
		for d in DIRS:
			var bucket: Variant = adjacency[gid_key].get(d, {})
			if bucket is not Dictionary:
				continue
			for nb_key in bucket.keys():
				if not GenAtlasAnalyze.opposing_edges_match(
					tile_edges.get(str(gid_key), {}),
					tile_edges.get(str(nb_key), {}),
					d
				):
					bucket.erase(nb_key)


static func _clone_adjacency(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for gid_key in src:
		out[str(gid_key)] = {}
		for d in DIRS:
			var bucket: Variant = src[gid_key].get(d, {})
			if bucket is Dictionary:
				out[str(gid_key)][d] = bucket.duplicate()
			else:
				out[str(gid_key)][d] = {}
	return out


static func _scan_context(
	map: Dictionary,
	context_weights: Dictionary,
	dir_context_weights: Dictionary,
	manifest: Dictionary,
) -> void:
	var w: int = map.width
	var h: int = map.height
	var gids: PackedInt32Array = map.gids
	var offsets: Array = [
		["north", Vector2i(0, -1)],
		["east", Vector2i(1, 0)],
		["south", Vector2i(0, 1)],
		["west", Vector2i(-1, 0)],
	]
	for y in h:
		for x in w:
			var center := _cell_gid(gids[y * w + x], manifest)
			if center <= 0:
				continue
			var key := _context_key_at(gids, manifest, x, y, w, h)
			if not context_weights.has(key):
				context_weights[key] = {}
			var bucket: Dictionary = context_weights[key]
			var center_s := str(center)
			bucket[center_s] = int(bucket.get(center_s, 0)) + 1

			for entry in offsets:
				var dir_name: String = entry[0]
				var off: Vector2i = entry[1]
				var nx: int = x + off.x
				var ny: int = y + off.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var neighbor := _cell_gid(gids[ny * w + nx], manifest)
				if neighbor <= 0:
					continue
				if not dir_context_weights.has(dir_name):
					dir_context_weights[dir_name] = {}
				var by_neighbor: Dictionary = dir_context_weights[dir_name]
				var nb_s := str(neighbor)
				if not by_neighbor.has(nb_s):
					by_neighbor[nb_s] = {}
				var picks: Dictionary = by_neighbor[nb_s]
				picks[center_s] = int(picks.get(center_s, 0)) + 1


static func _scan_patterns_3x3(
	map: Dictionary,
	patterns: Dictionary,
	manifest: Dictionary,
) -> void:
	var w: int = map.width
	var h: int = map.height
	var gids: PackedInt32Array = map.gids
	for y in h:
		for x in w:
			var parts: PackedStringArray = PackedStringArray()
			parts.resize(9)
			for dy in 3:
				for dx in 3:
					var px: int = x + dx - 1
					var py: int = y + dy - 1
					var slot: int = dy * 3 + dx
					if px < 0 or py < 0 or px >= w or py >= h:
						parts[slot] = "0"
					else:
						parts[slot] = str(_cell_gid(gids[py * w + px], manifest))
			var center_gid: int = int(parts[4])
			if center_gid <= 0:
				continue
			var key := "|".join(parts)
			if not patterns.has(key):
				patterns[key] = 0
			patterns[key] = int(patterns[key]) + 1


static func _context_key_at(
	gids: PackedInt32Array,
	manifest: Dictionary,
	x: int,
	y: int,
	w: int,
	h: int,
) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var offsets: Array = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]
	for off in offsets:
		var nx: int = x + off.x
		var ny: int = y + off.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			parts.append("0")
		else:
			var g := _cell_gid(gids[ny * w + nx], manifest)
			parts.append(str(g))
	return "|".join(parts)


static func _normalize_context_weights(raw: Dictionary, min_key_count: int) -> Dictionary:
	var out: Dictionary = {}
	for key in raw:
		var bucket: Dictionary = raw[key]
		var total := 0
		for k in bucket:
			total += int(bucket[k])
		if total < min_key_count:
			continue
		var norm: Dictionary = {}
		for k in bucket:
			norm[k] = float(bucket[k]) / float(total)
		out[key] = norm
	return out


static func _normalize_dir_context_weights(raw: Dictionary, min_key_count: int) -> Dictionary:
	var out: Dictionary = {}
	for dir_name in raw:
		var by_neighbor: Dictionary = raw[dir_name]
		var norm_neighbors: Dictionary = {}
		for nb_key in by_neighbor:
			var bucket: Dictionary = by_neighbor[nb_key]
			var total := 0
			for k in bucket:
				total += int(bucket[k])
			if total < min_key_count:
				continue
			var norm: Dictionary = {}
			for k in bucket:
				norm[k] = float(bucket[k]) / float(total)
			norm_neighbors[nb_key] = norm
		if not norm_neighbors.is_empty():
			out[dir_name] = norm_neighbors
	return out


static func _dir_context_bucket_count(dir_context: Dictionary) -> int:
	var n := 0
	for dir_name in dir_context:
		var by_neighbor: Dictionary = dir_context[dir_name]
		n += by_neighbor.size()
	return n


static func _normalize_patterns_3x3(raw: Dictionary, min_count: int) -> Dictionary:
	var by_center: Dictionary = {}
	for key in raw:
		var total: int = int(raw[key])
		if total < min_count:
			continue
		var parts: PackedStringArray = key.split("|")
		if parts.size() != 9:
			continue
		var center_s: String = parts[4]
		if not by_center.has(center_s):
			by_center[center_s] = {"_total": 0, "_patterns": {}}
		var bucket: Dictionary = by_center[center_s]
		bucket["_total"] = int(bucket["_total"]) + total
		bucket["_patterns"][key] = int(bucket["_patterns"].get(key, 0)) + total

	var out: Dictionary = {}
	for center_s in by_center:
		var bucket: Dictionary = by_center[center_s]
		var center_total: int = int(bucket["_total"])
		if center_total < min_count:
			continue
		var norm: Dictionary = {}
		for pattern_key in bucket["_patterns"]:
			norm[pattern_key] = float(bucket["_patterns"][pattern_key]) / float(center_total)
		out[center_s] = norm
	return out


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


static func _active_gid_set(tile_counts: Dictionary, _unused: Array = []) -> Dictionary:
	var active: Dictionary = {}
	for gid in tile_counts:
		active[gid] = true
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


static func _scan_map(
	map: Dictionary,
	tile_counts: Dictionary,
	adjacency: Dictionary,
	manifest: Dictionary,
	gid_to_sig: Dictionary = {},
	bg_gid: int = 0,
	bg_sig: String = "",
) -> void:
	var w: int = map.width
	var h: int = map.height
	var gids: PackedInt32Array = map.gids

	for y in h:
		for x in w:
			var raw := _cell_gid(gids[y * w + x], manifest)
			if raw <= 0:
				continue
			var a := _remap_analyze_gid(raw, gid_to_sig, bg_gid, bg_sig)
			tile_counts[a] = tile_counts.get(a, 0) + 1
			_ensure_adj(adjacency, a)

			if y > 0:
				var b := _remap_analyze_gid(_cell_gid(gids[(y - 1) * w + x], manifest), gid_to_sig, bg_gid, bg_sig)
				if b > 0:
					adjacency[str(a)]["north"][str(b)] = adjacency[str(a)]["north"].get(str(b), 0) + 1
			if x < w - 1:
				var b_e := _remap_analyze_gid(_cell_gid(gids[y * w + x + 1], manifest), gid_to_sig, bg_gid, bg_sig)
				if b_e > 0:
					adjacency[str(a)]["east"][str(b_e)] = adjacency[str(a)]["east"].get(str(b_e), 0) + 1
			if y < h - 1:
				var b_s := _remap_analyze_gid(_cell_gid(gids[(y + 1) * w + x], manifest), gid_to_sig, bg_gid, bg_sig)
				if b_s > 0:
					adjacency[str(a)]["south"][str(b_s)] = adjacency[str(a)]["south"].get(str(b_s), 0) + 1
			if x > 0:
				var b_w := _remap_analyze_gid(_cell_gid(gids[y * w + x - 1], manifest), gid_to_sig, bg_gid, bg_sig)
				if b_w > 0:
					adjacency[str(a)]["west"][str(b_w)] = adjacency[str(a)]["west"].get(str(b_w), 0) + 1


static func _remap_analyze_gid(
	gid: int,
	gid_to_sig: Dictionary,
	bg_gid: int,
	bg_sig: String,
) -> int:
	if gid <= 0 or gid_to_sig.is_empty() or bg_sig.is_empty() or bg_gid <= 0:
		return gid
	var sig: String = str(gid_to_sig.get(str(gid), ""))
	if sig == bg_sig and gid != bg_gid:
		return bg_gid
	return gid


static func _map_adjacency_to_sig(map_adjacency: Dictionary, gid_to_sig: Dictionary) -> Dictionary:
	var sig_adj: Dictionary = {}
	for gid_a_key in map_adjacency:
		var sig_a: String = str(gid_to_sig.get(str(int(gid_a_key)), ""))
		if sig_a.is_empty():
			continue
		_ensure_sig_adj(sig_adj, sig_a)
		for d in DIRS:
			var bucket: Variant = map_adjacency[gid_a_key].get(d, {})
			if bucket is not Dictionary:
				continue
			for gid_b_key in bucket:
				var sig_b: String = str(gid_to_sig.get(str(int(gid_b_key)), ""))
				if sig_b.is_empty():
					continue
				var count: int = int(bucket[gid_b_key])
				sig_adj[sig_a][d][sig_b] = int(sig_adj[sig_a][d].get(sig_b, 0)) + count
	return sig_adj


static func _build_generatable_members(
	signatures: Dictionary,
	sig_counts: Dictionary,
	gid_to_sig: Dictionary,
	bg_gid: int,
	bg_sig: String,
	min_count: int,
) -> Dictionary:
	var out: Dictionary = {}
	for sig in signatures:
		var gids: Array = signatures[sig]
		if gids.is_empty():
			continue
		if sig == bg_sig and bg_gid > 0:
			out[sig] = [bg_gid]
			continue
		var count: int = int(sig_counts.get(sig, 0))
		if count < min_count:
			continue
		var members: Array = []
		for gid_v in gids:
			var gid: int = int(gid_v)
			if bg_sig.is_empty() or str(gid_to_sig.get(str(gid), "")) != bg_sig:
				members.append(gid)
				continue
			if gid == bg_gid:
				members.append(gid)
		if members.is_empty():
			continue
		members.sort()
		out[sig] = members
	if bg_sig.is_empty() or not out.has(bg_sig):
		if bg_gid > 0:
			out[bg_sig] = [bg_gid]
	return out


static func _mirror_member_adjacency(adjacency: Dictionary, members: Array) -> void:
	if members.size() <= 1:
		return
	for d in DIRS:
		var union: Dictionary = {}
		for gid_a in members:
			var bucket: Variant = adjacency.get(str(gid_a), {}).get(d, {})
			if bucket is Dictionary:
				for nb_key in bucket:
					union[nb_key] = maxi(int(union.get(nb_key, 0)), int(bucket[nb_key]))
		for gid_a in members:
			_ensure_adj(adjacency, int(gid_a))
			for nb_key in union:
				adjacency[str(gid_a)][d][nb_key] = maxi(
					int(adjacency[str(gid_a)][d].get(nb_key, 0)), int(union[nb_key])
				)


static func _clone_sig_adjacency(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for sig_a in src:
		out[sig_a] = {}
		for d in DIRS:
			var bucket: Variant = src[sig_a].get(d, {})
			out[sig_a][d] = bucket.duplicate() if bucket is Dictionary else {}
	return out


static func _ensure_sig_adj(into: Dictionary, sig: String) -> void:
	if into.has(sig):
		return
	into[sig] = {}
	for d in DIRS:
		into[sig][d] = {}


static func _filter_sig_adjacency(sig_adjacency: Dictionary, min_count: int) -> void:
	for sig_a in sig_adjacency:
		for d in DIRS:
			var bucket: Dictionary = sig_adjacency[sig_a][d]
			for other in bucket.keys():
				if bucket[other] < min_count:
					bucket.erase(other)


static func _cap_sig_adjacency(sig_adjacency: Dictionary, max_mates: int) -> void:
	if max_mates <= 0:
		return
	for sig_a in sig_adjacency:
		for d in DIRS:
			var bucket: Dictionary = sig_adjacency[sig_a][d]
			if bucket.size() <= max_mates:
				continue
			var ranked: Array = []
			for nb_key in bucket:
				ranked.append({"key": nb_key, "count": int(bucket[nb_key])})
			ranked.sort_custom(func(a, b): return a.count > b.count)
			var kept: Dictionary = {}
			for i in mini(max_mates, ranked.size()):
				var entry: Dictionary = ranked[i]
				kept[str(entry.key)] = int(entry.count)
			sig_adjacency[sig_a][d] = kept


static func _symmetrize_sig_adjacency(sig_adjacency: Dictionary) -> void:
	var pairs: Array = []
	for sig_a in sig_adjacency:
		for d in DIRS:
			var bucket: Dictionary = sig_adjacency[sig_a][d]
			for sig_b in bucket:
				pairs.append([sig_b, OPPOSITE[d], sig_a, bucket[sig_b]])
	for pair in pairs:
		var other_sig: String = str(pair[0])
		var opp_dir: String = pair[1]
		var back_sig: String = str(pair[2])
		var count: int = int(pair[3])
		_ensure_sig_adj(sig_adjacency, other_sig)
		var back_bucket: Dictionary = sig_adjacency[other_sig][opp_dir]
		back_bucket[back_sig] = maxi(int(back_bucket.get(back_sig, 0)), count)


static func _merge_sig_adjacency(into: Dictionary, from: Dictionary, weight: int = 1) -> void:
	for sig_a in from:
		_ensure_sig_adj(into, sig_a)
		for d in DIRS:
			var bucket: Variant = from[sig_a].get(d, {})
			if bucket is not Dictionary:
				continue
			for sig_b in bucket:
				into[sig_a][d][sig_b] = into[sig_a][d].get(sig_b, 0) + int(bucket[sig_b]) * weight


static func _merge_sig_edge_gap_fill(
	into: Dictionary,
	from: Dictionary,
	weight: int,
	active_sigs: Dictionary,
	max_neighbors: int = DEFAULT_EDGE_GAP_MAX,
) -> void:
	for sig_a in from:
		if not active_sigs.has(sig_a):
			continue
		_ensure_sig_adj(into, sig_a)
		for d in DIRS:
			var map_bucket: Dictionary = into[sig_a][d]
			if not map_bucket.is_empty():
				continue
			var edge_bucket: Variant = from[sig_a].get(d, {})
			if edge_bucket is not Dictionary or edge_bucket.is_empty():
				continue
			var ranked: Array = []
			for sig_b in edge_bucket:
				if not active_sigs.has(sig_b):
					continue
				ranked.append({"key": sig_b, "count": int(edge_bucket[sig_b])})
			ranked.sort_custom(func(a, b): return a.count > b.count)
			var limit: int = mini(maxi(max_neighbors, 1), ranked.size())
			for i in limit:
				var entry: Dictionary = ranked[i]
				var sig_b_key: String = str(entry.key)
				into[sig_a][d][sig_b_key] = (
					into[sig_a][d].get(sig_b_key, 0) + int(entry.count) * weight
				)



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


static func _cap_adjacency(adjacency: Dictionary, max_mates: int) -> void:
	if max_mates <= 0:
		return
	for gid_key in adjacency:
		for d in DIRS:
			var bucket: Dictionary = adjacency[gid_key][d]
			if bucket.size() <= max_mates:
				continue
			var ranked: Array = []
			for nb_key in bucket:
				ranked.append({"key": nb_key, "count": int(bucket[nb_key])})
			ranked.sort_custom(func(a, b): return a.count > b.count)
			var kept: Dictionary = {}
			for i in mini(max_mates, ranked.size()):
				var entry: Dictionary = ranked[i]
				kept[str(entry.key)] = int(entry.count)
			adjacency[gid_key][d] = kept


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
