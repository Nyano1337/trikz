/* put the line below after all of the includes!
#pragma newdecls required
*/

#if defined _timercore_included
  #endinput
#endif
#define _timercore_included

#define VERSION "1.8.3"

#define MAX_TYPES 3

#define TIMER_MAIN 0
#define TIMER_BONUS 1
#define TIMER_SOLOBONUS 2
#define TIMER_ANY 3

#define ALL -1

enum
{
    SQL_Column_Type = 2,
    SQL_Column_Style,
    SQL_Column_PlayerID,
    SQL_Column_Time,
    SQL_Column_Jumps,
    SQL_Column_Strafes,
    SQL_Column_Points,
    SQL_Column_Timestamp
};

// Core natives

/*
* Gets a client's player id in the database.
* 
* @param client        Client index.
* 
* @return            Client's player id.
*/
native int GetClientID(int client);

/*
* A better name for GetClientID()
* 
* @param client        Client index.
* 
* @return              Client's player id.
*/
stock int GetPlayerID(int client)
{
    return GetClientID(client);
}

/*
* Gets the name of a player in the database by their Player ID
* 
* @param PlayerID      Player ID in the database.
* @param sName         Buffer to store the given name.
* @param maxlength     Maxlength of the sName string.
*/
native int GetNameFromPlayerID(int PlayerID, char[] sName, int maxlength);

/*
* Gets a SteamID given a PlayerID in the timer database
* 
* @param PlayerID      Player ID in the database.
* @param sAuth         Buffer to store the SteamID.
* @param maxlength     Maxlength of the sAuth string.
*/
native int GetSteamIDFromPlayerID(int PlayerID, char[] sAuth, int maxlength);

/*
* Gets the map id in the timer database from a map name
* 
* @param sMapName      The name of the map to get the map id for.
* 
* @return              The map's map id, 0 if map not found.
*/
native int GetMapIdFromMapName(const char[] sMapName);

/*
* Gets the map name from a map id
* 
* @param MapID         The map id you use to get the map name for.
* @param sMapName      The buffer to hold the map name.
* @param maxlength     The max length of the sMapName buffer.
* 
* @return              True if the map was found, false otherwise.
*/
native bool GetMapNameFromMapId(int MapID, char[] sMapName, int maxlength);

/*
* Gets if a client is spamming SQL related commands or not.
* 
* @param client        Client index.
* 
* @return             True if client is spamming; false otherwise.
*/
native bool IsSpamming(client);

/*
* Sets a client as spamming commands.
* 
* @param client        Client index.
* 
* @noreturn
*/
native void SetIsSpamming(int client, float BlockTime);

/*
* Adds a command to the timer's command list.
* 
* @param sCommand        The command to add to the command list.
* @param sDescription    The description of the command added to the command list.
* 
* @noreturn
*/
native void RegisterCommand(const char[] sCommand, const char[] sDescription);

#include <clientprefs>

/**
* A simpler way of getting the bool value of a client's cookie.
* 
* @param client        Client index.
* @param cookie        Handle to the cookie.
* 
* @return              Boolean value of the client's cookie, false if client's cookies are not cached.
*/
stock bool GetCookieBool(int client, Handle cookie)
{
    if(AreClientCookiesCached(client))
    {
        char sCookie[16];
        GetClientCookie(client, cookie, sCookie, sizeof(sCookie));
        
        if(strlen(sCookie) == 0)
            return true;
        else
            return bool StringToInt(sCookie);
    }
    
    return true;
}

stock bool GetCookieInt(int client, Handle cookie)
{
    if(AreClientCookiesCached(client))
    {
        char sCookie[16];
        GetClientCookie(client, cookie, sCookie, sizeof(sCookie));
        
        if(strlen(sCookie) == 0)
            return 0;
        else
            return StringToInt(sCookie);
    }
    
    return true;
}

/**
* A simpler of of setting a client's cookie with a boolean value
* 
* @param client        Client index.
* @param cookie        Handle to the cookie.
* @param value         Value to set the client's cookie to.
* 
* @noreturn
*/
stock void SetCookieBool(int client, Handle cookie, bool value)
{
    if(AreClientCookiesCached(client))
    {
        char sCookie[32];
        IntToString(value, sCookie, sizeof(sCookie));
        SetClientCookie(client, cookie, sCookie);
    }
}

stock void SetCookieInt(int client, Handle cookie, int value)
{
    if(AreClientCookiesCached(client))
    {
        char sCookie[32];
        IntToString(value, sCookie, sizeof(sCookie));
        SetClientCookie(client, cookie, sCookie);
    }
}

#include <console>

