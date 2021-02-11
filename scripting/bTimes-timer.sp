#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = 
{
    name = "[bTimes] Timer",
    author = "blacky",
    description = "The timer portion of the bTimes plugin",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sourcemod>
#include <bTimes-zones>
#include <bTimes-teams>
#include <bTimes-timer>
#include <bTimes-ranks>
#include <bTimes-random>
#include <sdktools>
#include <sdkhooks>
#include <smlib/entities>
#include <cstrike>
#include <clientprefs>

#undef REQUIRE_PLUGIN
#include <bTimes-ghost>

#pragma newdecls required

enum
{
    GameType_CSS,
    GameType_CSGO
};

int g_GameType;

int g_MapAirAccelerate;

// database
Database g_DB;

// Current map info
char g_sMapName[64];

ArrayList g_MapList;

// Player timer info
float g_fCurrentTime[MAXPLAYERS + 1];
bool g_bTiming[MAXPLAYERS + 1];
bool g_bShownWR[MAXPLAYERS + 1];

StyleConfig g_StyleConfig[32];
int g_TotalStyles;

int g_Type[MAXPLAYERS + 1];
int g_Style[MAXPLAYERS + 1][MAX_TYPES];
    
bool g_bTimeIsLoaded[MAXPLAYERS + 1];
float g_fTime[MAXPLAYERS + 1][MAX_TYPES][MAX_STYLES];
char g_sTime[MAXPLAYERS + 1][MAX_TYPES][MAX_STYLES][64];

int g_Strafes[MAXPLAYERS + 1],
    g_Flashes[MAXPLAYERS + 1],
    g_Jumps[MAXPLAYERS + 1],
    g_SWStrafes[MAXPLAYERS + 1][2];
float g_HSWCounter[MAXPLAYERS + 1],
    g_fSpawnTime[MAXPLAYERS + 1];
    
float g_fNoClipSpeed[MAXPLAYERS + 1];

int g_Buttons[MAXPLAYERS + 1],
    g_UnaffectedButtons[MAXPLAYERS + 1];

ArrayList g_hSoundsArray,
    g_hSound_Path_Record,
    g_hSound_Position_Record,
    g_hSound_Path_Personal,
    g_hSound_Path_Fail;

bool g_bPaused[MAXPLAYERS + 1];
float g_fPauseTime[MAXPLAYERS + 1],
    g_fPausePos[MAXPLAYERS + 1][3];
    
float g_Fps[MAXPLAYERS + 1];
    
char g_msg_start[128],
    g_msg_varcol[128],
    g_msg_textcol[128];
    
// Warning
float g_fWarningTime[MAXPLAYERS + 1];

// Sync measurement
float g_fOldAngle[MAXPLAYERS + 1],
    g_totalSync[MAXPLAYERS + 1],
    g_goodSync[MAXPLAYERS + 1],
    g_goodSyncVel[MAXPLAYERS + 1];
    
// Hint text
float g_WorldRecord[MAX_TYPES][MAX_STYLES];
char g_sRecord[MAX_TYPES][MAX_STYLES][64];

// Cvars
ConVar g_hHintSpeed,
    g_hAllowYawspeed,
    g_hAllowPause,
    g_hChangeClanTag,
    g_hShowTimeLeft,
    g_hAdvancedSounds,
    g_hAllowNoClip,
    g_hVelocityCap,
    g_hAllowAuto,
    g_hJumpInStartZone,
    g_hAutoStopsTimer;
    
Handle g_hTimerChangeClanTag,
    g_hTimerDisplay;
    
bool g_bAllowVelocityCap,
    g_bAllowAuto,
    g_bJumpInStartZone,
    g_bAutoStopsTimer;
    
// All map times
ArrayList g_hTimes[MAX_TYPES][MAX_STYLES],
    g_hTimesUsers[MAX_TYPES][MAX_STYLES];
bool g_bTimesAreLoaded;
    
// Forwards
Handle g_fwdOnTimerFinished_Pre,
    g_fwdOnTimerFinished_Post,
    g_fwdOnTimerStart_Pre,
    g_fwdOnTimerStart_Post,
    g_fwdOnTimesDeleted,
    g_fwdOnTimesUpdated,
    g_fwdOnStylesLoaded,
    g_fwdOnTimesLoaded,
    g_fwdOnStyleChanged;
    
ConVar g_ConVar_AirAccelerate;
    
// Admin
bool g_bIsAdmin[MAXPLAYERS + 1];

bool g_bMapStart;

// Other plugins
bool g_bGhostPluginLoaded;

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
    
    // Connect to the database
    DB_Connect();
    
    // Server cvars
    g_hHintSpeed       = CreateConVar("timer_hintspeed", "0.1", "Changes the hint text update speed (bottom center text)", 0, true, 0.1);
    g_hAllowYawspeed   = CreateConVar("timer_allowyawspeed", "0", "Lets players use +left/+right commands without stopping their timer.", 0, true, 0.0, true, 1.0);
    g_hAllowPause      = CreateConVar("timer_allowpausing", "1", "Lets players use the !pause/!unpause commands.", 0, true, 0.0, true, 1.0);
    g_hChangeClanTag   = CreateConVar("timer_changeclantag", "1", "Means player clan tags will show their current timer time.", 0, true, 0.0, true, 1.0);
    g_hShowTimeLeft    = CreateConVar("timer_showtimeleft", "1", "Shows the time left until a map change on the right side of player screens.", 0, true, 0.0, true, 1.0);
    g_hAdvancedSounds  = CreateConVar("timer_advancedsounds", "1", "Reads record sound options from wrsounds_adv.txt", 0, true, 0.0, true, 1.0);
    g_hAllowNoClip     = CreateConVar("timer_noclip", "1", "Allows players to use the !p commands to noclip themselves.", 0, true, 0.0, true, 1.0);
    g_hVelocityCap     = CreateConVar("timer_velocitycap", "1", "Allows styles with a max velocity cap to cap player velocity.", 0, true, 0.0, true, 1.0);
    g_hJumpInStartZone = CreateConVar("timer_allowjumpinstart", "1", "Allows players to jump in the start zone. (This is not exactly anti-prespeed)", 0, true, 0.0, true, 1.0);
    g_hAllowAuto       = CreateConVar("timer_allowauto", "1", "Allows players to use auto bunnyhop.", 0, true, 0.0, true, 1.0);
    g_hAutoStopsTimer  = CreateConVar("timer_autostopstimer", "0", "Players can't get times with autohop on.");
    
    g_hHintSpeed.AddChangeHook(OnTimerHintSpeedChanged);
    g_hChangeClanTag.AddChangeHook(OnChangeClanTagChanged);
    g_hVelocityCap.AddChangeHook(OnVelocityCapChanged);
    g_hAutoStopsTimer.AddChangeHook(OnAutoStopsTimerChanged);
    g_hAllowAuto.AddChangeHook(OnAllowAutoChanged);
    g_hJumpInStartZone.AddChangeHook(OnAllowJumpInStartZoneChanged);
    
    AutoExecConfig(true, "timer", "timer");
    
    // Event hooks
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Pre);
    HookEvent("player_jump", Event_PlayerJump, EventHookMode_Pre);
    HookEvent("player_jump", Event_PlayerJump_Post, EventHookMode_Post);
    
    // Admin commands
    RegAdminCmd("sm_delete", SM_Delete, ADMFLAG_CHEATS, "Deletes map times.");
    RegAdminCmd("sm_spj", SM_SPJ, ADMFLAG_GENERIC, "Check the strafes per jump ratios for any player.");
    RegAdminCmd("sm_enablestyle", SM_EnableStyle, ADMFLAG_RCON, "Enables a style for players to use. (Resets to default setting on map change)");
    RegAdminCmd("sm_disablestyle", SM_DisableStyle, ADMFLAG_RCON, "Disables a style so players can no longer use it. (Resets to default setting on map change)");
    
    // Player commands
    RegConsoleCmdEx("sm_stop", SM_StopTimer, "Stops your timer.");
    RegConsoleCmdEx("sm_style", SM_Style, "Change your style.");
    RegConsoleCmdEx("sm_mode", SM_Style, "Change your style.");
    RegConsoleCmdEx("sm_bstyle", SM_BStyle, "Change your bonus style.");
    RegConsoleCmdEx("sm_bmode", SM_BStyle, "Change your bonus style.");
    RegConsoleCmdEx("sm_sbstyle", SM_SBStyle, "Change your solo bonus style.");
    RegConsoleCmdEx("sm_sbmode", SM_SBStyle, "Change your solo bonus style.");
    RegConsoleCmdEx("sm_practice", SM_Practice, "Puts you in noclip. Stops your timer.");
    RegConsoleCmdEx("sm_p", SM_Practice, "Puts you in noclip. Stops your timer.");
    RegConsoleCmdEx("sm_noclipme", SM_Practice, "Puts you in noclip. Stops your timer.");
    RegConsoleCmdEx("sm_fullhud", SM_Fullhud, "Shows all info in the hint text when being timed.");
    RegConsoleCmdEx("sm_maxinfo", SM_Fullhud, "Shows all info in the hint text when being timed.");
    RegConsoleCmdEx("sm_display", SM_Fullhud, "Shows all info in the hint text when being timed.");
    RegConsoleCmdEx("sm_hud", SM_Hud, "Change what shows up on the right side of your hud.");
    RegConsoleCmdEx("sm_truevel", SM_TrueVelocity, "Toggles between 2D and 3D velocity velocity meters");
    RegConsoleCmdEx("sm_velocity", SM_TrueVelocity, "Toggles between 2D and 3D velocity velocity meters");
    //RegConsoleCmdEx("sm_pause", SM_Pause, "Pauses your timer and freezes you.");
    //RegConsoleCmdEx("sm_unpause", SM_Unpause, "Unpauses your timer and unfreezes you.");
    //RegConsoleCmdEx("sm_resume", SM_Unpause, "Unpauses your timer and unfreezes you.");
    RegConsoleCmdEx("sm_fps", SM_Fps, "Shows a list of every player's fps_max value.");
    RegConsoleCmdEx("sm_auto", SM_Auto, "Toggles auto bunnyhop");
    RegConsoleCmdEx("sm_bhop", SM_Auto, "Toggles auto bunnyhop");
    RegConsoleCmdEx("sm_b", SM_B_, "");
    RegConsoleCmdEx("sm_bonus", SM_B_, "");
    RegConsoleCmdEx("sm_br", SM_B_, "");
    RegConsoleCmdEx("sm_sb", SM_SB_, "");
    RegConsoleCmdEx("sm_sbonus", SM_SB_, "");
    RegConsoleCmdEx("sm_sbr", SM_SB_, "");
    RegConsoleCmdEx("sm_r", SM_R_, "");
    RegConsoleCmdEx("sm_restart", SM_R_, "");
    RegConsoleCmdEx("sm_respawn", SM_R_, "");
    RegConsoleCmdEx("sm_start", SM_R_, "");
    
    // Makes FindTarget() work properly
    LoadTranslations("common.phrases");
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            g_hTimes[Type][Style]      = new ArrayList(2);
            g_hTimesUsers[Type][Style] = new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
        }
    }
    
    g_hSoundsArray           = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    g_hSound_Path_Record     = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    g_hSound_Position_Record = new ArrayList();
    g_hSound_Path_Personal   = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    g_hSound_Path_Fail       = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    
    g_ConVar_AirAccelerate = FindConVar( "sv_airaccelerate" );
    
    if ( g_ConVar_AirAccelerate == INVALID_HANDLE )
        SetFailState( "Unable to find cvar handle for sv_airaccelerate!" );
    
    int flags = g_ConVar_AirAccelerate.Flags;
    
    flags &= ~FCVAR_NOTIFY;
    //flags &= ~FCVAR_REPLICATED;
    
    g_ConVar_AirAccelerate.Flags = flags ;
    
}

public void OnAllPluginsLoaded()
{
    if(LibraryExists("ghost"))
    {
        g_bGhostPluginLoaded = true;
    }
    
    ReadStyleConfig();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Natives
    CreateNative("StartTimer", Native_StartTimer);
    CreateNative("StopTimer", Native_StopTimer);
    CreateNative("IsBeingTimed", Native_IsBeingTimed);
    CreateNative("FinishTimer", Native_FinishTimer);
    CreateNative("GetClientStyle", Native_GetClientStyle);
    CreateNative("IsTimerPaused", Native_IsTimerPaused);
    CreateNative("GetStyleName", Native_GetStyleName);
    CreateNative("GetStyleAbbr", Native_GetStyleAbbr);
    CreateNative("Style_IsEnabled", Native_Style_IsEnabled);
    CreateNative("Style_IsTypeAllowed", Native_Style_IsTypeAllowed);
    CreateNative("Style_IsFreestyleAllowed", Native_Style_IsFreestyleAllowed);
    CreateNative("Style_GetTotal", Native_Style_GetTotal);
    CreateNative("Style_CanUseReplay", Native_Style_CanUseReplay);
    CreateNative("Style_CanReplaySave", Native_Style_CanReplaySave);
    CreateNative("GetTypeStyleFromCommand", Native_GetTypeStyleFromCommand);
    CreateNative("GetClientTimerType", Native_GetClientTimerType);
    CreateNative("Style_GetConfig", Native_GetStyleConfig);
    CreateNative("Timer_GetButtons", Native_GetButtons);
    
    // Forwards
    g_fwdOnTimerStart_Pre     = CreateGlobalForward("OnTimerStart_Pre", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
    g_fwdOnTimerStart_Post    = CreateGlobalForward("OnTimerStart_Post", ET_Event, Param_Cell, Param_Cell, Param_Cell);
    g_fwdOnTimerFinished_Pre  = CreateGlobalForward("OnTimerFinished_Pre", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
    g_fwdOnTimerFinished_Post = CreateGlobalForward("OnTimerFinished_Post", ET_Event, Param_Cell, Param_Float, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_fwdOnTimesDeleted       = CreateGlobalForward("OnTimesDeleted", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Any);
    g_fwdOnTimesUpdated       = CreateGlobalForward("OnTimesUpdated", ET_Event, Param_String, Param_Cell, Param_Cell, Param_Any);
    g_fwdOnStylesLoaded       = CreateGlobalForward("OnStylesLoaded", ET_Event);
    g_fwdOnTimesLoaded        = CreateGlobalForward("OnMapTimesLoaded", ET_Event);
    g_fwdOnStyleChanged       = CreateGlobalForward("OnStyleChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    
    return APLRes_Success;
}

public void OnMapStart()
{
    // Set the map id
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    
    if(g_MapList != INVALID_HANDLE)
    {
        delete g_MapList;
    }
    
    g_MapList = new ArrayList(ByteCountToCells(64));
    ReadMapList(g_MapList);
    
    g_bTimesAreLoaded = false;
    
    char sTypeAbbr[32];
    char sStyleAbbr[32];
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        GetTypeAbbr(Type, sTypeAbbr, sizeof(sTypeAbbr), true);
        StringToUpper(sTypeAbbr);
        
        for(int Style; Style < g_TotalStyles; Style++)
        {
            GetStyleAbbr(Style, sStyleAbbr, sizeof(sStyleAbbr), true);
            StringToUpper(sStyleAbbr);
            
            FormatEx(g_sRecord[Type][Style], sizeof(g_sRecord[][]), "%sWR%s: Loading..", sTypeAbbr, sStyleAbbr);
        }
    }
    
    // Key hint text messages
    CreateTimer(1.0, Timer_SpecList, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    
    g_MapAirAccelerate = g_ConVar_AirAccelerate.IntValue;
    g_bMapStart = false;
    CreateTimer(3.0, Timer_GetAA, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_GetAA(Handle timer, any data)
{
    g_MapAirAccelerate = g_ConVar_AirAccelerate.IntValue;
    g_bMapStart = true;
    return Plugin_Continue;
}

public void OnStylesLoaded()
{
    RegConsoleCmdPerStyle("wr", SM_WorldRecord, "Show the world record info for {Type} timer on {Style} style.");
    RegConsoleCmdPerStyle("time", SM_Time, "Show your time for {Type} timer on {Style} style.");
    
    char sType[32];
    char sStyle[32];
    char sTypeAbbr[32];
    char sStyleAbbr[32];
    char sCommand[64];
    char sDescription[256];
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        GetTypeName(Type, sType, sizeof(sType));
        GetTypeAbbr(Type, sTypeAbbr, sizeof(sTypeAbbr), true);
        
        for(int Style; Style < g_TotalStyles; Style++)
        {
            if(Style_IsEnabled(Style) && g_StyleConfig[Style].AllowType[Type])
            {
                GetStyleName(Style, sStyle, sizeof(sStyle));
                GetStyleAbbr(Style, sStyleAbbr, sizeof(sStyleAbbr));
                
                FormatEx(sCommand, sizeof(sCommand), "sm_%s%s", sTypeAbbr, sStyleAbbr);
                FormatEx(sDescription, sizeof(sDescription), "Set your style to %s on the %s timer.", sStyle, sType);
                
                if(Type == TIMER_MAIN)
                    RegConsoleCmdEx(sCommand, SM_SetStyle, sDescription);
                else if(Type == TIMER_BONUS)
                    RegConsoleCmdEx(sCommand, SM_SetBonusStyle, sDescription);
                else if(Type == TIMER_SOLOBONUS)
                    RegConsoleCmdEx(sCommand, SM_SetSoloBonusStyle, sDescription);
            }
        }
    }
}

public void OnStyleChanged(int client, int oldStyle, int newStyle, int type)
{
    int oldAA = g_StyleConfig[oldStyle].AirAcceleration;
    int newAA = g_StyleConfig[newStyle].AirAcceleration;
    
    if(oldAA != newAA)
    {
        if(newAA == 0)
        {
            newAA = g_MapAirAccelerate;
        }
        PrintColorText(client, "%s%sYour airacceleration has been set to %s%d%s.",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            newAA,
            g_msg_textcol);
    }
    
    if(newAA == 0)
    {
        newAA = g_MapAirAccelerate;
    }
    
    SendNewAA(client, newAA);
}

public void OnConfigsExecuted()
{
    // Reset temporary enabled and disabled styles
    for(int Style; Style < g_TotalStyles; Style++)
    {
        g_StyleConfig[Style].TempEnabled = g_StyleConfig[Style].Enabled;
    }
    
    if(g_hChangeClanTag.IntValue == 0)
    {
        KillTimer(g_hTimerChangeClanTag);
    }
    else
    {
        g_hTimerChangeClanTag = CreateTimer(1.0, SetClanTag, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
    }
    
    if(g_hAdvancedSounds.BoolValue)
    {
        LoadRecordSounds_Advanced();
    }
    else
    {
        LoadRecordSounds();
    }
    
    g_hTimerDisplay = CreateTimer(g_hHintSpeed.FloatValue, Timer_DrawHintText, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
    
    g_bAllowVelocityCap = g_hVelocityCap.BoolValue;
    g_bAllowAuto        = g_hAllowAuto.BoolValue;
    g_bAutoStopsTimer   = g_hAutoStopsTimer.BoolValue;
    g_bJumpInStartZone  = g_hJumpInStartZone.BoolValue;
    
    ExecMapConfig();
}

public bool OnClientConnect(int client)
{
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            g_fTime[client][Type][Style] = 0.0;
            FormatEx(g_sTime[client][Type][Style], sizeof(g_sTime[][][]), "Best: Loading..");
        }
    }
    
    // Set player times to null
    g_bTimeIsLoaded[client] = false;
    
    // Unpause timers
    g_bPaused[client] = false;
    
    // Reset noclip speed
    g_fNoClipSpeed[client] = 1.0;
    
    // Set style to first available style for each timer type
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            if(Style_IsEnabled(Style) && g_StyleConfig[Style].AllowType[Type])
            {
                g_Style[client][Type] = Style;
                break;
            }
        }
    }
    
    g_bIsAdmin[client] = false;
    
    g_fNoClipSpeed[client] = 1.0;
    
    return true;
}

public void OnClientPutInServer(int client)
{
    QueryClientConVar(client, "fps_max", OnFpsMaxRetrieved);
    g_Flashes[client] = 0;
    SDKHook(client, SDKHook_PreThink, Hook_PreThink);
}

public void Hook_PreThink(int client)
{
    if(!IsFakeClient(client) && g_bMapStart)
    {
        if(g_StyleConfig[g_Style[client][g_Type[client]]].AirAcceleration == 0)
        {
            g_ConVar_AirAccelerate.SetInt(g_MapAirAccelerate);
        }
        else
        {
            g_ConVar_AirAccelerate.IntValue = g_StyleConfig[g_Style[client][g_Type[client]]].AirAcceleration;
        }
    }
}

public void OnFpsMaxRetrieved(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
    g_Fps[client] = StringToFloat(cvarValue);
    
    if(g_Fps[client] > 1000)
        g_Fps[client] = 1000.0;
}

public void OnClientPostAdminCheck(int client)
{
    g_bIsAdmin[client] = GetUserAdmin(client).HasFlag(Admin_Generic, Access_Effective);
}

public int OnPlayerIDLoaded(int client)
{
    if(g_bTimesAreLoaded == true)
    {
        DB_LoadPlayerInfo(client);
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

public void OnZonesLoaded()
{    
    DB_LoadTimes(true);
}

public void OnTimerHintSpeedChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    KillTimer(g_hTimerDisplay);
    
    g_hTimerDisplay = CreateTimer(convar.FloatValue, Timer_DrawHintText, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public void OnChangeClanTagChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if(convar.IntValue == 0)
    {
        KillTimer(g_hTimerChangeClanTag);
    }
    else
    {
        g_hTimerChangeClanTag = CreateTimer(1.0, SetClanTag, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
    }
}

public void OnVelocityCapChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_bAllowVelocityCap = view_as<bool>(StringToInt(newValue));
}

public void OnAutoStopsTimerChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if(StringToInt(newValue) == 1)
    {
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientInGame(client) && IsBeingTimed(client, TIMER_ANY) && (GetClientSettings(client) & AUTO_BHOP))
            {
                StopTimer(client);
            }
        }
    }
}

public void OnAllowJumpInStartZoneChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_bJumpInStartZone = view_as<bool>(StringToInt(newValue));
}

public void OnAllowAutoChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_bAllowAuto = view_as<bool>(StringToInt(newValue));
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    // Player timers should stop when they die
    StopTimer(client);
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    // Player timers should stop when they switch teams
    StopTimer(client);
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    // Anti-time-cheat
    g_fSpawnTime[client] = GetEngineTime();
    
    // Player timers should stop when they spawn
    StopTimer(client);
}

