#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = 
{
    name = "[bTimes] Ghost",
    author = "blacky",
    description = "Shows a bot that replays the top times",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <smlib/weapons>
#include <smlib/entities>
#include <cstrike>
#include <bTimes-timer>
#include <bTimes-teams>

#pragma newdecls required

/*
enum
{
    GameType_CSS,
    GameType_CSGO
};

new g_GameType;
*/

char g_sMapName[64];

Database g_DB;

ArrayList g_hFrame[MAXPLAYERS + 1];
bool g_bUsedFrame[MAXPLAYERS + 1];

ArrayList g_hGhost[MAX_TYPES][MAX_STYLES][2];
int g_Ghost[MAX_TYPES][MAX_STYLES][2],
    g_GhostFrame[MAX_TYPES][MAX_STYLES][2],
    g_GhostPlayerID[MAX_TYPES][MAX_STYLES][2],
    g_iBotQuota,
    g_iGhostSize[MAX_TYPES][MAX_STYLES][2];
bool g_GhostPaused[MAX_TYPES][MAX_STYLES][2],
    g_bGhostLoadedOnce[MAX_TYPES][MAX_STYLES],
    g_bGhostLoaded[MAX_TYPES][MAX_STYLES],
    g_bReplayFileExists[MAX_TYPES][MAX_STYLES];
float g_fGhostTime[MAX_TYPES][MAX_STYLES][2],
    g_fPauseTime[MAX_TYPES][MAX_STYLES][2];
char g_sGhost[MAX_TYPES][MAX_STYLES][2][48];
    
float g_fStartTime[MAX_TYPES][MAX_STYLES][2];

// Cvars
ConVar g_hGhostClanTag[MAX_TYPES][MAX_STYLES],
    g_hGhostWeapon[MAX_TYPES][MAX_STYLES],
    g_hGhostStartPauseTime,
    g_hGhostEndPauseTime;
    
// Weapon control
bool g_bNewWeapon;

ConVar g_hBotQuota;

float g_fCurrentFrame[MAXPLAYERS+1][5];
int g_CurrentFrame[MAXPLAYERS+1];
int g_CurrentButtons[MAXPLAYERS+1];
bool g_bLateLoad = false;
    
public void OnPluginStart()
{    
    /*
    decl String:sGame[64];
    GetGameFolderName(sGame, sizeof(sGame));
    
    if(StrEqual(sGame, "cstrike"))
        g_GameType = GameType_CSS;
    else if(StrEqual(sGame, "csgo"))
        g_GameType = GameType_CSGO;
    else
        SetFailState("This timer does not support this game (%s)", sGame);
        */
    
    // Connect to the database
    DB_Connect();
    
    g_hGhostStartPauseTime = CreateConVar("timer_ghoststartpause", "5.0", "How long the ghost will pause before starting its run.");
    g_hGhostEndPauseTime   = CreateConVar("timer_ghostendpause", "2.0", "How long the ghost will pause after it finishes its run.");
    g_hBotQuota = FindConVar("bot_quota");
    
    AutoExecConfig(true, "ghost", "timer");
    
    // Events
    HookEvent("player_spawn", Event_PlayerSpawn);
    
    // Create admin command that deletes the ghost
    RegAdminCmd("sm_deleteghost", SM_DeleteGhost, ADMFLAG_CHEATS, "Deletes the ghost.");
    
    ConVar hBotDontShoot = FindConVar("bot_dont_shoot");
    hBotDontShoot.Flags = hBotDontShoot.Flags & ~FCVAR_CHEAT;
    
    if(g_bLateLoad)
    {
        OnStylesLoaded();
        OnMapStart();
        LoadGhost();
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{    
    CreateNative("GetBotInfo", Native_GetBotInfo);
    
    RegPluginLibrary("ghost");
    
    g_bLateLoad = late;
    
    return APLRes_Success;
}

public void OnStylesLoaded()
{
    char sTypeAbbr[8];
    char sType[16];
    char sStyleAbbr[8];
    char sStyle[16];
    char sTypeStyleAbbr[24];
    char sCvar[32];
    char sDesc[128];
    char sValue[32];
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        GetTypeName(Type, sType, sizeof(sType));
        GetTypeAbbr(Type, sTypeAbbr, sizeof(sTypeAbbr));
        
        for(int Style; Style < MAX_STYLES; Style++)
        {
            // Don't create cvars for styles on bonus except normal style
            if(Style_CanUseReplay(Style, Type))
            {
                GetStyleName(Style, sStyle, sizeof(sStyle));
                GetStyleAbbr(Style, sStyleAbbr, sizeof(sStyleAbbr));
                
                Format(sTypeStyleAbbr, sizeof(sTypeStyleAbbr), "%s%s", sTypeAbbr, sStyleAbbr);
                StringToUpper(sTypeStyleAbbr);
                
                Format(sCvar, sizeof(sCvar), "timer_ghosttag_%s%s", sTypeAbbr, sStyleAbbr);
                Format(sDesc, sizeof(sDesc), "The replay bot's clan tag for the scoreboard (%s style on %s timer)", sStyle, sType);
                Format(sValue, sizeof(sValue), "Ghost :: %s", sTypeStyleAbbr);
                g_hGhostClanTag[Type][Style] = CreateConVar(sCvar, sValue, sDesc);
                
                Format(sCvar, sizeof(sCvar), "timer_ghostweapon_%s%s", sTypeAbbr, sStyleAbbr);
                Format(sDesc, sizeof(sDesc), "The weapon the replay bot will always use (%s style on %s timer)", sStyle, sType);
                g_hGhostWeapon[Type][Style] = CreateConVar(sCvar, "weapon_glock", sDesc, 0, true, 0.0, true, 1.0);
                
                g_hGhostWeapon[Type][Style].AddChangeHook(OnGhostWeaponChanged);
                
                if(g_hGhost[Type][Style][0] == INVALID_HANDLE || !g_hGhost[Type][Style][0])
                    g_hGhost[Type][Style][0] = new ArrayList(6);
                    
                if(Type != TIMER_SOLOBONUS)
                {
                    if(g_hGhost[Type][Style][1] == INVALID_HANDLE || !g_hGhost[Type][Style][1])
                        g_hGhost[Type][Style][1] = new ArrayList(6);
                }
            }
        }
    }
}

public int Native_GetBotInfo(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    if(!IsFakeClient(client))
        return false;
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            if(Style_CanUseReplay(Style, Type))
            {
                int maxghost = 2;
                if(Type == TIMER_SOLOBONUS)
                {
                    maxghost = 1;
                }
                for(int ghostnum; ghostnum < maxghost; ghostnum++)
                {    
                    if(g_Ghost[Type][Style][ghostnum] == client)
                    {
                        SetNativeCellRef(2, Type);
                        SetNativeCellRef(3, Style);
                    
                        return true;
                    }
                }
            }
        }
    }
    
    return false;
}

