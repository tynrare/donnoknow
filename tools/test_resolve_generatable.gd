# agent: composer-2.5 | 2026-07-10 | resolve generatable test | 781436
extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const TEST_GIDS := [35, 36, 37]


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenService.analyze_manifest(manifest)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var sigs: Dictionary = {}
	for gid in TEST_GIDS:
		sigs[GenAtlasAnalyze.sig_for_gid(rules, gid)] = true
	if sigs.size() != 1:
		push_error("FAIL: test gids span %d signatures" % sigs.size())
		quit(1)
		return

	var seen: Dictionary = {}
	for _i in 48:
		for gid in TEST_GIDS:
			var picked: int = GenRules.resolve_generatable_gid(rules, gid, rng)
			seen[picked] = true

	if seen.size() < 2:
		push_error("FAIL: resolve_generatable_gid returned only %s" % str(seen.keys()))
		quit(1)
		return

	print("PASS resolve_generatable_gid pool=%s" % str(seen.keys()))
	quit(0)
