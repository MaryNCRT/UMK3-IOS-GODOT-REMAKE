## The eleven fight stages, in one place.
##
## Listed rather than scanned: a scan of `res/` also turns up the ending
## scenes, WHIRLWIND and the two stub exports, and a menu that offers things
## which cannot load is worse than a short menu. Every stem here was checked
## against the folder -- all eleven have a .meshset and a .scene.
class_name UMK3StageList
extends RefCounted

const STAGES := [
	"GRAVEYARD_LEVEL_SCENE", "BALCONY_LEVEL_SCENE", "BELLTOWER_LEVEL_SCENE",
	"BRIDGE_LEVEL_SCENE", "CAVE_LEVEL_SCENE", "JADESDESERT_LEVEL_SCENE",
	"LAIR_LEVEL_SCENE", "NOOBSDORFEN_LEVEL_SCENE", "PIT_LEVEL_SCENE",
	"ROOFTOP_LEVEL_SCENE", "SCISLACBUSOREZ_LEVEL_SCENE",
]

## The stage music, by the same index. `res/audio` holds one mp3 per stage and
## the names do not match the scene stems, so the pairing is by name where one
## is obvious and a guess where it is not. Marked as such in both projects.
const MUSIC := [
	"GraveYard", "Church", "Church", "Bridge", "SoulChamber", "Street",
	"SoulChamber", "NoobDorfen", "Pit", "Roof", "Subway",
]


static func pretty(stem: String) -> String:
	return stem.replace("_LEVEL_SCENE", "").replace("_", " ")