public void OnMapStart()
{    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            if(Style_CanUseReplay(Style, Type))
            {
                g_hGhost[Type][Style][0].Clear();
                if(Type != TIMER_SOLOBONUS)
                {
                    g_hGhost[Type][Style][1].Clear();
                }
                
                g_iGhostSize[Type][Style][0] = 0;
                g_iGhostSize[Type][Style][1] = 0;
                g_Ghost[Type][Style][0]  = 0;
                g_Ghost[Type][Style][1]  = 0;
                g_fGhostTime[Type][Style][0] = 0.0;
                g_fGhostTime[Type][Style][1] = 0.0;
                g_GhostFrame[Type][Style][0] = 0;
                g_GhostFrame[Type][Style][1] = 0;
                g_GhostPlayerID[Type][Style][0] = 0;
                g_GhostPlayerID[Type][Style][1] = 0;
                g_bGhostLoaded[Type][Style] = false;
                
                char sNameStart[64];
                if(Type == TIMER_MAIN)
                {
                    GetStyleName(Style, sNameStart, sizeof(sNameStart));
                }
                else
                {
                    GetTypeName(Type, sNameStart, sizeof(sNameStart));
                }
                
                FormatEx(g_sGhost[Type][Style][0], sizeof(g_sGhost[][][]), "%s - No Record", sNameStart);
                FormatEx(g_sGhost[Type][Style][1], sizeof(g_sGhost[][][]), "%s - No Record", sNameStart);
            }
        }
    }
    
    // Get map name to use the database
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    
    // Check path to folder that holds all the ghost data
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes");
    if(!DirExists(sPath))
    {
        // Create ghost data directory if it doesn't exist
        CreateDirectory(sPath, 511);
    }
    
    // Timer to check ghost things such as clan tag
    CreateTimer(0.1, GhostCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnZonesLoaded()
{
    LoadGhost();
}

public void OnConfigsExecuted()
{
    CalculateBotQuota();
}

public void OnUseGhostChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    CalculateBotQuota();
}

public void OnGhostWeaponChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            if(0 < g_Ghost[Type][Style][0] <= MaxClients && Style_CanUseReplay(Style, Type))
            {
                if(g_hGhostWeapon[Type][Style] == convar)
                {
                    CheckWeapons(Type, Style, 0);
                }
            }
            else if(0 < g_Ghost[Type][Style][1] <= MaxClients && Style_CanUseReplay(Style, Type))
            {
                if(g_hGhostWeapon[Type][Style] == convar)
                {
                    CheckWeapons(Type, Style, 1);
                }
            }
        }
    }
}

public void OnMapEnd()
{
    // Remove ghost to get a clean start next map
    ServerCommand("bot_kick all");
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            g_Ghost[Type][Style][0] = 0;
            g_Ghost[Type][Style][1] = 0;
        }
    }
}

