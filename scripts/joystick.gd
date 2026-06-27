extends Control
class_name DDTJoystick

# Joystick.gd
# A simple touchscreen virtual joystick for mobile devices.

var is_active: bool = false
var touch_index: int = -1
var joystick_center: Vector2 = Vector2.ZERO
var joystick_vector: Vector2 = Vector2.ZERO

@export var max_radius: float = 120.0


@onready var handle = $Handle
@onready var ring = $Ring

func _ready() -> void:
	# Store the initial center
	joystick_center = ring.position + ring.size / 2.0
	_reset_joystick()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.is_pressed():
			# Start dragging
			if touch_index == -1:
				touch_index = event.index
				is_active = true
				_update_joystick(event.position)
		elif event.index == touch_index:
			# Stop dragging
			_reset_joystick()
			
	elif event is InputEventScreenDrag:
		if event.index == touch_index:
			_update_joystick(event.position)

func _update_joystick(touch_pos: Vector2) -> void:
	var offset = touch_pos - joystick_center
	var dist = offset.length()
	
	if dist > max_radius:
		offset = offset.normalized() * max_radius
		
	# Move handle
	handle.position = joystick_center + offset - handle.size / 2.0
	
	# Output normalized vector (-1.0 to 1.0)
	joystick_vector = offset / max_radius

func _reset_joystick() -> void:
	is_active = false
	touch_index = -1
	joystick_vector = Vector2.ZERO
	handle.position = joystick_center - handle.size / 2.0

func get_output() -> Vector2:
	return joystick_vector
