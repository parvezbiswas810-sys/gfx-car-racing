class_name TrackData
extends Node
## Static track catalogue.
##
## Each track is a closed control polygon in metres on the X/Z plane. The
## polygon is smoothed with Chaikin corner cutting (see TrackBuilder), which
## never overshoots the control polygon, so a hand-written layout can never
## fold back on itself and break the lap logic.
##
## Coordinates are metres; a car is ~4.3 m long, so a 200 m straight is roughly
## 45 car lengths.

const ROAD_WIDTH := 16.0
const LAPS := 12
const CHECKPOINTS := 12

const TRACKS := {
	"city_circuit": {
		"name": "City Circuit",
		"theme": "city",
		"difficulty": 2,
		"width": 16.0,
		"points": [
			Vector2(-200, -150), Vector2(-80, -150), Vector2(-30, -108),
			Vector2(30, -190), Vector2(80, -150), Vector2(200, -150),
			Vector2(222, -75), Vector2(222, 75), Vector2(200, 150),
			Vector2(80, 150), Vector2(-80, 150), Vector2(-200, 150),
			Vector2(-222, 75), Vector2(-222, -75),
		],
	},
	"forest_track": {
		"name": "Forest Track",
		"theme": "forest",
		"difficulty": 2,
		"width": 15.0,
		"points": [
			Vector2(-180, -160), Vector2(-40, -192), Vector2(90, -170),
			Vector2(172, -92), Vector2(200, 8), Vector2(150, 92),
			Vector2(58, 122), Vector2(30, 190), Vector2(-72, 202),
			Vector2(-162, 140), Vector2(-212, 40), Vector2(-200, -70),
		],
	},
	"desert_road": {
		"name": "Desert Road",
		"theme": "desert",
		"difficulty": 3,
		"width": 17.0,
		"points": [
			Vector2(-330, -140), Vector2(-120, -152), Vector2(80, -152),
			Vector2(300, -140), Vector2(345, -62), Vector2(345, 22),
			Vector2(318, 62), Vector2(250, 82), Vector2(120, 92),
			Vector2(-20, 102), Vector2(-140, 112), Vector2(-262, 122),
			Vector2(-336, 100), Vector2(-356, 20), Vector2(-336, -72),
		],
	},
	"snow_track": {
		"name": "Snow Track",
		"theme": "snow",
		"difficulty": 4,
		"width": 14.0,
		"points": [
			Vector2(-142, -122), Vector2(-40, -152), Vector2(60, -132),
			Vector2(122, -72), Vector2(88, 0), Vector2(152, 60),
			Vector2(112, 132), Vector2(0, 152), Vector2(-92, 122),
			Vector2(-142, 40), Vector2(-100, -40),
		],
	},
	"night_city": {
		"name": "Night City",
		"theme": "night",
		"difficulty": 3,
		"width": 16.0,
		"points": [
			Vector2(-250, -132), Vector2(-80, -152), Vector2(80, -152),
			Vector2(250, -132), Vector2(292, -30), Vector2(250, 122),
			Vector2(80, 152), Vector2(-80, 152), Vector2(-250, 132),
			Vector2(-292, 30),
		],
	},
	"championship_circuit": {
		"name": "Championship Circuit",
		"theme": "stadium",
		"difficulty": 5,
		"width": 18.0,
		"points": [
			Vector2(-360, -200), Vector2(-150, -232), Vector2(60, -222),
			Vector2(250, -200), Vector2(352, -120), Vector2(372, -10),
			Vector2(300, 70), Vector2(352, 152), Vector2(250, 222),
			Vector2(60, 242), Vector2(-150, 232), Vector2(-330, 200),
			Vector2(-400, 110), Vector2(-412, -20), Vector2(-400, -122),
		],
	},
}

## Display order for the track selection screen.
const ORDER := [
	"city_circuit", "forest_track", "desert_road",
	"snow_track", "night_city", "championship_circuit",
]

