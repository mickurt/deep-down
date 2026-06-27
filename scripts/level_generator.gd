extends Node2D
class_name LevelGenerator

# LevelGenerator.gd
# Procedurally generates a vertical pit with platforms and hazard spikes downwards.
# Relies on a shared seed for deterministic generation across all clients.

@export var platform_scene: PackedScene = null # Optional: Custom platform scene, otherwise we create them via code
@export var chunk_size_y: float = 600.0 # Height of each level chunk
@export var wall_width: float = 40.0
@export var viewport_width: float = 1170.0


var generated_chunks: Dictionary = {} # chunk_y_index -> Node2D (holding chunk children)
var last_tracked_y: float = 0.0

func _ready() -> void:
	# Chunks will be generated dynamically when the game starts to ensure correct synchronization.
	pass

func _physics_process(_delta: float) -> void:
	# Check the deepest active player to trigger new chunk generation
	var players = get_tree().get_nodes_in_group("players")
	if players.size() == 0:
		return
		
	var deepest_y = -INF
	for player in players:
		if is_instance_valid(player):
			deepest_y = max(deepest_y, player.global_position.y)
			
	# Convert absolute Y position to a chunk index
	var current_chunk_idx = int(deepest_y / chunk_size_y)
	
	# Keep ahead of players: generate current, previous, and next chunk
	for offset in [-1, 0, 1, 2]:
		var target_idx = current_chunk_idx + offset
		if target_idx >= 0 and not generated_chunks.has(target_idx):
			generate_chunk(target_idx)
			
	# Cleanup far-above chunks to free memory
	for idx in generated_chunks.keys():
		if idx < current_chunk_idx - 2:
			generated_chunks[idx].queue_free()
			generated_chunks.erase(idx)

func generate_chunk(chunk_idx: int) -> void:
	var chunk_node = Node2D.new()
	chunk_node.name = "Chunk_" + str(chunk_idx)
	add_child(chunk_node)
	generated_chunks[chunk_idx] = chunk_node
	
	var y_offset = chunk_idx * chunk_size_y
	
	# Instantiate side walls for this chunk
	_create_wall(chunk_node, Vector2(wall_width / 2.0, y_offset + chunk_size_y / 2.0), Vector2(wall_width, chunk_size_y))
	_create_wall(chunk_node, Vector2(viewport_width - wall_width / 2.0, y_offset + chunk_size_y / 2.0), Vector2(wall_width, chunk_size_y))

	# Deterministic random generator for this specific chunk based on the network seed
	var rng = RandomNumberGenerator.new()
	var net_manager = get_node_or_null("/root/Game/NetworkManager")
	var base_seed = net_manager.start_seed if net_manager else 12345
	rng.seed = base_seed + chunk_idx * 133742
	
	# Don't place platforms in the spawn zone of Chunk 0
	if chunk_idx == 0:
		# Just a solid floor at the starting point
		_create_platform(chunk_node, Vector2(viewport_width / 2.0, 200), 400.0)
		return

	# Place random platforms in this chunk
	var platform_count = rng.randi_range(3, 5)
	for i in range(platform_count):
		# Avoid placing too close to walls
		var margin = wall_width + 50.0
		var px = rng.randf_range(margin, viewport_width - margin)
		var py = y_offset + (float(i) / platform_count) * chunk_size_y + rng.randf_range(-30, 30)
		var p_width = rng.randf_range(100.0, 180.0)
		
		var is_breaking = rng.randf() < 0.25 and chunk_idx > 0
		var platform
		if is_breaking:
			platform = _create_breaking_platform(chunk_node, Vector2(px, py), p_width)
		else:
			platform = _create_platform(chunk_node, Vector2(px, py), p_width)
			
			if chunk_idx > 0:
				# 15% chance to place a spring booster on top of the platform
				if rng.randf() < 0.15:
					_spawn_spring(platform, Vector2(0, -10))
				# 20% chance to place a hazard spike on the platform (static or moving)
				elif rng.randf() < 0.2:
					if rng.randf() < 0.4:
						# Spawn moving spike patrolling the platform
						var move_range = p_width / 3.0
						_spawn_moving_spike(platform, Vector2(0, -15), move_range, rng.randf_range(80, 150))
					else:
						# Spawn static spike
						var spike_offset_x = rng.randf_range(-p_width / 3.0, p_width / 3.0)
						_create_spike(platform, Vector2(spike_offset_x, -15))
				
		# Chance to spawn a swinging hazard below the platform (pendulum or battle axe) - 17.5% chance
		if rng.randf() < 0.175 and chunk_idx > 0:
			if rng.randf() < 0.5:
				_spawn_pendulum(chunk_node, Vector2(px, py + 10), rng.randf_range(120, 180), rng.randf_range(1.5, 3.0), rng.randf() * PI)
			else:
				_spawn_axe(chunk_node, Vector2(px, py + 10), rng.randf_range(120, 180), rng.randf_range(1.5, 3.0), rng.randf() * PI)

	# Spawn floating rotating saws in the open air - Reduced by 50% (from average of 1.5 saws to 0.75 saws per chunk)
	var saws_count = 0
	if chunk_idx > 0:
		if rng.randf() < 0.75:
			saws_count = 1
	for j in range(saws_count):
		var margin = wall_width + 80.0
		var sx = rng.randf_range(margin, viewport_width - margin)
		var sy = y_offset + rng.randf_range(100, chunk_size_y - 100)
		_spawn_rotating_saw(chunk_node, Vector2(sx, sy), rng.randf_range(30, 45), rng.randf_range(4.0, 8.0))

