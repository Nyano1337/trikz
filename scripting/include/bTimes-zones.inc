#define ZONE_COUNT 8

#define MAIN_START  0
#define MAIN_END    1
#define BONUS_START 2
#define BONUS_END   3
#define SOLOBONUS_START 4
#define SOLOBONUS_END   5
#define ANTICHEAT   6
#define FREESTYLE   7

#define FLAG_ANTICHEAT_MAIN  1<<0
#define FLAG_ANTICHEAT_BONUS 1<<1
#define FLAG_ANTICHEAT_SOLOBONUS 1<<2

/*
* Gets if a client is inside a zone type
* 
* @param client        Client index.
* @param Zone          The zone type to check if they are inside.
* @param flags         Optional flags required for a zone to have, -1 for no flags required
* 
* @return              The ZoneNumber a client is inside of, -1 if client is not inside a zone with the given parameters.
*/
native int Timer_InsideZone(int client, int Zone, int flags = -1);

/*
* Gets if a point is inside a zone
* 
* @param pos           The position to check is inside a zone.
* @param Zone          Zone type.
* @param ZoneNumber    Zone number.
* 
* @return              True if the point is inside the specified zone, false otherwise.
*/
native bool Timer_IsPointInsideZone(float pos[3], int Zone, int ZoneNumber);

/*
* Teleports a client to a specified zone
* 
* @param client        Client index.
* @param Zone          The zone type to teleport to.
* @param ZoneNumber    The zone number to teleport to.
* @param bottom        If set to true, the client will teleport to the bottom of the zone.
* 
* @noreturn
*/
native void Timer_TeleportToZone(int client, int Zone, int ZoneNumber, bool bottom = false);

/*
* Gets how many zones their are in the database for every map in the map list.
* 
* @param Zone          Zone type to check.
* 
* @return              Total number of zones for the zone type.
*/
native int GetTotalZonesAllMaps(int Zone);

/*
* Called when the zones have been loaded.
*/
forward void OnZonesLoaded();

/*
* Called when someone enters a zone
*/
forward void OnZoneStartTouch(int client, int Zone, int ZoneNumber);

/*
* Called when someone leaves a zone
*/
forward void OnZoneEndTouch(int client, int Zone, int ZoneNumber);
