extends Area2D
class_name MovingSpike

@export var speed: float = 120.0
@export var range_x: float = 60.0

var start_x: float
var direction: float = 1.0

func _ready():
	collision_layer = 0
	collision_mask = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) # Detect players (Layers 2, 3, 4, 5)
	start_x = position.x
	
	# Create triangular collision shape
	var col = CollisionShape2D.new()
	var shape = ConvexPolygonShape2D.new()
	shape.points = PackedVector2Array([
		Vector2(0, -10),
		Vector2(-12, 10),
		Vector2(12, 10)
	])
	col.shape = shape
	add_child(col)
	
	# Draw spike (Black)
	var poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0, -10),
		Vector2(-12, 10),
		Vector2(12, 10)
	])
	poly.color = Color("#111111")
	add_child(poly)
	
	# Inner yellow warning stripe
	var stripe = Polygon2D.new()
	stripe.polygon = PackedVector2Array([
		Vector2(0, -3),
		Vector2(-7, 5),
		Vector2(7, 5)
	])
	stripe.color = Color("#ffeb3b")
	add_child(stripe)
	
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	position.x += speed * direction * delta
	if abs(position.x - start_x) >= range_x:
		direction *= -1.0
		position.x = start_x + range_x * sign(position.x - start_x)
		
	# Mirror the graphic if moving left/right (just for visual detail)
	# (spikes are symmetrical so not strictly necessary, but good template)
	
func _on_body_entered(body):
	if body is PlayerController:
		var game_node = get_node_or_null("/root/Game")
		if game_node:
			# Normal side of contact (left or right)
			var side = sign(body.global_position.x - global_position.x)
			if side == 0.0:
				side = 1.0
				
			# Combine contact bounce direction with the patrol movement velocity projection
			var patrol_vel = speed * direction
			var knockback = Vector2(side * 200.0 + patrol_vel * 0.8, -400.0)
			
			game_node.call_deferred("player_hit_spike", body, knockback)