const THEMES := {
	"city": {
		"ground_texture": "res://assets/textures/asphalt.png",
		"ground_tint": Color(0.55, 0.58, 0.52),
		"sky_top": Color(0.16, 0.34, 0.68),
		"sky_horizon": Color(0.78, 0.86, 0.94),
		"sun_colour": Color(1.0, 0.96, 0.88),
		"sun_energy": 1.15,
		"sun_angle": Vector3(-48, 35, 0),
		"ambient": Color(0.55, 0.62, 0.72),
		"fog": false,
		"prop": "building",
		"prop_count": 46,
		"barrier_colour": Color(0.86, 0.87, 0.90),
	},
	"forest": {
		"ground_texture": "res://assets/textures/grass.png",
		"ground_tint": Color(0.62, 0.78, 0.55),
		"sky_top": Color(0.22, 0.44, 0.74),
		"sky_horizon": Color(0.82, 0.90, 0.96),
		"sun_colour": Color(1.0, 0.97, 0.86),
		"sun_energy": 1.05,
		"sun_angle": Vector3(-55, 120, 0),
		"ambient": Color(0.48, 0.58, 0.52),
		"fog": true,
		"prop": "tree",
		"prop_count": 120,
		"barrier_colour": Color(0.92, 0.90, 0.84),
	},
	"desert": {
		"ground_texture": "res://assets/textures/sand.png",
		"ground_tint": Color(0.95, 0.86, 0.66),
		"sky_top": Color(0.30, 0.52, 0.82),
		"sky_horizon": Color(0.96, 0.90, 0.76),
		"sun_colour": Color(1.0, 0.93, 0.76),
		"sun_energy": 1.35,
		"sun_angle": Vector3(-72, 20, 0),
		"ambient": Color(0.72, 0.66, 0.55),
		"fog": true,
		"prop": "rock",
		"prop_count": 70,
		"barrier_colour": Color(0.94, 0.90, 0.82),
	},
	"snow": {
		"ground_texture": "res://assets/textures/snow.png",
		"ground_tint": Color(0.94, 0.96, 1.0),
		"sky_top": Color(0.60, 0.70, 0.84),
		"sky_horizon": Color(0.94, 0.96, 0.99),
		"sun_colour": Color(0.94, 0.96, 1.0),
		"sun_energy": 0.85,
		"sun_angle": Vector3(-38, 200, 0),
		"ambient": Color(0.78, 0.82, 0.88),
		"fog": true,
		"prop": "tree",
		"prop_count": 90,
		"barrier_colour": Color(0.70, 0.74, 0.82),
	},
	"night": {
		"ground_texture": "res://assets/textures/asphalt.png",
		"ground_tint": Color(0.30, 0.33, 0.42),
		"sky_top": Color(0.02, 0.03, 0.09),
		"sky_horizon": Color(0.10, 0.12, 0.24),
		"sun_colour": Color(0.42, 0.48, 0.72),
		"sun_energy": 0.30,
		"sun_angle": Vector3(-24, 300, 0),
		"ambient": Color(0.18, 0.20, 0.30),
		"fog": true,
		"prop": "building",
		"prop_count": 52,
		"barrier_colour": Color(0.30, 0.34, 0.44),
		"neon": true,
	},
	"stadium": {
		"ground_texture": "res://assets/textures/grass.png",
		"ground_tint": Color(0.50, 0.68, 0.44),
		"sky_top": Color(0.14, 0.30, 0.62),
		"sky_horizon": Color(0.76, 0.84, 0.92),
		"sun_colour": Color(1.0, 0.97, 0.90),
		"sun_energy": 1.20,
		"sun_angle": Vector3(-58, 75, 0),
		"ambient": Color(0.52, 0.60, 0.66),
		"fog": false,
		"prop": "stand",
		"prop_count": 24,
		"barrier_colour": Color(0.90, 0.91, 0.94),
	},
}


static func get_track(id: String) -> Dictionary:
	return TRACKS.get(id, TRACKS["city_circuit"])


static func theme_of(track: Dictionary) -> Dictionary:
	return THEMES.get(track.get("theme", "city"), THEMES["city"])


static func display_name(id: String) -> String:
	return str(get_track(id).get("name", id))
