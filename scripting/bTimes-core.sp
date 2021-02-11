#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = 
{
    name = "[bTimes] Core",
    author = "blacky",
    description = "The root of bTimes",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sourcemod>
#include <sdktools>
#include <scp>
#include <smlib/clients>
#include <bTimes-timer>

#pragma newdecls required

enum
{
    GameType_CSS,
    GameType_CSGO
};

int g_GameType;

ArrayList g_hCommandList;
bool g_bCommandListLoaded;

Database g_DB;

char g_sMapName[64];
int g_PlayerID[MAXPLAYERS+1];
ArrayList g_MapList,
    g_hDbMapNameList,
    g_hDbMapIdList;
bool g_bDbMapsLoaded;
float g_fMapStart;
    
float g_fSpamTime[MAXPLAYERS + 1],
    g_fJoinTime[MAXPLAYERS + 1];
    
// Chat
char g_msg_start[128] = {""};
char g_msg_varcol[128] = {"\x07B4D398"};
char g_msg_textcol[128] = {"\x01"};

// Forwards
Handle g_fwdMapIDPostCheck,
    g_fwdMapListLoaded,
    g_fwdPlayerIDLoaded;

// PlayerID retrieval data
ArrayList g_hPlayerID,
    g_hUser;
bool g_bPlayerListLoaded;

// Cvars
ConVar g_hChangeLogURL;

public void OnPluginStart()
{    
    char sGame[64];
    GetGameFolderName(sGame, sizeof(sGame));
    
    if(StrEqual(sGame, "cstrike"))
        g_GameType = GameType_CSS;
    else if(StrEqual(sGame, "csgo"))
        g_GameType = GameType_CSGO;
    else
        SetFailState("This timer does not support this game (%s)", sGame);
    
    // Database
    DB_Connect();
    
    // Cvars
    if(g_GameType == GameType_CSS)
    {
        g_hChangeLogURL = CreateConVar("timer_changelog", "http://textuploader.com/14vc/raw", "The URL in to the timer changelog, in case the current URL breaks for some reason.");
        RegConsoleCmdEx("sm_changes", SM_Changes, "See the changes in the newer timer version.");
    }
    
    AutoExecConfig(true, "core", "timer");
    
    // Events
    HookEvent("player_changename", Event_PlayerChangeName, EventHookMode_Pre);
    HookEvent("player_team", Event_PlayerTeam_Post, EventHookMode_Post);
    
    // Commands
    RegConsoleCmdEx("sm_mostplayed", SM_TopMaps, "Displays the most played maps");
    RegConsoleCmdEx("sm_lastplayed", SM_LastPlayed, "Shows the last played maps");
    RegConsoleCmdEx("sm_playtime", SM_Playtime, "Shows the people who played the most.");
    RegConsoleCmdEx("sm_thelp", SM_THelp, "Shows the timer commands.");
    RegConsoleCmdEx("sm_commands", SM_THelp, "Shows the timer commands.");
    RegConsoleCmdEx("sm_search", SM_Search, "Search the command list for the given string of text.");
    
    // Makes FindTarget() work properly
    LoadTranslations("common.phrases");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("GetClientID", Native_GetClientID);
    CreateNative("IsSpamming", Native_IsSpamming);
    CreateNative("SetIsSpamming", Native_SetIsSpamming);
    CreateNative("RegisterCommand", Native_RegisterCommand);
    CreateNative("GetMapIdFromMapName", Native_GetMapIdFromMapName);
    CreateNative("GetMapNameFromMapId", Native_GetMapNameFromMapId);
    CreateNative("GetNameFromPlayerID", Native_GetNameFromPlayerID);
    CreateNative("GetSteamIDFromPlayerID", Native_GetSteamIDFromPlayerID);
    
    g_fwdMapIDPostCheck = CreateGlobalForward("OnMapIDPostCheck", ET_Event);
    g_fwdPlayerIDLoaded = CreateGlobalForward("OnPlayerIDLoaded", ET_Event, Param_Cell);
    g_fwdMapListLoaded  = CreateGlobalForward("OnDatabaseMapListLoaded", ET_Event);
    
    return APLRes_Success;
}

public void OnMapStart()
{
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    
    g_fMapStart = GetEngineTime();
    
    if(g_MapList != INVALID_HANDLE)
    {
        delete g_MapList;
    }
    
    g_MapList = new ArrayList(ByteCountToCells(64));
    ReadMapList(g_MapList);
    
    // Creates map if it doesn't exist, sets map as recently played, and loads map playtime
    CreateCurrentMapID();
}

public void OnMapEnd()
{
    DB_SaveMapPlaytime();
    DB_SetMapLastPlayed();
}

public void OnClientPutInServer(int client)
{
    g_fJoinTime[client] = GetEngineTime();
}

public void OnClientDisconnect(int client)
{
    // Save player's play time
    if(g_PlayerID[client] != 0 && !IsFakeClient(client))
    {
        DB_SavePlaytime(client);
    }
    
    // Reset the playerid for the client index
    g_PlayerID[client]   = 0;
}

public void OnClientAuthorized(int client)
{
    if(!IsFakeClient(client) && g_bPlayerListLoaded == true)
    {
        CreatePlayerID(client);
    }
}

public void OnTimerChatChanged(int MessageType, char[] Message)
{
    if(MessageType == 0)
    {
        Format(g_msg_start, sizeof(g_msg_start), Message);
        ReplaceMessage(g_msg_start, sizeof(g_msg_start));
    }
    else if(MessageType == 1)
    {
        Format(g_msg_varcol, sizeof(g_msg_varcol), Message);
        ReplaceMessage(g_msg_varcol, sizeof(g_msg_varcol));
    }
    else if(MessageType == 2)
    {
        Format(g_msg_textcol, sizeof(g_msg_textcol), Message);
        ReplaceMessage(g_msg_textcol, sizeof(g_msg_textcol));
    }
}

void ReplaceMessage(char[] message, int maxlength)
{
    if(g_GameType == GameType_CSS)
    {
        ReplaceString(message, maxlength, "^", "\x07", false);
    }
    else if(g_GameType == GameType_CSGO)
    {
        ReplaceString(message, maxlength, "^A", "\x0A");
        ReplaceString(message, maxlength, "^1", "\x01");
        ReplaceString(message, maxlength, "^2", "\x02");
        ReplaceString(message, maxlength, "^3", "\x03");
        ReplaceString(message, maxlength, "^4", "\x04");
        ReplaceString(message, maxlength, "^5", "\x05");
        ReplaceString(message, maxlength, "^6", "\x06");
        ReplaceString(message, maxlength, "^7", "\x07");
    }
}

public Action Event_PlayerTeam_Post(Event event, const char[] name, bool dontBroadcast)
{
    int client  = GetClientOfUserId(event.GetInt("userid"));
    
    if(0 < client <= MaxClients)
    {
        if(IsClientInGame(client))
        {
            int oldteam = event.GetInt("oldteam");
            if(oldteam == 0)
            {    
                if(g_GameType == GameType_CSS)
                {
                    PrintColorText(client, "%s%sType %s!thelp%s for a command list. %s!changes%s to see the changelog.",
                        g_msg_start,
                        g_msg_textcol,
                        g_msg_varcol,
                        g_msg_textcol,
                        g_msg_varcol,
                        g_msg_textcol);
                }
                else if(g_GameType == GameType_CSGO)
                {
                    PrintColorText(client, "%s%sType %s!thelp%s for a command list.",
                        g_msg_start,
                        g_msg_textcol,
                        g_msg_varcol,
                        g_msg_textcol);
                }
            }
        }
    }
}


public Action OnChatMessage(int &author, Handle recipients, char[] name, char[] message)
{
    if(IsChatTrigger())
    {
        return Plugin_Stop;
    }
    
    /*
    decl String:sType[16], String:sStyle[32], String:sCommand[48];
    for(new Type; Type < MAX_TYPES; Type++)
    {
        GetTypeAbbr(Type, sType, sizeof(sType), true);
        for(new Style; Style < MAX_STYLES; Style++)
        {
            GetStyleAbbr(Style, sStyle, sizeof(sStyle), true);
            
            Format(sCommand, sizeof(sCommand), "%srank%s", sType, sStyle);
            
            if(StrEqual(message, sCommand, true))
            {
                FakeClientCommand(author, "sm_%s", message);
                return Plugin_Stop;
            }
        }
    }
    */
    
    return Plugin_Continue;
}


public Action SM_TopMaps(int client, int args)
{
    if(!IsSpamming(client))
    {
        SetIsSpamming(client, 1.0);
        
        char query[256];
        Format(query, sizeof(query), "SELECT MapName, MapPlaytime FROM maps ORDER BY MapPlaytime DESC");
        g_DB.Query(TopMaps_Callback, query, client);
    }
    
    return Plugin_Handled;
}

public void TopMaps_Callback(Database owner, DBResultSet results, char[] error, any client)
{
    if(results != INVALID_HANDLE)
    {
        if(IsClientInGame(client))
        {
            Menu menu = new Menu(Menu_TopMaps, MENU_ACTIONS_DEFAULT);
            menu.SetTitle("Most played maps\n---------------------------------------");
            
            int rows = results.RowCount;
            if(rows > 0)
            {
                char mapname[64],
                    timeplayed[32],
                    display[128];
                int iTime;
                
                for(int i, j; i < rows; i++)
                {
                    results.FetchRow();
                    iTime = results.FetchInt(1);
                    
                    if(iTime != 0)
                    {
                        results.FetchString(0, mapname, sizeof(mapname));
                        
                        if(g_MapList.FindString(mapname) != -1)
                        {
                            FormatPlayerTime(float(iTime), timeplayed, sizeof(timeplayed), false, 1);
                            SplitString(timeplayed, ".", timeplayed, sizeof(timeplayed));
                            Format(display, sizeof(display), "#%d: %s - %s", ++j, mapname, timeplayed);
                            
                            menu.AddItem(display, display);
                        }
                    }
                }
                
                menu.ExitButton = true;
                menu.Display(client, MENU_TIME_FOREVER);
            }
        }
    }
    else
    {
        LogError(error);
    }
}

public int Menu_TopMaps(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        FakeClientCommand(param1, "sm_nominate %s", info);
    }
    else if(action == MenuAction_End)
        delete menu;
}

