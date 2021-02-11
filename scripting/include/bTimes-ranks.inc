/*
* Updates the rankings for the current map, probably will become useless eventually
* 
* @param sMapName      The map to update ranks for.
* @param Type          The timer type to update ranks for.
* @param Style         The timer style to update ranks for.
*/
native void DB_UpdateRanks(const char[] sMapName, int Type, int Style);

/*
* Gives custom chat privileges to a specified SteamID.
* 
* @param sAuth         The SteamID to enable custom chat for.
*/
native void Timer_EnableCustomChat(const char[] sAuth);

/*
* Disables custom chat privileges for a specified SteamID.
* 
* @param sAuth         The SteamID to disable custom chat for.
*/
native void Timer_DisableCustomChat(const char[] sAuth);

/*
* Gets if a specified SteamID has custom chat privileges
* 
* @param sAuth         The SteamID to get custom chat privileges for
*/
native void Timer_SteamIDHasCustomChat(const char[] sAuth);

/*
* Opens the stats menu to a client for the specified PlayerID
* 
* @param client        Client index.
* @param PlayerID      PlayerID from the database to show stats for.
* @param Type          Timer type to show stats.
* @param Style         Timer style to show stats.
*/
native void Timer_OpenStatsMenu(int client, int PlayerID, int Type, int Style);