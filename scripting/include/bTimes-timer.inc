#if defined _timer_included
  #endinput
#endif
#define _timer_included

#define MAX_STYLES 32

enum struct StyleConfig {
	char Name[32];
	char Name_Short[32];
	bool Enabled;
	bool TempEnabled;
	bool AllowType[3];
	bool Freestyle;
	bool Freestyle_Unrestrict;
	bool Freestyle_EzHop;
	bool Freestyle_Auto;
	bool Auto;
	bool EzHop;
	float Gravity;
	float RunSpeed;
	float MaxVel;
	float MinFps;
	bool CalcSync;
	bool Prevent_Left;
	bool Prevent_Right;
	bool Prevent_Back;
	bool Prevent_Forward;
	bool Require_Left;
	bool Require_Right;
	bool Require_Back;
	bool Require_Forward;
	bool Hud_Style;
	bool Hud_Strafes;
	bool Hud_Jumps;
	bool Count_Left_Strafe;
	bool Count_Right_Strafe;
	bool Count_Back_Strafe;
	bool Count_Forward_Strafe;
	bool Ghost_Use[3];
	bool Ghost_Save[3];
	float PreSpeed;
	float SlowedSpeed;
	bool Special;
	char Special_Key[32];
	bool GunJump;
	char GunJump_Weapon[64];
	bool UnrealPhys;
	int AirAcceleration;
	bool EnableBunnyhopping;
}

/*
* Stops a client's timer.
* 
* @param client		Client index.
* 
* @noreturn
*/
native void StopTimer(int client);

/*
* Starts a client's timer.
* 
* @param client        Client index.
* 
* @noreturn
*/
native void StartTimer(int client, int Type);

/*
* Gets if someone is being timed.
* 
* @param client        Client index.
* @param Type          The timer type being checked.
* 
* @return              True if they are being timed, false otherwise.
*/
native bool IsBeingTimed(int client, int Type);

/*
* Ends someone's timer, attempting to save their time if it is new.
* 
* @param client        Client index.
* 
* @noreturn
*/
native void FinishTimer(int client);

/*
* Gets a client's style (Normal, Sideways, etc..).
* 
* @param client        Client index
* 
* @return              The client's style.
*/
native int GetClientStyle(int client);

/*
* Gets a client's timer type (main or bonus).
* 
* @param client        Client index.
* 
* @return              The client's timer type.
*/
native int GetClientTimerType(int client);

/*
* Gets if a player has their timer paused.
* 
* @param client        Client index.
* 
* @return              True if they are paused, false otherwise.
*/
native bool IsTimerPaused(int client);

/*
* Gets if a style is allowed.
* 
* @param Style         Timer style.
* 
* @return              True if the style is allowed, false otherwise.
*/
native bool IsStyleAllowed(int Style);

/*
* Gets the name of a specified style.
* 
* @param Style         The style you want the name for.
* @param sStyle        The buffer to hold the style name.
* @param maxlength     The max length of the style buffer.
* 
* @noreturn
*/
native void GetStyleName(int Style, char[] sStyle, int maxlength, bool bBlankIfDefault = false);

/*
* Gets the short name of a specified style.
* 
* @param Style         The style you want the name for.
* @param sStyle        The buffer to hold the style name.
* @param maxlength     The max length of the style buffer.
* 
* @noreturn
*/
native void GetStyleAbbr(int Style, char[] sStyle, int maxlength, bool bBlankIfDefault = false);

/*
* Gets the complete configuration for a specified style.
* 
* @param Style         The style to get a configuration for.
* @param Properties    The buffer to store all the style properties, (properties are listed in the StyleConfig enum)
* 
* @return              True if the style exists, false otherwise.
*/
native bool Style_GetConfig(int Style, any[] Properties);

/*
* Gets if a specified style is enabled for players to use.
* 
* @param Style         The style you want to know is enabled.
* 
* @return              True if the style is enabled, false otherwise.
*/
native bool Style_IsEnabled(int Style);

/*
* Gets if a style allows a specified timer type
* 
* @param Style         The style you are checking.
* @param Type          The type you want to know is allowed for the specified style.
* 
* @return              True if the timer type is allowed, false otherwise.
*/
native bool Style_IsTypeAllowed(int Style, int Type);

