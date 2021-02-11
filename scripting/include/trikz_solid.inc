/*
* Gets a client's solid state to a given toggleable

* @param entity		Entity index.
* @param client		Client index.
* 
* @return			false, if the entity is not a toggleable or not colliding with the player, true otherwise.
*/
native bool Trikz_IsToggleableEnabledForPlayer(int entity, int client);

/*
* Check's a given entities existance to the plugin
* 
* @param entity		Entity index.
* 
* @return			false, if the entity is not a toggleable, true otherwise.
*/
native bool Trikz_IsEntityToggleable(int entity);

forward Action Trikz_CheckSolidity(int ent1, int ent2);