public void OnClientPutInServer(int client)
{
    if(IsFakeClient(client))
    {
        SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
    }
    else
    {
        // Reset player recorded movement
        if(g_bUsedFrame[client] == false)
        {
            g_hFrame[client]     = new ArrayList(6);
            g_bUsedFrame[client] = true;
        }
        else
        {
            g_hFrame[client].Clear();
        }
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if(StrContains(classname, "trigger_", false) != -1)
    {
        SDKHook(entity, SDKHook_StartTouch, OnTrigger);
        SDKHook(entity, SDKHook_EndTouch, OnTrigger);
        SDKHook(entity, SDKHook_Touch, OnTrigger);
    }
}
 
public Action OnTrigger(int entity, int other)
{
    if(0 < other <= MaxClients)
    {
        if(IsClientConnected(other))
        {
            if(IsFakeClient(other))
            {
                return Plugin_Handled;
            }
        }
    }
   
    return Plugin_Continue;
}

public bool OnClientConnect(int client, char[] rejectmsg, int maxlen)
{
    // Find out if it's the bot added from another time
    if(IsFakeClient(client) && !IsClientSourceTV(client))
    {
        for(int Type; Type < MAX_TYPES; Type++)
        {
            for(int Style; Style < MAX_STYLES; Style++)
            {
                int maxghost = 2;
                if(Type == TIMER_SOLOBONUS)
                {
                    maxghost = 1;
                }
                for(int ghostnum; ghostnum < maxghost; ghostnum++)
                {
                    if(g_Ghost[Type][Style][ghostnum] == 0)
                    {
                        if(Style_CanUseReplay(Style, Type))
                        {
                            g_Ghost[Type][Style][ghostnum] = client;
                            CS_SwitchTeam(client, 2);
                            //CS_RespawnPlayer(client);
                            
                            return true;
                        }
                    }
                }
            }
        }
    }
    
    return true;
}

public void OnClientDisconnect(int client)
{
    // Prevent players from becoming the ghost.
    if(IsFakeClient(client))
    {
        for(int Type; Type < MAX_TYPES; Type++)
        {
            for(int Style; Style < MAX_STYLES; Style++)
            {
                if(Style_CanUseReplay(Style, Type))
                {
                    int maxghost = 2;
                    if(Type == TIMER_SOLOBONUS)
                    {
                        maxghost = 1;
                    }
                    for(int ghostnum; ghostnum < maxghost; ghostnum++)
                    {
                        if(client == g_Ghost[Type][Style][ghostnum])
                        {
                            g_Ghost[Type][Style][ghostnum] = 0;
                            break;
                        }
                    }
                }
            }
        }
    }
}

public void OnTimesDeleted(int Type, int Style, int RecordOne, int RecordTwo, ArrayList Times)
{
    int iSize = Times.Length;
    
    if(RecordTwo <= iSize)
    {
        for(int idx = RecordOne - 1; idx < RecordTwo; idx++)
        {
            if(Times.Get(idx) == g_GhostPlayerID[Type][Style][0] || Times.Get(idx) == g_GhostPlayerID[Type][Style][1])
            {
                DeleteGhost(Type, Style);
                break;
            }
        }
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if(IsFakeClient(client))
    {
        for(int Type; Type < MAX_TYPES; Type++)
        {
            for(int Style; Style < MAX_STYLES; Style++)
            {
                if(Style_CanUseReplay(Style, Type))
                {
                    int maxghost = 2;
                    if(Type == TIMER_SOLOBONUS)
                    {
                        maxghost = 1;
                    }
                    for(int ghostnum; ghostnum < maxghost; ghostnum++)
                    {
                        if(g_Ghost[Type][Style][ghostnum] == client)
                        {
                            CreateTimer(0.1, Timer_CheckWeapons, client);
                        }
                    }
                }
            }
        }
    }
}

public Action Timer_CheckWeapons(Handle timer, any client)
{
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            if(Style_CanUseReplay(Style, Type))
            {
                int maxghost = 2;
                if(Type == TIMER_SOLOBONUS)
                {
                    maxghost = 1;
                }
                for(int ghostnum; ghostnum < maxghost; ghostnum++)
                {
                    if(g_Ghost[Type][Style][ghostnum] == client)
                    {
                        CheckWeapons(Type, Style, ghostnum);
                    }
                }
            }
        }
    }
}

void CheckWeapons(int Type, int Style, int ghostnum)
{
    for(int i = 0; i < 8; i++)
    {
        FakeClientCommand(g_Ghost[Type][Style][ghostnum], "drop");
        
        char sWeapon[32];
        if(g_hGhostWeapon[Type][Style] != INVALID_HANDLE)
        {
            g_hGhostWeapon[Type][Style].GetString(sWeapon, sizeof(sWeapon));
        
            g_bNewWeapon = true;
            GivePlayerItem(g_Ghost[Type][Style][ghostnum], sWeapon);
        }
    }
}

public Action SM_DeleteGhost(int client, int args)
{
    OpenDeleteGhostMenu(client);
    
    return Plugin_Handled;
}

void OpenDeleteGhostMenu(int client)
{
    Menu menu = new Menu(Menu_DeleteGhost);
    
    menu.SetTitle("Select ghost to delete");
    
    char sDisplay[64];
    char sType[32];
    char sStyle[32];
    char sInfo[8];
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        GetTypeName(Type, sType, sizeof(sType));
        
        for(int Style; Style < MAX_STYLES; Style++)
        {
            if(Style_CanUseReplay(Style, Type))
            {
                GetStyleName(Style, sStyle, sizeof(sStyle));
                FormatEx(sDisplay, sizeof(sDisplay), "%s (%s)", sType, sStyle);
                Format(sInfo, sizeof(sInfo), "%d;%d", Type, Style);
                menu.AddItem(sInfo, sDisplay);
            }
        }
    }
    
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_DeleteGhost(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[16];
        char sTypeStyle[2][8];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrContains(info, ";") != -1)
        {
            ExplodeString(info, ";", sTypeStyle, 2, 8);
            
            DeleteGhost(StringToInt(sTypeStyle[0]), StringToInt(sTypeStyle[1]));
            
            LogMessage("%L deleted the ghost", param1);
        }
    }
    else if (action == MenuAction_End)
        delete menu;
}