## --- Code-driven Physics Body Creators ---

func _create_wall(parent: Node2D, pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall = StaticBody2D.new()
	wall.global_position = pos
	
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	wall.add_child(col)
	
	# Fall Guys yellow wall
	var color_rect = ColorRect.new()
	color_rect.size = size
	color_rect.position = -size / 2.0
	color_rect.color = Color("#ffd54f") # Bright pastel yellow
	wall.add_child(color_rect)
	
	# Bubbly cyan border on the inner edge of each wall
	var border = ColorRect.new()
	var border_width = 8.0
	border.size = Vector2(border_width, size.y)
	if pos.x < viewport_width / 2.0:
		border.position = Vector2(size.x / 2.0 - border_width, -size.y / 2.0)
	else:
		border.position = Vector2(-size.x / 2.0, -size.y / 2.0)
	border.color = Color("#00e5ff") # Neon cyan border
	wall.add_child(border)
	
	parent.add_child(wall)
	return wall

func _create_platform(parent: Node2D, pos: Vector2, width: float) -> StaticBody2D:
	var platform = StaticBody2D.new()
	platform.global_position = pos
	platform.add_to_group("platforms")
	
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(width, 20)
	col.shape = shape
	platform.add_child(col)
	
	# Fall Guys platform palette
	var platform_colors = [
		Color("#ff4081"), # Bright Pink
		Color("#00e5ff"), # Neon Cyan
		Color("#ff6d00"), # Vivid Orange
		Color("#7c4dff"), # Sweet Violet
		Color("#00e676")  # Bubbly Green
	]
	# Use deterministic selection based on coordinates to prevent network desync
	var color_index = int(abs(pos.x + pos.y)) % platform_colors.size()
	var random_color = platform_colors[color_index]
	
	# Main colorful rounded cushion base
	var base_poly = Polygon2D.new()
	base_poly.polygon = _get_rounded_rect_points(Vector2(width, 20), 8.0)
	base_poly.color = random_color
	platform.add_child(base_poly)
	
	# Soft white top cushion highlight (aligned to top edge)
	var top_highlight = Polygon2D.new()
	top_highlight.polygon = _get_rounded_rect_points(Vector2(width, 8), 4.0)
	top_highlight.position = Vector2(0, -6)
	top_highlight.color = Color(1.0, 1.0, 1.0, 0.65) # Semi-transparent glossy white
	platform.add_child(top_highlight)
	
	parent.add_child(platform)
	return platform

func _get_rounded_rect_points(size: Vector2, radius: float, steps: int = 8) -> PackedVector2Array:
	var points = PackedVector2Array()
	var w = size.x / 2.0
	var h = size.y / 2.0
	
	# Clamp radius
	radius = min(radius, min(w, h))
	
	# Bottom-Right corner
	for i in range(steps + 1):
		var angle = lerp(0.0, PI / 2.0, float(i) / steps)
		points.append(Vector2(w - radius, h - radius) + Vector2(cos(angle) * radius, sin(angle) * radius))
		
	# Bottom-Left corner
	for i in range(steps + 1):
		var angle = lerp(PI / 2.0, PI, float(i) / steps)
		points.append(Vector2(-w + radius, h - radius) + Vector2(cos(angle) * radius, sin(angle) * radius))
		
	# Top-Left corner
	for i in range(steps + 1):
		var angle = lerp(PI, 3.0 * PI / 2.0, float(i) / steps)
		points.append(Vector2(-w + radius, -h + radius) + Vector2(cos(angle) * radius, sin(angle) * radius))
		
	# Top-Right corner
	for i in range(steps + 1):
		var angle = lerp(3.0 * PI / 2.0, 2.0 * PI, float(i) / steps)
		points.append(Vector2(w - radius, -h + radius) + Vector2(cos(angle) * radius, sin(angle) * radius))
		
	return points

func _create_spike(parent_platform: Node2D, local_pos: Vector2) -> Area2D:
	var spike = Area2D.new()
	spike.position = local_pos
	spike.add_to_group("spikes")
	spike.collision_layer = 0
	spike.collision_mask = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) # Detect players (Layers 2, 3, 4, 5)
	
	var col = CollisionShape2D.new()
	var shape = ConvexPolygonShape2D.new()
	# Triangular shape for a spike
	shape.points = PackedVector2Array([
		Vector2(0, -10),
		Vector2(-12, 10),
		Vector2(12, 10)
	])
	col.shape = shape
	spike.add_child(col)
	
	# Fall Guys warn-styled cone: rich black base with yellow warning stripe
	var poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0, -10),
		Vector2(-12, 10),
		Vector2(12, 10)
	])
	poly.color = Color("#111111") # Rich black
	spike.add_child(poly)
	
	# Inner stripe
	var stripe = Polygon2D.new()
	stripe.polygon = PackedVector2Array([
		Vector2(0, -3),
		Vector2(-7, 5),
		Vector2(7, 5)
	])
	stripe.color = Color("#ffeb3b") # Neon yellow
	spike.add_child(stripe)
	
	# Connect collision detection to kill / reset players
	spike.body_entered.connect(func(body):
		if body is PlayerController:
			var game_node = get_node_or_null("/root/Game")
			if game_node:
				# Side of contact
				var side = sign(body.global_position.x - spike.global_position.x)
				if side == 0.0:
					side = 1.0 if randf() > 0.5 else -1.0
				var knockback = Vector2(side * 250.0, -450.0)
				game_node.call_deferred("player_hit_spike", body, knockback)
	)
	
	parent_platform.add_child(spike)
	return spike