/*
* Registers a console command and adds it to the timer's command list.
* 
* @param sCommand        The command to register and add to the command list.
* @param callback        The callback for the command.
* @param sDescription    The description of the command.
* 
* @noreturn
*/
stock void RegConsoleCmdEx(const char[] sCommand, ConCmd callback, const char[] sDescription)
{
    RegConsoleCmd(sCommand, callback, sDescription);
    
    RegisterCommand(sCommand, sDescription);
}

#include <bTimes-timer>

stock void RegConsoleCmdPerStyle(const char[] sBaseCmd, ConCmd callback, const char[] sDescription)
{
    char sLiteralDesc[256];
    char sType[32];
    char sStyle[32];
    char sTypeAbbr[32];
    char sStyleAbbr[32];
    char sLiteralBaseCmd[64];
    
    int TotalStyles = Style_GetTotal();
    for(int Type; Type < MAX_TYPES; Type++)
    {
        GetTypeName(Type, sType, sizeof(sType));
        GetTypeAbbr(Type, sTypeAbbr, sizeof(sTypeAbbr), true);
        
        for(int Style; Style < TotalStyles; Style++)
        {
            GetStyleName(Style, sStyle, sizeof(sStyle));
            GetStyleAbbr(Style, sStyleAbbr, sizeof(sStyleAbbr), true);
            
            if(Style_IsEnabled(Style) && Style_IsTypeAllowed(Style, Type))
            {
                strcopy(sLiteralDesc, sizeof(sLiteralDesc), sDescription);
                ReplaceString(sLiteralDesc, sizeof(sLiteralDesc), "{Type}", sType, false);
                ReplaceString(sLiteralDesc, sizeof(sLiteralDesc), "{Style}", sStyle, false);
                
                FormatEx(sLiteralBaseCmd, sizeof(sLiteralBaseCmd), "sm_%s%s%s", sTypeAbbr, sBaseCmd, sStyleAbbr);
                
                RegConsoleCmdEx(sLiteralBaseCmd, callback, sLiteralDesc);
            }
        }
    }
}
/*
* Called when a map's MapID is gauranteed to be in the database
*/
forward OnMapIDPostCheck();

/*
* Called when the list of maps from the maps table in the database has been loaded into memory
*/
forward OnDatabaseMapListLoaded();

/*
* Called when a player's PlayerID is retrieved and gauranteed to be in the database
*/
forward OnPlayerIDLoaded(client);

/*
* Used to print messages to all players and allows special colors without annoying hexadecimal spam in console
*/
stock void PrintColorTextAll(const char[] msg, any ...)
{
    char buffer[300];
    VFormat(buffer, sizeof(buffer), msg, 2);
    Handle hMessage = StartMessageAll("SayText2"); 
    if (hMessage != INVALID_HANDLE) 
    {
        if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
        {
            PbSetInt(hMessage, "ent_idx", 0);
            PbSetBool(hMessage, "chat", true);
            PbSetString(hMessage, "msg_name", buffer);
            PbAddString(hMessage, "params", "");
            PbAddString(hMessage, "params", "");
            PbAddString(hMessage, "params", "");
            PbAddString(hMessage, "params", "");
        }
        else
        {
            BfWriteByte(hMessage, 0);
            BfWriteByte(hMessage, true);
            BfWriteString(hMessage, buffer);
        }
        
        EndMessage();
    }
}

/*
* Used to print messages to a single player and allows special colors without annoying hexadecimal spam in console
*/
stock void PrintColorText(int client, const char[] msg, any ...)
{
    if(IsClientInGame(client))
    {
        char buffer[300];
        VFormat(buffer, sizeof(buffer), msg, 3);
        
        Handle hMessage = StartMessageOne("SayText2", client); 
        if (hMessage != INVALID_HANDLE) 
        { 
            if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
            {
                PbSetInt(hMessage, "ent_idx", client);
                PbSetBool(hMessage, "chat", true);
                PbSetString(hMessage, "msg_name", buffer);
                PbAddString(hMessage, "params", "");
                PbAddString(hMessage, "params", "");
                PbAddString(hMessage, "params", "");
                PbAddString(hMessage, "params", "");
            }
            else
            {
                BfWriteByte(hMessage, client);
                BfWriteByte(hMessage, true);
                BfWriteString(hMessage, buffer);
            }
            
            EndMessage();
        }
    }
}

