extends SceneTree

const Sim = preload("res://scripts/game/village_sim.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		printerr("FAIL ", text)


func _run() -> void:
	var sim = Sim.new()
	sim.units.clear()
	for index in 400:
		sim._add_unit(["builder", "farmer", "lumberjack", "miner"][index % 4])
	sim.paused = false
	var sim_start: int = Time.get_ticks_msec()
	for tick in 40:
		sim.tick(0.05)
	var sim_ms: int = Time.get_ticks_msec() - sim_start
	check(sim.units.size() == 400, "400-villager simulation keeps the full population")
	var finite_positions: bool = true
	for unit: Dictionary in sim.units:
		finite_positions = finite_positions and is_finite(float(unit["x"])) and is_finite(float(unit["y"]))
	check(finite_positions, "heavy-population simulation keeps valid positions")
	print("COMMAND_CONTROL_SIM_400_MS ", sim_ms)

	# Raid performance profile: large saves should shelter civilians instead of
	# turning the settlement into a 400-character evacuation/render crowd.
	var raid_sim = Sim.new()
	raid_sim.units.clear()
	for index in 400:
		var unit_type: String = ["builder", "farmer", "lumberjack", "miner"][index % 4]
		if index % 20 == 0:
			unit_type = "warrior"
		elif index % 20 == 10:
			unit_type = "archer"
		raid_sim._add_unit(unit_type)
	raid_sim.paused = false
	check(raid_sim.start_raid(), "raid profiling wave starts")
	var nav_before_alarm: int = raid_sim.living.navigation_revision
	var warning_start: int = Time.get_ticks_usec()
	raid_sim.tick(0.05)
	var warning_ms: float = float(Time.get_ticks_usec() - warning_start) / 1000.0
	var sheltered: int = 0
	var defenders: int = 0
	for unit: Dictionary in raid_sim.units:
		if str(raid_sim.troop_specs[unit["type"]]["role"]) == "combat":
			defenders += 1
		elif str(unit.get("phase", "")) == "shelter":
			sheltered += 1
	check(sheltered == raid_sim.units.size() - defenders, "every civilian shelters without raid movement/pathfinding")
	check(raid_sim.living.navigation_revision == nav_before_alarm, "sheltering does not rewrite desire-path navigation")
	# Force the active wave now, keep enemies alive, then profile sustained combat.
	raid_sim.wave = 7
	raid_sim.next_raid_at = raid_sim.elapsed
	raid_sim.tick(0.05)
	for enemy: Dictionary in raid_sim.enemies:
		enemy["hp"] = 100000.0
		enemy["max_hp"] = 100000.0
	var active_worst_ms: float = 0.0
	var active_total_ms: float = 0.0
	for tick in 80:
		var active_start: int = Time.get_ticks_usec()
		raid_sim.tick(0.05)
		var active_ms: float = float(Time.get_ticks_usec() - active_start) / 1000.0
		active_total_ms += active_ms
		active_worst_ms = maxf(active_worst_ms, active_ms)
	check(raid_sim.raid_active and raid_sim.enemies.size() == 8, "sustained profile keeps a full eight-enemy raid active")
	print("RAID_SUSTAINED_PROFILE_400 warning_ms=", warning_ms, " avg_active_ms=", active_total_ms / 80.0, " worst_active_ms=", active_worst_ms, " sheltered=", sheltered, " defenders=", defenders)


	root.size = Vector2i(1280, 800)
	var packed: PackedScene = load("res://scenes/game.tscn")
	var game = packed.instantiate()
	game.no_save = true
	root.add_child(game)
	await process_frame
	game._enter_village()
	var initial_actor_count: int = game.actors.size()
	game.sim.units.clear()
	for index in 400:
		game.sim._add_unit(["builder", "farmer", "lumberjack", "miner"][index % 4])
	game.actor_accumulator = 0.0
	game._process(0.016)
	check(game.actors.size() == initial_actor_count, "render actors are not rebuilt every display frame")
	var render_start: int = Time.get_ticks_msec()
	game._process(0.04)
	var first_sync_ms: int = Time.get_ticks_msec() - render_start
	check(game.actors.size() == 400, "20 Hz visual sync catches up to all 400 villagers")
	print("COMMAND_CONTROL_RENDER_400_FIRST_SYNC_MS ", first_sync_ms)
	game.target = Vector3.ZERO
	game._camera_update()
	game.sim.raid_warning = true
	game._apply_lighting()
	var shelter_render_start: int = Time.get_ticks_usec()
	game._update_actors(0.067)
	var shelter_render_ms: float = float(Time.get_ticks_usec() - shelter_render_start) / 1000.0
	var hidden_shelter: int = 0
	var disabled_shelter: int = 0
	for record: Dictionary in game.actors.values():
		var actor_model: Node3D = record["model"]
		if not actor_model.visible:
			hidden_shelter += 1
		if actor_model.process_mode == Node.PROCESS_MODE_DISABLED:
			disabled_shelter += 1
	check(hidden_shelter == 400 and disabled_shelter == 400, "raid warning hides and disables all non-combat crowd models")
	check(not game.fireflies.emitting and not game.mist.emitting, "raid visual budget disables ambient particles")
	print("RAID_RENDER_SHELTER_400_MS ", shelter_render_ms)
	game.sim.raid_warning = false
	game._apply_lighting()
	game._update_actors(0.05)
	var still_disabled: int = 0
	for record: Dictionary in game.actors.values():
		if (record["model"] as Node3D).process_mode == Node.PROCESS_MODE_DISABLED:
			still_disabled += 1
	check(still_disabled == 0, "civilian actors resume after the alarm clears")
	game.target = Vector3(200, 0, 200)
	game._camera_update()
	game._update_actors(0.05)
	var visible: int = 0
	for record: Dictionary in game.actors.values():
		if (record["model"] as Node3D).visible:
			visible += 1
	check(visible < 50, "off-screen actor culling drops insignificant villagers from rendering")

	game._open_panel("people")
	await process_frame
	await process_frame
	check(game.side_scroll != null and game.side_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED, "long manor panels retain vertical scrolling")
	check(game.side_content.get_combined_minimum_size().y > game.side_scroll.size.y, "400-person menu exceeds the viewport and remains scrollable")
	check(game.side_close_button != null and game.side_close_button.get_parent() != game.side_content, "menu close control stays pinned outside scrolling content")
	check(game.side_scroll.scroll_deadzone >= 8, "menu scrolling keeps a touch deadzone so button taps do not turn into accidental swipes")
	var scroll_before: int = game.side_scroll.scroll_vertical
	game._scroll_sidebar(1)
	await process_frame
	check(game.side_scroll.scroll_vertical > scroll_before, "phone menu paging control advances long menus")
	game._toggle_more()
	await process_frame
	check(game.more_sheet.visible and game.more_scroll != null, "More actions opens inside a dedicated scroll container")
	check(game.more_close_button != null and game.more_close_button.get_parent() != game.more_scroll, "More close control stays pinned outside scrolling content")
	check(game.more_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED, "More actions supports vertical scrolling")
	check(game.more_scroll.scroll_deadzone >= 8, "More actions uses the same tap-safe scroll deadzone")
	game._toggle_more()

	game.battery_saver = true
	game._apply_power_settings()
	check(Engine.max_fps == 30, "battery saver caps rendering at 30 fps")
	game.battery_saver = false
	game._apply_power_settings()
	game.free()
	await process_frame
	print("COMMAND_CONTROL_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