public Action SM_LastPlayed(int client, int args)
{
    if(!IsSpamming(client))
    {
        SetIsSpamming(client, 1.0);
        
        char query[256];
        Format(query, sizeof(query), "SELECT MapName, LastPlayed FROM maps ORDER BY LastPlayed DESC");
        g_DB.Query(LastPlayed_Callback, query, client);
    }
    
    return Plugin_Handled;
}

public void LastPlayed_Callback(Database owner, DBResultSet results, char[] error, any client)
{
    if(results != INVALID_HANDLE)
    {
        if(IsClientInGame(client))
        {
            Menu menu = new Menu(Menu_LastPlayed, MENU_ACTIONS_DEFAULT);
            menu.SetTitle("Last played maps\n---------------------------------------");
            
            char sMapName[64];
            char sDate[32];
            char sTimeOfDay[32];
            char display[256];
            int iTime;
            
            int rows = results.RowCount;
            for(int i=1; i<=rows; i++)
            {
                results.FetchRow();
                iTime = results.FetchInt(1);
                
                if(iTime != 0)
                {
                    results.FetchString(0, sMapName, sizeof(sMapName));
                    
                    if(g_MapList.FindString(sMapName) != -1)
                    {
                        FormatTime(sDate, sizeof(sDate), "%x", iTime);
                        FormatTime(sTimeOfDay, sizeof(sTimeOfDay), "%X", iTime);
                        
                        Format(display, sizeof(display), "%s - %s - %s", sMapName, sDate, sTimeOfDay);
                        
                        menu.AddItem(display, display);
                    }
                }
            }
            
            menu.ExitButton = true;
            menu.Display(client, MENU_TIME_FOREVER);
        }
    }
    else
    {
        LogError(error);
    }
}