void AssignToReplay(int client)
{
    bool bAssigned;
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            int maxghost = 2;
            if(Type == TIMER_SOLOBONUS)
            {
                maxghost = 1;
            }
            for(int ghostnum; ghostnum < maxghost; ghostnum++)
            {
                if(g_Ghost[Type][Style][ghostnum] == 0 || !IsClientConnected(g_Ghost[Type][Style][ghostnum]) || !IsFakeClient(g_Ghost[Type][Style][ghostnum]))
                {
                    if(Style_CanUseReplay(Style, Type))
                    {
                        g_Ghost[Type][Style][ghostnum] = client;
                        CS_SwitchTeam(client, 2);
                        //CS_RespawnPlayer(client);
                        bAssigned = true;
                        break;
                    }
                }
            }
        }
        
        if(bAssigned == true)
        {
            break;
        }
    }
    
    if(bAssigned == false)
    {
        KickClient(client);
    }
}

public Action GhostCheck(Handle timer, any data)
{
    int iBotQuota = g_hBotQuota.IntValue;
    
    if(iBotQuota != g_iBotQuota)
        ServerCommand("bot_quota %d", g_iBotQuota);
    
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientConnected(client) && IsFakeClient(client) && !IsClientSourceTV(client))
        {
            bool bIsReplay;
            
            for(int Type; Type < MAX_TYPES; Type++)
            {
                for(int Style; Style < MAX_STYLES; Style++)
                {
                    int maxghost = 2;
                    if(Type == TIMER_SOLOBONUS)
                    {
                        maxghost = 1;
                    }
                    for(int ghostnum; ghostnum < maxghost; ghostnum++)
                    {
                        if(client == g_Ghost[Type][Style][ghostnum])
                        {
                            bIsReplay = true;
                            break;
                        }
                    }
                }
                
                if(bIsReplay == true)
                {
                    break;
                }
            }
            
            if(!bIsReplay)
            {
                AssignToReplay(client);
            }
        }
    }
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            if(Style_CanUseReplay(Style, Type))
            {
                int maxghost = 2;
                if(Type == TIMER_SOLOBONUS)
                {
                    maxghost = 1;
                }
                for(int ghostnum; ghostnum < maxghost; ghostnum++)
                {    
                    if(g_Ghost[Type][Style][ghostnum] != 0)
                    {
                        if(IsClientInGame(g_Ghost[Type][Style][ghostnum]))
                        {
                            SetEntProp(g_Ghost[Type][Style][ghostnum], Prop_Data, "m_iFrags", 0);
                            SetEntProp(g_Ghost[Type][Style][ghostnum], Prop_Data, "m_iDeaths", 0);
                    
                            // Check clan tag
                            char sClanTag[64];
                            CS_GetClientClanTag(g_Ghost[Type][Style][ghostnum], sClanTag, sizeof(sClanTag));
                        
                            if(!StrEqual("Replay -", sClanTag))
                            {
                                CS_SetClientClanTag(g_Ghost[Type][Style][ghostnum], "Replay -");
                            }    
                        
                            // Check name
                            if(strlen(g_sGhost[Type][Style][ghostnum]) > 0)
                            {
                                char sGhostname[48];
                                GetClientName(g_Ghost[Type][Style][ghostnum], sGhostname, sizeof(sGhostname));
                                if(!StrEqual(sGhostname, g_sGhost[Type][Style][ghostnum]))
                                {
                                    SetClientInfo(g_Ghost[Type][Style][ghostnum], "name", g_sGhost[Type][Style][ghostnum]);
                                }
                            }
                        
                            // Check if ghost is dead
                            if(g_bReplayFileExists[Type][Style])
                            {
                                if(!IsPlayerAlive(g_Ghost[Type][Style][ghostnum]))
                                {
                                    CS_RespawnPlayer(g_Ghost[Type][Style][ghostnum]);
                                }
                            }
                            else if(!g_bReplayFileExists[Type][Style])
                            {
                                if(IsPlayerAlive(g_Ghost[Type][Style][ghostnum]))
                                {
                                    FakeClientCommand(g_Ghost[Type][Style][ghostnum], "kill");
                                }
                            }
                        
                        
                            // Display ghost's current time to spectators
                            int iSize = g_hGhost[Type][Style][ghostnum].Length;
                            for(int client = 1; client <= MaxClients; client++)
                            {
                                if(IsClientInGame(client))
                                {
                                    if(!IsPlayerAlive(client))
                                    {
                                        int target      = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
                                        int ObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
                                    
                                        if(target == g_Ghost[Type][Style][ghostnum] && (ObserverMode == 4 || ObserverMode == 5))
                                        {
                                            if(!g_GhostPaused[Type][Style][ghostnum] && (0 < g_GhostFrame[Type][Style][ghostnum] < iSize))
                                            {
                                                float time = GetEngineTime() - g_fStartTime[Type][Style][ghostnum];
                                                char sTime[32];
                                                FormatPlayerTime(time, sTime, sizeof(sTime), false, 0);
                                            
                                                char sName[MAX_NAME_LENGTH];
                                                GetNameFromPlayerID(g_GhostPlayerID[Type][Style][ghostnum], sName, sizeof(sName));
                                            
                                                float fVel = GetClientVelocity(g_Ghost[Type][Style][ghostnum], true, true, false);
                                            
                                                PrintHintText(client, "[Replay]\n%s\n%s\nSpeed: %d", sName, sTime, RoundToFloor(fVel));
                                            }
                                        }
                                    }
                                }
                            }
                        
                            int weaponIndex = GetEntPropEnt(g_Ghost[Type][Style][ghostnum], Prop_Send, "m_hActiveWeapon");
                        
                            if(weaponIndex != -1)
                            {
                                int ammo = Weapon_GetPrimaryClip(weaponIndex);
                                
                                if(ammo < 1)
                                    Weapon_SetPrimaryClip(weaponIndex, 9999);
                            }
                        }
                    }
                }
            }
        }
    }
}