/*
* Used to print messages to a player's spectators and allows special colors without annoying hexadecimal spam in console
*/
stock void PrintColorTextObservers(int target, const char[] msg, any ...)
{
    char buffer[300];
    VFormat(buffer, sizeof(buffer), msg, 3);
    
    int observercount;
    
    int[] clients = new int[MaxClients];
    
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsPlayerAlive(client) && !IsFakeClient(client))
        {
            int observee         = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
            int ObserverMode     = GetEntProp(client, Prop_Send, "m_iObserverMode");
            
            if(observee == target && (ObserverMode == 4 || ObserverMode == 5))
            {
                clients[observercount++] = client;
            }
        }
    }
    
    if(observercount == 0)
        return;
    
    Handle hMessage = StartMessage("SayText2", clients, observercount); 
    if (hMessage != INVALID_HANDLE) 
    { 
        if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf) 
        {
            PbSetInt(hMessage, "ent_idx", 0);
            PbSetBool(hMessage, "chat", true);
            PbSetString(hMessage, "msg_name", buffer);
            PbAddString(hMessage, "params", "");
            PbAddString(hMessage, "params", "");
            PbAddString(hMessage, "params", "");
            PbAddString(hMessage, "params", "");
        }
        else
        {
            BfWriteByte(hMessage, 0);
            BfWriteByte(hMessage, true);
            BfWriteString(hMessage, buffer);
        }
        
        EndMessage();
    }
}

/*
* Converts a time into a formatted string
*/
stock void FormatPlayerTime(float Time, char[] result, int maxlength, bool showDash, int precision)
{
    if(Time <= 0.0 && showDash == true)
    {
        Format(result, maxlength, "-");
        return;
    }
    
    int hours     = RoundToFloor(Time/3600);
    Time         -= hours*3600;
    int minutes     = RoundToFloor(Time/60);
    Time         -= minutes*60;
    float seconds = Time;
    
    char sPrecision[16];
    
    if(precision == 0)
        Format(sPrecision, sizeof(sPrecision), (hours > 0 || minutes > 0)?"%04.1f":"%.1f", seconds);
    else if(precision == 1)
        Format(sPrecision, sizeof(sPrecision), (hours > 0 || minutes > 0)?"%06.3f":"%.3f", seconds);
    else if(precision == 2)
        Format(sPrecision, sizeof(sPrecision), (hours > 0 || minutes > 0)?"%09.6f":"%.6f", seconds);
    
    if(hours > 0)
        Format(result, maxlength, "%d:%02d:%s", hours, minutes, sPrecision);
    else if(minutes > 0)
        Format(result, maxlength, "%d:%s", minutes, sPrecision);
    else
        Format(result, maxlength, "%s", sPrecision);
}

/*
* Gets a client's velocity with extra settings to disallow velocity on certain axes
*/
stock float GetClientVelocity(int client, bool UseX, bool UseY, bool UseZ)
{
    float vVel[3];
    
    if(UseX)
    {
        vVel[0] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
    }
    
    if(UseY)
    {
        vVel[1] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
    }
    
    if(UseZ)
    {
        vVel[2] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[2]");
    }
    
    return GetVectorLength(vVel);
}

/*
* Gets the name of a specified type
*/
stock void GetTypeName(int Type, char[] sType, int maxlength, bool bBlankIfMain = false)
{
    if((Type == TIMER_MAIN && bBlankIfMain == true) || Type == ALL)
    {
        FormatEx(sType, maxlength, "");
        return;
    }
    
    char sTypeList[MAX_TYPES][] = {"Main", "Bonus", "Solo Bonus"};
    
    FormatEx(sType, maxlength, sTypeList[Type]);
}

/*
* Gets the abbreviation of a specified type
*/
stock void GetTypeAbbr(int Type, char[] sAbbr, int maxlength, bool bBlankIfMain = false)
{
    if((Type == TIMER_MAIN && bBlankIfMain == true) || Type == ALL)
    {
        FormatEx(sAbbr, maxlength, "");
        return;
    }
    
    char sAbbrList[MAX_TYPES][] = {"", "b", "sb"};
    
    FormatEx(sAbbr, maxlength, sAbbrList[Type]);
}

/*
* Turns all lowercase letters in a string to uppercase
*/
stock void StringToUpper(char[] buffer)
{
    int len = strlen(buffer);
    
    for(int idx = 0; idx < len; idx++)
    {
        buffer[idx] = CharToUpper(buffer[idx]);
    }
}

/*
* Adds brackets to a string, might change so players can choose brackets
*/
stock void AddBracketsToString(char[] buffer, int maxlength)
{
    if(strlen(buffer) > 0)
        Format(buffer, maxlength, "[%s]", buffer);
}

/*
* Adds a space to the end of a string, probably gonna remove this
*/
stock void AddSpaceToEnd(char[] buffer, int maxlength)
{
    if(strlen(buffer) > 0)
        Format(buffer, maxlength, "%s ", buffer);
}
