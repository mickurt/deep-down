extends Area2D
class_name HazardSaw

@export var radius_outer: float = 35.0
@export var radius_inner: float = 25.0
@export var teeth_count: int = 16
@export var rotation_speed: float = 6.0 # radians per sec

func _ready():
	collision_layer = 0
	collision_mask = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) # Detect players (Layers 2, 3, 4, 5)
	
	# Circle collision shape
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = radius_inner + 4.0 # safe collision margin
	col.shape = shape
	add_child(col)
	
	# Programmatic saw blade polygon
	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	for i in range(teeth_count * 2):
		var angle = float(i) * PI / float(teeth_count)
		var r = radius_outer if (i % 2 == 0) else radius_inner
		var offset_angle = angle
		if i % 2 == 0:
			offset_angle += 0.08
		points.append(Vector2(cos(offset_angle) * r, sin(offset_angle) * r))
	poly.polygon = points
	poly.color = Color("#111111") # Rich black for warning
	add_child(poly)
	
	# Inner hub highlight (neon yellow)
	var hub = Polygon2D.new()
	var hub_points = PackedVector2Array()
	for i in range(16):
		var angle = float(i) * 2.0 * PI / 16.0
		hub_points.append(Vector2(cos(angle) * 15.0, sin(angle) * 15.0))
	hub.polygon = hub_points
	hub.color = Color("#ffeb3b") # Neon yellow hub
	add_child(hub)
	
	# White center core dot
	var core = Polygon2D.new()
	var core_points = PackedVector2Array()
	for i in range(12):
		var angle = float(i) * 2.0 * PI / 12.0
		core_points.append(Vector2(cos(angle) * 5.0, sin(angle) * 5.0))
	core.polygon = core_points
	core.color = Color(1.0, 1.0, 1.0, 1.0)
	add_child(core)
	
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	rotation += rotation_speed * delta

func _on_body_entered(body):
	if body is PlayerController:
		var game_node = get_node_or_null("/root/Game")
		if game_node:
			# Radial normal (away from the center of the saw)
			var normal = (body.global_position - global_position).normalized()
			# Tangential vector aligned with rotation
			var tangent = Vector2(-normal.y, normal.x) * sign(rotation_speed)
			
			# Combine forces: bounce away and fling along rotation
			var knockback = normal * 350.0 + tangent * 250.0
			# Ensure we pop the player upward somewhat if they hit the top/side
			if knockback.y > -200.0:
				knockback.y = -200.0
				
			game_node.call_deferred("player_hit_spike", body, knockback)