/*
* Gets the total number of added styles.
* 
* @return              The total number of styles.
*/
native int Style_GetTotal();

/*
* Gets if a style uses freestyle zones.
* 
* @param Style         The style to check.
* 
* @return              True if the style allows freestyle zones, false otherwise.
*/
native bool Style_IsFreestyleAllowed(int Style);

/*
* Gets if a replay bot should be used for the specified style and specified timer type.
* 
* @param Style         The style to check.
* @param Type          The timer type to check.
* 
* @return              True if the replay bot is allowed.
*/
native bool Style_CanUseReplay(int Style, int Type);

/*
* Gets if a replay bot should be saved for the specified style and specified timer type.
* 
* @param Style         The style to check.
* @param Type          The timer type to check.
* 
* @return              True if the replay bot should be saved.
*/
native bool Style_CanReplaySave(int Style, int Type);

/*
* Used to tell what type and what style a player wants information for given a command, can only be used during a command callback.
* 
* @param sCommand      The command the player used.
* @param sDelimeter    The delimeter to get the type and style strings.
* @param Type          The timer type to return.
* @param Style         The timer style to return.
* 
* @return              True if a type and a style were found, false otherwise.
*/
native bool GetTypeStyleFromCommand(const char[] sDelimiter, int &Type, int &Style);

/*
* Gets the unaffected bitsum of buttons (in case someone wants to do something with something like the IN_JUMP value to players on auto)
* 
* @param client        Client index.
*/
native int Timer_GetButtons(int client);

/*
* Called before a player finishes their run.
* 
* @param client        Client index.
* @param Type          Timer type.
* @param Style         Timer style.
*/
forward Action OnTimerFinished_Pre(int client, int Type, int Style);

/*
* Called after a player finishes their run.
* 
* @param client        Client index.
* @param Time          The player's finishing time.
* @param Type          The player's timer type.
* @param Style         The player's timer style.
* @param NewTime       true if it's a new time, false otherwise.
* @param OldPosition   The player's position before finishing the map.
* @param NewPosition   The player's position after finishing the map.
*/
forward void OnTimerFinished_Post(int client, float Time, int Type, int Style, bool NewTime, int OldPosition, int NewPosition);

/*
* Called when their is an attempt to start a client's timer.
* 
* @param client        Client index.
* @param Type          Timer type.
* @param Style         Timer style.
*/
forward Action OnTimerStart_Pre(int client, int Type, int Style);

/*
* Called after a player's timer is started.
* 
* @param client        Client index.
* @param Type          Timer type.
* @param Style         Timer style.
*/
forward void OnTimerStart_Post(int client, int Type, int Style);

/*
* Called when times have been deleted.
* 
* @param Type          The timer type of the times deleted.
* @param Style         The timer style of the times deleted.
* @param RecordOne     The first record in the range of records deleted. RecordOne - 1 is the index in the Times param.
* @param RecordRwo     The last record in the range of records deleted. RecordTwo - 1 is the index in the Times param.
* @param Times         The adt_array of all the map times before the times have been deleted.
*/
forward void OnTimesDeleted(int Type, int Style, int RecordOne, int RecordTwo, ArrayList Times);

/*
* Called when times have been updated in the database.
* 
* @param Type          The timer type of the times updated.
* @param Style         The timer style of the times updated.
* @param Times         The adt_array of all the map times before the times have been updated.
*/
forward void OnTimesUpdated(const char[] sMapName, int Type, int Style, ArrayList Times);

/*
* Called when the style have been read from the styles.cfg file
*/
forward void OnStylesLoaded();

/*
* Called when a map's times have been loaded
*/
forward void OnMapTimesLoaded();

/**
* Called when a client changes their style. (Can be called if a client switches the to the style they were already on)
* 
* @param client        Client index.
* @param OldStyle      The previous style a player was on.
* @param NewStyle      The new style a player is on.
* @param Type          The timer type the styles are being changed for.
*/
forward void OnStyleChanged(int client, int OldStyle, int NewStyle, int Type);
