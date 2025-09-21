extends Camera2D

@export var min_zoom := 0.1
@export var max_zoom := 5.0
@export var zoom_factor := 0.1
@export var zoom_duration := 0.2
var zoom_level: float = 1
var position_before_drag
var position_before_drag2


func _ready():
	pass


func _unhandled_input(event):
	if event.is_action_pressed("zoom_in"):
		set_zoom_level(zoom_level + zoom_factor)
	elif event.is_action_pressed("zoom_out"):
		set_zoom_level(zoom_level - zoom_factor)
	elif event.is_action_pressed("camera_drag"):
		position_before_drag = event.global_position
		position_before_drag2 = self.global_position
	elif event.is_action_released("camera_drag"):
		position_before_drag = null
	elif event is InputEventPanGesture:
		self.global_position += event.delta
	elif event is InputEventScreenDrag:
		self.global_position -= event.relative
	elif event is InputEventMagnifyGesture:
		if event.factor > 1:
			set_zoom_level(zoom_level + (zoom_factor * 0.5))
		elif event.factor < 1:
			set_zoom_level(zoom_level - (zoom_factor * 0.5))
	
	if position_before_drag and event is InputEventMouseMotion:
		self.global_position = position_before_drag2 + (position_before_drag - event.global_position) * (1/zoom_level)
		self.global_position.x = clamp(self.global_position.x, -100, 2000)
		self.global_position.y = clamp(self.global_position.y, -100, 1500)


func set_zoom_level(level: float, mouse_world_position = self.get_global_mouse_position()):
	var old_zoom_level = zoom_level
	
	zoom_level = clampf(level, min_zoom, max_zoom)
	
	var direction = (mouse_world_position - self.global_position)
	var new_position = self.global_position + direction - ((direction) / (zoom_level/old_zoom_level))
	
	self.zoom = Vector2(zoom_level, zoom_level)
	self.global_position = new_position
