#if defined _teams_included
  #endinput
#endif
#define _teams_included

/*
* Get's a client's trikz partner.
* 
* @param client		Client index.
* 
* @return			Client index of partner, 0 if no partner or invalid client.
*/
native int Timer_GetPartner(int client);

forward void OnTrikzNewPartner(int client, int partner);
forward void OnTrikzBreakup(int client, int partner);