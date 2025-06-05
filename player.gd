# Player class, which bots and real players are objects of
extends Node
class_name Player

var _name
var type
var color
var id # Player Num
var dice_roll_result
var turn_num
var vp = 0
var settlements = []
var cities = []
var roads = []
var harbors = [] # 3:1, Sheep, Wheat .. etc.
var resources = {
	"Tree": 0,
	"Sheep": 0,
	"Brick": 0,
	"Wheat": 0,
	"Stone": 0
}
var dev_cards = {
	"Invention_DevCard": 0,
	"Knight_DevCard": 0,
	"Monopoly_DevCard": 0,
	"Road_DevCard": 0,
	"VP_DevCard": 0
}
var total_resources = 0
var last_vertex_selected = null
var last_node_selected = null
var knights_played = 0
var longest_road = 0
var dev_card_played_this_turn = false

# UI
var PLAYER_RESOURCE_BAR_POSITIONS = [null, null, null, null, null]
var PLAYER_RESOURCE_BAR_POSITIONS_DEVCARDS = [null, null, null, null, null]
