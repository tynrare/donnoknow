# agent: composer-2.5 | 2026-07-10 | signature adjacency test | 702380
extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenService.analyze_manifest(manifest)
	if rules.is_empty() or rules.get("sig_adjacency", {}).is_empty():
		push_error("FAIL: analyze_manifest missing sig_adjacency")
		quit(1)
		return

	var gid: int = 27
	var sig: String = GenAtlasAnalyze.sig_for_gid(rules, gid)
	if sig.is_empty():
		push_error("FAIL: gid %d has no signature" % gid)
		quit(1)
		return

	var gid_opts: Dictionary = GenRules.adj_options(rules, gid, "north", false)
	var sig_opts: Dictionary = GenRules.adj_options(rules, gid, "north", true)
	if sig_opts.is_empty():
		push_error("FAIL: sig adj_options empty for gid %d" % gid)
		quit(1)
		return

	var expanded := 0
	for nb_key in sig_opts:
		var nb: int = int(nb_key)
		var nb_sig: String = GenAtlasAnalyze.sig_for_gid(rules, nb)
		for member in GenAtlasAnalyze.generatable_members(rules, nb_sig):
			if int(member) == nb:
				expanded += 1
				break

	if expanded < sig_opts.size():
		push_error("FAIL: sig adj_options not expanded to generatable members")
		quit(1)
		return

	if sig_opts.size() <= gid_opts.size() and not gid_opts.is_empty():
		print(
			"WARN: sig opts (%d) not wider than gid opts (%d)"
			% [sig_opts.size(), gid_opts.size()]
		)

	print("PASS adj_options sig expansion gid=%d sig=%s opts=%d" % [gid, sig, sig_opts.size()])
	quit(0)
