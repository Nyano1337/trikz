#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = 
{
    name = "[bTimes] Zones",
    author = "blacky",
    description = "Used to create map zones",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <smlib/entities>
#include <bTimes-timer>
#include <bTimes-random>
#include <bTimes-zones>
#include <bTimes-teams>

#pragma newdecls required

enum
{
    GameType_CSS,
    GameType_CSGO
};

int g_GameType;

Database g_DB;
ArrayList g_MapList;
char g_sMapName[64];
float g_fSpawnPos[3];
int g_TotalZoneAllMaps[ZONE_COUNT];
    
bool g_bFinishedFirst[MAXPLAYERS+1];

// Zone properties
enum struct Properties
{
    int Max;
    int Count;
    int Entity[64];
    bool Ready[64];
    int RowID[64];
    int Flags[64];
    bool Replaceable;
    bool TriggerBased;
    char Name[64];
    int Color[4];
    int HaloIndex;
    int ModelIndex;
    int Offset;
}

Properties g_Properties[ZONE_COUNT]; // Properties for each type of zone

// Zone setup
enum struct Setup
{
    bool InZonesMenu;
    bool InSetFlagsMenu;
    int CurrentZone;
    Handle SetupTimer;
    bool Snapping;
    int GridSnap;
    bool ViewAnticheats;
}

Setup g_Setup[MAXPLAYERS + 1];

int g_Entities_ZoneType[2048] = {-1, ...}, // For faster lookup of zone type by entity number
    g_Entities_ZoneNumber[2048] = {-1, ...}, // For faster lookup of zone number by entity number
    g_TotalZoneCount;
float g_Zones[ZONE_COUNT][64][8][3]; // Zones that have been created
    
bool g_bInside[MAXPLAYERS + 1][ZONE_COUNT][64];

int g_SnapModelIndex,
    g_SnapHaloIndex;
    
// Zone drawing
int g_Drawing_Zone,
    g_Drawing_ZoneNumber;

// Cvars
ConVar g_hZoneColor[ZONE_COUNT],
    g_hZoneOffset[ZONE_COUNT],
    g_hZoneTexture[ZONE_COUNT],
    g_hZoneTrigger[ZONE_COUNT];
    
// Forwards
Handle g_fwdOnZonesLoaded,
    g_fwdOnZoneStartTouch,
    g_fwdOnZoneEndTouch;
    
// Chat
char g_msg_start[128],
    g_msg_varcol[128],
    g_msg_textcol[128];

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
    
    // Connect to database
    DB_Connect();
    
    // Cvars
    g_hZoneColor[MAIN_START]  = CreateConVar("timer_mainstart_color", "0 255 0 255", "Set the main start zone's RGBA color");
    g_hZoneColor[MAIN_END]    = CreateConVar("timer_mainend_color", "255 0 0 255", "Set the main end zone's RGBA color");
    g_hZoneColor[BONUS_START] = CreateConVar("timer_bonusstart_color", "0 255 0 255", "Set the bonus start zone's RGBA color");
    g_hZoneColor[BONUS_END]   = CreateConVar("timer_bonusend_color", "255 0 0 255", "Set the bonus end zone's RGBA color");
    g_hZoneColor[SOLOBONUS_START] = CreateConVar("timer_sbonusstart_color", "240 165 0 255", "Set the solo bonus start zone's RGBA color");
    g_hZoneColor[SOLOBONUS_END]   = CreateConVar("timer_sbonusend_color", "255 0 0 255", "Set the solo bonus end zone's RGBA color");
    g_hZoneColor[ANTICHEAT]   = CreateConVar("timer_ac_color", "255 255 0 255", "Set the anti-cheat zone's RGBA color");
    g_hZoneColor[FREESTYLE]   = CreateConVar("timer_fs_color", "0 0 255 255", "Set the freestyle zone's RGBA color");
    
    g_hZoneOffset[MAIN_START]  = CreateConVar("timer_mainstart_offset", "128", "Set the the default height for the main start zone.");
    g_hZoneOffset[MAIN_END]    = CreateConVar("timer_mainend_offset", "128", "Set the the default height for the main end zone.");
    g_hZoneOffset[BONUS_START] = CreateConVar("timer_bonusstart_offset", "128", "Set the the default height for the bonus start zone.");
    g_hZoneOffset[BONUS_END]   = CreateConVar("timer_bonusend_offset", "128", "Set the the default height for the bonus end zone.");
    g_hZoneOffset[SOLOBONUS_START] = CreateConVar("timer_sbonusstart_offset", "128", "Set the the default height for the solo bonus start zone.");
    g_hZoneOffset[SOLOBONUS_END]   = CreateConVar("timer_sbonusend_offset", "128", "Set the the default height for the solo bonus end zone.");
    g_hZoneOffset[ANTICHEAT]   = CreateConVar("timer_ac_offset", "0", "Set the the default height for the anti-cheat zone.");
    g_hZoneOffset[FREESTYLE]   = CreateConVar("timer_fs_offset", "0", "Set the the default height for the freestyle zone.");
    
    g_hZoneTexture[MAIN_START]  = CreateConVar("timer_mainstart_tex", "materials/sprites/trails/bluelightning", "Texture for main start zone. (Exclude the file types like .vmt/.vtf)");
    g_hZoneTexture[MAIN_END]    = CreateConVar("timer_mainend_tex", "materials/sprites/trails/bluelightning", "Texture for main end zone.");
    g_hZoneTexture[BONUS_START] = CreateConVar("timer_bonusstart_tex", "materials/sprites/trails/bluelightning", "Texture for bonus start zone.");
    g_hZoneTexture[BONUS_END]   = CreateConVar("timer_bonusend_tex", "materials/sprites/trails/bluelightning", "Texture for bonus end zone.");
    g_hZoneTexture[SOLOBONUS_START] = CreateConVar("timer_sbonusstart_tex", "materials/sprites/trails/bluelightning", "Texture for solo bonus start zone.");
    g_hZoneTexture[SOLOBONUS_END]   = CreateConVar("timer_sbonusend_tex", "materials/sprites/trails/bluelightning", "Texture for solo bonus end zone.");
    g_hZoneTexture[ANTICHEAT]   = CreateConVar("timer_ac_tex", "materials/sprites/trails/bluelightning", "Texture for anti-cheat zone.");
    g_hZoneTexture[FREESTYLE]   = CreateConVar("timer_fs_tex", "materials/sprites/trails/bluelightning", "Texture for freestyle zone.");
    
    g_hZoneTrigger[MAIN_START]  = CreateConVar("timer_mainstart_trigger", "1", "Main start zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
    g_hZoneTrigger[MAIN_END]    = CreateConVar("timer_mainend_trigger", "1", "Main end zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
    g_hZoneTrigger[BONUS_START] = CreateConVar("timer_bonusstart_trigger", "1", "Bonus start zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
    g_hZoneTrigger[BONUS_END]   = CreateConVar("timer_bonusend_trigger", "1", "Bonus end zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
    g_hZoneTrigger[SOLOBONUS_START] = CreateConVar("timer_sbonusstart_trigger", "1", "Solo bonus start zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
    g_hZoneTrigger[SOLOBONUS_END]   = CreateConVar("timer_sbonusend_trigger", "1", "Solo bonus end zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
    g_hZoneTrigger[ANTICHEAT]   = CreateConVar("timer_ac_trigger", "1", "Anti-cheat zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
    g_hZoneTrigger[FREESTYLE]   = CreateConVar("timer_fs_trigger", "1", "Freestyle zone trigger based (1) or uses old player detection method (0)", 0, true, 0.0, true, 1.0);
    
    AutoExecConfig(true, "zones", "timer");
    
    // Hook changes
    for(int Zone = 0; Zone < ZONE_COUNT; Zone++)
    {
        g_hZoneColor[Zone].AddChangeHook(OnZoneColorChanged);
        g_hZoneOffset[Zone].AddChangeHook(OnZoneOffsetChanged);    
        g_hZoneTrigger[Zone].AddChangeHook(OnZoneTriggerChanged);
    }
    
    // Admin Commands
    RegAdminCmd("sm_zones", SM_Zones, ADMFLAG_CHEATS, "Opens the zones menu.");
    
    // Player Commands
    RegConsoleCmdEx("sm_b", SM_B, "Teleports you to the bonus area");
    RegConsoleCmdEx("sm_bonus", SM_B, "Teleports you to the bonus area");
    RegConsoleCmdEx("sm_br", SM_B, "Teleports you to the bonus area");
    RegConsoleCmdEx("sm_sb", SM_SB, "Teleports you to the solo bonus area");
    RegConsoleCmdEx("sm_sbonus", SM_SB, "Teleports you to the solo bonus area");
    RegConsoleCmdEx("sm_sbr", SM_SB, "Teleports you to the solo bonus area");
    RegConsoleCmdEx("sm_r", SM_R, "Teleports you to the starting zone");
    RegConsoleCmdEx("sm_restart", SM_R, "Teleports you to the starting zone");
    RegConsoleCmdEx("sm_respawn", SM_R, "Teleports you to the starting zone");
    RegConsoleCmdEx("sm_start", SM_R, "Teleports you to the starting zone");
    RegConsoleCmdEx("sm_end", SM_End, "Teleports your to the end zone");
    RegConsoleCmdEx("sm_endb", SM_EndB, "Teleports you to the bonus end zone");
    RegConsoleCmdEx("sm_endsb", SM_EndSB, "Teleports you to the solo bonus end zone");
    RegConsoleCmdEx("sm_showac", SM_ShowAC, "Toggles anticheats being visible");
    RegConsoleCmdEx("sm_showacs", SM_ShowAC, "Toggles anticheats being visible");
    
    // Command listeners for easier team joining
    if(g_GameType == GameType_CSS)
    {
        AddCommandListener(Command_JoinTeam, "jointeam");
        AddCommandListener(Command_JoinTeam, "spectate");
    }
    
    // Events
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Natives
    CreateNative("Timer_InsideZone", Native_InsideZone);
    CreateNative("Timer_IsPointInsideZone", Native_IsPointInsideZone);
    CreateNative("Timer_TeleportToZone", Native_TeleportToZone);
    CreateNative("GetTotalZonesAllMaps", Native_GetTotalZonesAllMaps);
    
    // Forwards
    g_fwdOnZonesLoaded    = CreateGlobalForward("OnZonesLoaded", ET_Event);
    g_fwdOnZoneStartTouch = CreateGlobalForward("OnZoneStartTouch", ET_Event, Param_Cell, Param_Cell, Param_Cell);
    g_fwdOnZoneEndTouch   = CreateGlobalForward("OnZoneEndTouch", ET_Event, Param_Cell, Param_Cell, Param_Cell);
}

/*
* Teleports a client to a zone, commented cause I think it causes my IDE to crash if I don't
*/
void TeleportToZone(int client, int Zone, int ZoneNumber, bool bottom = false)
{
    StopTimer(client);
    
    if(g_Properties[Zone].Ready[ZoneNumber] == true)
    {
        float vPos[3];
        GetZonePosition(Zone, ZoneNumber, vPos);
        
        if(bottom)
        {
            float fBottom = (g_Zones[Zone][ZoneNumber][0][2] < g_Zones[Zone][ZoneNumber][7][2])?g_Zones[Zone][ZoneNumber][0][2]:g_Zones[Zone][ZoneNumber][7][2];
            
            TR_TraceRayFilter(vPos, view_as<float>({90.0, 0.0, 0.0}), MASK_PLAYERSOLID_BRUSHONLY, RayType_Infinite, TraceRayDontHitSelf, client);
            
            if(TR_DidHit())
            {
                float vHitPos[3];
                TR_GetEndPosition(vHitPos);
                
                if(vHitPos[2] < fBottom)
                    vPos[2] = fBottom;
                else
                    vPos[2] = vHitPos[2] + 0.5;
            }
            else
            {
                vPos[2] = fBottom;
            }
        }
        
        
        TeleportEntity(client, vPos, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
    }
    else
    {
        TeleportEntity(client, g_fSpawnPos, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
    }
}

public void OnMapStart()
{
    if(g_MapList != INVALID_HANDLE)
        delete g_MapList;
    
    g_MapList = new ArrayList(ByteCountToCells(64));
    ReadMapList(g_MapList);
    
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    
    if(g_GameType == GameType_CSS)
    {
        g_SnapHaloIndex = PrecacheModel("materials/sprites/halo01.vmt");
        g_SnapModelIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
    }
    else if(g_GameType == GameType_CSGO)
    {
        g_SnapHaloIndex = PrecacheModel("materials/sprites/light_glow02.vmt");
        g_SnapModelIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
    }
    
    PrecacheModel("models/props/cs_office/vending_machine.mdl");
    
    CreateTimer(0.1, Timer_SnapPoint, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.1, Timer_DrawBeams, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    
    // Check for t/ct spawns
    int t  = FindEntityByClassname(-1, "info_player_terrorist");
    int ct = FindEntityByClassname(-1, "info_player_counterterrorist");
    
    // Set map team and get spawn position
    if(t != -1)
        Entity_GetAbsOrigin(t, g_fSpawnPos);
    else
        Entity_GetAbsOrigin(ct, g_fSpawnPos);
}

public int OnMapIDPostCheck()
{
    DB_LoadZones();
}

public bool OnClientConnect(int client, char[] rejectmsg, int maxlen)
{
    InitializePlayerProperties(client);
    
    return true;
}

public void OnConfigsExecuted()
{
    for(int client = 1; client <= MaxClients; client++)
        InitializePlayerProperties(client);
    
    InitializeZoneProperties();
    ResetEntities();
}

public void OnClientDisconnect(int client)
{
    g_Setup[client].CurrentZone    = -1;
    g_Setup[client].InZonesMenu    = false;
    g_Setup[client].InSetFlagsMenu = false;
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

public void OnZoneColorChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    for(int Zone; Zone < ZONE_COUNT; Zone++)
    {
        if(g_hZoneColor[Zone] == convar)
        {
            UpdateZoneColor(Zone);
            break;
        }
    }
}

public void OnZoneOffsetChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    for(int Zone; Zone < ZONE_COUNT; Zone++)
    {
        if(g_hZoneOffset[Zone] == convar)
        {
            g_Properties[Zone].Offset = StringToInt(newValue);
            break;
        }
    }
}

public void OnZoneTriggerChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    for(int Zone; Zone < ZONE_COUNT; Zone++)
    {
        if(g_hZoneTrigger[Zone] == convar)
        {
            g_Properties[Zone].TriggerBased = view_as<bool>(StringToInt(newValue));
            break;
        }
    }
}

void InitializeZoneProperties()
{
    g_TotalZoneCount     = 0;
    g_Drawing_Zone       = 0;
    g_Drawing_ZoneNumber = 0;
    
    for(int Zone; Zone < ZONE_COUNT; Zone++)
    {
        GetZoneName(Zone, g_Properties[Zone].Name, 64);
        UpdateZoneColor(Zone);
        UpdateZoneBeamTexture(Zone);
        UpdateZoneSpriteTexture(Zone);
        g_Properties[Zone].Offset       = g_hZoneOffset[Zone].IntValue;
        g_Properties[Zone].TriggerBased = g_hZoneTrigger[Zone].BoolValue;
        g_Properties[Zone].Count        = 0;
        
        switch(Zone)
        {
            case MAIN_START, MAIN_END, BONUS_START, BONUS_END, SOLOBONUS_START, SOLOBONUS_END:
            {
                g_Properties[Zone].Max         = 1;
                g_Properties[Zone].Replaceable = true;
            }
            case ANTICHEAT, FREESTYLE:
            {
                g_Properties[Zone].Max         = 64;
                g_Properties[Zone].Replaceable = false;
            }
        }
        
        for(int i; i < g_Properties[Zone].Max; i++)
        {
            g_Properties[Zone].Ready[i]  = false;
            g_Properties[Zone].RowID[i]  = 0;
            g_Properties[Zone].Entity[i] = -1;
            g_Properties[Zone].Flags[i]  = 0;
        }
    }
}

void InitializePlayerProperties(int client)
{
    g_Setup[client].CurrentZone    = -1;
    g_Setup[client].ViewAnticheats = false;
    g_Setup[client].Snapping       = true;
    g_Setup[client].GridSnap       = 64;
    g_Setup[client].InZonesMenu    = false;
    g_Setup[client].InSetFlagsMenu = false;
}

void GetZoneName(int Zone, char[] buffer, int maxlength)
{
    switch(Zone)
    {
        case MAIN_START:
        {
            FormatEx(buffer, maxlength, "Main Start");
        }
        case MAIN_END:
        {
            FormatEx(buffer, maxlength, "Main End");
        }
        case BONUS_START:
        {
            FormatEx(buffer, maxlength, "Bonus Start");
        }
        case BONUS_END:
        {
            FormatEx(buffer, maxlength, "Bonus End");
        }
        case SOLOBONUS_START:
        {
            FormatEx(buffer, maxlength, "Solo Bonus Start");
        }
        case SOLOBONUS_END:
        {
            FormatEx(buffer, maxlength, "Solo Bonus End");
        }
        case ANTICHEAT:
        {
            FormatEx(buffer, maxlength, "Anti-cheat");
        }
        case FREESTYLE:
        {
            FormatEx(buffer, maxlength, "Freestyle");
        }
        default:
        {
            FormatEx(buffer, maxlength, "Unknown");
        }
    }
}

void UpdateZoneColor(int Zone)
{
    char sColor[32];
    char sColorExp[4][8];
    
    g_hZoneColor[Zone].GetString(sColor, sizeof(sColor));
    ExplodeString(sColor, " ", sColorExp, 4, 8);
    
    for(int i; i < 4; i++)
        g_Properties[Zone].Color[i] = StringToInt(sColorExp[i]);
}

void UpdateZoneBeamTexture(int Zone)
{
    if(g_GameType == GameType_CSS)
    {
        char sBuffer[PLATFORM_MAX_PATH];
        g_hZoneTexture[Zone].GetString(sBuffer, PLATFORM_MAX_PATH);
        
        char sBeam[PLATFORM_MAX_PATH];
        FormatEx(sBeam, PLATFORM_MAX_PATH, "%s.vmt", sBuffer);
        g_Properties[Zone].ModelIndex = PrecacheModel(sBeam);
        AddFileToDownloadsTable(sBeam);
        
        FormatEx(sBeam, PLATFORM_MAX_PATH, "%s.vtf", sBuffer);
        AddFileToDownloadsTable(sBeam);
    }
    else if(g_GameType == GameType_CSGO)
    {
        g_Properties[Zone].ModelIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
    }
}

void UpdateZoneSpriteTexture(int Zone)
{
    char sSprite[PLATFORM_MAX_PATH];
    
    if(g_GameType == GameType_CSS)
    {
        FormatEx(sSprite, sizeof(sSprite), "materials/sprites/halo01.vmt");
    }
    else if(g_GameType == GameType_CSGO)
    {
        FormatEx(sSprite, sizeof(sSprite), "materials/sprites/light_glow02.vmt");
    }
    
    g_Properties[Zone].HaloIndex = PrecacheModel(sSprite);
}

void ResetEntities()
{
    for(int entity; entity < 2048; entity++)
    {
        g_Entities_ZoneType[entity]   = -1;
        g_Entities_ZoneNumber[entity] = -1;
    }
}

// Might remove this or place into a separate plugin
public Action Command_JoinTeam(int client, const char[] command, int argc)
{
    if(StrEqual(command, "jointeam"))
    {
        char sArg[192];
        GetCmdArgString(sArg, sizeof(sArg));
        
        int team = StringToInt(sArg);
        
        if(team == 0 || team == 2 || team == 3)
        {
            if(IsFakeClient(client))
            {
                team = 2;
            }
            else
            {
                team = 3;
            }
        }
        
        if(team == 2 || team == 3)
        {
            CS_SwitchTeam(client, team);
            CS_RespawnPlayer(client);
        }
        else if(team == 0)
        {
            CS_SwitchTeam(client, GetRandomInt(2, 3));
            CS_RespawnPlayer(client);
        }
        else if(team == 1)
        {
            ForcePlayerSuicide(client);
            ChangeClientTeam(client, 1);
        }
    }
    else
    {
        ForcePlayerSuicide(client);
        ChangeClientTeam(client, 1);
    }
    
    return Plugin_Handled;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{    
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if(IsClientInGame(client))
    {
        if(g_Properties[MAIN_START].Ready[0] == true)
        {
            TeleportToZone(client, MAIN_START, 0, true);
        }
        else
        {
            TeleportEntity(client, g_fSpawnPos, NULL_VECTOR, NULL_VECTOR);
        }
    }
    
    return Plugin_Continue;
}

public Action SM_ShowAC(int client, int args)
{
    g_Setup[client].ViewAnticheats = !g_Setup[client].ViewAnticheats;
    return Plugin_Handled;
}

public Action SM_R(int client, int args)
{
    if(g_Properties[MAIN_START].Ready[0] == true)
    {
        StopTimer(client);
        TeleportToZone(client, MAIN_START, 0, true);
        
        if(g_Properties[MAIN_END].Ready[0] == true)
        {
            StartTimer(client, TIMER_MAIN);
        }
    }
    else
    {
        PrintColorText(client, "%s%sThe main start zone is not ready yet.",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_SB(int client, int args)
{
    if(g_Properties[SOLOBONUS_START].Ready[0] == true)
    {
        StopTimer(client);
        TeleportToZone(client, SOLOBONUS_START, 0, true);
        
        if(g_Properties[SOLOBONUS_START].Ready[0] == true)
        {
            StartTimer(client, TIMER_SOLOBONUS);
        }
    }
    else
    {
        PrintColorText(client, "%s%sThe solo bonus start zone is not ready yet.",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_End(int client, int args)
{
    if(g_Properties[MAIN_END].Ready[0] == true)
    {
        StopTimer(client);
        TeleportToZone(client, MAIN_END, 0, true);
    }
    else
    {
        PrintColorText(client, "%s%sThe main end zone is not ready yet.",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_B(int client, int args)
{
    if(g_Properties[BONUS_START].Ready[0] == true)
    {
        StopTimer(client);
        TeleportToZone(client, BONUS_START, 0, true);
        
        if(g_Properties[BONUS_END].Ready[0] == true)
        {
            StartTimer(client, TIMER_BONUS);
        }
    }
    else
    {
        PrintColorText(client, "%s%sThe bonus zone has not been created.",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_EndB(int client, int args)
{
    if(g_Properties[BONUS_END].Ready[0] == true)
    {
        StopTimer(client);
        TeleportToZone(client, BONUS_END, 0, true);
    }
    else
    {
        PrintColorText(client, "%s%sThe bonus end zone has not been created.",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_EndSB(int client, int args)
{
    if(g_Properties[SOLOBONUS_END].Ready[0] == true)
    {
        StopTimer(client);
        TeleportToZone(client, SOLOBONUS_END, 0, true);
    }
    else
    {
        PrintColorText(client, "%s%sThe solo bonus end zone has not been created.",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_Zones(int client, int args)
{
    OpenZonesMenu(client);
    
    return Plugin_Handled;
}

void OpenZonesMenu(int client)
{
    Menu menu = new Menu(Menu_Zones);
    
    menu.SetTitle("Zone Control");
    
    menu.AddItem("add", "Add a zone");
    menu.AddItem("goto", "Go to zone");
    menu.AddItem("del", "Delete a zone");
    menu.AddItem("set", "Set zone flags");
    menu.AddItem("snap", g_Setup[client].Snapping?"Wall Snapping: On":"Wall Snapping: Off");
    
    char sDisplay[64];
    IntToString(g_Setup[client].GridSnap, sDisplay, sizeof(sDisplay));
    Format(sDisplay, sizeof(sDisplay), "Grid Snapping: %s", sDisplay);
    menu.AddItem("grid", sDisplay);
    menu.AddItem("ac", g_Setup[client].ViewAnticheats?"Anti-cheats: Visible":"Anti-cheats: Invisible");
    
    menu.Display(client, MENU_TIME_FOREVER);
    
    g_Setup[client].InZonesMenu = true;
}

public int Menu_Zones(Menu menu, MenuAction action, int client, int param2)
{
    if(action & MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "add"))
        {
            OpenAddZoneMenu(client);
        }
        else if(StrEqual(info, "goto"))
        {
            OpenGoToMenu(client);
        }
        else if(StrEqual(info, "del"))
        {
            OpenDeleteMenu(client);
        }
        else if(StrEqual(info, "set"))
        {
            OpenSetFlagsMenu(client);
        }
        else if(StrEqual(info, "snap"))
        {
            g_Setup[client].Snapping = !g_Setup[client].Snapping;
            OpenZonesMenu(client);
        }
        else if(StrEqual(info, "grid"))
        {
            g_Setup[client].GridSnap *= 2;
                
            if(g_Setup[client].GridSnap > 64)
                g_Setup[client].GridSnap = 1;
            
            OpenZonesMenu(client);
        }
        else if(StrEqual(info, "ac"))
        {
            g_Setup[client].ViewAnticheats = !g_Setup[client].ViewAnticheats;
            OpenZonesMenu(client);
        }
    }
    
    if(action & MenuAction_End)
    {
        delete menu;
    }
    
    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_Exit)
        {
            g_Setup[client].InZonesMenu = false;
        }
    }
}

void OpenAddZoneMenu(int client)
{
    Menu menu = new Menu(Menu_AddZone);
    menu.SetTitle("Add a Zone");
    
    char sInfo[8];
    for(int Zone; Zone < ZONE_COUNT; Zone++)
    {
        IntToString(Zone, sInfo, sizeof(sInfo));
        menu.AddItem(sInfo, g_Properties[Zone].Name);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_AddZone(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        CreateZone(client, StringToInt(info));
        
        OpenAddZoneMenu(client);
    }
    else if(action == MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
            OpenZonesMenu(client);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    
    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_Exit)
        {
            g_Setup[client].InZonesMenu = false;
        }
    }
}

void CreateZone(int client, int Zone)
{
    if(ClientCanCreateZone(client, Zone))
    {
        if((g_Properties[Zone].Count < g_Properties[Zone].Max) || g_Properties[Zone].Replaceable == true)
        {
            int ZoneNumber;
            
            if(g_Properties[Zone].Count >= g_Properties[Zone].Max)
                ZoneNumber = 0;
            else
                ZoneNumber = g_Properties[Zone].Count;
            
            if(g_Setup[client].CurrentZone == -1)
            {
                if(g_Properties[Zone].Ready[ZoneNumber] == true)
                    DB_DeleteZone(client, Zone, ZoneNumber);
                
                if(Zone == ANTICHEAT)
                    g_Setup[client].ViewAnticheats = true;
                
                g_Setup[client].CurrentZone = Zone;
                
                GetZoneSetupPosition(client, g_Zones[Zone][ZoneNumber][0]);
                
                DataPack data;
                g_Setup[client].SetupTimer = CreateDataTimer(0.1, Timer_ZoneSetup, data, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
                data.WriteCell(GetClientUserId(client));
                data.WriteCell(ZoneNumber);
            }
            else if(g_Setup[client].CurrentZone == Zone)
            {    
                if(g_Properties[Zone].Count < g_Properties[Zone].Max)
                {
                    g_Properties[Zone].Count++;
                    g_TotalZoneCount++;
                }
                
                KillTimer(g_Setup[client].SetupTimer, true);
                
                GetZoneSetupPosition(client, g_Zones[Zone][ZoneNumber][7]);
                    
                g_Zones[Zone][ZoneNumber][7][2] += g_Properties[Zone].Offset;
                
                g_Setup[client].CurrentZone = -1;
                g_Properties[Zone].Ready[ZoneNumber] = true;
                
                DB_SaveZone(Zone, ZoneNumber);
                
                if(g_Properties[Zone].TriggerBased == true)
                    CreateZoneTrigger(Zone, ZoneNumber);
            }
            else
            {
                PrintColorText(client, "%s%sYou are already setting up a different zone (%s%s%s).",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol,
                    g_Properties[g_Setup[client].CurrentZone].Name,
                    g_msg_textcol);
            }
        }
        else
        {
            PrintColorText(client, "%s%sThere are too many of this zone (Max %s%d%s).",
                g_msg_start,
                g_msg_textcol,
                g_msg_varcol,
                g_Properties[Zone].Max,
                g_msg_textcol);
        }
    }
    else
    {
        PrintColorText(client, "%s%sSomeone else is already creating this zone (%s%s%s).",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            g_Properties[Zone].Name,
            g_msg_textcol);
    }
}

bool ClientCanCreateZone(int client, int Zone)
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(g_Setup[i].CurrentZone == Zone && client != i)
        {
            return false;
        }
    }
    
    return true;
}

public Action Timer_ZoneSetup(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    
    if(client != 0)
    {
        int ZoneNumber = pack.ReadCell();
        int Zone       = g_Setup[client].CurrentZone;
        
        // Get setup position
        GetZoneSetupPosition(client, g_Zones[Zone][ZoneNumber][7]);
        g_Zones[Zone][ZoneNumber][7][2] += g_Properties[Zone].Offset;
        
        // Draw zone
        CreateZonePoints(g_Zones[Zone][ZoneNumber]);
        DrawZone(Zone, ZoneNumber, 0.1);
    }
    else
    {
        KillTimer(timer, true);
    }
}

void CreateZonePoints(float Zone[8][3])
{
    for(int i=1; i<7; i++)
    {
        for(int j=0; j<3; j++)
        {
            Zone[i][j] = Zone[((i >> (2 - j)) & 1) * 7][j];
        }
    }
}

void DrawZone(int Zone, int ZoneNumber, float life)
{
    int color[4];
    
    for(int i = 0; i < 4; i++)
        color[i] = g_Properties[Zone].Color[i];
    
    for(int i=0, i2=3; i2>=0; i+=i2--)
    {
        for(int j=1; j<=7; j+=(j/2)+1)
        {
            if(j != 7-i)
            {
                TE_SetupBeamPoints(g_Zones[Zone][ZoneNumber][i], g_Zones[Zone][ZoneNumber][j], g_Properties[Zone].ModelIndex, g_Properties[Zone].HaloIndex, 0, 0, (life < 0.1)?0.1:life, 5.0, 5.0, 10, 0.0, color, 0);
                
                int numClients;
                int[] clients = new int[MaxClients];
                
                switch(Zone)
                {
                    case MAIN_START, MAIN_END, BONUS_START, BONUS_END, SOLOBONUS_START, SOLOBONUS_END, FREESTYLE:
                    {
                        TE_SendToAll();
                    }
                    case ANTICHEAT:
                    {
                        for(int client = 1; client <= MaxClients; client++)
                            if(IsClientInGame(client) && g_Setup[client].ViewAnticheats == true)
                                clients[numClients++] = client;
                        
                        if(numClients > 0)
                            TE_Send(clients, numClients);
                    }
                }
            }
        }
    }
}

public Action Timer_DrawBeams(Handle timer, any data)
{
    // Draw 4 zones (32 temp ents limit) per timer frame so all zones will draw
    if(g_TotalZoneCount > 0)
    {
        int ZonesDrawnThisFrame;
        
        for(int cycle; cycle < ZONE_COUNT; g_Drawing_Zone = (g_Drawing_Zone + 1) % ZONE_COUNT, cycle++)
        {
            for(; g_Drawing_ZoneNumber < g_Properties[g_Drawing_Zone].Count; g_Drawing_ZoneNumber++)
            {    
                if(g_Properties[g_Drawing_Zone].Ready[g_Drawing_ZoneNumber] == true)
                {
                    DrawZone(g_Drawing_Zone, g_Drawing_ZoneNumber, (float(g_TotalZoneCount)/40.0) + 0.3);
                    
                    if(++ZonesDrawnThisFrame == 4)
                    {
                        g_Drawing_ZoneNumber++;
                        
                        return Plugin_Continue;
                    }
                }
            }
            
            g_Drawing_ZoneNumber = 0;
        }
    }
    
    return Plugin_Continue;
}

void CreateZoneTrigger(int Zone, int ZoneNumber)
{    
    int entity = CreateEntityByName("trigger_multiple");
    if(entity != -1)
    {
        DispatchKeyValue(entity, "spawnflags", "4097");
        
        DispatchSpawn(entity);
        ActivateEntity(entity);
        
        float fPos[3];
        GetZonePosition(Zone, ZoneNumber, fPos);
        TeleportEntity(entity, fPos, NULL_VECTOR, NULL_VECTOR);
        
        SetEntityModel(entity, "models/props/cs_office/vending_machine.mdl");
        
        float fBounds[2][3];
        GetMinMaxBounds(Zone, ZoneNumber, fBounds);
        SetEntPropVector(entity, Prop_Send, "m_vecMins", fBounds[0]);
        SetEntPropVector(entity, Prop_Send, "m_vecMaxs", fBounds[1]);
        
        SetEntProp(entity, Prop_Send, "m_nSolidType", 2);
        SetEntProp(entity, Prop_Send, "m_fEffects", GetEntProp(entity, Prop_Send, "m_fEffects") | 32);
        
        g_Entities_ZoneType[entity]            = Zone;
        g_Entities_ZoneNumber[entity]          = ZoneNumber;
        g_Properties[Zone].Entity[ZoneNumber] = entity;
        
        SDKHook(entity, SDKHook_StartTouch, Hook_StartTouch);
        SDKHook(entity, SDKHook_EndTouch, Hook_EndTouch);
        SDKHook(entity, SDKHook_Touch, Hook_Touch);
    }
}

public Action Hook_StartTouch(int entity, int other)
{
    // Anti-cheats, freestyles, and end zones
    int Zone       = g_Entities_ZoneType[entity];
    int ZoneNumber = g_Entities_ZoneNumber[entity];
    
    if(0 < other <= MaxClients)
    {
        if(IsClientInGame(other))
        {
            if(IsPlayerAlive(other))
            {
                if(g_Properties[Zone].TriggerBased == true)
                {
                    g_bInside[other][Zone][ZoneNumber] = true;
                    
                    switch(Zone)
                    {
                        case MAIN_END:
                        {
                            int partner = Timer_GetPartner(other);
                            if(!g_bFinishedFirst[partner] && IsBeingTimed(other, TIMER_MAIN))
                            {
                                FinishTimer(other);
                                FinishTimer(partner);
                                TeleportToZone(Timer_GetPartner(other), MAIN_END, 0, true);
                                g_bFinishedFirst[other] = true;
                            }
                        }
                        case BONUS_END:
                        {
                            int partner = Timer_GetPartner(other);
                            if(!g_bFinishedFirst[partner] && IsBeingTimed(other, TIMER_BONUS))
                            {
                                FinishTimer(other);
                                FinishTimer(partner);
                                TeleportToZone(Timer_GetPartner(other), BONUS_END, 0, true);
                                g_bFinishedFirst[other] = true;
                            }
                        }
                        case SOLOBONUS_END:
                        {
                            if(IsBeingTimed(other, TIMER_SOLOBONUS))
                                FinishTimer(other);
                        }
                        case ANTICHEAT:
                        {
                            if(IsBeingTimed(other, TIMER_MAIN) && (g_Properties[Zone].Flags[ZoneNumber] & FLAG_ANTICHEAT_MAIN))
                            {
                                StopTimer(other);
                                
                                PrintColorText(other, "%s%sYour timer was stopped for using a shortcut.",
                                    g_msg_start,
                                    g_msg_textcol);
                            }
                            
                            if(IsBeingTimed(other, TIMER_BONUS) && (g_Properties[Zone].Flags[ZoneNumber] & FLAG_ANTICHEAT_BONUS))
                            {
                                StopTimer(other);
                                
                                PrintColorText(other, "%s%sYour timer was stopped for using a shortcut.",
                                    g_msg_start,
                                    g_msg_textcol);
                            }
                            
                            if(IsBeingTimed(other, TIMER_SOLOBONUS) && (g_Properties[Zone].Flags[ZoneNumber] & FLAG_ANTICHEAT_SOLOBONUS))
                            {
                                StopTimer(other);
                                
                                PrintColorText(other, "%s%sYour timer was stopped for using a shortcut.",
                                    g_msg_start,
                                    g_msg_textcol);
                            }
                        }
                    }
                }
            }
            
            if(g_Setup[other].InSetFlagsMenu == true)
                if(Zone == ANTICHEAT || Zone == FREESTYLE)
                    OpenSetFlagsMenu(other, Zone, ZoneNumber);
                
            Call_StartForward(g_fwdOnZoneStartTouch);
            Call_PushCell(other);
            Call_PushCell(Zone);
            Call_PushCell(ZoneNumber);
            Call_Finish();
        }
    }
}

public Action Hook_EndTouch(int entity, int other)
{
    int Zone       = g_Entities_ZoneType[entity];
    int ZoneNumber = g_Entities_ZoneNumber[entity];
    
    if(0 < other <= MaxClients)
    {
        if(g_Properties[Zone].TriggerBased == true)
        {
            g_bInside[other][Zone][ZoneNumber] = false;
        }
        
        Call_StartForward(g_fwdOnZoneEndTouch);
        Call_PushCell(other);
        Call_PushCell(Zone);
        Call_PushCell(ZoneNumber);
        Call_Finish();
    }
}

public Action Hook_Touch(int entity, int other)
{
    // Anti-prespeed (Start zones)
    int Zone = g_Entities_ZoneType[entity];
    
    if(g_Properties[Zone].TriggerBased == true && (0 < other <= MaxClients))
    {
        if(IsClientInGame(other))
        {    
            if(IsPlayerAlive(other))
            {
                switch(Zone)
                {
                    case MAIN_START:
                    {                        
                        if(g_Properties[MAIN_END].Ready[0] == true)
                        {
                            int partner = Timer_GetPartner(other);
                            if(partner && Timer_InsideZone(partner, Zone) != -1)
                            {
                                StartTimer(other, TIMER_MAIN);
                                //StartTimer(partner, TIMER_MAIN);
                                g_bFinishedFirst[other] = false;
                            }
                        }
                    }
                    case BONUS_START:
                    {
                        if(g_Properties[BONUS_END].Ready[0] == true)
                        {
                            int partner = Timer_GetPartner(other);
                            if(partner && Timer_InsideZone(partner, Zone) != -1)
                            {
                                StartTimer(other, TIMER_BONUS);
                                //StartTimer(partner, TIMER_BONUS);
                                g_bFinishedFirst[other] = false;
                            }
                        }
                    }
                    case SOLOBONUS_START:
                    {
                        if(g_Properties[SOLOBONUS_END].Ready[0] == true)
                            StartTimer(other, TIMER_SOLOBONUS);
                    }
                }
            }
        }
    }
}

void GetZoneSetupPosition(int client, float fPos[3])
{
    bool bSnapped;
    
    if(g_Setup[client].Snapping == true)
        bSnapped = GetWallSnapPosition(client, fPos);
        
    if(bSnapped == false)
        GetGridSnapPosition(client, fPos);
}

void GetGridSnapPosition(int client, float fPos[3])
{
    Entity_GetAbsOrigin(client, fPos);
    
    for(int i = 0; i < 2; i++)
        fPos[i] = float(RoundFloat(fPos[i] / float(g_Setup[client].GridSnap)) * g_Setup[client].GridSnap);
    
    // Snap to z axis only if the client is off the ground
    if(!(GetEntityFlags(client) & FL_ONGROUND))
        fPos[2] = float(RoundFloat(fPos[2] / float(g_Setup[client].GridSnap)) * g_Setup[client].GridSnap);
}

public Action Timer_SnapPoint(Handle timer, any data)
{
    float fSnapPos[3];
    float fClientPos[3];
    
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsFakeClient(client) && g_Setup[client].InZonesMenu)
        {
            Entity_GetAbsOrigin(client, fClientPos);
            GetZoneSetupPosition(client, fSnapPos);
            
            if(GetVectorDistance(fClientPos, fSnapPos) > 0)
            {
                TE_SetupBeamPoints(fClientPos, fSnapPos, g_SnapModelIndex, g_SnapHaloIndex, 0, 0, 0.1, 5.0, 5.0, 0, 0.0, {0, 255, 255, 255}, 0);
                TE_SendToAll();
            }
        }
    }
}

bool GetWallSnapPosition(int client, float fPos[3])
{
    GetEntPropVector(client, Prop_Send, "m_vecOrigin", fPos);
    
    float fHitPos[3];
    float vAng[3];
    bool bSnapped;
    
    for(; vAng[1] < 360; vAng[1] += 90)
    {
        TR_TraceRayFilter(fPos, vAng, MASK_PLAYERSOLID_BRUSHONLY, RayType_Infinite, TraceRayDontHitSelf, client);
        
        if(TR_DidHit())
        {
            TR_GetEndPosition(fHitPos);
            
            if(GetVectorDistance(fPos, fHitPos) < 17)
            {
                if(vAng[1] == 0 || vAng[1] == 180)
                {
                    // Change x
                    fPos[0] = fHitPos[0];
                }
                else
                {
                    // Change y
                    fPos[1] = fHitPos[1];
                }
                
                bSnapped = true;
            }
        }
    }
    
    return bSnapped;
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
    return entity != data && !(0 < entity <= MaxClients);
}

void GetZonePosition(int Zone, int ZoneNumber, float fPos[3])
{
    for(int i = 0; i < 3; i++)
        fPos[i] = (g_Zones[Zone][ZoneNumber][0][i] + g_Zones[Zone][ZoneNumber][7][i]) / 2;
}

void GetMinMaxBounds(int Zone, int ZoneNumber, float fBounds[2][3])
{
    float length;
    
    for(int i = 0; i < 3; i++)
    {
        length = FloatAbs(g_Zones[Zone][ZoneNumber][0][i] - g_Zones[Zone][ZoneNumber][7][i]);
        fBounds[0][i] = -(length / 2);
        fBounds[1][i] = length / 2;
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

void DB_LoadZones()
{
    char query[512];
    FormatEx(query, sizeof(query), "SELECT Type, RowID, flags, point00, point01, point02, point10, point11, point12 FROM zones WHERE MapID = (SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1)",
        g_sMapName);
    g_DB.Query(LoadZones_Callback, query);
}

public void LoadZones_Callback(Database db, DBResultSet results, char[] error, any data)
{
    if(results != INVALID_HANDLE)
    {
        int Zone, ZoneNumber;
        
        while(results.FetchRow())
        {
            Zone       = results.FetchInt(0);
            ZoneNumber = g_Properties[Zone].Count;
            
            g_Properties[Zone].RowID[ZoneNumber] = results.FetchInt(1);
            g_Properties[Zone].Flags[ZoneNumber] = results.FetchInt(2);
            
            for(int i = 0; i < 6; i++)
            {
                g_Zones[Zone][ZoneNumber][(i / 3) * 7][i % 3] = results.FetchFloat(i + 3);
            }
            
            CreateZonePoints(g_Zones[Zone][ZoneNumber]);
            CreateZoneTrigger(Zone, ZoneNumber);
            
            g_Properties[Zone].Ready[ZoneNumber] = true;
            g_Properties[Zone].Count++;
            g_TotalZoneCount++;
        }
        
        char sQuery[128];
        FormatEx(sQuery, sizeof(sQuery), "SELECT MapID, Type FROM zones");
        g_DB.Query(LoadZones_Callback2, sQuery);
    }
    else
    {
        LogError(error);
    }
}

public void LoadZones_Callback2(Database db, DBResultSet results, char[] error, any data)
{
    if(results != INVALID_HANDLE)
    {
        for(int Zone; Zone < ZONE_COUNT; Zone++)
            g_TotalZoneAllMaps[Zone] = 0;
        
        int MapID;
        char sMapName[64];
        while(results.FetchRow())
        {
            MapID = results.FetchInt(0);
            
            GetMapNameFromMapId(MapID, sMapName, sizeof(sMapName));
            
            if(g_MapList.FindString(sMapName) != -1)
            {
                g_TotalZoneAllMaps[results.FetchInt(1)]++;
            }
        }
        
        Call_StartForward(g_fwdOnZonesLoaded);
        Call_Finish();
    }
    else
    {
        LogError(error);
    }
}

void DB_SaveZone(int Zone, int ZoneNumber)
{
    DataPack data = new DataPack();
    data.WriteCell(Zone);
    data.WriteCell(ZoneNumber);
    
    char query[512];
    FormatEx(query, sizeof(query), "INSERT INTO zones (MapID, Type, point00, point01, point02, point10, point11, point12, flags) VALUES ((SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1), %d, %f, %f, %f, %f, %f, %f, %d)", 
        g_sMapName,
        Zone,
        g_Zones[Zone][ZoneNumber][0][0], g_Zones[Zone][ZoneNumber][0][1], g_Zones[Zone][ZoneNumber][0][2], 
        g_Zones[Zone][ZoneNumber][7][0], g_Zones[Zone][ZoneNumber][7][1], g_Zones[Zone][ZoneNumber][7][2],
        g_Properties[Zone].Flags[ZoneNumber]);
    g_DB.Query(SaveZone_Callback, query, data);
}

public void SaveZone_Callback(Database db, DBResultSet results, char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        int Zone       = data.ReadCell();
        int ZoneNumber = data.ReadCell();
        
        g_Properties[Zone].RowID[ZoneNumber] = results.InsertId;
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

void DB_DeleteZone(int client, int Zone, int ZoneNumber, bool ManualDelete = false)
{
    if(g_Properties[Zone].Ready[ZoneNumber] == true)
    {        
        // Delete from database
        DataPack data = new DataPack();
        data.WriteCell(GetClientUserId(client));
        data.WriteCell(Zone);
        
        char query[512];
        FormatEx(query, sizeof(query), "DELETE FROM zones WHERE RowID = %d",
            g_Properties[Zone].RowID[ZoneNumber]);
        g_DB.Query(DeleteZone_Callback, query, data);
        
        
        // Delete in memory
        for(int client2 = 1; client2 <= MaxClients; client2++)
        {
            g_bInside[client2][Zone][ZoneNumber] = false;
            
            if(ManualDelete == true)
            {
                if(Zone == MAIN_START || Zone == MAIN_END)
                {
                    if(IsBeingTimed(client2, TIMER_MAIN))
                    {
                        StopTimer(client2);
                        
                        PrintColorText(client2, "%s%sYour timer was stopped because the %s%s%s zone was deleted.",
                            g_msg_start,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Properties[Zone].Name,
                            g_msg_textcol);
                    }
                }
                
                if(Zone == BONUS_START || Zone == BONUS_END)
                {
                    if(IsBeingTimed(client2, TIMER_BONUS))
                    {
                        StopTimer(client2);
                        
                        PrintColorText(client2, "%s%sYour timer was stopped because the %s%s%s zone was deleted.",
                            g_msg_start,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Properties[Zone].Name,
                            g_msg_textcol);
                    }
                }
                
                if(Zone == SOLOBONUS_START || Zone == SOLOBONUS_END)
                {
                    if(IsBeingTimed(client2, TIMER_SOLOBONUS))
                    {
                        StopTimer(client2);
                        
                        PrintColorText(client2, "%s%sYour timer was stopped because the %s%s%s zone was deleted.",
                            g_msg_start,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Properties[Zone].Name,
                            g_msg_textcol);
                    }
                }
            }
        }
        
        if(IsValidEntity(g_Properties[Zone].Entity[ZoneNumber]))
        {
            AcceptEntityInput(g_Properties[Zone].Entity[ZoneNumber], "Kill");
        }
        
        if(-1 < g_Properties[Zone].Entity[ZoneNumber] < 2048)
        {
            g_Entities_ZoneNumber[g_Properties[Zone].Entity[ZoneNumber]] = -1;
            g_Entities_ZoneType[g_Properties[Zone].Entity[ZoneNumber]]   = -1;
        }
        
        for(int i = ZoneNumber; i < g_Properties[Zone].Count - 1; i++)
        {
            for(int point = 0; point < 8; point++)
                for(int axis = 0; axis < 3; axis++)
                    g_Zones[Zone][i][point][axis] = g_Zones[Zone][i + 1][point][axis];
            
            g_Properties[Zone].Entity[i] = g_Properties[Zone].Entity[i + 1];
            
            if(-1 < g_Properties[Zone].Entity[i] < 2048)
            {
                g_Entities_ZoneNumber[g_Properties[Zone].Entity[i]]--;
            }
            
            g_Properties[Zone].RowID[i]  = g_Properties[Zone].RowID[i + 1];
            g_Properties[Zone].Flags[i]  = g_Properties[Zone].Flags[i + 1];
            
        }
        
        g_Properties[Zone].Ready[g_Properties[Zone].Count - 1] = false;
        
        g_Properties[Zone].Count--;
        g_TotalZoneCount--;
    }
    else
    {
        PrintColorText(client, "%s%sAttempted to delete a zone that doesn't exist.",
            g_msg_start,
            g_msg_textcol);
    }
}

public void DeleteZone_Callback(Database db, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        int userid = data.ReadCell();
        int client = GetClientOfUserId(userid);
        
        if(client != 0)
        {
            int Zone = data.ReadCell();
            LogMessage("%L deleted zone %s", client, g_Properties[Zone].Name);
        }
        else
        {
            LogMessage("Player with UserID %d deleted a zone.", userid);
        }
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

void OpenGoToMenu(int client)
{
    if(g_TotalZoneCount > 0)
    {
        Menu menu = new Menu(Menu_GoToZone);
        
        menu.SetTitle("Go to a Zone");
        
        char sInfo[8];
        for(int Zone; Zone < ZONE_COUNT; Zone++)
        {
            if(g_Properties[Zone].Count > 0)
            {
                IntToString(Zone, sInfo, sizeof(sInfo));
                menu.AddItem(sInfo, g_Properties[Zone].Name);
            }
        }
        
        menu.ExitBackButton = true;
        menu.Display(client, MENU_TIME_FOREVER);
    }
    else
    {
        OpenZonesMenu(client);
    }
}

public int Menu_GoToZone(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        int Zone = StringToInt(info);
        
        switch(Zone)
        {
            case MAIN_START, MAIN_END, BONUS_START, BONUS_END, SOLOBONUS_START, SOLOBONUS_END:
            {
                TeleportToZone(client, Zone, 0);
                OpenGoToMenu(client);
            }
            case ANTICHEAT, FREESTYLE:
            {
                ListGoToZones(client, Zone);
            }
        }
    }
    else if(action == MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
            OpenZonesMenu(client);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    
    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_Exit)
        {
            g_Setup[client].InZonesMenu = false;
        }
    }
}

void ListGoToZones(int client, int Zone)
{
    Menu menu = new Menu(Menu_GoToList);
    menu.SetTitle("Go to %s zones", g_Properties[Zone].Name);
    
    char sInfo[16];
    char sDisplay[16];
    for(int ZoneNumber; ZoneNumber < g_Properties[Zone].Count; ZoneNumber++)
    {
        FormatEx(sInfo, sizeof(sInfo), "%d;%d", Zone, ZoneNumber);
        IntToString(ZoneNumber + 1, sDisplay, sizeof(sDisplay));
        
        menu.AddItem(sInfo, sDisplay);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_GoToList(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        char sZoneAndNumber[2][16];
        ExplodeString(info, ";", sZoneAndNumber, 2, 16);
        
        int Zone       = StringToInt(sZoneAndNumber[0]);
        int ZoneNumber = StringToInt(sZoneAndNumber[1]);
        
        TeleportToZone(client, Zone, ZoneNumber);
        
        ListGoToZones(client, Zone);
    }
    else if(action == MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
            OpenGoToMenu(client);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    
    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_Exit)
        {
            g_Setup[client].InZonesMenu = false;
        }
    }
}

void OpenDeleteMenu(int client)
{
    if(g_TotalZoneCount > 0)
    {
        Menu menu = new Menu(Menu_DeleteZone);
        
        menu.SetTitle("Delete a Zone");
        
        menu.AddItem("sel", "Selected Zone");
        
        char sInfo[8];
        for(int Zone = 0; Zone < ZONE_COUNT; Zone++)
        {
            if(g_Properties[Zone].Count > 0)
            {
                IntToString(Zone, sInfo, sizeof(sInfo));
                
                menu.AddItem(sInfo, g_Properties[Zone].Name);
            }
        }
        
        menu.ExitBackButton = true;
        menu.Display(client, MENU_TIME_FOREVER);
    }
    else
    {
        OpenZonesMenu(client);
    }
}

public int Menu_DeleteZone(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "sel"))
        {
            for(int Zone = 0; Zone < ZONE_COUNT; Zone++)
            {
                for(int ZoneNumber = 0; ZoneNumber < g_Properties[Zone].Count; ZoneNumber++)
                {
                    if(g_bInside[client][Zone][ZoneNumber] == true)
                    {
                        DB_DeleteZone(client, Zone, ZoneNumber, true);
                    }
                }
            }
            
            OpenDeleteMenu(client);
        }
        else
        {
            int Zone = StringToInt(info);
            
            switch(Zone)
            {
                case MAIN_START, MAIN_END, BONUS_START, BONUS_END, SOLOBONUS_START, SOLOBONUS_END:
                {
                    DB_DeleteZone(client, Zone, 0, true);
                    
                    OpenDeleteMenu(client);
                }
                case ANTICHEAT, FREESTYLE:
                {
                    ListDeleteZones(client, Zone);
                }
            }
        }
    }
    else if (action == MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
            OpenZonesMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    
    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_Exit)
        {
            g_Setup[client].InZonesMenu = false;
        }
    }
}

void ListDeleteZones(int client, int Zone)
{
    Menu menu = new Menu(Menu_DeleteList);
    menu.SetTitle("Delete %s zones", g_Properties[Zone].Name);
    
    char sInfo[16];
    char sDisplay[16];
    for(int ZoneNumber = 0; ZoneNumber < g_Properties[Zone].Count; ZoneNumber++)
    {
        FormatEx(sInfo, sizeof(sInfo), "%d;%d", Zone, ZoneNumber);
        IntToString(ZoneNumber + 1, sDisplay, sizeof(sDisplay));
        
        menu.AddItem(sInfo, sDisplay);
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_DeleteList(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        char sZoneAndNumber[2][16];
        ExplodeString(info, ";", sZoneAndNumber, 2, 16);
        
        int Zone       = StringToInt(sZoneAndNumber[0]);
        int ZoneNumber = StringToInt(sZoneAndNumber[1]);
        
        DB_DeleteZone(client, Zone, ZoneNumber);
        
        ListDeleteZones(client, Zone);
    }
    else if(action == MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
            OpenGoToMenu(client);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    
    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_Exit)
        {
            g_Setup[client].InZonesMenu = false;
        }
    }
}

void OpenSetFlagsMenu(int client, int Zone = -1, int ZoneNumber = -1)
{
    g_Setup[client].InSetFlagsMenu = true;
    g_Setup[client].ViewAnticheats = true;
    
    Menu menu = new Menu(Menu_SetFlags);
    menu.ExitBackButton = true;
    
    if(Zone == -1 && ZoneNumber == -1)
    {
        for(Zone = ANTICHEAT; Zone <= FREESTYLE; Zone++)
        {
            if((ZoneNumber = Timer_InsideZone(client, Zone)) != -1)
            {
                break;
            }
        }
    }
    
    if(ZoneNumber != -1)
    {
        menu.SetTitle("Set %s flags", g_Properties[Zone].Name);
                
        char sInfo[16];
        
        switch(Zone)
        {
            case ANTICHEAT:
            {
                FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", ANTICHEAT, ZoneNumber, FLAG_ANTICHEAT_MAIN);
                menu.AddItem(sInfo, (g_Properties[Zone].Flags[ZoneNumber] & FLAG_ANTICHEAT_MAIN)?"Main: Yes":"Main: No");
                
                FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", ANTICHEAT, ZoneNumber, FLAG_ANTICHEAT_BONUS);
                menu.AddItem(sInfo, (g_Properties[Zone].Flags[ZoneNumber] & FLAG_ANTICHEAT_BONUS)?"Bonus: Yes":"Bonus: No");
                
                FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", ANTICHEAT, ZoneNumber, FLAG_ANTICHEAT_SOLOBONUS);
                menu.AddItem(sInfo, (g_Properties[Zone].Flags[ZoneNumber] & FLAG_ANTICHEAT_SOLOBONUS)?"Solo Bonus: Yes":"Solo Bonus: No");
                
                menu.Display(client, MENU_TIME_FOREVER);
                
                return;
            }
            case FREESTYLE:
            {
                char sStyle[32];
                char sDisplay[128];
                for(int Style; Style < MAX_STYLES; Style++)
                {
                    if(Style_IsEnabled(Style) && Style_IsFreestyleAllowed(Style))
                    {
                        GetStyleName(Style, sStyle, sizeof(sStyle));
                        
                        FormatEx(sDisplay, sizeof(sDisplay), (g_Properties[Zone].Flags[ZoneNumber] & (1 << Style))?"%s: Yes":"%s: No", sStyle);
                        
                        FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", FREESTYLE, ZoneNumber, 1 << Style);
                        
                        menu.AddItem(sInfo, sDisplay);
                    }
                }
                
                menu.Display(client, MENU_TIME_FOREVER);
                
                return;
            }
        }
    }
    else
    {
        menu.SetTitle("Not in Anti-cheat nor Freestyle zone");
        menu.AddItem("choose", "Go to a zone", ITEMDRAW_DISABLED);
        menu.Display(client, MENU_TIME_FOREVER);
    }
}

public int Menu_SetFlags(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "choose"))
        {
            OpenSetFlagsMenu(client);
        }
        else
        {
            char sExplode[3][16];
            ExplodeString(info, ";", sExplode, 3, 16);
            
            int Zone       = StringToInt(sExplode[0]);
            int ZoneNumber = StringToInt(sExplode[1]);
            int flags      = StringToInt(sExplode[2]);
            
            SetZoneFlags(Zone, ZoneNumber, g_Properties[Zone].Flags[ZoneNumber] ^ flags);
            
            OpenSetFlagsMenu(client, Zone, ZoneNumber);
        }
    }
    else if(action == MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
            OpenGoToMenu(client);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    
    if(action & MenuAction_Cancel)
    {        
        if(param2 == MenuCancel_Exit)
        {
            g_Setup[client].InZonesMenu    = false;
            g_Setup[client].InSetFlagsMenu = false;
        }
        else if(param2 == MenuCancel_ExitBack)
        {
            g_Setup[client].InSetFlagsMenu = false;
            
            OpenZonesMenu(client);
        }
    }
}

void SetZoneFlags(int Zone, int ZoneNumber, int flags)
{
    g_Properties[Zone].Flags[ZoneNumber] = flags;
    
    char query[128];
    FormatEx(query, sizeof(query), "UPDATE zones SET flags = %d WHERE RowID = %d",
        g_Properties[Zone].Flags[ZoneNumber],
        g_Properties[Zone].RowID[ZoneNumber]);
    g_DB.Query(SetZoneFlags_Callback, query);
}

public void SetZoneFlags_Callback(Database db, DBResultSet results, char[] error, any data)
{
    if(results == INVALID_HANDLE)
    {
        LogError(error);
    }
}

bool IsClientInsideZone(int client, float point[8][3])
{
    float fPos[3];
    Entity_GetAbsOrigin(client, fPos);
    
    // Add 5 units to a player's height or it won't work
    fPos[2] += 5.0;
    
    return IsPointInsideZone(fPos, point);
}

bool IsPointInsideZone(float pos[3], float point[8][3])
{
    for(int i = 0; i < 3; i++)
    {
        if(point[0][i] >= pos[i] == point[7][i] >= pos[i])
        {
            return false;
        }
    }
    
    return true;
}

public int Native_InsideZone(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int Zone   = GetNativeCell(2);
    int flags  = GetNativeCell(3);
    
    for(int ZoneNumber; ZoneNumber < g_Properties[Zone].Count; ZoneNumber++)
    {
        if(g_bInside[client][Zone][ZoneNumber] == true)
        {
            if(flags != -1)
            {
                if(g_Properties[Zone].Flags[ZoneNumber] & flags)
                    return ZoneNumber;
            }
            else
            {
                return ZoneNumber;
            }
        }
    }
        
    return -1;
}

public int Native_IsPointInsideZone(Handle plugin, int numParams)
{
    float fPos[3];
    GetNativeArray(1, fPos, 3);
    
    int Zone       = GetNativeCell(2);
    int ZoneNumber = GetNativeCell(3);
    
    if(g_Properties[Zone].Ready[ZoneNumber] == true)
    {
        return IsPointInsideZone(fPos, g_Zones[Zone][ZoneNumber]);
    }
    else
    {
        return false;
    }
}

public int Native_TeleportToZone(Handle plugin, int numParams)
{
    int client      = GetNativeCell(1);
    int Zone        = GetNativeCell(2);
    int ZoneNumber  = GetNativeCell(3);
    bool bottom = GetNativeCell(4);
    
    TeleportToZone(client, Zone, ZoneNumber, bottom);
}

public int Native_GetTotalZonesAllMaps(Handle plugin, int numParams)
{
    return g_TotalZoneAllMaps[GetNativeCell(1)];
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{    
    if(IsPlayerAlive(client) && !IsFakeClient(client))
    {
        for(int Zone = 0; Zone < ZONE_COUNT; Zone++)
        {
            if(g_Properties[Zone].TriggerBased == false)
            {
                for(int ZoneNumber = 0; ZoneNumber < g_Properties[Zone].Count; ZoneNumber++)
                {
                    g_bInside[client][Zone][ZoneNumber] = IsClientInsideZone(client, g_Zones[Zone][ZoneNumber]);
                    
                    if(g_bInside[client][Zone][ZoneNumber] == true)
                    {
                        switch(Zone)
                        {
                            case MAIN_START:
                            {
                                if(g_Properties[MAIN_END].Ready[0] == true)
                                    StartTimer(client, TIMER_MAIN);
                            }
                            case MAIN_END:
                            {
                                if(IsBeingTimed(client, TIMER_MAIN))
                                    FinishTimer(client);
                            }
                            case BONUS_START:
                            {
                                if(g_Properties[BONUS_END].Ready[0] == true)
                                    StartTimer(client, TIMER_BONUS);
                            }
                            case BONUS_END:
                            {
                                if(IsBeingTimed(client, TIMER_BONUS))
                                    FinishTimer(client);
                            }
                            case SOLOBONUS_START:
                            {
                                if(g_Properties[SOLOBONUS_END].Ready[0] == true)
                                    StartTimer(client, TIMER_SOLOBONUS);
                            }
                            case SOLOBONUS_END:
                            {
                                if(IsBeingTimed(client, TIMER_SOLOBONUS))
                                    FinishTimer(client);
                            }
                            case ANTICHEAT:
                            {
                                if(IsBeingTimed(client, TIMER_MAIN) && g_Properties[Zone].Flags[ZoneNumber] & FLAG_ANTICHEAT_MAIN)
                                {
                                    StopTimer(client);
                                    
                                    PrintColorText(client, "%s%sYour timer was stopped for using a shortcut.",
                                        g_msg_start,
                                        g_msg_textcol);
                                }
                                else if(IsBeingTimed(client, TIMER_BONUS) && g_Properties[Zone].Flags[ZoneNumber] & FLAG_ANTICHEAT_BONUS)
                                {
                                    StopTimer(client);
                                    
                                    PrintColorText(client, "%s%sYour timer was stopped for using a shortcut.",
                                        g_msg_start,
                                        g_msg_textcol);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