public int Menu_LastPlayed(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        FakeClientCommand(param1, "sm_nominate %s", info);
    }
    else if(action == MenuAction_End)
        delete menu;
}

public Action Event_PlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if(!IsFakeClient(client) && g_PlayerID[client] != 0)
    {
        char sNewName[MAX_NAME_LENGTH];
        event.GetString("newname", sNewName, sizeof(sNewName));
        UpdateName(client, sNewName);
    }
}

public Action SM_Changes(int client, int args)
{
    if(g_GameType == GameType_CSS)
    {
        char sChangeLog[PLATFORM_MAX_PATH];
        g_hChangeLogURL.GetString(sChangeLog, PLATFORM_MAX_PATH);
        
        ShowMOTDPanel(client, "Timer changelog", sChangeLog, MOTDPANEL_TYPE_URL);
        
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

void DB_Connect()
{    
    if(g_DB != INVALID_HANDLE)
        delete g_DB;
    
    char error[255];
    g_DB = SQL_Connect("timer", true, error, sizeof(error));
    
    if(g_DB == INVALID_HANDLE)
    {
        LogError(error);
        delete g_DB;
    }
    else
    {
        char query[512];
        
        // Create maps table
        Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS maps(MapID INTEGER NOT NULL AUTO_INCREMENT, MapName TEXT, MapPlaytime INTEGER NOT NULL, LastPlayed INTEGER NOT NULL, PRIMARY KEY (MapID))");
        g_DB.Query(DB_Connect_Callback, query);
        
        // Create zones table
        Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS zones(RowID INTEGER NOT NULL AUTO_INCREMENT, MapID INTEGER, Type INTEGER, point00 REAL, point01 REAL, point02 REAL, point10 REAL, point11 REAL, point12 REAL, flags INTEGER, PRIMARY KEY (RowID))");
        g_DB.Query(DB_Connect_Callback, query);
        
        // Create players table
        Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS players(PlayerID INTEGER NOT NULL AUTO_INCREMENT, SteamID TEXT, User Text, Playtime INTEGER NOT NULL, ccname TEXT, ccmsgcol TEXT, ccuse INTEGER, PRIMARY KEY (PlayerID))");
        g_DB.Query(DB_Connect_Callback, query);
        
        // Create times table
        Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS times(rownum INTEGER NOT NULL AUTO_INCREMENT, MapID INTEGER, Type INTEGER, Style INTEGER, PlayerID INTEGER, PartnerPlayerID INTEGER, Time REAL, Jumps INTEGER, Strafes INTEGER, Flashes INTEGER, Points REAL, Timestamp INTEGER, Sync REAL, SyncTwo REAL, PRIMARY KEY (rownum))");
        g_DB.Query(DB_Connect_Callback, query);
        
        LoadPlayers();
        LoadDatabaseMapList();
    }
}

public void DB_Connect_Callback(Database owner, DBResultSet results, const char[] error, any data)
{
    if(results == INVALID_HANDLE)
    {
        LogError(error);
    }
}

void LoadDatabaseMapList()
{    
    char query[256];
    FormatEx(query, sizeof(query), "SELECT MapID, MapName FROM maps");
    g_DB.Query(LoadDatabaseMapList_Callback, query);
}

public void LoadDatabaseMapList_Callback(Database owner, DBResultSet results, char[] error, any data)
{
    if(results != INVALID_HANDLE)
    {
        if(g_bDbMapsLoaded == false)
        {
            g_hDbMapNameList = new ArrayList(ByteCountToCells(64));
            g_hDbMapIdList   = new ArrayList();
            g_bDbMapsLoaded  = true;
        }
        
        char sMapName[64];
        
        while(results.FetchRow())
        {
            results.FetchString(1, sMapName, sizeof(sMapName));
            
            g_hDbMapNameList.PushString(sMapName);
            g_hDbMapIdList.Push(results.FetchInt(0));
        }
        
        Call_StartForward(g_fwdMapListLoaded);
        Call_Finish();
    }
    else
    {
        LogError(error);
    }
}

void LoadPlayers()
{
    g_hPlayerID = new ArrayList(ByteCountToCells(32));
    g_hUser     = new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
    
    char query[128];
    FormatEx(query, sizeof(query), "SELECT SteamID, PlayerID, User FROM players");
    g_DB.Query(LoadPlayers_Callback, query);
}

public void LoadPlayers_Callback(Database owner, DBResultSet results, char[] error, any data)
{
    if(results != INVALID_HANDLE)
    {
        char sName[32];
        char sAuth[32];
        
        int RowCount = results.RowCount, PlayerID, iSize;
        for(int Row; Row < RowCount; Row++)
        {
            results.FetchRow();
            
            results.FetchString(0, sAuth, sizeof(sAuth));
            PlayerID = results.FetchInt(1);
            results.FetchString(2, sName, sizeof(sName));
            
            iSize = g_hPlayerID.Length;
            
            if(PlayerID >= iSize)
            {
                g_hPlayerID.Resize(PlayerID + 1);
                g_hUser.Resize(PlayerID + 1);
            }
            
            g_hPlayerID.SetString(PlayerID, sAuth);
            g_hUser.SetString(PlayerID, sName);
        }
        
        g_bPlayerListLoaded = true;
        
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientConnected(client) && !IsFakeClient(client))
            {
                if(IsClientAuthorized(client))
                {
                    CreatePlayerID(client);
                }
            }
        }
    }
    else
    {
        LogError(error);
    }
}