func _spawn_moving_spike(parent: Node2D, local_pos: Vector2, range_x: float, speed: float) -> void:
	var script = load("res://scripts/moving_spike.gd")
	var spike = Area2D.new()
	spike.set_script(script)
	spike.position = local_pos
	spike.speed = speed
	spike.range_x = range_x
	parent.add_child(spike)

func _spawn_pendulum(parent: Node2D, pos: Vector2, length: float, speed: float, phase: float) -> void:
	var script = load("res://scripts/hazard_pendulum.gd")
	var pendulum = Node2D.new()
	pendulum.set_script(script)
	pendulum.global_position = pos
	pendulum.length = length
	pendulum.swing_speed = speed
	pendulum.phase_offset = phase
	parent.add_child(pendulum)

func _spawn_rotating_saw(parent: Node2D, pos: Vector2, radius: float, rot_speed: float) -> void:
	var script = load("res://scripts/hazard_saw.gd")
	var saw = Area2D.new()
	saw.set_script(script)
	saw.global_position = pos
	saw.radius_outer = radius
	saw.radius_inner = radius * 0.75
	saw.rotation_speed = rot_speed
	parent.add_child(saw)

func _spawn_spring(parent: Node2D, local_pos: Vector2) -> void:
	var script = load("res://scripts/spring.gd")
	var spring = Area2D.new()
	spring.set_script(script)
	spring.position = local_pos
	parent.add_child(spring)

func _spawn_axe(parent: Node2D, pos: Vector2, length: float, speed: float, phase: float) -> void:
	var script = load("res://scripts/hazard_axe.gd")
	var axe = Node2D.new()
	axe.set_script(script)
	axe.global_position = pos
	axe.length = length
	axe.swing_speed = speed
	axe.phase_offset = phase
	parent.add_child(axe)

func _create_breaking_platform(parent: Node2D, pos: Vector2, width: float) -> StaticBody2D:
	var script = load("res://scripts/breaking_platform.gd")
	var platform = StaticBody2D.new()
	platform.set_script(script)
	platform.global_position = pos
	platform.width = width
	parent.add_child(platform)
	return platform

func reset_generator() -> void:
	for chunk in generated_chunks.values():
		if is_instance_valid(chunk):
			if chunk.get_parent():
				chunk.get_parent().remove_child(chunk)
			chunk.queue_free()
	generated_chunks.clear()
	generate_chunk(0)
	generate_chunk(1)