public Action Event_PlayerJump(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    // Increase jump count for the hud hint text, it resets to 0 when StartTimer for the client is called
    if(g_bTiming[client] == true)
    {
        g_Jumps[client]++;
    }
    
    int Style = g_Style[client][g_Type[client]];
    
    if(g_StyleConfig[Style].EzHop == true)
    {
        SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
    }
    else if(g_StyleConfig[Style].Freestyle && g_StyleConfig[Style].Freestyle_EzHop)
    {
        if(Timer_InsideZone(client, FREESTYLE, 1 << Style) != -1)
        {
            SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
        }
    }
}

public Action Event_PlayerJump_Post(Event event, const char[] name, bool dontBroadcast)
{
    // Check max velocity on player jump event rather than OnPlayerRunCmd, rewards better strafing
    if(g_bAllowVelocityCap == true)
    {
        int client = GetClientOfUserId(event.GetInt("userid"));
        
        int Style = g_Style[client][g_Type[client]];
        
        if(g_bAllowVelocityCap == true && g_StyleConfig[Style].MaxVel != 0.0)
        {
            // Has to be on next game frame, TeleportEntity doesn't seem to work in event player_jump
            CreateTimer(0.0, Timer_CheckVel, client);
        }
    }
}

public Action Timer_CheckVel(Handle timer, any client)
{
    int Style = g_Style[client][g_Type[client]];
    
    float fVel = GetClientVelocity(client, true, true, false);
        
    if(fVel > g_StyleConfig[Style].MaxVel)
    {
        float vVel[3];
        Entity_GetAbsVelocity(client, vVel);
        
        float fTemp = vVel[2];
        ScaleVector(vVel, g_StyleConfig[Style].MaxVel/fVel);
        vVel[2] = fTemp;
        
        TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vVel);
    }
}

public Action SM_B_(int client, int args)
{
    SetStyle(client, TIMER_BONUS, GetStyle(client));
    return Plugin_Handled;
}

public Action SM_SB_(int client, int args)
{
    SetStyle(client, TIMER_SOLOBONUS, GetStyle(client));
    return Plugin_Handled;
}

public Action SM_R_(int client, int args)
{
    SetStyle(client, TIMER_MAIN, GetStyle(client));
    return Plugin_Handled;
}

// Auto bhop
public Action SM_Auto(int client, int args)
{
    if(g_bAllowAuto == true)
    {
        if (args < 1)
        {
            SetClientSettings(client, GetClientSettings(client) ^ AUTO_BHOP);
            
            if(g_bAutoStopsTimer && (GetClientSettings(client) & AUTO_BHOP))
            {
                StopTimer(client);
            }
            
            if(GetClientSettings(client) & AUTO_BHOP)
            {
                PrintColorText(client, "%s%sAuto bhop %senabled",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol);
            }
            else
            {
                PrintColorText(client, "%s%sAuto bhop %sdisabled",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol);
            }
        }
        else if (args == 1)
        {
            char TargetArg[128];
            GetCmdArgString(TargetArg, sizeof(TargetArg));
            int TargetID = FindTarget(client, TargetArg, true, false);
            if(TargetID != -1)
            {
                char TargetName[128];
                GetClientName(TargetID, TargetName, sizeof(TargetName));
                if(GetClientSettings(TargetID) & AUTO_BHOP)
                {
                    PrintColorText(client, "%s%sPlayer %s%s%s has auto bhop %senabled",
                        g_msg_start,
                        g_msg_textcol,
                        g_msg_varcol,
                        TargetName,
                        g_msg_textcol,
                        g_msg_varcol);
                }
                else
                {
                    PrintColorText(client, "%s%sPlayer %s%s%s has auto bhop %sdisabled",
                        g_msg_start,
                        g_msg_textcol,
                        g_msg_varcol,
                        TargetName,
                        g_msg_textcol,
                        g_msg_varcol);
                }
            }
        }
    }
    
    return Plugin_Handled;
}

