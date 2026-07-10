# agent: composer-2.5 | 2026-07-10 | signature group test tool | 6027e2
extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"

const SIGNATURE_GROUPS := [
	[35, 36, 37],
	[195, 196, 197],
	[54, 78, 102],
]


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var atlas := GenAtlasAnalyze.analyze_signatures(manifest)
	var gid_to_sig: Dictionary = atlas.get("gid_to_sig", {})
	var signatures: Dictionary = atlas.get("signatures", {})
	var descs: Dictionary = atlas.get("tile_descs", {})

	if gid_to_sig.is_empty() or signatures.is_empty():
		push_error("FAIL: analyze_signatures returned empty data")
		quit(1)
		return

	var ok := true
	for group in SIGNATURE_GROUPS:
		if group is not Array or group.is_empty():
			continue
		var gids: Array = []
		for g in group:
			gids.append(int(g))
		var sigs: Dictionary = {}
		for gid in gids:
			var sig: String = str(gid_to_sig.get(str(gid), ""))
			if sig.is_empty():
				ok = false
				print("FAIL group %s -> gid %d has no signature" % [str(gids), gid])
				continue
			sigs[sig] = true
		var sig_list: Array = sigs.keys()
		if sig_list.size() != 1:
			ok = false
			print("FAIL group %s -> %d signatures: %s" % [str(gids), sig_list.size(), sig_list])
			for gid in gids:
				print("  GID %d sig=%s" % [gid, gid_to_sig.get(str(gid), "")])
			continue
		var sig: String = str(sig_list[0])
		var members: Array = signatures.get(sig, [])
		print("PASS group %s sig=%s members=%s" % [str(gids), sig, str(members)])
		if not _check_full_tile_members(descs, gids):
			ok = false

	if ok:
		print("PASS all signature groups")
		quit(0)
	else:
		push_error("FAIL signature group validation")
		quit(1)


func _check_full_tile_members(descs: Dictionary, gids: Array) -> bool:
	if gids.is_empty():
		return true
	var rep: Array = descs.get(str(gids[0]), {}).get("cells", [])
	if rep.is_empty():
		return true
	for gid in gids:
		var cells: Array = descs.get(str(gid), {}).get("cells", [])
		if not GenAtlasAnalyze.cells_equal(cells, rep):
			push_error(
				"FAIL group %s: gid %d differs in full tile (edge-only alias rejected)"
				% [str(gids), gid]
			)
			return false
	return true