void CreateCurrentMapID()
{
    DataPack pack = new DataPack();
    pack.WriteString(g_sMapName);
    
    char query[512];
    FormatEx(query, sizeof(query), "INSERT INTO maps (MapName) SELECT * FROM (SELECT '%s') AS tmp WHERE NOT EXISTS (SELECT MapName FROM maps WHERE MapName = '%s') LIMIT 1",
        g_sMapName,
        g_sMapName);
    g_DB.Query(DB_CreateCurrentMapID_Callback, query, pack);
}

public void DB_CreateCurrentMapID_Callback(Database owner, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        if(results.AffectedRows > 0)
        {

            data.Reset();
            
            char sMapName[64];
            data.ReadString(sMapName, sizeof(sMapName));
            
            int MapID = results.InsertId;
            LogMessage("MapID for %s created (%d)", sMapName, MapID);
            
            if(g_bDbMapsLoaded == false)
            {
                g_hDbMapNameList = new ArrayList(ByteCountToCells(64));
                g_hDbMapIdList   = new ArrayList();
                g_bDbMapsLoaded  = true;
            }
            
            g_hDbMapNameList.PushString(sMapName);
            g_hDbMapIdList.Push(MapID);
        }
        
        Call_StartForward(g_fwdMapIDPostCheck);
        Call_Finish();
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

void CreatePlayerID(int client)
{    
    char sName[MAX_NAME_LENGTH];
    GetClientName(client, sName, sizeof(sName));
    
    char sAuth[32];
    GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
    
    int idx = g_hPlayerID.FindString(sAuth);
    if(idx != -1)
    {
        g_PlayerID[client] = idx;
        
        char sOldName[MAX_NAME_LENGTH];
        g_hUser.GetString(idx, sOldName, sizeof(sOldName));
        
        if(!StrEqual(sName, sOldName))
        {
            UpdateName(client, sName);
        }
        
        Call_StartForward(g_fwdPlayerIDLoaded);
        Call_PushCell(client);
        Call_Finish();
    }
    else
    {
        char sEscapeName[(2 * MAX_NAME_LENGTH) + 1] ;
        SQL_LockDatabase(g_DB);
        g_DB.Escape(sName, sEscapeName, sizeof(sEscapeName));
        SQL_UnlockDatabase(g_DB);
        
        DataPack pack = new DataPack();
        pack.WriteCell(GetClientUserId(client));
        pack.WriteString(sAuth);
        pack.WriteString(sName);
        
        char query[128];
        FormatEx(query, sizeof(query), "INSERT INTO players (SteamID, User) VALUES ('%s', '%s')",
            sAuth,
            sEscapeName);
        g_DB.Query(CreatePlayerID_Callback, query, pack);
    }
}

public void CreatePlayerID_Callback(Database owner, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        int client = GetClientOfUserId(data.ReadCell());
        
        char sAuth[32];
        data.ReadString(sAuth, sizeof(sAuth));
        
        char sName[MAX_NAME_LENGTH];
        data.ReadString(sName, sizeof(sName));
        
        int PlayerID = results.InsertId;
        
        int iSize = g_hPlayerID.Length;
        
        if(PlayerID >= iSize)
        {
            g_hPlayerID.Resize(PlayerID + 1);
            g_hUser.Resize(PlayerID + 1);
        }
        
        g_hPlayerID.SetString(PlayerID, sAuth);
        g_hUser.SetString(PlayerID, sName);
        
        if(client != 0)
        {
            g_PlayerID[client] = PlayerID;
            
            Call_StartForward(g_fwdPlayerIDLoaded);
            Call_PushCell(client);
            Call_Finish();
        }
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

void UpdateName(int client, const char[] sName)
{
    g_hUser.SetString(g_PlayerID[client], sName);
    
    char sEscapeName[(2 * MAX_NAME_LENGTH) + 1];
    SQL_LockDatabase(g_DB);
    g_DB.Escape(sName, sEscapeName, sizeof(sEscapeName));
    SQL_UnlockDatabase(g_DB);
    
    char query[128];
    FormatEx(query, sizeof(query), "UPDATE players SET User='%s' WHERE PlayerID=%d",
        sEscapeName,
        g_PlayerID[client]);
    g_DB.Query(UpdateName_Callback, query);
}

public void UpdateName_Callback(Database owner, DBResultSet results, const char[] error, any userid)
{
    if(results == INVALID_HANDLE)
        LogError(error);
}

public int Native_GetClientID(Handle plugin, int numParams)
{
    return g_PlayerID[GetNativeCell(1)];
}

void DB_SavePlaytime(int client)
{
    if(IsClientInGame(client))
    {
        int PlayerID = GetPlayerID(client);
        if(PlayerID != 0)
        {        
            char query[128];
            Format(query, sizeof(query), "UPDATE players SET Playtime=(SELECT Playtime FROM (SELECT * FROM players) AS x WHERE PlayerID=%d)+%d WHERE PlayerID=%d",
                PlayerID,
                RoundToFloor(GetEngineTime() - g_fJoinTime[client]),
                PlayerID);
                
            g_DB.Query(DB_SavePlaytime_Callback, query);
        }
    }
}

public void DB_SavePlaytime_Callback(Database owner, DBResultSet results, char[] error, any data)
{
    if(results == INVALID_HANDLE)
        LogError(error);
}

void DB_SaveMapPlaytime()
{
    char query[256];

    Format(query, sizeof(query), "UPDATE maps SET MapPlaytime=(SELECT MapPlaytime FROM (SELECT * FROM maps) AS x WHERE MapName='%s' LIMIT 0, 1)+%d WHERE MapName='%s'",
        g_sMapName,
        RoundToFloor(GetEngineTime()-g_fMapStart),
        g_sMapName);
        
    g_DB.Query(DB_SaveMapPlaytime_Callback, query);
}

public void DB_SaveMapPlaytime_Callback(Database owner, DBResultSet results, char[] error, any data)
{
    if(results == INVALID_HANDLE)
        LogError(error);
}

void DB_SetMapLastPlayed()
{
    char query[128];
    
    Format(query, sizeof(query), "UPDATE maps SET LastPlayed=%d WHERE MapName='%s'",
        GetTime(),
        g_sMapName);
        
    g_DB.Query(DB_SetMapLastPlayed_Callback, query);
}

public void DB_SetMapLastPlayed_Callback(Database owner, DBResultSet results, char[] error, any data)
{
    if(results == INVALID_HANDLE)
        LogError(error);
}

public Action SM_Playtime(int client, int args)
{
    if(!IsSpamming(client))
    {
        SetIsSpamming(client, 1.0);
        
        if(args == 0)
        {
            if(g_PlayerID[client] != 0)
            {
                DB_ShowPlaytime(client, g_PlayerID[client]);
            }
        }
        else
        {
            char sArg[MAX_NAME_LENGTH];
            GetCmdArgString(sArg, sizeof(sArg));
            
            int target = FindTarget(client, sArg, true, false);
            if(target != -1)
            {
                if(g_PlayerID[target] != 0)
                {
                    DB_ShowPlaytime(client, g_PlayerID[target]);
                }
            }
        }
    }
    
    return Plugin_Handled;
}

void DB_ShowPlaytime(int client, int PlayerID)
{
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(PlayerID);
    
    char query[512];
    Format(query, sizeof(query), "SELECT (SELECT Playtime FROM players WHERE PlayerID=%d) AS TargetPlaytime, User, Playtime, PlayerID FROM players ORDER BY Playtime DESC LIMIT 0, 100",
        PlayerID);
    g_DB.Query(DB_ShowPlaytime_Callback, query, pack);
}

public void DB_ShowPlaytime_Callback(Database owner, DBResultSet results, char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        int client = GetClientOfUserId(data.ReadCell());
        
        if(client != 0)
        {            
            int rows = results.RowCount;
            if(rows != 0)
            {
                int TargetPlayerID = data.ReadCell();
                
                Menu menu = new Menu(Menu_ShowPlaytime, MENU_ACTIONS_DEFAULT );
                
                char sName[MAX_NAME_LENGTH], sTime[32], sDisplay[64],sInfo[16], PlayTime;
                int PlayerID, TargetPlaytime;
                
                for(int i = 1; i <= rows; i++)
                {
                    results.FetchRow();
                    
                    TargetPlaytime = results.FetchInt(0);
                    results.FetchString(1, sName, sizeof(sName));
                    PlayTime = results.FetchInt(2);
                    PlayerID = results.FetchInt(3);
                    
                    // Set info
                    IntToString(PlayerID, sInfo, sizeof(sInfo));
                    
                    // Set display
                    FormatPlayerTime(float(PlayTime), sTime, sizeof(sTime), false, 1);
                    SplitString(sTime, ".", sTime, sizeof(sTime));
                    FormatEx(sDisplay, sizeof(sDisplay), "#%d: %s: %s", i, sName, sTime);
                    if((i % 7) == 0 || i == rows)
                    {
                        Format(sDisplay, sizeof(sDisplay), "%s\n--------------------------------------", sDisplay);
                    }
                    
                    // Add item
                    menu.AddItem(sInfo, sDisplay);
                }
                
                GetNameFromPlayerID(TargetPlayerID, sName, sizeof(sName));
                
                float ConnectionTime;
                
                int target = GetClientFromPlayerID(TargetPlayerID);
                
                if(target != 0)
                {
                    ConnectionTime = GetEngineTime() - g_fJoinTime[target];
                }
                
                FormatPlayerTime(ConnectionTime + float(TargetPlaytime), sTime, sizeof(sTime), false, 1);
                SplitString(sTime, ".", sTime, sizeof(sTime));
                
                menu.SetTitle("Playtimes\n \n%s: %s\n--------------------------------------",
                    sName,
                    sTime);
                
                menu.ExitButton = true;
                menu.Display(client, MENU_TIME_FOREVER);
            }
        }
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

public int Menu_ShowPlaytime(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_End)
        delete menu;
}

public Action SM_THelp(int client, int args)
{    
    int iSize = g_hCommandList.Length;
    char sResult[256];
    
    if(0 < client <= MaxClients)
    {
        if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
            ReplyToCommand(client, "[SM] Look in your console for timer command list.");
        
        char sCommand[32];
        GetCmdArg(0, sCommand, sizeof(sCommand));
        
        if(args == 0)
        {
            ReplyToCommand(client, "[SM] %s 10 for the next page.", sCommand);
            for(int i=0; i<10 && i < iSize; i++)
            {
                g_hCommandList.GetString(i, sResult, sizeof(sResult));
                PrintToConsole(client, sResult);
            }
        }
        else
        {
            char arg[250];
            GetCmdArgString(arg, sizeof(arg));
            int iStart = StringToInt(arg);
            
            if(iStart < (iSize-10))
            {
                ReplyToCommand(client, "[SM] %s %d for the next page.", sCommand, iStart + 10);
            }
            
            for(int i = iStart; i < (iStart + 10) && (i < iSize); i++)
            {
                g_hCommandList.GetString(i, sResult, sizeof(sResult));
                PrintToConsole(client, sResult);
            }
        }
    }
    else if(client == 0)
    {
        for(int i; i < iSize; i++)
        {
            g_hCommandList.GetString(i, sResult, sizeof(sResult));
            PrintToServer(sResult);
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Search(int client, int args)
{
    if(args > 0)
    {
        char sArgString[255];
        char sResult[256];
        GetCmdArgString(sArgString, sizeof(sArgString));
        
        int iSize = g_hCommandList.Length;
        for(int i=0; i<iSize; i++)
        {
            g_hCommandList.GetString(i, sResult, sizeof(sResult));
            if(StrContains(sResult, sArgString, false) != -1)
            {
                PrintToConsole(client, sResult);
            }
        }
    }
    else
    {
        PrintColorText(client, "%s%ssm_search must have a string to search with after it.",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

int GetClientFromPlayerID(int PlayerID)
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsFakeClient(client) && g_PlayerID[client] == PlayerID)
        {
            return client;
        }
    }
    
    return 0;
}

public int Native_IsSpamming(Handle plugin, int numParams)
{
    return GetEngineTime() < g_fSpamTime[GetNativeCell(1)];
}

public int Native_SetIsSpamming(Handle plugin, int numParams)
{
    g_fSpamTime[GetNativeCell(1)] = view_as<float>(GetNativeCell(2)) + GetEngineTime();
}

public int Native_RegisterCommand(Handle plugin, int numParams)
{
    if(g_bCommandListLoaded == false)
    {
        g_hCommandList = new ArrayList(ByteCountToCells(256));
        g_bCommandListLoaded = true;
    }
    
    char sListing[256];
    char sCommand[32];
    char sDesc[224];
    
    GetNativeString(1, sCommand, sizeof(sCommand));
    GetNativeString(2, sDesc, sizeof(sDesc));
    
    FormatEx(sListing, sizeof(sListing), "%s - %s", sCommand, sDesc);
    
    char sIndex[256];
    int idxlen;
    int listlen = strlen(sListing);
    int iSize = g_hCommandList.Length;
    bool IdxFound;
    int idx;
    
    for(idx = 0; idx < iSize; idx++)
    {
        g_hCommandList.GetString(idx, sIndex, sizeof(sIndex));
        idxlen = strlen(sIndex);
        
        for(int cmpidx = 0; cmpidx < listlen && cmpidx < idxlen; cmpidx++)
        {
            if(sListing[cmpidx] < sIndex[cmpidx])
            {
                IdxFound = true;
                break;
            }
            else if(sListing[cmpidx] > sIndex[cmpidx])
            {
                break;
            }
        }
        
        if(IdxFound == true)
            break;
    }
    
    if(idx >= iSize)
        g_hCommandList.Resize(idx + 1);
    else
        g_hCommandList.ShiftUp(idx);
    
    g_hCommandList.SetString(idx, sListing);
}

public int Native_GetMapNameFromMapId(Handle plugin, int numParams)
{
    int Index = g_hDbMapIdList.FindValue(GetNativeCell(1));
    
    if(Index != -1)
    {
        char sMapName[64];
        g_hDbMapNameList.GetString(Index, sMapName, sizeof(sMapName));
        SetNativeString(2, sMapName, GetNativeCell(3));
        
        return true;
    }
    else
    {
        return false;
    }
}

public int Native_GetNameFromPlayerID(Handle plugin, int numParams)
{
    char sName[MAX_NAME_LENGTH];
    
    g_hUser.GetString(GetNativeCell(1), sName, sizeof(sName));
    
    SetNativeString(2, sName, GetNativeCell(3));
}

public int Native_GetSteamIDFromPlayerID(Handle plugin, int numParams)
{
    char sAuth[32];
    
    g_hPlayerID.GetString(GetNativeCell(1), sAuth, sizeof(sAuth));
    
    SetNativeString(2, sAuth, GetNativeCell(3));
}

public int Native_GetMapIdFromMapName(Handle plugin, int numParams)
{
    char sMapName[64];
    GetNativeString(1, sMapName, sizeof(sMapName));
    
    int Index = g_hDbMapNameList.FindString(sMapName);
    
    if(Index != -1)
    {
        return g_hDbMapIdList.Get(Index);
    }
    else
    {
        return 0;
    }
}