// Toggles amount of info display in hint text area
public Action SM_Fullhud(int client, int args)
{
    SetClientSettings(client, GetClientSettings(client) ^ SHOW_HINT);
    
    if(GetClientSettings(client) & SHOW_HINT)
    {
        PrintColorText(client, "%s%sShowing advanced timer hint text.", 
            g_msg_start, 
            g_msg_textcol);
    }
    else
    {
        PrintColorText(client, "%s%sShowing simple timer hint text.", 
            g_msg_start, 
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

// Toggles between 2d vector and 3d vector velocity
public Action SM_TrueVelocity(int client, int args)
{    
    SetClientSettings(client, GetClientSettings(client) ^ SHOW_2DVEL);
    
    if(GetClientSettings(client) & SHOW_2DVEL)
    {
        PrintColorText(client, "%s%sShowing %strue %svelocity",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            g_msg_textcol);
    }
    else
    {
        PrintColorText(client, "%s%sShowing %snormal %svelocity",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_SPJ(int client, int args)
{
    // Get target
    char sArg[255];
    GetCmdArgString(sArg, sizeof(sArg));
    
    // Write data to send to query callback
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(sArg);
    
    // Do query
    char query[512];
    Format(query, sizeof(query), "SELECT User, SPJ, SteamID, MStrafes, MJumps FROM (SELECT t2.User, t2.SteamID, AVG(t1.Strafes/t1.Jumps) AS SPJ, SUM(t1.Strafes) AS MStrafes, SUM(t1.Jumps) AS MJumps FROM times AS t1, players AS t2 WHERE t1.PlayerID=t2.PlayerID  AND t1.Style=0 GROUP BY t1.PlayerID ORDER BY AVG(t1.Strafes/t1.Jumps) DESC) AS x WHERE MStrafes > 100");
    g_DB.Query(SPJ_Callback, query, pack);
    
    return Plugin_Handled;
}

public void SPJ_Callback(Database db, DBResultSet results, char[] error, any datapack)
{
    DataPack pack = view_as<DataPack>(datapack);
    if(results != INVALID_HANDLE)
    {
        // Get data from command arg
        char sTarget[MAX_NAME_LENGTH];
        
        pack.Reset();
        int client = GetClientOfUserId(pack.ReadCell());
        pack.ReadString(sTarget, sizeof(sTarget));
        
        int len = strlen(sTarget);
        
        char item[255];
        char info[255];
        char sAuth[32];
        char sName[MAX_NAME_LENGTH];
        float SPJ;
        int Strafes, Jumps;
        
        // Create menu
        Menu menu = new Menu(Menu_ShowSPJ);
        menu.SetTitle("Showing strafes per jump\nSelect an item for more info\n ");
        
        int rows = results.RowCount;
        for(int i=0; i<rows; i++)
        {
            results.FetchRow();
            
            results.FetchString(0, sName, sizeof(sName));
            SPJ = results.FetchFloat(1);
            results.FetchString(2, sAuth, sizeof(sAuth));
            Strafes = results.FetchInt(3);
            Jumps = results.FetchInt(4);
            
            if(StrContains(sName, sTarget) != -1 || len == 0)
            {
                Format(item, sizeof(item), "%.1f - %s",
                    SPJ,
                    sName);
                
                Format(info, sizeof(info), "%s <%s> SPJ: %.1f, Strafes: %d, Jumps: %d",
                    sName,
                    sAuth,
                    SPJ,
                    Strafes,
                    Jumps);
                    
                menu.AddItem(info, item);
            }
        }
        
        menu.Display(client, MENU_TIME_FOREVER);
    }
    else
    {
        LogError(error);
    }
    
    delete pack;
}

public int Menu_ShowSPJ(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[255];
        menu.GetItem(param2, info, sizeof(info));
        PrintToChat(param1, info);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
}

// Admin command for deleting times
public Action SM_Delete(int client, int args)
{
    if(args == 0)
    {
        if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
            PrintToConsole(client, "[SM] Usage:\nsm_delete record - Deletes a specific record.\nsm_delete record1 record2 - Deletes all times from record1 to record2.");
    }
    else if(args == 1)
    {
        char input[128];
        GetCmdArgString(input, sizeof(input));
        int value = StringToInt(input);
        if(value != 0)
        {
            AdminCmd_DeleteRecord(client, value, value);
        }
    }
    else if(args == 2)
    {
        char sValue0[128];
        char sValue1[128];
        GetCmdArg(1, sValue0, sizeof(sValue0));
        GetCmdArg(2, sValue1, sizeof(sValue1));
        AdminCmd_DeleteRecord(client, StringToInt(sValue0), StringToInt(sValue1));
    }
    
    return Plugin_Handled;
}

void AdminCmd_DeleteRecord(int client, int value1, int value2)
{
    Menu menu = new Menu(AdminMenu_DeleteRecord);
    
    if(value1 == value2)
        menu.SetTitle("Delete record %d", value1);
    else
        menu.SetTitle("Delete records %d to %d", value1, value2);
    
    char sDisplay[64];
    char sInfo[32];
    char sStyle[32];
    char sType[32];
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        GetTypeName(Type, sType, sizeof(sType));
        
        for(int Style; Style < g_TotalStyles; Style++)
        {
            if(Style_IsEnabled(Style) && g_StyleConfig[Style].AllowType[Type])
            {
                Format(sInfo, sizeof(sInfo), "%d;%d;%d;%d", value1, value2, Type, Style);
                
                GetStyleName(Style, sStyle, sizeof(sStyle));
                
                FormatEx(sDisplay, sizeof(sDisplay), "%s (%s)", sStyle, sType);
                
                menu.AddItem(sInfo, sDisplay);
            }
        }
    }
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int AdminMenu_DeleteRecord(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        char sTypeStyle[4][8];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrContains(info, ";") != -1)
        {
            ExplodeString(info, ";", sTypeStyle, 4, 8);
            
            int RecordOne = StringToInt(sTypeStyle[0]);
            int RecordTwo = StringToInt(sTypeStyle[1]);
            int Type      = StringToInt(sTypeStyle[2]);
            int Style     = StringToInt(sTypeStyle[3]);
            
            DB_DeleteRecord(param1, Type, Style, RecordOne, RecordTwo);
            //DB_UpdateRanks(g_sMapName, Type, Style);
        }
    }
    else if (action == MenuAction_End)
        delete menu;
}

public Action SM_StopTimer(int client, int args)
{
    StopTimer(client);
    
    return Plugin_Handled;
}

public Action SM_WorldRecord(int client, int args)
{
    int Type, Style;
    if(GetTypeStyleFromCommand("wr", Type, Style))
    {
        if(!IsSpamming(client))
        {
            SetIsSpamming(client, 1.0);
            
            if(args == 0)
            {
                DB_DisplayRecords(client, g_sMapName, Type, Style);
            }
            else if(args == 1)
            {
                char arg[64];
                GetCmdArgString(arg, sizeof(arg));
                if(g_MapList.FindString(arg) != -1)
                {
                    DB_DisplayRecords(client, arg, Type, Style);
                }
                else
                {
                    PrintColorText(client, "%s%sNo map found named %s%s",
                        g_msg_start,
                        g_msg_textcol,
                        g_msg_varcol,
                        arg);
                }
            }
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Time(int client, int args)
{
    int Type, Style;
    if(GetTypeStyleFromCommand("time", Type, Style))
    {
        if(!IsSpamming(client))
        {
            SetIsSpamming(client, 1.0);
            
            if(args == 0)
            {
                DB_ShowTime(client, client, g_sMapName, Type, Style);
            }
            else if(args == 1)
            {
                char arg[250];
                GetCmdArgString(arg, sizeof(arg));
                if(arg[0] == '@')
                {
                    ReplaceString(arg, 250, "@", "");
                    DB_ShowTimeAtRank(client, g_sMapName, StringToInt(arg), Type, Style);
                }
                else
                {
                    int target = FindTarget(client, arg, true, false);
                    bool mapValid = (g_MapList.FindString(arg) != -1);
                    if(mapValid == true)
                    {
                        DB_ShowTime(client, client, arg, Type, Style);
                    }
                    if(target != -1)
                    {
                        DB_ShowTime(client, target, g_sMapName, Type, Style);
                    }
                    if(!mapValid && target == -1)
                    {
                        PrintColorText(client, "%s%sNo map or player found named %s%s",
                            g_msg_start,
                            g_msg_textcol,
                            g_msg_varcol,
                            arg);
                    }
                }
            }
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Style(int client, int args)
{
    Menu menu = new Menu(Menu_Style);
    
    menu.SetTitle("Change Style");
    char sStyle[32];
    char sInfo[16];
    
    for(int Style; Style < g_TotalStyles; Style++)
    {
        if(Style_IsEnabled(Style) && g_StyleConfig[Style].AllowType[TIMER_MAIN])
        {
            GetStyleName(Style, sStyle, sizeof(sStyle));
            
            FormatEx(sInfo, sizeof(sInfo), "%d;%d", TIMER_MAIN, Style);
            
            menu.AddItem(sInfo, sStyle);
        }
    }
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
    
    return Plugin_Handled;
}

public Action SM_BStyle(int client, int args)
{
    Menu menu = new Menu(Menu_Style);
    
    menu.SetTitle("Change Bonus Style");
    char sStyle[32];
    char sInfo[16];
    
    for(int Style; Style < g_TotalStyles; Style++)
    {
        if(Style_IsEnabled(Style) && g_StyleConfig[Style].AllowType[TIMER_BONUS])
        {
            GetStyleName(Style, sStyle, sizeof(sStyle));
            
            FormatEx(sInfo, sizeof(sInfo), "%d;%d", TIMER_BONUS, Style);
            
            menu.AddItem(sInfo, sStyle);
        }
    }
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
    
    return Plugin_Handled;
}

public Action SM_SBStyle(int client, int args)
{
    Menu menu = new Menu(Menu_Style);
    
    menu.SetTitle("Change Solo Bonus Style");
    char sStyle[32];
    char sInfo[16];
    
    for(int Style; Style < g_TotalStyles; Style++)
    {
        if(Style_IsEnabled(Style) && g_StyleConfig[Style].AllowType[TIMER_SOLOBONUS])
        {
            GetStyleName(Style, sStyle, sizeof(sStyle));
            
            FormatEx(sInfo, sizeof(sInfo), "%d;%d", TIMER_SOLOBONUS, Style);
            
            menu.AddItem(sInfo, sStyle);
        }
    }
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
    
    return Plugin_Handled;
}

public Action SM_SetStyle(int client, int args)
{
    char sCommand[64];
    GetCmdArg(0, sCommand, sizeof(sCommand));
    ReplaceStringEx(sCommand, sizeof(sCommand), "sm_", "");
    
    char sStyle[32];
    for(int Style; Style < g_TotalStyles; Style++)
    {
        if(Style_IsEnabled(Style) && g_StyleConfig[Style].AllowType[TIMER_MAIN])
        {
            GetStyleAbbr(Style, sStyle, sizeof(sStyle));
            
            if(StrEqual(sCommand, sStyle))
            {
                SetStyle(client, TIMER_MAIN, Style);
            }
        }
    }
    
    return Plugin_Handled;
}

public Action SM_SetBonusStyle(int client, int args)
{
    char sCommand[64];
    GetCmdArg(0, sCommand, sizeof(sCommand));
    ReplaceStringEx(sCommand, sizeof(sCommand), "sm_b", "");
    
    char sStyle[32];
    for(int Style; Style < g_TotalStyles; Style++)
    {
        if(Style_IsEnabled(Style) && g_StyleConfig[Style].AllowType[TIMER_BONUS])
        {
            GetStyleAbbr(Style, sStyle, sizeof(sStyle));
            
            if(StrEqual(sCommand, sStyle))
            {
                SetStyle(client, TIMER_BONUS, Style);
            }
        }
    }
    
    return Plugin_Handled;
}

public Action SM_SetSoloBonusStyle(int client, int args)
{
    char sCommand[64];
    GetCmdArg(0, sCommand, sizeof(sCommand));
    ReplaceStringEx(sCommand, sizeof(sCommand), "sm_sb", "");
    
    char sStyle[32];
    for(int Style; Style < g_TotalStyles; Style++)
    {
        if(Style_IsEnabled(Style) && g_StyleConfig[Style].AllowType[TIMER_SOLOBONUS])
        {
            GetStyleAbbr(Style, sStyle, sizeof(sStyle));
            
            if(StrEqual(sCommand, sStyle))
            {
                SetStyle(client, TIMER_SOLOBONUS, Style);
            }
        }
    }
    
    return Plugin_Handled;
}

public int Menu_Style(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrContains(info, ";") != -1)
        {
            char sInfoExplode[2][16];
            ExplodeString(info, ";", sInfoExplode, sizeof(sInfoExplode), sizeof(sInfoExplode[]));
            
            SetStyle(client, StringToInt(sInfoExplode[0]), StringToInt(sInfoExplode[1]));
        }
    }
    else if(action == MenuAction_End)
        delete menu;
}

void SetStyle(int client, int Type, int Style)
{
    int OldStyle = g_Style[client][Type];
    
    g_Style[client][Type] = Style;
    g_Type[client] = Type;
    StopTimer(client);
    
    if(Type == TIMER_MAIN)
        Timer_TeleportToZone(client, MAIN_START, 0, true);
    else if(Type == TIMER_BONUS)
        Timer_TeleportToZone(client, BONUS_START, 0, true);
    else if(Type == TIMER_SOLOBONUS)
        Timer_TeleportToZone(client, SOLOBONUS_START, 0, true);
    
    Call_StartForward(g_fwdOnStyleChanged);
    Call_PushCell(client);
    Call_PushCell(OldStyle);
    Call_PushCell(Style);
    Call_PushCell(Type);
    Call_Finish();
}

public Action SM_Practice(int client, int args)
{
    if(g_hAllowNoClip.BoolValue)
    {
        if(args == 0)
        {
            StopTimer(client);
            
            MoveType movetype = GetEntityMoveType(client);
            if (movetype != MOVETYPE_NOCLIP)
            {
                SetEntityMoveType(client, MOVETYPE_NOCLIP);
                SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fNoClipSpeed[client]);
            }
            else
            {
                SetEntityMoveType(client, MOVETYPE_WALK);
                SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
            }
        }
        else
        {
            char sArg[250];
            GetCmdArgString(sArg, sizeof(sArg));
            
            float fSpeed = StringToFloat(sArg);
            
            if(!(0 <= fSpeed <= 10))
            {
                PrintColorText(client, "%s%sYour noclip speed must be between 0 and 10",
                    g_msg_start,
                    g_msg_textcol);
                    
                return Plugin_Handled;
            }
            
            g_fNoClipSpeed[client] = fSpeed;
        
            PrintColorText(client, "%s%sNoclip speed changed to %s%f%s%s",
                g_msg_start,
                g_msg_textcol,
                g_msg_varcol,
                fSpeed,
                g_msg_textcol,
                (fSpeed != 1.0)?" (Default is 1)":" (Default)");
                
            if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
            {
                SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", fSpeed);
            }
        }
        
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public Action SM_Pause(int client, int args)
{
    if(g_hAllowPause.BoolValue)
    {
        if(Timer_InsideZone(client, MAIN_START, -1) == -1 && Timer_InsideZone(client, BONUS_START, -1) == -1)
        {
            if(g_bTiming[client] == true)
            {
                if(g_bPaused[client] == false)
                {
                    if(GetClientVelocity(client, true, true, true) == 0.0)
                    {
                        GetEntPropVector(client, Prop_Send, "m_vecOrigin", g_fPausePos[client]);
                        g_fPauseTime[client] = g_fCurrentTime[client];
                        g_bPaused[client]      = true;
                        
                        PrintColorText(client, "%s%sTimer paused.",
                            g_msg_start,
                            g_msg_textcol);
                    }
                    else
                    {
                        PrintColorText(client, "%s%sYou can't pause while moving.",
                            g_msg_start,
                            g_msg_textcol);
                    }
                }
                else
                {
                    PrintColorText(client, "%s%sYou are already paused.",
                        g_msg_start,
                        g_msg_textcol);
                }
            }
            else
            {
                PrintColorText(client, "%s%sYou have no timer running.",
                    g_msg_start,
                    g_msg_textcol);
            }
        }
        else
        {
            PrintColorText(client, "%s%sYou can't pause while inside a starting zone.",
                g_msg_start,
                g_msg_textcol);
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Unpause(int client, int args)
{
    if(g_hAllowPause.BoolValue)
    {
        if(g_bTiming[client] == true)
        {
            if(g_bPaused[client] == true)
            {
                // Teleport player to the position they paused at
                TeleportEntity(client, g_fPausePos[client], NULL_VECTOR, view_as<float>({0, 0, 0}));
                
                // Set their new start time
                g_fCurrentTime[client] = g_fPauseTime[client];
                
                // Unpause
                g_bPaused[client] = false;
                
                PrintColorText(client, "%s%sTimer unpaused.",
                    g_msg_start,
                    g_msg_textcol);
            }
            else
            {
                PrintColorText(client, "%s%sYou are not currently paused.",
                    g_msg_start,
                    g_msg_textcol);
            }
        }
        else
        {
            PrintColorText(client, "%s%sYou have no timer running.",
                g_msg_start,
                g_msg_textcol);
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Hud(int client, int args)
{
    OpenHudMenu(client);
    
    return Plugin_Handled;
}

public Action SM_Fps(int client, int args)
{
    Menu hMenu = new Menu(Menu_Fps);
    hMenu.SetTitle("List of player fps_max values");
    
    char sFps[64];
    for(int target = 1; target <= MaxClients; target++)
    {
        if(IsClientInGame(target) && !IsFakeClient(target))
        {
            FormatEx(sFps, sizeof(sFps), "%N - %.3f", target, g_Fps[target]);
            hMenu.AddItem("", sFps);
        }
    }
    
    hMenu.Display(client, MENU_TIME_FOREVER);
    
    return Plugin_Handled;
}

public int Menu_Fps(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_End)
        delete menu;
}

void OpenHudMenu(int client)
{
    Menu menu = new Menu(Menu_Hud);
    menu.SetTitle("Hud control");
    
    int settings = GetClientSettings(client);
    
    char sInfo[16];
    
    //IntToString(KH_TIMELEFT, sInfo, sizeof(sInfo));
    //Format(sInfo, sizeof(sInfo), ";%s", sInfo);
    //menu.AddItem(sInfo, (settings & KH_TIMELEFT)?"Timeleft: On":"Timeleft: Off");
    
    IntToString(KH_RECORD, sInfo, sizeof(sInfo));
    Format(sInfo, sizeof(sInfo), ";%s", sInfo);
    menu.AddItem(sInfo, (settings & KH_RECORD)?"World record: On":"World record: Off");
    
    IntToString(KH_BEST, sInfo, sizeof(sInfo));
    Format(sInfo, sizeof(sInfo), ";%s", sInfo);
    menu.AddItem(sInfo, (settings & KH_BEST)?"Personal best: On":"Personal best: Off");
    
    IntToString(KH_SPECS, sInfo, sizeof(sInfo));
    Format(sInfo, sizeof(sInfo), ";%s", sInfo);
    menu.AddItem(sInfo, (settings & KH_SPECS)?"Spectator count: On":"Spectator count: Off");
    
    IntToString(KH_SYNC, sInfo, sizeof(sInfo));
    Format(sInfo, sizeof(sInfo), ";%s", sInfo);
    menu.AddItem(sInfo, (settings & KH_SYNC)?"Sync: On":"Sync: Off");
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Hud(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));
        
        if(sInfo[0] == ';')
        {
            ReplaceString(sInfo, sizeof(sInfo), ";", "");
            
            int iInfo = StringToInt(sInfo);
            SetClientSettings(param1, GetClientSettings(param1) ^ iInfo);
            
            OpenHudMenu(param1);
        }
    }
    else if(action == MenuAction_End)
        delete menu;
}

public Action SM_EnableStyle(int client, int args)
{
    if(args == 1)
    {
        char sArg[32];
        GetCmdArg(1, sArg, sizeof(sArg));
        int Style = StringToInt(sArg);
        
        if(0 <= Style < g_TotalStyles)
        {
            g_StyleConfig[Style].TempEnabled = true;
            ReplyToCommand(client, "[Timer] - Style '%d' has been enabled.", Style);
        }
        else
        {
            ReplyToCommand(client, "[Timer] - Style '%d' is not a valid style number. It will not be enabled.", Style);
        }
    }
    else
    {
        ReplyToCommand(client, "[Timer] - Example: \"sm_enablestyle 1\" will enable the style with number value of 1 in the styles.cfg");
    }
    
    return Plugin_Handled;
}

public Action SM_DisableStyle(int client, int args)
{
    if(args == 1)
    {
        char sArg[32];
        GetCmdArg(1, sArg, sizeof(sArg));
        int Style = StringToInt(sArg);
        
        if(0 <= Style < g_TotalStyles)
        {
            g_StyleConfig[Style].TempEnabled = false;
            ReplyToCommand(client, "[Timer] - Style '%d' has been disabled.", Style);
        }
        else
        {
            ReplyToCommand(client, "[Timer] - Style '%d' is not a valid style number. It will not be disabled.", Style);
        }
    }
    else
    {
        ReplyToCommand(client, "[Timer] - Example: \"sm_disablestyle 1\" will disable the style with number value of 1 in the styles.cfg");
    }
    
    return Plugin_Handled;
}

public Action SetClanTag(Handle timer, any data)
{
    char sTag[32];
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            if(IsPlayerAlive(client) && !IsFakeClient(client))
            {
                GetClanTagString(client, sTag, sizeof(sTag));
                CS_SetClientClanTag(client, sTag);
            }
        }
    }
}

void GetClanTagString(int client, char[] tag, int maxlength)
{
    if(g_bTiming[client] == true)
    {
        if(Timer_InsideZone(client, MAIN_START, -1) != -1 || Timer_InsideZone(client, BONUS_START, -1) != -1 || Timer_InsideZone(client, SOLOBONUS_START, -1) != -1)
        {
            FormatEx(tag, maxlength, "START");
            return;
        }
        else if(g_bPaused[client])
        {
            FormatEx(tag, maxlength, "PAUSED");
            return;
        }
        else
        {
            GetTypeAbbr(g_Type[client], tag, maxlength, true);
            Format(tag, maxlength, "%s%s :: ", tag, g_StyleConfig[g_Style[client][g_Type[client]]].Name_Short);
            StringToUpper(tag);
            
            char sTime[32];
            float fTime = GetClientTimer(client);
            FormatPlayerTime(fTime, sTime, sizeof(sTime), false, 0);
            SplitString(sTime, ".", sTime, sizeof(sTime));
            Format(tag, maxlength, "%s%s", tag, sTime);
        }
    }
    else
    {
        FormatEx(tag, maxlength, "NO TIMER");
    }
}

public Action Timer_DrawHintText(Handle timer, any data)
{
    char sHintMessage[256];
    
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsFakeClient(client))
        {
            int Time = RoundToFloor(g_fTime[client][TIMER_MAIN][0]);
            if(g_fTime[client][TIMER_MAIN][0] == 0.0 || g_fTime[client][TIMER_MAIN][0] > 2000.0)
                Time = 2000;
            SetEntProp(client, Prop_Data, "m_iFrags", -Time);
            
            if(GetHintMessage(client, sHintMessage, sizeof(sHintMessage)))
            {
                if(g_GameType == GameType_CSS)
                    PrintHintText(client, sHintMessage);
            }
        }
    }
}

bool GetHintMessage(int client, char[] buffer, int maxlength)
{
    FormatEx(buffer, maxlength, "");
    
    int target;
    
    if(IsPlayerAlive(client))
    {
        target = client;
    }
    else
    {
        target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        int mode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        if(!((0 < target <= MaxClients) && (mode == 4 || mode == 5)))
            return false;
        
        if(IsFakeClient(target))
            return false;
    }
    
    int settings = GetClientSettings(client);
    
    if(Timer_InsideZone(target, MAIN_START) != -1 || Timer_InsideZone(target, BONUS_START) != -1 || Timer_InsideZone(target, SOLOBONUS_START) != -1)
    {
        FormatEx(buffer, maxlength, "In Start Zone\n \n%d",
            RoundToFloor(GetClientVelocity(target, true, true, !view_as<bool>((settings & SHOW_2DVEL)))));
    }
    else
    {
        if(g_bTiming[target])
        {
            if(g_bPaused[target] == false)
            {
                if(settings & SHOW_HINT)
                {
                    GetTimerAdvancedString(target, buffer, maxlength);
                }
                else
                {
                    GetTimerSimpleString(target, buffer, maxlength);
                }
            }
            else
            {
                GetTimerPauseString(target, buffer, maxlength);
            }
        }
        else
        {
            FormatEx(buffer, maxlength, "%d",
                RoundToFloor(GetClientVelocity(target, true, true, !view_as<bool>((settings & SHOW_2DVEL)))));
        }
    }
    
    return true;
}

void GetTimerAdvancedString(int client, char[] sResult, int maxlength)
{    
    FormatEx(sResult, maxlength, "");
    
    int Style    = g_Style[client][g_Type[client]];
    
    if(g_Type[client] == TIMER_BONUS)
        FormatEx(sResult, maxlength, "Bonus\n");
    else if(g_Type[client] == TIMER_SOLOBONUS)
        FormatEx(sResult, maxlength, "Solo Bonus\n");
    
    if(g_StyleConfig[Style].Hud_Style)
    {
        Format(sResult, maxlength, "%s%s", sResult, g_StyleConfig[Style].Name);
        
        if(g_StyleConfig[Style].Freestyle)
        {
            if(Timer_InsideZone(client, FREESTYLE, 1 << Style) != -1)
                Format(sResult, maxlength, "%s (FS)", sResult);
        }
        
        Format(sResult, maxlength, "%s\n", sResult);
    }
    
    float fTime = GetClientTimer(client);
    char sTime[32];
    FormatPlayerTime(fTime, sTime, sizeof(sTime), false, 0);
    Format(sResult, maxlength, "%sTime: %s (%d)\n", sResult, sTime, GetPlayerPosition(fTime, g_Type[client], Style));
    
    if(g_StyleConfig[Style].Hud_Jumps)
    {
        Format(sResult, maxlength, "%sJumps: %d\n", sResult, g_Jumps[client]);
    }
    
    if(g_StyleConfig[Style].Hud_Strafes)
    {
        Format(sResult, maxlength, "%sStrafes: %d\n", sResult, g_Strafes[client]);
    }
    
    if(g_Type[client] != TIMER_SOLOBONUS)
    {
        Format(sResult, maxlength, "%sFlashes: %d\n", sResult, g_Flashes[client]);
    }
    
    Format(sResult, maxlength, "%sSpeed: %d", sResult, RoundToFloor(GetClientVelocity(client, true, true, (GetClientSettings(client) & SHOW_2DVEL) == 0)));
}

void GetTimerSimpleString(int client, char[] sResult, int maxlength)
{
    float fTime = GetClientTimer(client);
    
    char sTime[32];
    FormatPlayerTime(fTime, sTime, sizeof(sTime), false, 0);
    Format(sResult, maxlength, "%s", sTime);
}

void GetTimerPauseString(int client, char[] buffer, int maxlen)
{
    float fTime = g_fPauseTime[client];
    
    char sTime[32];
    FormatPlayerTime(fTime, sTime, sizeof(sTime), false, 0);
    
    Format(buffer, maxlen, "Paused\n \nTime: %s", sTime);
}

int GetPlayerPosition(const float Time, int Type, int Style)
{    
    if(g_bTimesAreLoaded == true)
    {
        int iSize = g_hTimes[Type][Style].Length;
        
        int sizeDiff;
        
        int Position = iSize;
        float fTime;
        float fOldTime = 0.0;
            
        for(int idx = 0; idx < iSize; idx++)
        {
            fTime = g_hTimes[Type][Style].Get(idx, 1);
                
            if(Time < fTime && (fOldTime == 0.0 || fOldTime != fTime))
            {
                Position = Position - 1;
            }
            else if(fOldTime == fTime)
            {
                sizeDiff = sizeDiff + 1;
            }
                        
            fOldTime = fTime;
        }
        
        return (Position - sizeDiff) + 1;
    }
    
    return 0;
}

int GetPlayerPositionByID(int PlayerID, int Type, int Style)
{
    if(g_bTimesAreLoaded == true)
    {
        int pos = g_hTimes[Type][Style].FindValue(PlayerID);
        
        if (pos == -1)
        {
            return g_hTimes[Type][Style].Length;
        }
        
        return GetPlayerPosition(g_hTimes[Type][Style].Get(pos, 1), Type, Style) - 1;
    }
    
    return 0;
}

// Controls what shows up on the right side of players screen, KeyHintText
public Action Timer_SpecList(Handle timer, any data)
{
    // Different arrays for admins and non-admins
    int[] SpecCount = new int[MaxClients+1], AdminSpecCount = new int[MaxClients+1];
    SpecCountToArrays(SpecCount, AdminSpecCount);
    
    char message[256];
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsFakeClient(client))
        {
            if(GetKeyHintMessage(client, message, sizeof(message), SpecCount, AdminSpecCount))
            {
                if(g_GameType == GameType_CSS)
                    PrintKeyHintText(client, message);
            }
            
            if(IsPlayerAlive(client))
            {
                ShowCornerTimes(client);
            }
            else
            {
                if(GetSyncHudMessage(client, message, sizeof(message)))
                {
                    Handle hText = CreateHudSynchronizer();
                    if(hText != INVALID_HANDLE)
                    {
                        SetHudTextParams(0.01, 0.01, 1.0, 255, 255, 255, 255);
                        ShowSyncHudText(client, hText, message);
                        delete hText;
                    }
                }
            }
        }
    }
}

public void ShowCornerTimes(int client)
{    
    char sMessage[128];
    if(GetSyncHudMessage(client, sMessage, sizeof(sMessage)))
    {
        Handle hText = CreateHudSynchronizer();
        
        if(hText != INVALID_HANDLE)
        {
            SetHudTextParams(0.01, 0.01, 1.0, 255, 255, 255, 255);
            ShowSyncHudText(client, hText, sMessage);
            delete hText;
        }
    }
}

bool GetSyncHudMessage(int client, char[] message, int maxlength)
{
    FormatEx(message, maxlength, "");
    
    int target;
    
    int settings = GetClientSettings(client);
    
    if(!IsPlayerAlive(client))
    {
        target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        int mode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        if(!((0 < target <= MaxClients) && (mode == 4 || mode == 5)))
        {
            return false;
        }
    }
    else
    {
        target = client;
        //return false;
    }
    
    if(!IsFakeClient(target))
    {
        int Type = g_Type[target];
        int Style = g_Style[target][g_Type[target]];
        
        if(settings & KH_RECORD)
        {
            Format(message, maxlength, g_sRecord[Type][Style]);
        }
        
        if(settings & KH_BEST)
        {
            if(settings & KH_RECORD)
                Format(message, maxlength, "%s\n%s", message, g_sTime[target][g_Type[target]][GetStyle(target)]);
            else
                Format(message, maxlength, "%s", g_sTime[target][g_Type[target]][GetStyle(target)]);
            
            int position;
        
            if(g_fTime[target][g_Type[target]][GetStyle(target)] != 0.0)
            {
                position = GetPlayerPositionByID(GetPlayerID(target), g_Type[target], GetStyle(target));
                Format(message, maxlength, "%s (#%d)", message, position);
            }
        }
        
        if((settings & KH_BEST) || (settings & KH_RECORD))
            return true;
    }
    else
    {
        if(g_bGhostPluginLoaded == true)
        {
            int Type, Style;
            if(GetBotInfo(target, Type, Style))
            {
                if(settings & KH_RECORD)
                    Format(message, maxlength, g_sRecord[Type][Style]);
                    
                return true;
            }
        }
    }
    
    return false;
}

void SpecCountToArrays(int[] clients, int[] admins)
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsFakeClient(client))
        {
            if(!IsPlayerAlive(client))
            {
                int Target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
                int ObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
                if((0 < Target <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5))
                {
                    if(g_bIsAdmin[client] == false)
                        clients[Target]++;
                    admins[Target]++;
                }
            }
        }
    }
}

bool GetKeyHintMessage(int client, char[] message, int maxlength, int[] SpecCount, int[] AdminSpecCount)
{
    FormatEx(message, maxlength, "");
    
    int target;
    
    if(IsPlayerAlive(client))
    {
        target = client;
    }
    else
    {
        target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        int mode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        if(!((0 < target <= MaxClients) && (mode == 4 || mode == 5)))
        {
            return false;
        }
    }
    
    int settings = GetClientSettings(client);
    
    if(settings & KH_TIMELEFT)
    {
        int timelimit;
        GetMapTimeLimit(timelimit);
        if(g_hShowTimeLeft.BoolValue && timelimit != 0)
        {
            int timeleft;
            GetMapTimeLeft(timeleft);
            
            if(timeleft <= 0)
            {
                FormatEx(message, maxlength, "Time left: Map finished\n");
            }
            else if(timeleft < 60)
            {
                FormatEx(message, maxlength, "Time left: <1 minute\n");
            }
            else
            {
                // Format the time left
                int minutes = RoundToFloor(float(timeleft)/60);
                FormatEx(message, maxlength, "Time left: %d minutes\n", minutes);
            }
        }
    }
    
    /*
    if(!IsFakeClient(target))
    {
        if(settings & KH_RECORD)
        {
            Format(message, maxlength, "%s%s\n", message, g_sRecord[g_Type[target]][GetStyle(target)]);
        }
        
        if(settings & KH_BEST)
        {
            new position;
            Format(message, maxlength, "%s%s", message, g_sTime[target][g_Type[target]][GetStyle(target)]);
            if(g_fTime[target][g_Type[target]][GetStyle(target)] != 0.0)
            {
                position = GetPlayerPositionByID(GetPlayerID(target), g_Type[target], GetStyle(target));
                Format(message, maxlength, "%s (#%d)", message, position);
            }
        }
    }
    else if(g_bGhostPluginLoaded == true)
    {
        new Type, Style;
        
        if(GetBotInfo(target, Type, Style))
        {
            Format(message, maxlength, "%s%s\n\n", message, g_sRecord[Type][Style]);
        }
    }
    */
    
    if(settings & KH_SPECS)
    {
        Format(message, maxlength, "%sSpectators: %d\n", message, (g_bIsAdmin[client])?AdminSpecCount[target]:SpecCount[target]);
    }
    
    if(settings & KH_SYNC)
    {
        int Style = g_Style[target][g_Type[target]];
        
        if(g_StyleConfig[Style].CalcSync && g_bTiming[target])
        {
            if(Timer_InsideZone(target, MAIN_START) == -1 && Timer_InsideZone(target, BONUS_START) == -1)
            {
                if(g_bIsAdmin[client] == true)
                {
                    Format(message, maxlength, "%s\nSync 1: %.2f\n", message, GetClientSync(target));
                    Format(message, maxlength, "%sSync 2: %.2f", message, GetClientSync2(target));
                }
                else
                {
                    Format(message, maxlength, "%s\nSync: %.2f", message, GetClientSync(target));
                }
            }
        }
    }
    
    return true;
}

void PrintKeyHintText(int client, const char[] message)
{
    Handle hMessage = StartMessageOne("KeyHintText", client);
    if (hMessage != INVALID_HANDLE) 
    { 
        BfWriteByte(hMessage, 1); 
        BfWriteString(hMessage, message);
    }
    EndMessage();
}

float GetClientSync(int client)
{
    if(g_totalSync[client] == 0)
        return 0.0;
    
    return view_as<float>(g_goodSync[client])/view_as<float>(g_totalSync[client]) * 100.0;
}

float GetClientSync2(int client)
{
    if(g_totalSync[client] == 0)
        return 0.0;
    
    return view_as<float>(g_goodSyncVel[client])/view_as<float>(g_totalSync[client]) * 100.0;
}

public Action OnTimerStart_Pre(int client, int Type, int Style)
{
    if(!IsClientInGame(client))
    {
        return Plugin_Handled;
    }
        
    if(!IsPlayerAlive(client))
    {
        return Plugin_Handled;
    }
    
    // Fixes a bug for players to completely cheat times by spawning in weird parts of the map
    if(GetEngineTime() < (g_fSpawnTime[client] + 0.1))
    {
        return Plugin_Handled;
    }
    
    // Don't start if their speed isn't default
    if((FloatCompare(GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue"),1.02) == 1) || (FloatCompare(GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue"),0.98) == -1))
    {
        WarnClient(client, "%s%sYour movement speed is off. Type %s!normalspeed%s to set it to default.", 30.0,
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            g_msg_textcol);
        return Plugin_Handled;
    }
    
    // Don't start if they are in noclip
    if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
    {
        return Plugin_Handled;
    }
    
    // Don't start if they are a fake client
    if(IsFakeClient(client))
    {
        return Plugin_Handled;
    }
    
    if(!g_StyleConfig[Style].AllowType[Type] || !Style_IsEnabled(Style))
    {
        return Plugin_Handled;
    }
    
    if(g_StyleConfig[Style].MinFps != 0 && g_Fps[client] < g_StyleConfig[Style].MinFps && g_Fps[client] != 0.0)
    {
        WarnClient(client, "%s%sPlease set your fps_max to a higher value (Minimum %s%.1f%s).", 30.0, 
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            g_StyleConfig[Style].MinFps,
            g_msg_textcol);
        return Plugin_Handled;
    }
    
    if((GetClientSettings(client) & AUTO_BHOP) && g_bAutoStopsTimer)
    {
        return Plugin_Handled;
    }
    
    if(Type == TIMER_SOLOBONUS)
        CheckPrespeed(client, Style);
    
    if(!(GetEntityFlags(client) & FL_ONGROUND))
    {
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public void OnTimerStart_Post(int client, int Type, int Style)
{
    // For an always convenient starting jump
    //SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
    
    if(g_StyleConfig[Style].RunSpeed != 0.0)
    {
        SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", g_StyleConfig[Style].RunSpeed);
    }
    
    // Set to correct gravity
    if(GetEntityGravity(client) != g_StyleConfig[Style].Gravity && GetEntityGravity(client) < 10)
    {
        SetEntityGravity(client, g_StyleConfig[Style].Gravity);
    }
}

public int Native_StartTimer(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int Type   = GetNativeCell(2);
    int Style  = g_Style[client][Type];
    
    Call_StartForward(g_fwdOnTimerStart_Pre);
    Call_PushCell(client);
    Call_PushCell(Type);
    Call_PushCell(Style);
    
    Action fResult;
    Call_Finish(fResult);
    
    int partner = Timer_GetPartner(client);
    
    if(fResult != Plugin_Handled)
    {    
        g_Type[client]         = Type;
        if(Type == TIMER_SOLOBONUS || ((Type == g_Type[partner]) && (Style == g_Style[partner][g_Type[partner]])))
        {
            g_Jumps[client]          = 0;
            g_Strafes[client]        = 0;
            g_SWStrafes[client][0]   = 1;
            g_SWStrafes[client][1]   = 1;
            g_bPaused[client]        = false;
            g_totalSync[client]      = 0.0;
            g_goodSync[client]       = 0.0;
            g_goodSyncVel[client]    = 0.0;
            g_Flashes[client]        = 0;

            g_bTiming[client]      = true;
            g_bShownWR[client]      = false;
            g_fCurrentTime[client] = 0.0;
        
            Call_StartForward(g_fwdOnTimerStart_Post);
            Call_PushCell(client);
            Call_PushCell(Type);
            Call_PushCell(Style);
            Call_Finish();
        }
        else if(g_bTiming[client])
        {
            StopTimer(client);
        }
    }
}

void CheckPrespeed(int client, int Style)
{    
    if(g_StyleConfig[Style].PreSpeed != 0.0)
    {
        float fVel = GetClientVelocity(client, true, true, true);
        
        if(fVel > g_StyleConfig[Style].PreSpeed)
        {
            float vVel[3];
            Entity_GetAbsVelocity(client, vVel);
            ScaleVector(vVel, g_StyleConfig[Style].SlowedSpeed/fVel);
            TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vVel);
        }
    }
}

void WarnClient(int client, const char[] message, float WarnTime, any ...)
{
    if(GetEngineTime() > g_fWarningTime[client])
    {
        char buffer[300];
        VFormat(buffer, sizeof(buffer), message, 4);
        PrintColorText(client, buffer);
        
        g_fWarningTime[client] = GetEngineTime() + WarnTime;    
    }
}

public int Native_StopTimer(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    // stop timer
    if(0 < client <= MaxClients)
    {
        g_bTiming[client] = false;
        g_bPaused[client] = false;
        
        int partner = Timer_GetPartner(client);
        
        if(0 < partner <= MaxClients && g_Type[client] != TIMER_SOLOBONUS && g_Type[partner] != TIMER_SOLOBONUS)
        {
            g_bTiming[partner] = false;
            g_bPaused[partner] = false;
            
            if(IsClientInGame(partner) && !IsFakeClient(partner))
            {
                if(GetEntityMoveType(partner) == MOVETYPE_NONE)
                {
                    SetEntityMoveType(partner, MOVETYPE_WALK);
                }
            }
        }
        
        if(IsClientInGame(client) && !IsFakeClient(client))
        {
            if(GetEntityMoveType(client) == MOVETYPE_NONE)
            {
                SetEntityMoveType(client, MOVETYPE_WALK);
            }
        }
    }
}

public int Native_IsBeingTimed(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int Type   = GetNativeCell(2);
    
    if(g_bTiming[client] == true)
    {
        if(Type == TIMER_ANY)
        {
            return true;
        }
        else
        {
            return g_Type[client] == Type;
        }
    }
    
    return false;
}

public Action OnTimerFinished_Pre(int client, int Type, int Style)
{
    if(g_bTimeIsLoaded[client] == false)
    {
        return Plugin_Handled;
    }
    
    if(GetPlayerID(client) == 0)
    {
        return Plugin_Handled;
    }
    
    if(g_bPaused[client] == true)
    {
        return Plugin_Handled;
    }
    
    // Anti-cheat sideways
    if(g_StyleConfig[Style].Special == true)
    {
        if(StrEqual(g_StyleConfig[Style].Special_Key, "sw"))
        {
            float WSRatio = float(g_SWStrafes[client][0])/float(g_SWStrafes[client][1]);
            if((WSRatio > 2.0) || (g_Strafes[client] < 10))
            {
                PrintColorText(client, "%s%sThat time did not count because you used W-Only too much",
                    g_msg_start,
                    g_msg_textcol);
                StopTimer(client);
                return Plugin_Handled;
            }
        }
    }
    
    if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
    {
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public void OnTimerFinished_Post(int client, float Time, int Type, int Style, bool NewTime, int OldPosition, int NewPosition)
{
    if(!g_bShownWR[Timer_GetPartner(client)])
        PlayFinishSound(client, NewTime, NewPosition);
}

public int Native_FinishTimer(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int Type   = g_Type[client];
    int Style  = g_Style[client][Type];
    
    Call_StartForward(g_fwdOnTimerFinished_Pre);
    Call_PushCell(client);
    Call_PushCell(Type);
    Call_PushCell(Style);
    
    Action fResult;
    Call_Finish(fResult);
    
    Action fPResult = Plugin_Continue;
    
    
    if(Type != TIMER_SOLOBONUS)
    {
        Call_StartForward(g_fwdOnTimerFinished_Pre);
        Call_PushCell(Timer_GetPartner(client));
        Call_PushCell(Type);
        Call_PushCell(Style);
        
        Call_Finish(fPResult);
    }
    
    if(fResult != Plugin_Handled && fPResult != Plugin_Handled)
    {
        StopTimer(client);
        
        int partner = 0;
        
        if(Type != TIMER_SOLOBONUS)
        {
            partner = Timer_GetPartner(client);
            g_fCurrentTime[partner] = g_fCurrentTime[client];
        }
        
        float fTime = GetClientTimer(client);
        char sTime[32];
        FormatPlayerTime(fTime, sTime, sizeof(sTime), false, 1);
        
        char sType[32];
        if(Type != TIMER_MAIN)
        {
            GetTypeAbbr(Type, sType, sizeof(sType));
            StringToUpper(sType);
        }
        
        char sStyle[32];
        if(Style != 0)
        {
            GetStyleAbbr(Style, sStyle, sizeof(sStyle));
            StringToUpper(sStyle);
        }
        
        char sTypeStyle[64];
        if(strlen(sStyle) + strlen(sType) > 0)
            FormatEx(sTypeStyle, sizeof(sTypeStyle), "[%s%s] ", sType, sStyle);
        
        int OldPosition, NewPosition;
        bool NewTime = false;
        
        if(fTime < g_fTime[client][Type][Style] || g_fTime[client][Type][Style] == 0.0)
        {
            NewTime = true;
            
            if(g_fTime[client][Type][Style] == 0.0)
                OldPosition = 0;
            else
                OldPosition = GetPlayerPositionByID(GetPlayerID(client), Type, Style);
            
            NewPosition = DB_UpdateTime(client, Type, Style, fTime, g_Jumps[client], g_Strafes[client], GetClientSync(client), GetClientSync2(client), g_Flashes[client], Timer_GetPartner(client));
            
            g_fTime[client][Type][Style] = fTime;
            
            FormatEx(g_sTime[client][Type][Style], sizeof(g_sTime[][][]), "Best: %s", sTime);
            
            if(NewPosition == 1)
            {
                g_WorldRecord[Type][Style] = fTime;
                
                char sTypeAbbr[8];
                GetTypeAbbr(Type, sTypeAbbr, sizeof(sTypeAbbr), true);
                StringToUpper(sTypeAbbr);
                
                char sStyleAbbr[8];
                GetStyleAbbr(Style, sStyleAbbr, sizeof(sStyleAbbr), true);
                StringToUpper(sStyleAbbr);
                
                if(Type == TIMER_SOLOBONUS)
                {
                    Format(g_sRecord[Type][Style], sizeof(g_sRecord[][]), "%sWR%s: %s (%N)", sTypeAbbr, sStyleAbbr, sTime, client);
                }
                else
                {
                    char sName1[20];
                    char sName2[20];
                    Format(sName1, sizeof(sName1), "%N", client);
                    Format(sName2, sizeof(sName2), "%N", partner);
                    Format(g_sRecord[Type][Style], sizeof(g_sRecord[][]), "%sWR%s: %s (%s | %s)", sTypeAbbr, sStyleAbbr, sTime, sName1, sName2);
                }
                
                if(g_StyleConfig[Style].Count_Left_Strafe || g_StyleConfig[Style].Count_Right_Strafe || g_StyleConfig[Style].Count_Back_Strafe || g_StyleConfig[Style].Count_Forward_Strafe)
                {
                    if(Type == TIMER_SOLOBONUS)
                    {
                        PrintColorTextAll("%s%sNEW %s%s%sRecord by %s%N %sin %s%s%s (%s%d%s jumps, %s%d%s strafes)",
                            g_msg_start,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTypeStyle,
                            g_msg_textcol,
                            g_msg_varcol,
                            client,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTime,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Jumps[client],
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Strafes[client],
                            g_msg_textcol);
                    }
                    else if(!g_bShownWR[partner])
                    {
                        PrintColorTextAll("%s%sNEW %s%s%sRecord by %s%N %s& %s%N %sin %s%s%s (%s%d%s jumps, %s%d%s strafes)",
                            g_msg_start,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTypeStyle,
                            g_msg_textcol,
                            g_msg_varcol,
                            client,
                            g_msg_textcol,
                            g_msg_varcol,
                            partner,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTime,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Jumps[client],
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Strafes[client],
                            g_msg_textcol);
                            
                        g_bShownWR[client] = true;
                    }
                }
                else
                {
                    if(Type == TIMER_SOLOBONUS)
                    {
                        PrintColorTextAll("%s%sNEW %s%s%sRecord by %s%N %sin %s%s%s (%s%d%s jumps)",
                            g_msg_start,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTypeStyle,
                            g_msg_textcol,
                            g_msg_varcol,
                            client,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTime,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Jumps[client],
                            g_msg_textcol);
                    }
                    else if(!g_bShownWR[partner])
                    {
                        PrintColorTextAll("%s%sNEW %s%s%sRecord by %s%N %s& %s%N %sin %s%s%s (%s%d%s jumps)",
                            g_msg_start,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTypeStyle,
                            g_msg_textcol,
                            g_msg_varcol,
                            client,
                            g_msg_textcol,
                            g_msg_varcol,
                            partner,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTime,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Jumps[client],
                            g_msg_textcol);
                            
                        g_bShownWR[client] = true;
                    }
                }
            }
            else
            {
                if(g_StyleConfig[Style].Count_Left_Strafe || g_StyleConfig[Style].Count_Right_Strafe || g_StyleConfig[Style].Count_Back_Strafe || g_StyleConfig[Style].Count_Forward_Strafe)
                {
                    if(Type == TIMER_SOLOBONUS)
                    {
                        PrintColorTextAll("%s%s%s%N %sfinished in %s%s%s (%s#%d%s) (%s%d%s jumps, %s%d%s strafes)", 
                            g_msg_start,
                            g_msg_varcol,
                            sTypeStyle,
                            client, 
                            g_msg_textcol,
                            g_msg_varcol,
                            sTime,
                            g_msg_textcol,
                            g_msg_varcol,
                            NewPosition,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Jumps[client],
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Strafes[client],
                            g_msg_textcol);
                    }
                    else if(!g_bShownWR[partner])
                    {
                        PrintColorTextAll("%s%s%s%N %s& %s%N %sfinished in %s%s%s (%s#%d%s) (%s%d%s jumps, %s%d%s strafes)", 
                            g_msg_start,
                            g_msg_varcol,
                            sTypeStyle,
                            client, 
                            g_msg_textcol,
                            g_msg_varcol,
                            partner,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTime,
                            g_msg_textcol,
                            g_msg_varcol,
                            NewPosition,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Jumps[client],
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Strafes[client],
                            g_msg_textcol);
                            
                        g_bShownWR[client] = true;
                    }
                }
                else
                {
                    if(Type == TIMER_SOLOBONUS)
                    {
                        PrintColorTextAll("%s%s%s%N %s& %s%N %sfinished in %s%s%s (%s#%d%s) (%s%d%s jumps)", 
                            g_msg_start,
                            g_msg_varcol,
                            sTypeStyle,
                            client, 
                            g_msg_textcol,
                            g_msg_varcol,
                            sTime,
                            g_msg_textcol,
                            g_msg_varcol,
                            NewPosition,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Jumps[client],
                            g_msg_textcol);
                    }
                    else if(!g_bShownWR[partner])
                    {
                        PrintColorTextAll("%s%s%s%N %sfinished in %s%s%s (%s#%d%s) (%s%d%s jumps)", 
                            g_msg_start,
                            g_msg_varcol,
                            sTypeStyle,
                            client, 
                            g_msg_textcol,
                            g_msg_varcol,
                            partner,
                            g_msg_textcol,
                            g_msg_varcol,
                            sTime,
                            g_msg_textcol,
                            g_msg_varcol,
                            NewPosition,
                            g_msg_textcol,
                            g_msg_varcol,
                            g_Jumps[client],
                            g_msg_textcol);
                            
                        g_bShownWR[client] = true;
                    }
                }
            }
        }
        else
        {
            OldPosition = GetPlayerPositionByID(GetPlayerID(client), Type, Style);
            NewPosition = OldPosition;
            
            char sPersonalBest[32];
            FormatPlayerTime(g_fTime[client][Type][Style], sPersonalBest, sizeof(sPersonalBest), false, 1);
            
            PrintColorText(client, "%s%s%s%sYou finished in %s%s%s, but did not improve on your previous time of %s%s",
                g_msg_start,
                g_msg_varcol,
                sTypeStyle,
                g_msg_textcol,
                g_msg_varcol,
                sTime,
                g_msg_textcol,
                g_msg_varcol,
                sPersonalBest);
                
            PrintColorTextObservers(client, "%s%s%s%N %sfinished in %s%s%s, but did not improve on their previous time of %s%s",
                g_msg_start,
                g_msg_varcol,
                sTypeStyle,
                client,
                g_msg_textcol,
                g_msg_varcol,
                sTime,
                g_msg_textcol,
                g_msg_varcol,
                sPersonalBest);
        }
        
        Call_StartForward(g_fwdOnTimerFinished_Post);
        Call_PushCell(client);
        Call_PushFloat(fTime);
        Call_PushCell(Type);
        Call_PushCell(Style);
        Call_PushCell(NewTime);
        Call_PushCell(OldPosition);
        Call_PushCell(NewPosition);
        Call_Finish();
    }
}

int GetStyle(int client)
{
    return g_Style[client][g_Type[client]];
}

float GetClientTimer(int client)
{
    return g_fCurrentTime[client];
}

void ReadStyleConfig()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/timer/styles.cfg");
    
    KeyValues kv = new KeyValues("Styles");
    kv.ImportFromFile(sPath);
    
    if(kv != INVALID_HANDLE)
    {
        int Key;
        bool KeyExists = true;
        char sKey[32];
        
        do
        {
            IntToString(Key, sKey, sizeof(sKey));
            KeyExists = kv.JumpToKey(sKey);
            
            if(KeyExists == true)
            {
                kv.GetString("name", g_StyleConfig[Key].Name, 32);
                kv.GetString("abbr", g_StyleConfig[Key].Name_Short, 32);
                g_StyleConfig[Key].Enabled                = view_as<bool>(kv.GetNum("enable"));
                g_StyleConfig[Key].AllowType[TIMER_MAIN]  = view_as<bool>(kv.GetNum("main"));
                g_StyleConfig[Key].AllowType[TIMER_BONUS] = view_as<bool>(kv.GetNum("bonus"));
                g_StyleConfig[Key].AllowType[TIMER_SOLOBONUS] = view_as<bool>(kv.GetNum("solobonus"));
                g_StyleConfig[Key].Freestyle              = view_as<bool>(kv.GetNum("freestyle"));
                g_StyleConfig[Key].Freestyle_Unrestrict   = view_as<bool>(kv.GetNum("freestyle_unrestrict"));
                g_StyleConfig[Key].Freestyle_EzHop        = view_as<bool>(kv.GetNum("freestyle_ezhop"));
                g_StyleConfig[Key].Freestyle_Auto         = view_as<bool>(kv.GetNum("freestyle_auto"));
                g_StyleConfig[Key].Auto                   = view_as<bool>(kv.GetNum("auto"));
                g_StyleConfig[Key].EzHop                  = view_as<bool>(kv.GetNum("ezhop"));
                g_StyleConfig[Key].Gravity                = kv.GetFloat("gravity");
                g_StyleConfig[Key].RunSpeed               = kv.GetFloat("runspeed");
                g_StyleConfig[Key].MaxVel                 = kv.GetFloat("maxvel");
                g_StyleConfig[Key].MinFps                 = kv.GetFloat("minfps");
                g_StyleConfig[Key].CalcSync               = view_as<bool>(kv.GetNum("sync"));
                g_StyleConfig[Key].Prevent_Left           = view_as<bool>(kv.GetNum("prevent_left"));
                g_StyleConfig[Key].Prevent_Right          = view_as<bool>(kv.GetNum("prevent_right"));
                g_StyleConfig[Key].Prevent_Back           = view_as<bool>(kv.GetNum("prevent_back"));
                g_StyleConfig[Key].Prevent_Forward        = view_as<bool>(kv.GetNum("prevent_forward"));
                g_StyleConfig[Key].Require_Left           = view_as<bool>(kv.GetNum("require_left"));
                g_StyleConfig[Key].Require_Right          = view_as<bool>(kv.GetNum("require_right"));
                g_StyleConfig[Key].Require_Back           = view_as<bool>(kv.GetNum("require_back"));
                g_StyleConfig[Key].Require_Forward        = view_as<bool>(kv.GetNum("require_forward"));
                g_StyleConfig[Key].Hud_Style              = view_as<bool>(kv.GetNum("hud_style"));
                g_StyleConfig[Key].Hud_Strafes            = view_as<bool>(kv.GetNum("hud_strafes"));
                g_StyleConfig[Key].Hud_Jumps              = view_as<bool>(kv.GetNum("hud_jumps"));
                g_StyleConfig[Key].Count_Left_Strafe      = view_as<bool>(kv.GetNum("count_left_strafe"));
                g_StyleConfig[Key].Count_Right_Strafe     = view_as<bool>(kv.GetNum("count_right_strafe"));
                g_StyleConfig[Key].Count_Back_Strafe      = view_as<bool>(kv.GetNum("count_back_strafe"));
                g_StyleConfig[Key].Count_Forward_Strafe   = view_as<bool>(kv.GetNum("count_forward_strafe"));
                g_StyleConfig[Key].Ghost_Use[0]           = view_as<bool>(kv.GetNum("ghost_use"));
                g_StyleConfig[Key].Ghost_Save[0]          = view_as<bool>(kv.GetNum("ghost_save"));
                g_StyleConfig[Key].Ghost_Use[1]           = view_as<bool>(kv.GetNum("ghost_use_b"));
                g_StyleConfig[Key].Ghost_Save[1]          = view_as<bool>(kv.GetNum("ghost_save_b"));
                g_StyleConfig[Key].Ghost_Use[2]           = view_as<bool>(kv.GetNum("ghost_use_sb"));
                g_StyleConfig[Key].Ghost_Save[2]          = view_as<bool>(kv.GetNum("ghost_save_sb"));
                g_StyleConfig[Key].PreSpeed               = kv.GetFloat("prespeed");
                g_StyleConfig[Key].SlowedSpeed            = kv.GetFloat("slowedspeed");
                g_StyleConfig[Key].Special                = view_as<bool>(kv.GetNum("special"));
                kv.GetString("specialid", g_StyleConfig[Key].Special_Key, 32);
                g_StyleConfig[Key].GunJump                = view_as<bool>(kv.GetNum("gunjump"));
                kv.GetString("gunjump_weapon", g_StyleConfig[Key].GunJump_Weapon, 64);
                g_StyleConfig[Key].UnrealPhys             = view_as<bool>(kv.GetNum("unrealphys"));
                g_StyleConfig[Key].AirAcceleration       = kv.GetNum("aa", 0);
                
                kv.GoBack();
                Key++;
            }
        }
        while(KeyExists == true && Key < MAX_STYLES);
            
        delete kv;
    
        g_TotalStyles = Key;
        
        // Reset temporary enabled and disabled styles
        for(int Style; Style < g_TotalStyles; Style++)
        {
            g_StyleConfig[Style].TempEnabled = g_StyleConfig[Style].Enabled;
        }
        
        Call_StartForward(g_fwdOnStylesLoaded);
        Call_Finish();
    }
    else
    {
        LogError("Something went wrong reading from the styles.cfg file.");
    }
}

void LoadRecordSounds()
{    
    g_hSoundsArray.Clear();
    
    // Create path and file variables
    char sPath[PLATFORM_MAX_PATH]; 
    File hFile;
    
    // Build a path to check if it exists
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/timer");
    
    // If it doesn't exist, create it
    if(!DirExists(sPath))
        CreateDirectory(sPath, 511);
    
    // Build a path to check if the config file exists
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/timer/wrsounds.cfg");
    
    // If the wrsounds exists, load the sounds
    if(FileExists(sPath))
    {
        hFile = OpenFile(sPath, "r");
        
        if(hFile != INVALID_HANDLE)
        {
            char sSound[PLATFORM_MAX_PATH];
            char sPSound[PLATFORM_MAX_PATH];
            while(!hFile.EndOfFile())
            {
                // get the next line in the file
                hFile.ReadLine(sSound, sizeof(sSound));
                ReplaceString(sSound, sizeof(sSound), "\n", "");
                
                if(StrContains(sSound, ".") != -1)
                {                    
                    // precache the sound
                    Format(sPSound, sizeof(sPSound), "btimes/%s", sSound);
                    PrecacheSound(sPSound);
                    
                    // make clients download it
                    Format(sPSound, sizeof(sPSound), "sound/%s", sPSound);
                    AddFileToDownloadsTable(sPSound);
                    
                    // add it to array for later downloading
                    g_hSoundsArray.PushString(sSound);
                }
            }
        }
    }
    else
    {
        // Create the file if it doesn't exist
        hFile = OpenFile(sPath, "w");
    }
    
    // Close it if it was opened succesfully
    if(hFile != INVALID_HANDLE)
        delete hFile;
    
}

void LoadRecordSounds_Advanced()
{    
    g_hSound_Path_Record.Clear();
    g_hSound_Position_Record.Clear();
    g_hSound_Path_Personal.Clear();
    g_hSound_Path_Fail.Clear();
    
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/timer/sounds.txt");
    
    KeyValues kv = new KeyValues("Sounds", "Sounds");
    kv.ImportFromFile(sPath);
    
    int Key;
    bool KeyExists = true;
    char sKey[64];
    char sPrecache[PLATFORM_MAX_PATH];
    char sDownload[PLATFORM_MAX_PATH];
    
    if(kv.JumpToKey("World Record"))
    {
        do
        {
            IntToString(++Key, sKey, sizeof(sKey));
            KeyExists = kv.JumpToKey(sKey);
            
            if(KeyExists == true)
            {
                int Position = kv.GetNum("Position");
                kv.GetString("Sound", sKey, sizeof(sKey));
                
                // precache the sound
                Format(sPrecache, sizeof(sPrecache), "btimes/%s", sKey);
                PrecacheSound(sPrecache);
                
                // make clients download it
                Format(sDownload, sizeof(sDownload), "sound/btimes/%s", sKey);
                AddFileToDownloadsTable(sDownload);
                
                // add it to array
                g_hSound_Path_Record.PushString(sPrecache);
                g_hSound_Position_Record.Push(Position);
                
                kv.GoBack();
            }
        }
        while(KeyExists == true);
    }
    kv.Rewind();
    
    if(kv.JumpToKey("Personal Record"))
    {
        Key = 0;
        KeyExists = true;
        
        do
        {
            IntToString(++Key, sKey, sizeof(sKey));
            KeyExists = kv.JumpToKey(sKey);
            
            if(KeyExists == true)
            {
                kv.GetString("Sound", sKey, sizeof(sKey));
                
                // precache the sound
                Format(sPrecache, sizeof(sPrecache), "btimes/%s", sKey);
                PrecacheSound(sPrecache);
                
                // make clients download it
                Format(sDownload, sizeof(sDownload), "sound/btimes/%s", sKey);
                AddFileToDownloadsTable(sDownload);
                
                // add it to array for later downloading
                g_hSound_Path_Personal.PushString(sPrecache);
                
                kv.GoBack();
            }
        }
        while(KeyExists == true);
    }
    kv.Rewind();
    
    if(kv.JumpToKey("No New Time"))
    {
        Key = 0;
        KeyExists = true;
        
        do
        {
            IntToString(++Key, sKey, sizeof(sKey));
            KeyExists = kv.JumpToKey(sKey);
            
            if(KeyExists == true)
            {
                kv.GetString("Sound", sKey, sizeof(sKey));
                
                // precache the sound
                Format(sPrecache, sizeof(sPrecache), "btimes/%s", sKey);
                PrecacheSound(sPrecache);
                
                // make clients download it
                Format(sDownload, sizeof(sDownload), "sound/btimes/%s", sKey);
                AddFileToDownloadsTable(sDownload);
                
                // add it to array for later downloading
                g_hSound_Path_Fail.PushString(sPrecache);
                
                kv.GoBack();
            }
        }
        while(KeyExists == true);
    }
    
    delete kv;
}

void PlayFinishSound(int client, bool NewTime, int Position)
{
    char sSound[64];
    
    if(g_hAdvancedSounds.BoolValue)
    {
        if(NewTime == true)
        {
            int iSize = g_hSound_Position_Record.Length;
            
            ArrayList IndexList = new ArrayList();
            
            for(int idx; idx < iSize; idx++)
            {
                if(g_hSound_Position_Record.Get(idx) == Position)
                {
                    IndexList.Push(idx);
                }
            }
            
            iSize = IndexList.Length;
            
            if(iSize > 0)
            {
                int Rand = GetRandomInt(0, iSize - 1);
                g_hSound_Path_Record.GetString(IndexList.Get(Rand), sSound, sizeof(sSound));
                
                int numClients;
                int[] clients = new int[MaxClients + 1];
                
                for(int target = 1; target <= MaxClients; target++)
                {
                    if(IsClientInGame(target) && !(GetClientSettings(target) & STOP_RECSND))
                        clients[numClients++] = target;
                }
                EmitSound(clients, numClients, sSound);
            }
            else
            {
                iSize = g_hSound_Path_Personal.Length;
                
                if(iSize > 0)
                {
                    int Rand = GetRandomInt(0, iSize - 1);
                    g_hSound_Path_Personal.GetString(Rand, sSound, sizeof(sSound));
                    if(!(GetClientSettings(client) & STOP_PBSND))
                        EmitSoundToClient(client, sSound);
                }
            }
            
            delete IndexList;
        }
        else
        {
            int iSize = g_hSound_Path_Fail.Length;
            
            if(iSize > 0)
            {
                int Rand = GetRandomInt(0, iSize - 1);
                g_hSound_Path_Fail.GetString(Rand, sSound, sizeof(sSound));
                if(!(GetClientSettings(client) & STOP_FAILSND))
                    EmitSoundToClient(client, sSound);
            }
        }
    }
    else
    {
        if(NewTime == true && Position == 1)
        {
            int iSize = g_hSoundsArray.Length;
            
            if(iSize > 0)
            {
                int Rand = GetRandomInt(0, iSize - 1);
                g_hSoundsArray.GetString(Rand, sSound, sizeof(sSound));
                if(!(GetClientSettings(client) & STOP_RECSND))
                    EmitSoundToClient(client, sSound);
            }
        }
    }
}

void ExecMapConfig()
{
    char sPath[PLATFORM_MAX_PATH];
    FormatEx(sPath, sizeof(sPath), "cfg/timer/maps");
    
    if(DirExists(sPath))
    {
        FormatEx(sPath, sizeof(sPath), "cfg/timer/maps/%s.cfg", g_sMapName);
        
        if(FileExists(sPath))
        {
            ServerCommand("exec timer/maps/%s.cfg", g_sMapName);
        }
    }
    else
    {
        CreateDirectory(sPath, 511);
    }
}

void DB_Connect()
{
    if(g_DB != INVALID_HANDLE)
    {
        delete g_DB;
    }
    
    char error[255];
    g_DB = SQL_Connect("timer", true, error, sizeof(error));
    
    if(g_DB == INVALID_HANDLE)
    {
        LogError(error);
        delete g_DB;
    }
}

void DB_LoadPlayerInfo(int client)
{
    int PlayerID = GetPlayerID(client);
    if(IsClientConnected(client) && PlayerID != 0)
    {
        if(!IsFakeClient(client))
        {
            int iSize;
            for(int Type; Type < MAX_TYPES; Type++)
            {
                for(int Style; Style < MAX_STYLES; Style++)
                {
                    if(g_StyleConfig[Style].AllowType[Type])
                    {
                        FormatEx(g_sTime[client][Type][Style], sizeof(g_sTime[][][]), "Best: No time");
                        
                        iSize = g_hTimes[Type][Style].Length;
                        
                        for(int idx = 0; idx < iSize; idx++)
                        {
                            if(g_hTimes[Type][Style].Get(idx) == PlayerID)
                            {
                                g_fTime[client][Type][Style] = g_hTimes[Type][Style].Get(idx, 1);
                                FormatPlayerTime(g_fTime[client][Type][Style], g_sTime[client][Type][Style], sizeof(g_sTime[][][]), false, 1);
                                Format(g_sTime[client][Type][Style], sizeof(g_sTime[][][]), "Best: %s", g_sTime[client][Type][Style]);
                            }
                        }
                    }
                }
            }
            
            g_bTimeIsLoaded[client] = true;
        }
    }
}

public int Native_GetClientStyle(Handle plugin, int numParams)
{
    return GetStyle(GetNativeCell(1));
}

public int Native_IsTimerPaused(Handle plugin, int numParams)
{
    return g_bPaused[GetNativeCell(1)];
}

public int Native_GetStyleName(Handle plugin, int numParams)
{
    int Style     = GetNativeCell(1);
    int maxlength = GetNativeCell(3);
    
    if(Style == 0 && GetNativeCell(4) == true)
    {
        SetNativeString(2, "", maxlength);
        return;
    }
    
    SetNativeString(2, g_StyleConfig[Style].Name, maxlength);
}

public int Native_GetStyleAbbr(Handle plugin, int numParams)
{
    int Style     = GetNativeCell(1);
    int maxlength = GetNativeCell(3);
    
    if(Style == 0 && GetNativeCell(4) == true)
    {
        SetNativeString(2, "", maxlength);
        return;
    }
    
    SetNativeString(2, g_StyleConfig[Style].Name_Short, maxlength);
}

public int Native_GetStyleConfig(Handle plugin, int numParams)
{
    int Style = GetNativeCell(1);
    
    if(Style < g_TotalStyles)
    {
        StyleConfig Config;
        Config = g_StyleConfig[Style];
        
        SetNativeArray(2, view_as<int>(Config), sizeof(Config));
    }
    
    return false;
}

public int Native_Style_IsEnabled(Handle plugin, int numParams)
{
    // Return 'TempEnabled' value because styles can be dynamically changed, 'Enabled' holds the setting from the config always
    return g_StyleConfig[GetNativeCell(1)].TempEnabled;
}

public int Native_Style_IsTypeAllowed(Handle plugin, int numParams)
{
    return g_StyleConfig[GetNativeCell(1)].AllowType[GetNativeCell(2)];
}

public int Native_Style_IsFreestyleAllowed(Handle plugin, int numParams)
{
    return g_StyleConfig[GetNativeCell(1)].Freestyle;
}

public int Native_Style_GetTotal(Handle plugin, int numParams)
{
    return g_TotalStyles;
}

public int Native_Style_CanUseReplay(Handle plugin, int numParams)
{
    return g_StyleConfig[GetNativeCell(1)].Ghost_Use[GetNativeCell(2)];
}

public int Native_Style_CanReplaySave(Handle plugin, int numParams)
{
    return g_StyleConfig[GetNativeCell(1)].Ghost_Save[GetNativeCell(2)];
}

public int Native_GetClientTimerType(Handle plugin, int numParams)
{
    return g_Type[GetNativeCell(1)];
}

public int Native_GetTypeStyleFromCommand(Handle plugin, int numParams)
{
    char sCommand[64];
    GetCmdArg(0, sCommand, sizeof(sCommand));
    ReplaceStringEx(sCommand, sizeof(sCommand), "sm_", "");
    
    int DelimiterLen;
    GetNativeStringLength(1, DelimiterLen);
    
    char[] sDelimiter = new char[DelimiterLen + 1];
    GetNativeString(1, sDelimiter, DelimiterLen + 1);
    
    char sTypeStyle[2][64];
    ExplodeString(sCommand, sDelimiter, sTypeStyle, 2, 64);
    
    if(StrEqual(sTypeStyle[0], ""))
    {
        SetNativeCellRef(2, TIMER_MAIN);
    }
    else if(StrEqual(sTypeStyle[0], "b"))
    {
        SetNativeCellRef(2, TIMER_BONUS);
    }
    else if(StrEqual(sTypeStyle[0], "sb"))
    {
        SetNativeCellRef(2, TIMER_SOLOBONUS);
    }
    else
    {
        return false;
    }
    
    for(int Style; Style < g_TotalStyles; Style++)
    {
        if(Style_IsEnabled(Style))
        {
            if(StrEqual(sTypeStyle[1], g_StyleConfig[Style].Name_Short) || (Style == 0 && StrEqual(sTypeStyle[1], "")))
            {
                SetNativeCellRef(3, Style);
                return true;
            }
        }
    }
    
    return false;
}

public int Native_GetButtons(Handle plugin, int numParams)
{
    return g_UnaffectedButtons[GetNativeCell(1)];
}

// Adds or updates a player's record on the map
int DB_UpdateTime(int client, int Type, int Style, float Time, int Jumps, int Strafes, float Sync, float Sync2, int Flashes, int Partner)
{
    int PlayerID = GetPlayerID(client);
    int PartnerID = 0;
    
    if(Partner != 0)
    {
        if(!IsFakeClient(Partner))
        {
            PartnerID = GetPlayerID(Partner);
        }
    }
    
    if(PlayerID != 0)
    {
        if(!IsFakeClient(client))
        {
            DataPack data = new DataPack();
            data.WriteString(g_sMapName);
            data.WriteCell(client);
            data.WriteCell(PlayerID);
            data.WriteCell(Type);
            data.WriteCell(Style);
            data.WriteFloat(Time);
            data.WriteCell(Jumps);
            data.WriteCell(Strafes);
            data.WriteFloat(Sync);
            data.WriteFloat(Sync2);
            data.WriteCell(Flashes);
            data.WriteCell(PartnerID);
            
            char query[256];
            Format(query, sizeof(query), "DELETE FROM times WHERE MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d AND PlayerID=%d",
                g_sMapName,
                Type,
                Style,
                PlayerID);
            g_DB.Query(DB_UpdateTime_Callback1, query, data);
            
            // Get player position
            int iSize = g_hTimes[Type][Style].Length, Position = -1;
            
            for(int idx = 0; idx < iSize; idx++)
            {
                if(g_hTimes[Type][Style].Get(idx) == PlayerID)
                {
                    Position = idx;
                    break;
                }
            }
            
            // Remove existing time from array if position exists
            if(Position != -1)
            {
                g_hTimes[Type][Style].Erase(Position);
                g_hTimesUsers[Type][Style].Erase(Position);
            }
            
            iSize = g_hTimes[Type][Style].Length;
            Position = iSize;
            
            int realPos = iSize;
            
            float fTime;
            float fOldTime = 0.0;
            int sizeDiff;
            
            for(int idx = 0; idx < iSize; idx++)
            {
                fTime = g_hTimes[Type][Style].Get(idx, 1);
                
                if(Time < fTime && (fOldTime == 0.0 || fOldTime != fTime))
                {
                    Position = Position - 1;
                    realPos = realPos - 1;
                }
                else if(fOldTime == fTime)
                {
                    sizeDiff = sizeDiff + 1;
                    if(Time < fTime)
                        realPos = realPos - 1;
                }
                
                fOldTime = fTime;
            }
            
            if(realPos >= iSize)
            {
                g_hTimes[Type][Style].Resize(realPos + 1);
                g_hTimesUsers[Type][Style].Resize(realPos + 1);
            }
            else
            {
                g_hTimes[Type][Style].ShiftUp(realPos);
                g_hTimesUsers[Type][Style].ShiftUp(realPos);
            }
                
            g_hTimes[Type][Style].Set(realPos, PlayerID, 0);
            g_hTimes[Type][Style].Set(realPos, Time, 1);
            
            char sName[MAX_NAME_LENGTH];
            GetClientName(client, sName, sizeof(sName));
            g_hTimesUsers[Type][Style].SetString(realPos, sName);
            
            return (Position - sizeDiff) + 1;
        }
    }
    
    return 0;
}

public void DB_UpdateTime_Callback1(Database db, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        char sMapName[64];
        
        data.Reset();
        data.ReadString(sMapName, sizeof(sMapName));
        data.ReadCell();
        int PlayerID     = data.ReadCell();
        int Type         = data.ReadCell();
        int Style        = data.ReadCell();
        float Time   = data.ReadFloat();
        int Jumps        = data.ReadCell();
        int Strafes      = data.ReadCell();
        float Sync   = data.ReadFloat();
        float Sync2  = data.ReadFloat();
        int Flashes      = data.ReadCell();
        int PartnerID    = data.ReadCell();
        
        char query[512];
        Format(query, sizeof(query), "INSERT INTO times (MapID, Type, Style, PlayerID, PartnerPlayerID, Time, Jumps, Strafes, Flashes, Points, Timestamp, Sync, SyncTwo) VALUES ((SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1), %d, %d, %d, %d, %f, %d, %d, %d, 0, %d, %f, %f)", 
            sMapName,
            Type,
            Style,
            PlayerID,
            PartnerID,
            Time,
            Jumps,
            Strafes,
            Flashes,
            GetTime(),
            Sync,
            Sync2);
        g_DB.Query(DB_UpdateTime_Callback2, query, data);
    }
    else
    {
        delete data;
        LogError(error);
    }
}

public void DB_UpdateTime_Callback2(Database db, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        
        char sMapName[64];
        data.ReadString(sMapName, sizeof(sMapName));
        data.ReadCell();
        data.ReadCell();
        int Type  = data.ReadCell();
        int Style = data.ReadCell();
        
        Call_StartForward(g_fwdOnTimesUpdated);
        Call_PushString(sMapName);
        Call_PushCell(Type);
        Call_PushCell(Style);
        Call_PushCell(g_hTimes[Type][Style]);
        Call_Finish();
        //DB_UpdateRanks(sMapName, Type, Style);
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

// Opens a menu that displays the records on the given map
void DB_DisplayRecords(int client, char[] sMapName, int Type, int Style)
{
    DataPack pack = new DataPack();
    pack.WriteCell(client);
    pack.WriteCell(Type);
    pack.WriteCell(Style);
    pack.WriteString(sMapName);
    
    char query[512];
    Format(query, sizeof(query), "SELECT Time, User, Jumps, Strafes, Flashes, Points, Timestamp, T.PlayerID, PartnerPlayerID, Sync, SyncTwo FROM times AS T JOIN players AS P ON T.PlayerID=P.PlayerID AND MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d ORDER BY Time, Timestamp",
        sMapName,
        Type,
        Style);
    g_DB.Query(DB_DisplayRecords_Callback1, query, pack);
}

public void DB_DisplayRecords_Callback1(Database db, DBResultSet results, char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {        
        data.Reset();
        int client = data.ReadCell();
        int Type   = data.ReadCell();
        int Style  = data.ReadCell();
        
        char sMapName[64];
        data.ReadString(sMapName, sizeof(sMapName));
        
        float fPrevTime = 0.0;
        
        int rowcount = results.RowCount;
        if(rowcount != 0)
        {    
            char name[(MAX_NAME_LENGTH*2)+1], title[128], item[256], info[256], sTime[32];
            int jumps, strafes, flashes, timestamp, PlayerID, PartnerPlayerID, MapRank;
            float time, points, ClientTime, Sync[2];
            
            Menu menu = new Menu(Menu_WorldRecord);    
            int RowCount = results.RowCount;
            int ci = 0;
            for(int i = 1; i <= RowCount; i++)
            {
                results.FetchRow();
                time      = results.FetchFloat(0);
                results.FetchString(1, name, sizeof(name));
                jumps     = results.FetchInt(2);
                FormatPlayerTime(time, sTime, sizeof(sTime), false, 1);
                strafes   = results.FetchInt(3);
                flashes   = results.FetchInt(4);
                points    = results.FetchFloat(5);
                timestamp = results.FetchInt(6);
                PlayerID  = results.FetchInt(7);
                PartnerPlayerID  = results.FetchInt(8);
                Sync[0]   = results.FetchFloat(9);
                Sync[1]   = results.FetchFloat(10);
                
                if(PlayerID == GetPlayerID(client))
                {
                    ClientTime    = time;
                    if(Type == TIMER_SOLOBONUS)
                        MapRank        = i;
                    else
                        MapRank        = ci;
                }
                
                if(fPrevTime != time)
                    ci       = ci + 1;
                
                Format(info, sizeof(info), "%d;%d;%d;%d;%s;%.1f;%d;%d;%d;%d;%d;%d;%s;%f;%f",
                    PlayerID,
                    PartnerPlayerID,
                    Type,
                    Style,
                    sTime,
                    points,
                    ci,
                    rowcount,
                    timestamp,
                    jumps,
                    strafes,
                    flashes,
                    sMapName,
                    Sync[0],
                    Sync[1]);
                    
                Format(item, sizeof(item), "#%d: %s - %s",
                    ci,
                    sTime,
                    name);
                
                if((i % 7) == 0 || i == RowCount)
                    Format(item, sizeof(item), "%s\n--------------------------------------", item);
                
                menu.AddItem(info, item);
                
                fPrevTime = time;
            }
            
            char sType[32];
            GetTypeName(Type, sType, sizeof(sType));
            
            char sStyle[32];
            GetStyleName(Style, sStyle, sizeof(sStyle));
            
            if(ClientTime != 0.0)
            {
                char sClientTime[32];
                FormatPlayerTime(ClientTime, sClientTime, sizeof(sClientTime), false, 1);
                FormatEx(title, sizeof(title), "%s records [%s] - [%s]\n \nYour time: %s ( %d / %d )\n--------------------------------------",
                    sMapName,
                    sType,
                    sStyle,
                    sClientTime,
                    MapRank,
                    rowcount);
            }
            else
            {
                FormatEx(title, sizeof(title), "%s records [%s] - [%s]\n \n%d total\n--------------------------------------",
                    sMapName,
                    sType,
                    sStyle,
                    rowcount);
            }
            
            menu.SetTitle(title);
            menu.ExitButton = true;
            menu.Display(client, MENU_TIME_FOREVER);
        }
        else
        {
            if(Type == TIMER_MAIN)
                PrintColorText(client, "%s%sNo one has beaten the map yet",
                    g_msg_start,
                    g_msg_textcol);
            else
                PrintColorText(client, "%s%sNo one has beaten the bonus on this map yet.",
                    g_msg_start,
                    g_msg_textcol);
        }
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

public int Menu_WorldRecord(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char sInfo[256];
        menu.GetItem(param2, sInfo, sizeof(sInfo));
        
        ShowRecordInfo(param1, sInfo);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
}

/*
PlayerID, 0
PartnerPlayerID, 1
Type, 2
Style, 3
sTime, 4
points, 5
map rank, 6
total map ranks, 7
timestamp, 8
jumps, 9
strafes, 10
flashes, 11
sMapName, 12
Sync[0], 13
Sync[1], 14
*/

void ShowRecordInfo(int client, const char sInfo[256])
{
    char sInfoExploded[15][64];
    ExplodeString(sInfo, ";", sInfoExploded, sizeof(sInfoExploded), sizeof(sInfoExploded[]));
    
    Menu menu = new Menu(Menu_ShowRecordInfo);
    
    int PlayerID = StringToInt(sInfoExploded[0]);
    char sName[MAX_NAME_LENGTH];
    GetNameFromPlayerID(PlayerID, sName, sizeof(sName));
    
    char sTitle[256];
    FormatEx(sTitle, sizeof(sTitle), "Record details of %s\n \n", sName);
    
    if(StringToInt(sInfoExploded[2]) != TIMER_SOLOBONUS)
    {
        int PPlayerID = StringToInt(sInfoExploded[1]);
        char sPName[MAX_NAME_LENGTH];
        GetNameFromPlayerID(PPlayerID, sPName, sizeof(sPName));
        
        Format(sTitle, sizeof(sTitle), "%sPartner: %s\n \n", sTitle, sPName);
    }
    
    Format(sTitle, sizeof(sTitle), "%sMap: %s\n \n", sTitle, sInfoExploded[12]);
    
    Format(sTitle, sizeof(sTitle), "%sTime: %s (%s / %s)\n \n", sTitle, sInfoExploded[4], sInfoExploded[6], sInfoExploded[7]);
    
    Format(sTitle, sizeof(sTitle), "%sPoints: %s\n \n", sTitle, sInfoExploded[5]);
    
    int Type = StringToInt(sInfoExploded[2]);
    char sType[32];
    GetTypeName(Type, sType, sizeof(sType));
    
    int Style = StringToInt(sInfoExploded[3]);
    char sStyle[32];
    GetStyleName(Style, sStyle, sizeof(sStyle));
    
    Format(sTitle, sizeof(sTitle), "%sTimer: %s\nStyle: %s\n \n", sTitle, sType, sStyle);
    
    if(g_StyleConfig[Style].Count_Left_Strafe || g_StyleConfig[Style].Count_Right_Strafe || g_StyleConfig[Style].Count_Back_Strafe || g_StyleConfig[Style].Count_Forward_Strafe)
    {
        if(Type == TIMER_SOLOBONUS)
        {
            Format(sTitle, sizeof(sTitle), "%sJumps/Strafes: %s/%s\n \n", sTitle, sInfoExploded[9], sInfoExploded[10]);
        }
        else
        {
            Format(sTitle, sizeof(sTitle), "%sJumps/Strafes/Flashes: %s/%s/%s\n \n", sTitle, sInfoExploded[9], sInfoExploded[10], sInfoExploded[11]);
        }
    }
    else
    {
        if(Type == TIMER_SOLOBONUS)
        {
            Format(sTitle, sizeof(sTitle), "%sJumps: %s\n \n", sTitle, sInfoExploded[9]);
        }
        else
        {
            Format(sTitle, sizeof(sTitle), "%sJumps/Flashes: %s/%s\n \n", sTitle, sInfoExploded[9], sInfoExploded[11]);
        }
    }
    
    char sTimeStamp[32];
    FormatTime(sTimeStamp, sizeof(sTimeStamp), "%x %X", StringToInt(sInfoExploded[8]));
    Format(sTitle, sizeof(sTitle), "%sDate: %s\n \n", sTitle, sTimeStamp);
    
    if(g_StyleConfig[Style].CalcSync)
    {
        if(g_bIsAdmin[client] == true)
        {
            Format(sTitle, sizeof(sTitle), "%sSync 1: %.3f%%\n", sTitle, StringToFloat(sInfoExploded[12]));
            Format(sTitle, sizeof(sTitle), "%sSync 2: %.3f%%\n \n", sTitle, StringToFloat(sInfoExploded[13]));
        }
        else
        {
            Format(sTitle, sizeof(sTitle), "%sSync: %.3f%%\n \n", sTitle, StringToFloat(sInfoExploded[12]));
        }
    }
    
    menu.SetTitle(sTitle);
    
    char sItemInfo[32];
    FormatEx(sItemInfo, sizeof(sItemInfo), "%d;%d;%d", PlayerID, Type, Style);
    
    menu.AddItem(sItemInfo, "Show player stats");
    
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_ShowRecordInfo(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));
        
        char sInfoExploded[3][16];
        ExplodeString(sInfo, ";", sInfoExploded, sizeof(sInfoExploded), sizeof(sInfoExploded[]));
        
        Timer_OpenStatsMenu(param1, StringToInt(sInfoExploded[0]), StringToInt(sInfoExploded[1]), StringToInt(sInfoExploded[2]));
    }
    if(action == MenuAction_End)
        delete menu;
}

void DB_ShowTimeAtRank(int client, const char[] MapName, int rank, int Type, int Style)
{        
    if(rank < 1)
    {
        PrintColorText(client, "%s%s%d%s is not a valid rank.",
            g_msg_start,
            g_msg_varcol,
            rank,
            g_msg_textcol);
            
        return;
    }
    
    DataPack pack = new DataPack();
    pack.WriteCell(client);
    pack.WriteCell(rank);
    pack.WriteCell(Type);
    pack.WriteCell(Style);
    
    char query[512];
    Format(query, sizeof(query), "SELECT t2.User, t1.Time, t1.Jumps, t1.Strafes, t1.Points, t1.Timestamp FROM times AS t1, players AS t2 WHERE t1.MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND t1.PlayerID=t2.PlayerID AND t1.Type=%d AND t1.Style=%d ORDER BY t1.Time LIMIT %d, 1",
        MapName,
        Type,
        Style,
        rank-1);
    g_DB.Query(DB_ShowTimeAtRank_Callback1, query, pack);
}

public void DB_ShowTimeAtRank_Callback1(Database db, DBResultSet results, char[] error, any datapack)
{
    DataPack pack = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {        
        pack.Reset();
        int client = pack.ReadCell();
        pack.ReadCell();
        int Type   = pack.ReadCell();
        int Style  = pack.ReadCell();
        
        if(results.RowCount == 1)
        {
            char sUserName[MAX_NAME_LENGTH];
            char sTimeStampDay[255];
            char sTimeStampTime[255];
            char sfTime[255];
            int iTimeStamp, iJumps, iStrafes;
            float fPoints, fTime;
            
            results.FetchRow();
            
            results.FetchString(0, sUserName, sizeof(sUserName));
            fTime      = results.FetchFloat(1);
            iJumps     = results.FetchInt(2);
            iStrafes   = results.FetchInt(3);
            fPoints    = results.FetchFloat(4);
            iTimeStamp = results.FetchInt(5);
            
            FormatPlayerTime(fTime, sfTime, sizeof(sfTime), false, 1);
            FormatTime(sTimeStampDay, sizeof(sTimeStampDay), "%x", iTimeStamp);
            FormatTime(sTimeStampTime, sizeof(sTimeStampTime), "%X", iTimeStamp);
            
            char sType[32];
            GetTypeName(Type, sType, sizeof(sType));
            
            char sStyle[32];
            GetStyleName(Style, sStyle, sizeof(sStyle));
            
            if(g_StyleConfig[Style].Count_Left_Strafe || g_StyleConfig[Style].Count_Right_Strafe || g_StyleConfig[Style].Count_Back_Strafe || g_StyleConfig[Style].Count_Forward_Strafe)
            {
                PrintColorText(client, "%s%s[%s] %s-%s [%s] %s%s has time %s%s%s\n(%s%d%s jumps, %s%.1f%s points)\nDate: %s%s %s%s.",
                    g_msg_start,
                    g_msg_varcol,
                    sType,
                    g_msg_textcol,
                    g_msg_varcol,
                    sStyle,
                    sUserName,
                    g_msg_textcol,
                    g_msg_varcol,
                    sfTime,
                    g_msg_textcol,
                    g_msg_varcol,
                    iJumps,
                    g_msg_textcol,
                    g_msg_varcol,
                    fPoints,
                    g_msg_textcol,
                    g_msg_varcol,
                    sTimeStampDay,
                    sTimeStampTime,
                    g_msg_textcol);
            }
            else
            {
                PrintColorText(client, "%s%s[%s] %s-%s [%s] %s%s has time %s%s%s\n(%s%d%s jumps, %s%d%s strafes, %s%.1f%s points)\nDate: %s%s %s%s.",
                    g_msg_start,
                    g_msg_varcol,
                    sType,
                    g_msg_textcol,
                    g_msg_varcol,
                    sStyle,
                    sUserName,
                    g_msg_textcol,
                    g_msg_varcol,
                    sfTime,
                    g_msg_textcol,
                    g_msg_varcol,
                    iJumps,
                    g_msg_textcol,
                    g_msg_varcol,
                    iStrafes,
                    g_msg_textcol,
                    g_msg_varcol,
                    fPoints,
                    g_msg_textcol,
                    g_msg_varcol,
                    sTimeStampDay,
                    sTimeStampTime,
                    g_msg_textcol);
            }
        }
    }
    else
    {
        LogError(error);
    }
    
    delete pack;
}

void DB_ShowTime(int client, int target, const char[] MapName, int Type, int Style)
{
    DataPack pack = new DataPack();
    pack.WriteCell(client);
    pack.WriteCell(target);
    pack.WriteCell(Type);
    pack.WriteCell(Style);
    
    int PlayerID = GetPlayerID(target);
    
    char query[800];
    FormatEx(query, sizeof(query), "SELECT (SELECT count(*) FROM times WHERE Time<=(SELECT Time FROM times WHERE MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d AND PlayerID=%d) AND MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d) AS Rank, (SELECT count(*) FROM times WHERE MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d) AS Timescount, Time, Jumps, Strafes, Points, Timestamp FROM times WHERE MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d AND PlayerID=%d", 
        MapName, 
        Type, 
        Style, 
        PlayerID, 
        MapName, 
        Type, 
        Style, 
        MapName, 
        Type, 
        Style, 
        MapName, 
        Type, 
        Style, 
        PlayerID);    
    g_DB.Query(DB_ShowTime_Callback1, query, pack);
}

public void DB_ShowTime_Callback1(Database db, DBResultSet results, char[] error, any datapack)
{
    DataPack pack = view_as<DataPack>(datapack);

    if(results != INVALID_HANDLE)
    {
        pack.Reset();
        int client    = pack.ReadCell();
        int target    = pack.ReadCell();
        int Type        = pack.ReadCell();
        int Style     = pack.ReadCell();
        
        int TargetID = GetPlayerID(target);
        
        if(IsClientInGame(client) && IsClientInGame(target) && TargetID)
        {
            char sTime[32];
            char sDate[32];
            char sDateDay[32];
            char sName[MAX_NAME_LENGTH];
            GetClientName(target, sName, sizeof(sName));
            
            char sType[32];
            GetTypeName(Type, sType, sizeof(sType));
            
            char sStyle[32];
            GetStyleName(Style, sStyle, sizeof(sStyle));
            
            if(results.RowCount == 1)
            {
                results.FetchRow();
                int Rank          = results.FetchInt(0);
                int Timescount        = results.FetchInt(1);
                float Time      = results.FetchFloat(2);
                int Jumps          = results.FetchInt(3);
                int Strafes           = results.FetchInt(4);
                float Points      = results.FetchFloat(5);
                int TimeStamp      = results.FetchInt(6);
                
                FormatPlayerTime(Time, sTime, sizeof(sTime), false, 1);
                FormatTime(sDate, sizeof(sDate), "%x", TimeStamp);
                FormatTime(sDateDay, sizeof(sDateDay), "%X", TimeStamp);
                
                if(g_StyleConfig[Style].Count_Left_Strafe || g_StyleConfig[Style].Count_Right_Strafe || g_StyleConfig[Style].Count_Back_Strafe || g_StyleConfig[Style].Count_Forward_Strafe)
                {
                    PrintColorText(client, "%s%s[%s] %s-%s [%s] %s %shas time %s%s%s (%s%d%s / %s%d%s)",
                        g_msg_start,
                        g_msg_varcol,
                        sType,
                        g_msg_textcol,
                        g_msg_varcol,
                        sStyle,
                        sName,
                        g_msg_textcol,
                        g_msg_varcol,
                        sTime,
                        g_msg_textcol,
                        g_msg_varcol,
                        Rank,
                        g_msg_textcol,
                        g_msg_varcol,
                        Timescount,
                        g_msg_textcol);
                    
                    PrintColorText(client, "%sDate: %s%s %s",
                        g_msg_textcol,
                        g_msg_varcol,
                        sDate,
                        sDateDay);
                    
                    PrintColorText(client, "%s(%s%d%s jumps, %s%d%s strafes, and %s%4.1f%s points)",
                        g_msg_textcol,
                        g_msg_varcol,
                        Jumps,
                        g_msg_textcol,
                        g_msg_varcol,
                        Strafes,
                        g_msg_textcol,
                        g_msg_varcol,
                        Points,
                        g_msg_textcol);
                }
                else
                {
                    PrintColorText(client, "%s%s[%s] %s-%s [%s] %s %shas time %s%s%s (%s%d%s / %s%d%s)",
                        g_msg_start,
                        g_msg_varcol,
                        sType,
                        g_msg_textcol,
                        g_msg_varcol,
                        sStyle,
                        sName,
                        g_msg_textcol,
                        g_msg_varcol,
                        sTime,
                        g_msg_textcol,
                        g_msg_varcol,
                        Rank,
                        g_msg_textcol,
                        g_msg_varcol,
                        Timescount,
                        g_msg_textcol);
                    
                    PrintColorText(client, "%sDate: %s%s %s",
                        g_msg_textcol,
                        g_msg_varcol,
                        sDate,
                        sDateDay);
                    
                    PrintColorText(client, "%s(%s%d%s jumps and %s%4.1f%s points)",
                        g_msg_textcol,
                        g_msg_varcol,
                        Jumps,
                        g_msg_textcol,
                        g_msg_varcol,
                        Points,
                        g_msg_textcol);
                }
            }
            else
            {
                if(GetPlayerID(client) != TargetID)
                {
                    PrintColorText(client, "%s%s[%s] %s-%s [%s] %s %shas no time on the map.",
                        g_msg_start,
                        g_msg_varcol,
                        sType,
                        g_msg_textcol,
                        g_msg_varcol,
                        sStyle,
                        sName,
                        g_msg_textcol);
                }
                else
                    PrintColorText(client, "%s%s[%s] %s-%s [%s] %sYou have no time on the map.",
                        g_msg_start,
                        g_msg_varcol,
                        sType,
                        g_msg_textcol,
                        g_msg_varcol,
                        sStyle,
                        g_msg_textcol);
            }
        }
    }
    else
    {
        LogError(error);
    }
    
    delete pack;
}

void DB_DeleteRecord(int client, int Type, int Style, int RecordOne, int RecordTwo)
{
    DataPack data = new DataPack();
    data.WriteCell(client);
    data.WriteCell(Type);
    data.WriteCell(Style);
    data.WriteCell(RecordOne);
    data.WriteCell(RecordTwo);
    
    char query[512];
    Format(query, sizeof(query), "SELECT COUNT(*) FROM times WHERE MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d",
        g_sMapName,
        Type,
        Style);
    g_DB.Query(DB_DeleteRecord_Callback1, query, data);
}

public void DB_DeleteRecord_Callback1(Database db, DBResultSet results, char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        int client        = data.ReadCell();
        int Type          = data.ReadCell();
        int Style            = data.ReadCell();
        int RecordOne     = data.ReadCell();
        int RecordTwo     = data.ReadCell();
        
        results.FetchRow();
        int timesCount = results.FetchInt(0);
        
        char sInfo[32];
        if(Type == TIMER_BONUS || Type == TIMER_SOLOBONUS)
        {
            GetTypeName(Type, sInfo, sizeof(sInfo), true);
            StringToUpper(sInfo);
            Format(sInfo, sizeof(sInfo), "[%s] ", sInfo);
        }
        else if(Style != 0)
        {
            GetStyleName(Style, sInfo, sizeof(sInfo), true);
            StringToUpper(sInfo);
            Format(sInfo, sizeof(sInfo), "[%s] ", sInfo);
        }
        
        if(RecordTwo > timesCount)
        {
            PrintColorText(client, "%s%s%s%sThere is no record %s%d%s.", 
                g_msg_start,
                g_msg_varcol,
                sInfo, 
                g_msg_textcol,
                g_msg_varcol,
                RecordTwo,
                g_msg_textcol);
                
            PrintToConsole(client, "[SM] Usage:\nsm_delete record - Deletes a specific record.\nsm_delete record1 record2 - Deletes all times from record1 to record2.");
            
            return;
        }
        if(RecordOne < 1)
        {
            PrintColorText(client, "%s%sThe minimum record number is 1.",
                g_msg_start,
                g_msg_textcol);
                
            PrintToConsole(client, "[SM] Usage:\nsm_delete record - Deletes a specific record.\nsm_delete record1 record2 - Deletes all times from record1 to record2.");
            
            return;
        }
        if(RecordOne > RecordTwo)
        {
            PrintColorText(client, "%s%sRecord 1 can't be larger than record 2.",
                g_msg_start,
                g_msg_textcol);
                
            PrintToConsole(client, "[SM] Usage:\nsm_delete record - Deletes a specific record.\nsm_delete record1 record2 - Deletes all times from record1 to record2.");
            
            return;
        }
        
        char query[700];
        Format(query, sizeof(query), "DELETE FROM times WHERE MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d AND Time BETWEEN (SELECT t1.Time FROM (SELECT * FROM times) AS t1 WHERE t1.MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND t1.Type=%d AND t1.Style=%d ORDER BY t1.Time LIMIT %d, 1) AND (SELECT t2.Time FROM (SELECT * FROM times) AS t2 WHERE t2.MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND t2.Type=%d AND t2.Style=%d ORDER BY t2.Time LIMIT %d, 1)",
            g_sMapName,
            Type,
            Style,
            g_sMapName,
            Type,
            Style,
            RecordOne-1,
            g_sMapName,
            Type,
            Style,
            RecordTwo-1);
        g_DB.Query(DB_DeleteRecord_Callback2, query, data);
    }
    else
    {
        delete data;
        LogError(error);
    }
}

public void DB_DeleteRecord_Callback2(Database db, DBResultSet results, char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        data.ReadCell();
        int Type      = data.ReadCell();
        int Style     = data.ReadCell();
        int RecordOne = data.ReadCell();
        int RecordTwo = data.ReadCell();
        
        int PlayerID;
        for(int client = 1; client <= MaxClients; client++)
        {
            PlayerID = GetPlayerID(client);
            if(GetPlayerID(client) != 0 && IsClientInGame(client))
            {
                for(int idx = RecordOne - 1; idx < RecordTwo; idx++)
                {
                    if(g_hTimes[Type][Style].Get(idx, 0) == PlayerID)
                    {
                        g_fTime[client][Type][Style] = 0.0;
                        Format(g_sTime[client][Type][Style], sizeof(g_sTime[][][]), "Best: No time");
                    }
                }
            }
        }
        
        // Start the OnTimesDeleted forward
        Call_StartForward(g_fwdOnTimesDeleted);
        Call_PushCell(Type);
        Call_PushCell(Style);
        Call_PushCell(RecordOne);
        Call_PushCell(RecordTwo);
        Call_PushCell(g_hTimes[Type][Style]);
        Call_Finish();
        
        // Reload the times because some were deleted
        DB_LoadTimes(false);
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

void DB_LoadTimes(bool FirstTime)
{    
    #if defined DEBUG
        LogMessage("Attempting to load map times");
    #endif
    
    char query[512];
    Format(query, sizeof(query), "SELECT t1.rownum, t1.MapID, t1.Type, t1.Style, t1.PlayerID, t1.Time, t1.Jumps, t1.Strafes, t1.Points, t1.Timestamp, t2.User, t1.PartnerPlayerID FROM times AS t1, players AS t2 WHERE MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND t1.PlayerID=t2.PlayerID ORDER BY t1.Type, t1.Style, t1.Time, t1.Timestamp",
        g_sMapName);
        
    DataPack pack = new DataPack();
    pack.WriteCell(FirstTime);
    pack.WriteString(g_sMapName);
    
    g_DB.Query(LoadTimes_Callback, query, pack);
}

public void LoadTimes_Callback(Database db, DBResultSet results, char[] error, any datapack)
{
    DataPack pack = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        #if defined DEBUG
            LogMessage("Loading times successful");
        #endif
        
        pack.Reset();
        bool FirstTime = view_as<bool>(pack.ReadCell());
        
        char sMapName[64];
        pack.ReadString(sMapName, sizeof(sMapName));
        
        if(StrEqual(g_sMapName, sMapName))
        {
            for(int Type; Type < MAX_TYPES; Type++)
            {
                for(int Style; Style < g_TotalStyles; Style++)
                {
                    g_hTimes[Type][Style].Clear();
                    g_hTimesUsers[Type][Style].Clear();
                }
            }
            
            int rows = results.RowCount, Type, Style, iSize;
            char sUser[MAX_NAME_LENGTH * 2], sName1[20], sName2[20];
            
            for(int i = 0; i < rows; i++)
            {
                results.FetchRow();
                
                Type  = results.FetchInt(SQL_Column_Type);
                Style = results.FetchInt(SQL_Column_Style);
                
                iSize = g_hTimes[Type][Style].Length;
                g_hTimes[Type][Style].Resize(iSize + 1);
                
                g_hTimes[Type][Style].Set(iSize, results.FetchInt(SQL_Column_PlayerID), 0);
                
                g_hTimes[Type][Style].Set(iSize, results.FetchFloat(SQL_Column_Time), 1);
                
                
                
                if(Type == TIMER_SOLOBONUS)
                {
                    results.FetchString(10, sUser, sizeof(sUser));
                    
                    g_hTimesUsers[Type][Style].PushString(sUser);
                }
                else
                {
                    results.FetchString(10, sName1, sizeof(sName1));
                    int partner = results.FetchInt(11);
                    
                    GetNameFromPlayerID(partner, sName2, sizeof(sName2));
                    Format(sUser, sizeof(sUser), "%s | %s", sName1, sName2);
                    g_hTimesUsers[Type][Style].PushString(sUser);
                }
            }
            
            LoadWorldRecordInfo();
            
            g_bTimesAreLoaded  = true;
            
            Call_StartForward(g_fwdOnTimesLoaded);
            Call_Finish();
            
            if(FirstTime)
            {
                for(int client = 1; client <= MaxClients; client++)
                {
                    DB_LoadPlayerInfo(client);
                }
            }
        }
    }
    else
    {
        LogError(error);
    }
}

void LoadWorldRecordInfo()
{
    char sUser[MAX_NAME_LENGTH], sStyleAbbr[8], sTypeAbbr[8];
    int iSize;
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        GetTypeAbbr(Type, sTypeAbbr, sizeof(sTypeAbbr), true);
        StringToUpper(sTypeAbbr);
        
        for(int Style; Style < MAX_STYLES; Style++)
        {
            if(g_StyleConfig[Style].AllowType[Type])
            {
                GetStyleAbbr(Style, sStyleAbbr, sizeof(sStyleAbbr), true);
                StringToUpper(sStyleAbbr);
                
                iSize = g_hTimes[Type][Style].Length;
                if(iSize > 0)
                {
                    g_WorldRecord[Type][Style] = g_hTimes[Type][Style].Get(0, 1);
                    
                    FormatPlayerTime(g_WorldRecord[Type][Style], g_sRecord[Type][Style], sizeof(g_sRecord[][]), false, 1);
                    
                    g_hTimesUsers[Type][Style].GetString(0, sUser, MAX_NAME_LENGTH);
                    
                    Format(g_sRecord[Type][Style], sizeof(g_sRecord[][]), "%sWR%s: %s (%s)", sTypeAbbr, sStyleAbbr, g_sRecord[Type][Style], sUser);
                }
                else
                {
                    g_WorldRecord[Type][Style] = 0.0;
                    
                    Format(g_sRecord[Type][Style], sizeof(g_sRecord[][]), "%sWR%s: No record", sTypeAbbr, sStyleAbbr);
                }
            }
        }
    }
}

void VectorAngles(float vel[3], float angles[3])
{
    float tmp;
    float yaw;
    float pitch;
    
    if (vel[1] == 0 && vel[0] == 0)
    {
        yaw = 0.0;
        if (vel[2] > 0)
            pitch = 270.0;
        else
            pitch = 90.0;
    }
    else
    {
        yaw = (ArcTangent2(vel[1], vel[0]) * (180 / 3.141593));
        if (yaw < 0)
            yaw += 360;

        tmp = SquareRoot(vel[0]*vel[0] + vel[1]*vel[1]);
        pitch = (ArcTangent2(-vel[2], tmp) * (180 / 3.141593));
        if (pitch < 0)
            pitch += 360;
    }
    
    angles[0] = pitch;
    angles[1] = yaw;
    angles[2] = 0.0;
}

int GetDirection(int client)
{
    float vVel[3];
    Entity_GetAbsVelocity(client, vVel);
    
    float vAngles[3];
    GetClientEyeAngles(client, vAngles);
    float fTempAngle = vAngles[1];

    VectorAngles(vVel, vAngles);

    if(fTempAngle < 0)
        fTempAngle += 360;

    float fTempAngle2 = fTempAngle - vAngles[1];

    if(fTempAngle2 < 0)
        fTempAngle2 = -fTempAngle2;
    
    if(fTempAngle2 < 22.5 || fTempAngle2 > 337.5)
        return 1; // Forwards
    if(fTempAngle2 > 22.5 && fTempAngle2 < 67.5 || fTempAngle2 > 292.5 && fTempAngle2 < 337.5 )
        return 2; // Half-sideways
    if(fTempAngle2 > 67.5 && fTempAngle2 < 112.5 || fTempAngle2 > 247.5 && fTempAngle2 < 292.5)
        return 3; // Sideways
    if(fTempAngle2 > 112.5 && fTempAngle2 < 157.5 || fTempAngle2 > 202.5 && fTempAngle2 < 247.5)
        return 4; // Backwards Half-sideways
    if(fTempAngle2 > 157.5 && fTempAngle2 < 202.5)
        return 5; // Backwards
    
    return 0; // Unknown
}

void CheckSync(int client, int buttons, float vel[3], float angles[3])
{
    int Direction = GetDirection(client);
    
    if(Direction == 1 && GetClientVelocity(client, true, true, false) != 0)
    {    
        int flags = GetEntityFlags(client);
        MoveType movetype = GetEntityMoveType(client);
        if(!(flags & (FL_ONGROUND|FL_INWATER)) && (movetype != MOVETYPE_LADDER))
        {
            // Normalize difference
            float fAngleDiff = angles[1] - g_fOldAngle[client];
            if (fAngleDiff > 180)
                fAngleDiff -= 360;
            else if(fAngleDiff < -180)
                fAngleDiff += 360;
            
            // Add to good sync if client buttons match up
            if(fAngleDiff > 0)
            {
                g_totalSync[client]++;
                if((buttons & IN_MOVELEFT) && !(buttons & IN_MOVERIGHT))
                {
                    g_goodSync[client]++;
                }
                if(vel[1] < 0)
                {
                    g_goodSyncVel[client]++;
                }
            }
            else if(fAngleDiff < 0)
            {
                g_totalSync[client]++;
                if((buttons & IN_MOVERIGHT) && !(buttons & IN_MOVELEFT))
                {
                    g_goodSync[client]++;
                }
                if(vel[1] > 0)
                {
                    g_goodSyncVel[client]++;
                }
            }
        }
    }
    
    g_fOldAngle[client] = angles[1];
}

bool CheckRestrict(float vel[3], int Style)
{
    if(g_StyleConfig[Style].Prevent_Left && vel[1] < 0)
        return true;
    if(g_StyleConfig[Style].Prevent_Right && vel[1] > 0)
        return true;
    if(g_StyleConfig[Style].Prevent_Back && vel[0] < 0)
        return true;
    if(g_StyleConfig[Style].Prevent_Forward && vel[0] > 0)
        return true;

    if(g_StyleConfig[Style].Require_Left && vel[1] >= 0)
        return true;
    if(g_StyleConfig[Style].Require_Right && vel[1] <= 0)
        return true;
    if(g_StyleConfig[Style].Require_Back && vel[0] >= 0)
        return true;
    if(g_StyleConfig[Style].Require_Forward && vel[0] <= 0)
        return true;
    return false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    g_UnaffectedButtons[client] = buttons;
    
    if(IsPlayerAlive(client))
    {
        int Style = g_Style[client][g_Type[client]];
        
        // Key restriction
        bool bRestrict = CheckRestrict(vel, Style);
        
        if(g_StyleConfig[Style].Special)
        {
            if(StrEqual(g_StyleConfig[Style].Special_Key, "hsw"))
            {
                if(vel[0] > 0 && vel[1] != 0)
                    g_HSWCounter[client] = GetEngineTime();
                
                if(((GetEngineTime() - g_HSWCounter[client] > 0.4) || vel[0] <= 0) && !(GetEntityFlags(client) & FL_ONGROUND))
                {
                    bRestrict = true;
                }
            }
            else if (StrEqual(g_StyleConfig[Style].Special_Key, "surfhsw-aw-sd", true))
            {
                if((vel[0] > 0.0 && vel[1] < 0.0) || (vel[0] < 0.0 && vel[1] > 0.0)) // If pressing w and a or s and d, keep unrestricted
                {
                    g_HSWCounter[client] = GetEngineTime();
                }
                else if(GetEngineTime() - g_HSWCounter[client] > 0.3) // Restrict if player hasn't held the right buttons for too long
                {
                    bRestrict = true;
                }
            }
            else if (StrEqual(g_StyleConfig[Style].Special_Key, "surfhsw-as-wd", true))
            {
                if ((vel[0] < 0.0 && vel[1] < 0.0) || (vel[0] > 0.0 && vel[1] > 0.0))
                {
                    g_HSWCounter[client] = GetEngineTime();
                }
                else if(GetEngineTime() - g_HSWCounter[client] > 0.3)
                {
                    bRestrict = true;
                }
            }
        }
        
        if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
            bRestrict = false;
        else if(g_StyleConfig[Style].Freestyle && g_StyleConfig[Style].Freestyle_Unrestrict)
            if(Timer_InsideZone(client, FREESTYLE, 1 << Style) != -1)
                bRestrict = false;
        
        if(bRestrict == true)
        {
            if(!(GetEntityFlags(client) & FL_ATCONTROLS))
                SetEntityFlags(client, GetEntityFlags(client) | FL_ATCONTROLS);
        }
        else
        {
            if(GetEntityFlags(client) & FL_ATCONTROLS)
                SetEntityFlags(client, GetEntityFlags(client) &  ~FL_ATCONTROLS);
        }
        
        // Count strafes
        if(g_StyleConfig[Style].Count_Left_Strafe && !(g_Buttons[client] & IN_MOVELEFT) && (buttons & IN_MOVELEFT))
            g_Strafes[client]++;
        if(g_StyleConfig[Style].Count_Right_Strafe && !(g_Buttons[client] & IN_MOVERIGHT) && (buttons & IN_MOVERIGHT))
            g_Strafes[client]++;
        if(g_StyleConfig[Style].Count_Back_Strafe && !(g_Buttons[client] & IN_BACK) && (buttons & IN_BACK))
            g_Strafes[client]++;
        if(g_StyleConfig[Style].Count_Forward_Strafe && !(g_Buttons[client] & IN_FORWARD) && (buttons & IN_FORWARD))
            g_Strafes[client]++;
        
        // Calculate sync
        if(g_StyleConfig[Style].CalcSync == true)
        {
            CheckSync(client, buttons, vel, angles);
        }
        
        // Check gravity
        if(g_StyleConfig[Style].Gravity != 0.0)
        {
            if(GetEntityGravity(client) == 0.0)
            {
                SetEntityGravity(client, g_StyleConfig[Style].Gravity);
            }
        }
            
        if(g_bTiming[client] == true)
        {
            // Anti - +left/+right
            if(g_hAllowYawspeed.BoolValue == false)
            {
                if(buttons & (IN_LEFT|IN_RIGHT))
                {
                    StopTimer(client);

                    PrintColorText(client, "%s%sYour timer was stopped for using +left/+right",
                        g_msg_start,
                        g_msg_textcol);
                }
            }
            
            // Pausing
            if(g_bPaused[client] == true)
            {
                if(GetEntityMoveType(client) == MOVETYPE_WALK)
                {
                    SetEntityMoveType(client, MOVETYPE_NONE);
                }
            }
            else
            {
                if(GetEntityMoveType(client) == MOVETYPE_NONE)
                {
                    SetEntityMoveType(client, MOVETYPE_WALK);
                }
            }
            
            if(g_Type[client] != TIMER_SOLOBONUS)
            {
                int partner = Timer_GetPartner(client);
            
                if(partner > client)
                {
                    g_fCurrentTime[client] += GetTickInterval();
                    g_fCurrentTime[partner] = g_fCurrentTime[client];
                }
                    
                if(!IsBeingTimed(partner, g_Type[client]))
                    StopTimer(client);
                
            }
            else
            {
                g_fCurrentTime[client] += GetTickInterval();
            }
        }
        
        // auto bhop check
        if(g_bAllowAuto)
        {
            if(g_StyleConfig[Style].Auto || (g_StyleConfig[Style].Freestyle && g_StyleConfig[Style].Freestyle_Auto && Timer_InsideZone(client, FREESTYLE, 1 << Style) != -1))
            {
                if(GetClientSettings(client) & AUTO_BHOP)
                {
                    if(buttons & IN_JUMP)
                    {
                        if(!(GetEntityFlags(client) & FL_ONGROUND))
                        {
                            if(!(GetEntityMoveType(client) & MOVETYPE_LADDER))
                            {
                                if(GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1)
                                {
                                    buttons &= ~IN_JUMP;
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if(g_bJumpInStartZone == false)
        {
            if(Timer_InsideZone(client, MAIN_START, -1) != -1 || Timer_InsideZone(client, BONUS_START, -1) != -1)
            {
                buttons &= ~IN_JUMP;
            }
        }
    }
    
    g_Buttons[client] = buttons;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (IsValidEdict(entity) && StrEqual(classname, "flashbang_projectile", true))
    {
        SDKHook(entity, SDKHook_SpawnPost, Increment_FlashSpawn);
    }
}

public Action Increment_FlashSpawn(int entity, int classname)
{
    int own = Entity_GetOwner(entity);
    if (0 < own <= MaxClients)
    {
        g_Flashes[own] += 1;
    }
    return Plugin_Continue;
}


void SendNewAA(int client, int aa)
{
    if (IsFakeClient(client))
    {
        return;
    }
    char szValue[8];
    FormatEx(szValue, 6, "%d", aa);
    g_ConVar_AirAccelerate.ReplicateToClient(client, szValue);
}