public Action Hook_WeaponCanUse(int client, int weapon)
{
    char sWeapon[32]; 
    GetEdictClassname(weapon, sWeapon, sizeof(sWeapon)); 
    
    if (g_bNewWeapon == false)
        return Plugin_Handled;
    
    g_bNewWeapon = false;
    
    return Plugin_Continue;
}

void CalculateBotQuota()
{
    g_iBotQuota = 0;
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style<MAX_STYLES; Style++)
        {
            if(Style_CanUseReplay(Style, Type))
            {
                if(Type == TIMER_SOLOBONUS)
                {
                    g_iBotQuota++;
                    
                    if(!g_Ghost[Type][Style][0])
                        ServerCommand("bot_add");
                }
                else
                {
                    g_iBotQuota += 2;
                    
                    if(!g_Ghost[Type][Style][0])
                        ServerCommand("bot_add");
                        
                    if(!g_Ghost[Type][Style][1])
                        ServerCommand("bot_add");
                }
            }
            else
            {
                if(g_Ghost[Type][Style][0])
                    KickClient(g_Ghost[Type][Style][0]);
                    
                if(g_Ghost[Type][Style][1])
                    KickClient(g_Ghost[Type][Style][1]);
            }
        }
    }
    
    ConVar hBotQuota = FindConVar("bot_quota");
    int iBotQuota = hBotQuota.IntValue;
    
    if(iBotQuota != g_iBotQuota)
        ServerCommand("bot_quota %d", g_iBotQuota);
    
    delete hBotQuota;
}

void LoadGhost()
{
    // Rename old version files
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s.rec", g_sMapName);
    if(FileExists(sPath))
    {
        char sPathTwo[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, sPathTwo, sizeof(sPathTwo), "data/btimes/%s_0_0.rec", g_sMapName);
        RenameFile(sPathTwo, sPath);
    }
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            int maxghost = 2;
            if(Type == TIMER_SOLOBONUS)
            {
                maxghost = 1;
            }
            for(int ghostnum; ghostnum < maxghost; ghostnum++)
            {
                if(Style_CanUseReplay(Style, Type))
                {
                    g_fGhostTime[Type][Style][ghostnum]    = 0.0;
                    g_GhostPlayerID[Type][Style][ghostnum] = 0;
                
                    BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s_%d_%d_%d.rec", g_sMapName, Type, Style, ghostnum);
                
                    if(FileExists(sPath))
                    {
                        g_bReplayFileExists[Type][Style] = true;
                        // Open file for reading
                        File hFile = OpenFile(sPath, "rb");
                        
                        // Load all data into the ghost handle
                        int Frame[6];
                        int iSize = 0;
                        
                        ReadFileCell(hFile, g_GhostPlayerID[Type][Style][ghostnum], 4);
                        ReadFileCell(hFile, view_as<int>(g_fGhostTime[Type][Style][ghostnum]), 4);
                    
                        while(!hFile.EndOfFile())
                        {
                            hFile.Read(Frame, 6, 4);
                            iSize = g_hGhost[Type][Style][ghostnum].Length + 1;
                            g_hGhost[Type][Style][ghostnum].Resize(iSize);
                            g_hGhost[Type][Style][ghostnum].Set(iSize - 1, Frame[0], 0);
                            g_hGhost[Type][Style][ghostnum].Set(iSize - 1, Frame[1], 1);
                            g_hGhost[Type][Style][ghostnum].Set(iSize - 1, Frame[2], 2);
                            g_hGhost[Type][Style][ghostnum].Set(iSize - 1, Frame[3], 3);
                            g_hGhost[Type][Style][ghostnum].Set(iSize - 1, Frame[4], 4);
                            g_hGhost[Type][Style][ghostnum].Set(iSize - 1, Frame[5], 5);
                        }
                        delete hFile;
                    
                        g_bGhostLoadedOnce[Type][Style] = true;
                    
                        DataPack pack = new DataPack();
                        pack.WriteCell(Type);
                        pack.WriteCell(Style);
                        pack.WriteCell(ghostnum);
                        pack.WriteString(g_sMapName);
                    
                        // Query for name/time of player the ghost is following the path of
                        char query[512];
                        Format(query, sizeof(query), "SELECT t2.User, t1.Time FROM times AS t1, players AS t2 WHERE t1.PlayerID=t2.PlayerID AND t1.PlayerID=%d AND t1.MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND t1.Type=%d AND t1.Style=%d",
                            g_GhostPlayerID[Type][Style][ghostnum],
                            g_sMapName,
                            Type,
                            Style);
                        g_DB.Query(LoadGhost_Callback, query, pack);
                    
                    }
                    else
                    {
                        g_bReplayFileExists[Type][Style] = false;
                        g_bGhostLoaded[Type][Style] = true;
                    }
                    g_iGhostSize[Type][Style][ghostnum] = g_hGhost[Type][Style][ghostnum].Length;
                }
            }
        }
    }
}

