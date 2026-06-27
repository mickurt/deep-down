extends Camera2D
class_name CameraFollow

# CameraFollow.gd
# Automatically centers and zooms to keep all active players in view.

@export var smooth_speed: float = 5.0
@export var zoom_speed: float = 3.0
@export var padding: float = 120.0 # Screen margin around players

# Zoom Limits
@export var max_zoom: float = 1.5 # Zoomed in (players are close)
@export var min_zoom: float = 0.6 # Zoomed out (players are far)

func _physics_process(delta: float) -> void:
	var players = get_tree().get_nodes_in_group("players")
	if players.size() == 0:
		return

	# Calculate Bounding Box of all players
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	
	for player in players:
		if is_instance_valid(player):
			var pos = player.global_position
			min_pos.x = min(min_pos.x, pos.x)
			min_pos.y = min(min_pos.y, pos.y)
			max_pos.x = max(max_pos.x, pos.x)
			max_pos.y = max(max_pos.y, pos.y)

	var target_center = (min_pos + max_pos) / 2.0
	
	# Determine target zoom level based on bounding box dimensions
	var bbox_size = max_pos - min_pos
	var viewport_size = get_viewport_rect().size
	
	# Compute required zoom ratio for width and height (leaving margin)
	var required_zoom_x = (viewport_size.x - padding * 2.0) / max(bbox_size.x, 1.0)
	var required_zoom_y = (viewport_size.y - padding * 2.0) / max(bbox_size.y, 1.0)
	
	# Choose the tighter zoom to guarantee everyone is on screen
	var target_zoom_val = min(required_zoom_x, required_zoom_y)
	target_zoom_val = clamp(target_zoom_val, min_zoom, max_zoom)
	
	# Smoothly interpolate position and zoom
	global_position = global_position.lerp(target_center, smooth_speed * delta)
	zoom = zoom.lerp(Vector2(target_zoom_val, target_zoom_val), zoom_speed * delta)