public void LoadGhost_Callback(Database db, DBResultSet results, char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        
        int Type  = data.ReadCell();
        int Style = data.ReadCell();
        int ghostnum = data.ReadCell();
        
        char sMapName[64];
        data.ReadString(sMapName, sizeof(sMapName));
        
        if(StrEqual(g_sMapName, sMapName))
        {
            if(results.RowCount != 0)
            {
                results.FetchRow();
                
                char sName[20];
                results.FetchString(0, sName, sizeof(sName));
                
                if(g_fGhostTime[Type][Style][ghostnum] == 0.0)
                    g_fGhostTime[Type][Style][ghostnum] = results.FetchFloat(1);
                
                char sNameStart[MAX_NAME_LENGTH];
                char sTime[32];
                FormatPlayerTime(g_fGhostTime[Type][Style][ghostnum], sTime, sizeof(sTime), false, 0);
                if(Type == TIMER_MAIN)
                {
                    GetStyleName(Style, sNameStart, sizeof(sNameStart));
                }
                else
                {
                    GetTypeName(Type, sNameStart, sizeof(sNameStart));
                }
                
                FormatEx(g_sGhost[Type][Style][ghostnum], sizeof(g_sGhost[][][]), "%s - %s", sNameStart, sTime);
            }
            
            g_bGhostLoaded[Type][Style] = true;
        }
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

public void OnTimerStart_Post(int client, int Type, int Style)
{
    g_CurrentFrame[client] = 0;
    
    // Reset saved ghost data
    g_hFrame[client].Clear();
}

public void OnTimerFinished_Post(int client, float Time, int Type, int Style, bool NewTime, int OldPosition, int NewPosition)
{
    if(g_bGhostLoaded[Type][Style] == true)
    {
        if(Style_CanReplaySave(Style, Type))
        {
            if(Time < g_fGhostTime[Type][Style][0] || g_fGhostTime[Type][Style][0] == 0.0)
            {
                SaveGhost(client, Time, Type, Style, 0);
                
                if(Type != TIMER_SOLOBONUS)
                    SaveGhost(Timer_GetPartner(client), Time, Type, Style, 1);
            }
        }
    }
}

void SaveGhost(int client, float Time, int Type, int Style, int ghostnum)
{
    g_fGhostTime[Type][Style][ghostnum] = Time;
    
    g_GhostPlayerID[Type][Style][ghostnum] = GetPlayerID(client);
    
    // Delete existing ghost for the map
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s_%d_%d_%d.rec", g_sMapName, Type, Style, ghostnum);
    if(FileExists(sPath))
    {
        DeleteFile(sPath);
    }
    
    // Open a file for writing
    File hFile = OpenFile(sPath, "wb");
    
    // save playerid to file to grab name and time for later times map is played
    WriteFileCell(hFile, g_GhostPlayerID[Type][Style][ghostnum], 4);
    WriteFileCell(hFile, view_as<int>(Time), 4);
    
    int iSize = g_hFrame[client].Length;
    float data[5];
    int buttons, Frame[6];
    
    g_hGhost[Type][Style][ghostnum].Clear();
    for(int i=0; i<iSize; i++)
    {
        g_hFrame[client].GetArray(i, data, 5);
        g_hGhost[Type][Style][ghostnum].PushArray(data, 5);
        
        buttons = g_hFrame[client].Get(i, 5);
        g_hGhost[Type][Style][ghostnum].Set(i, buttons, 5);
        
        Frame[0] = view_as<int>(data[0]);
        Frame[1] = view_as<int>(data[1]);
        Frame[2] = view_as<int>(data[2]);
        Frame[3] = view_as<int>(data[3]);
        Frame[4] = view_as<int>(data[4]);
        Frame[5] = view_as<int>(buttons);
        
        hFile.Write(Frame, 6, 4);
    }
    delete hFile;
    
    g_iGhostSize[Type][Style][ghostnum] = g_hGhost[Type][Style][ghostnum].Length;
    g_GhostFrame[Type][Style][ghostnum] = 0;
    
    char sNameStart[MAX_NAME_LENGTH];
    char sTime[32];
    FormatPlayerTime(g_fGhostTime[Type][Style][ghostnum], sTime, sizeof(sTime), false, 0);
    if(Type == TIMER_MAIN)
    {
        GetStyleName(Style, sNameStart, sizeof(sNameStart));
    }
    else
    {
        GetTypeName(Type, sNameStart, sizeof(sNameStart));
    }
    
    FormatEx(g_sGhost[Type][Style][ghostnum], sizeof(g_sGhost[][][]), "%s - %s", sNameStart, sTime);
    
    g_bReplayFileExists[Type][Style] = true;
    
    if(g_Ghost[Type][Style][ghostnum] != 0)
    {
        if(!IsPlayerAlive(g_Ghost[Type][Style][ghostnum]))
        {
            CS_RespawnPlayer(g_Ghost[Type][Style][ghostnum]);
        }
    }
    
}

void DeleteGhost(int Type, int Style)
{
    int maxghost = 2;
    if(Type == TIMER_SOLOBONUS)
    {
        maxghost = 1;
    }
    for(int ghostnum; ghostnum < maxghost; ghostnum++)
    {    
        // delete map ghost file
        char sPath[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s_%d_%d_%d.rec", g_sMapName, Type, Style, ghostnum);
        if(FileExists(sPath))
            DeleteFile(sPath);
    
        // reset ghost
        if(g_Ghost[Type][Style][ghostnum] != 0)
        {
            g_fGhostTime[Type][Style][ghostnum] = 0.0;
            g_hGhost[Type][Style][ghostnum].Clear();
            char sNameStart[64];
            if(Type == TIMER_MAIN)
            {
                GetStyleName(Style, sNameStart, sizeof(sNameStart));
            }
            else
            {
                GetTypeName(Type, sNameStart, sizeof(sNameStart));
            }
        
            FormatEx(g_sGhost[Type][Style][ghostnum], sizeof(g_sGhost[][][]), "%s - No Record", sNameStart);
            //CS_RespawnPlayer(g_Ghost[Type][Style]);
            FakeClientCommand(g_Ghost[Type][Style][ghostnum], "kill");
        }
    
        g_bReplayFileExists[Type][Style] = false;
    }
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
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(IsPlayerAlive(client))
    {
        if(!IsFakeClient(client))
        {
            int Type = GetClientTimerType(client);
            int Style = GetClientStyle(client);
            if(IsBeingTimed(client, TIMER_ANY) && !IsTimerPaused(client) && Style_CanReplaySave(Style, Type))
            {
                // Record player movement data
                int iSize = g_hFrame[client].Length;
                
                if(Type != TIMER_SOLOBONUS)
                {
                    int partner = Timer_GetPartner(client);
                    int iDiff = 1;
                    
                    if (partner && IsValidEdict(partner))
                    {
                        if (g_CurrentFrame[partner] && g_CurrentFrame[partner] > iSize + 1)
                        {
                            iDiff = g_CurrentFrame[partner] - iSize + 1;
                        }
                    }
                    g_hFrame[client].Resize(iDiff + iSize);
                    if (iDiff > 1)
                    {
                        int i;
                        while (iDiff + -1 > i)
                        {
                            g_hFrame[client].Set(i + iSize, g_fCurrentFrame[client][0], 0);
                            g_hFrame[client].Set(i + iSize, g_fCurrentFrame[client][1], 1);
                            g_hFrame[client].Set(i + iSize, g_fCurrentFrame[client][2], 2);
                            g_hFrame[client].Set(i + iSize, g_fCurrentFrame[client][3], 3);
                            g_hFrame[client].Set(i + iSize, g_fCurrentFrame[client][4], 4);
                            g_hFrame[client].Set(i + iSize, g_CurrentButtons[client], 5);
                            i++;
                        }
                        iSize = iDiff + -1 + iSize;
                    }
                }
                else
                {
                    g_hFrame[client].Resize(iSize + 1);
                }
                
                float vPos[3];
                float vAng[3];
                Entity_GetAbsOrigin(client, vPos);
                GetClientEyeAngles(client, vAng);
                
                g_hFrame[client].Set(iSize, vPos[0], 0);
                g_hFrame[client].Set(iSize, vPos[1], 1);
                g_hFrame[client].Set(iSize, vPos[2], 2);
                g_hFrame[client].Set(iSize, vAng[0], 3);
                g_hFrame[client].Set(iSize, vAng[1], 4);
                g_hFrame[client].Set(iSize, buttons, 5);
                
                g_CurrentFrame[client] = iSize;
                g_fCurrentFrame[client][0] = vPos[0];
                g_fCurrentFrame[client][1] = vPos[1];
                g_fCurrentFrame[client][2] = vPos[2];
                g_fCurrentFrame[client][3] = vAng[0];
                g_fCurrentFrame[client][4] = vAng[1];
                g_CurrentButtons[client] = buttons;
            }
        }
        else
        {
            for(int Type; Type < MAX_TYPES; Type++)
            {
                for(int Style; Style < MAX_STYLES; Style++)
                {
                    int maxghost = 2;
                    if(Type == TIMER_SOLOBONUS)
                    {
                        maxghost = 1;
                    }
                    for(int ghostnum; ghostnum < maxghost; ghostnum++)
                    {    
                        if(client == g_Ghost[Type][Style][ghostnum] && g_hGhost[Type][Style][ghostnum] != INVALID_HANDLE)
                        {
                            float vPos[3];
                            float vAng[3];
                            if(g_GhostFrame[Type][Style][ghostnum] == 1 && g_iGhostSize[Type][Style][ghostnum] != 0)
                            {
                            
                                vPos[0] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 0);
                                vPos[1] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 1);
                                vPos[2] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 2);
                                vAng[0] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 3);
                                vAng[1] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 4);
                                TeleportEntity(g_Ghost[Type][Style][ghostnum], vPos, vAng, view_as<float>({0.0, 0.0, 0.0}));
                            
                                if(ghostnum == 0)
                                {
                                    g_fStartTime[Type][Style][ghostnum] = GetEngineTime();
                                    g_fStartTime[Type][Style][1] = GetEngineTime();
                                    
                                    if(g_GhostPaused[Type][Style][ghostnum] == false)
                                    {
                                        g_GhostPaused[Type][Style][ghostnum] = true;
                                        g_GhostPaused[Type][Style][1] = true;
                                        g_fPauseTime[Type][Style][ghostnum]  = GetEngineTime();
                                    }
                            
                                    if(GetEngineTime() > g_fPauseTime[Type][Style][ghostnum] + g_hGhostStartPauseTime.FloatValue)
                                    {
                                        g_GhostPaused[Type][Style][ghostnum] = false;
                                        g_GhostPaused[Type][Style][1] = false;
                                        g_GhostFrame[Type][Style][ghostnum]++;
                                        g_GhostFrame[Type][Style][1]++;
                                    }
                                }
                            }
                            else if(g_iGhostSize[Type][Style][ghostnum] != 0 && g_GhostFrame[Type][Style][ghostnum] >= (g_iGhostSize[Type][Style][ghostnum] - 1))
                            {
                                g_GhostFrame[Type][Style][ghostnum] = g_iGhostSize[Type][Style][ghostnum] - 1;
                                
                                vPos[0] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 0);
                                vPos[1] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 1);
                                vPos[2] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 2);
                                vAng[0] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 3);
                                vAng[1] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 4);
                            
                                TeleportEntity(g_Ghost[Type][Style][ghostnum], vPos, vAng, view_as<float>({0.0, 0.0, 0.0}));
                            
                                if(ghostnum == 0)
                                {
                                    if(g_GhostPaused[Type][Style][ghostnum] == false)
                                    {                    
                                        g_GhostPaused[Type][Style][ghostnum] = true;
                                        g_GhostPaused[Type][Style][1] = true;
                                        g_fPauseTime[Type][Style][ghostnum]  = GetEngineTime();
                                    }
                            
                                    if(GetEngineTime() > g_fPauseTime[Type][Style][ghostnum] + g_hGhostEndPauseTime.FloatValue)
                                    {
                                        g_GhostPaused[Type][Style][ghostnum] = false;
                                        g_GhostPaused[Type][Style][1] = false;
                                        g_GhostFrame[Type][Style][ghostnum] = 1;
                                        g_GhostFrame[Type][Style][1] = 1;
                                    }
                                }
                            }
                            else if(g_GhostFrame[Type][Style][ghostnum] > 0)
                            {
                                float vPos2[3];
                                Entity_GetAbsOrigin(client, vPos2);
                            
                                vPos[0] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 0);
                                vPos[1] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 1);
                                vPos[2] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 2);
                                vAng[0] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 3);
                                vAng[1] = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 4);
                                buttons = g_hGhost[Type][Style][ghostnum].Get(g_GhostFrame[Type][Style][ghostnum], 5);
                            
                                if (buttons & IN_USE)
                                {
                                    buttons = buttons & ~IN_USE;
                                }
                                
                                if (buttons & IN_ATTACK)
                                {
                                    buttons = buttons & ~IN_ATTACK;
                                }
                            
                                // Get the new velocity from the the 2 points
                                float vVel[3];
                                MakeVectorFromPoints(vPos2, vPos, vVel);
                                ScaleVector(vVel, 100.0);
                            
                                TeleportEntity(g_Ghost[Type][Style][ghostnum], NULL_VECTOR, vAng, vVel);
                            
                                if(GetEntityFlags(g_Ghost[Type][Style][ghostnum]) & FL_ONGROUND)
                                {
                                    MoveType movetype = MOVETYPE_WALK;
                                    if(GetVectorLength(vVel) > 300.0)
                                    {
                                        TR_TraceRay(vPos, vPos2, MASK_PLAYERSOLID, RayType_EndPoint);
                                        if(TR_DidHit())
                                        {
                                            movetype = MOVETYPE_NOCLIP;
                                        }
                                        
                                    }
                                    SetEntityMoveType(g_Ghost[Type][Style][ghostnum], movetype);
                                }
                                else
                                    SetEntityMoveType(g_Ghost[Type][Style][ghostnum], MOVETYPE_NOCLIP);
                            
                                if(ghostnum == 0)
                                {
                                    g_GhostFrame[Type][Style][ghostnum]++;
                                    g_GhostFrame[Type][Style][1]++;
                                }
                            }
                            //This should only run the first time a ghost is loaded per map
                            else if(g_GhostFrame[Type][Style][ghostnum] == 0 && g_iGhostSize[Type][Style][ghostnum] > 0)
                                g_GhostFrame[Type][Style][ghostnum]++;
                        
                            if(g_GhostPaused[Type][Style][ghostnum] == true)
                            {
                                if(GetEntityMoveType(g_Ghost[Type][Style][ghostnum]) != MOVETYPE_NONE)
                                {
                                    SetEntityMoveType(g_Ghost[Type][Style][ghostnum], MOVETYPE_NONE);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return Plugin_Changed;
}
