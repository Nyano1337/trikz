#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = 
{
    name = "[bTimes] Random",
    author = "blacky",
    description = "Handles events and modifies them to fit bTimes' needs",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>
#include <dhooks>
#include <bTimes-timer>
#include <bTimes-teams>
#include <bTimes-zones>
#include <bTimes-random>
#include <clientprefs>
#include <trikz_solid>

#pragma newdecls required

/*
#undef REQUIRE_PLUGIN
#include <bTimes-gunjump>
*/

#define HUD_OFF (1<<0|1<<3|1<<4|1<<8)
#define HUD_ON  0
#define HUD_FUCK (1<<0|1<<1|1<<2|1<<3|1<<4|1<<5|1<<6|1<<7|1<<8|1<<9|1<<10|1<<11)

enum
{
    GameType_CSS,
    GameType_CSGO
};

int g_GameType;
 
int g_Settings[MAXPLAYERS+1] = {SHOW_HINT, ...};
bool g_bHooked;
    
float g_fMapStart;
    
Handle g_hSettingsCookie;

int g_iSoundEnts[2048];
int g_iNumSounds;

// Settings
ConVar g_MessageStart,
    g_MessageVar,
    g_MessageText,
    g_hNoDamage,
    g_hAllowHide,
    g_hAllowKeysAlive,
    g_hKeysShowsJumps,
    g_hAllowKnifeDrop,
    g_WeaponDespawn;
    
Handle g_fwdChatChanged;
    
char g_msg_start[128] = {""};
char g_msg_varcol[128] = {"\x07B4D398"};
char g_msg_textcol[128] = {"\x01"};

Handle g_hSoundscapeUpdate;

//new bool:g_TimerGunJump;
 
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
    
    // Server settings
    g_hAllowKeysAlive  = CreateConVar("timer_allowkeysalive", "1", "Allows players to see !keys while alive.", 0, true, 0.0, true, 1.0);
    g_hKeysShowsJumps  = CreateConVar("timer_keysshowsjumps", "1", "The !keys features shows when a player is using their jump button.", 0, true, 0.0, true, 1.0);
    g_hAllowKnifeDrop  = CreateConVar("timer_allowknifedrop", "1", "Allows players to drop any weapons (including knives and grenades)", 0, true, 0.0, true, 1.0);
    g_WeaponDespawn    = CreateConVar("timer_weapondespawn", "1", "Kills weapons a second after spawning to prevent flooding server.", 0, true, 0.0, true, 1.0);
    g_hNoDamage        = CreateConVar("timer_nodamage", "1", "Blocks all player damage when on", 0, true, 0.0, true, 1.0);
    g_hAllowHide       = CreateConVar("timer_allowhide", "1", "Allows players to use the !hide command", 0, true, 0.0, true, 1.0);
    
    if(g_GameType == GameType_CSS)
    {
        g_MessageStart     = CreateConVar("timer_msgstart", "^556b2f[Timer] ^daa520- ", "Sets the start of all timer messages.");
        g_MessageVar       = CreateConVar("timer_msgvar", "^B4D398", "Sets the color of variables in timer messages such as player names.");
        g_MessageText      = CreateConVar("timer_msgtext", "^DAA520", "Sets the color of general text in timer messages.");
    }
    else if(g_GameType == GameType_CSGO)
    {
        g_MessageStart     = CreateConVar("timer_msgstart", "^3^A^3[^4Timer^3] ^2- ", "Sets the start of all timer messages. (Always keep the ^A after the first color code)");
        g_MessageVar       = CreateConVar("timer_msgvar", "^4", "Sets the color of variables in timer messages such as player names.");
        g_MessageText      = CreateConVar("timer_msgtext", "^5", "Sets the color of general text in timer messages.");
    }
    
    // Hook specific convars
    g_MessageStart.AddChangeHook(OnMessageStartChanged);
    g_MessageVar.AddChangeHook(OnMessageVarChanged);
    g_MessageText.AddChangeHook(OnMessageTextChanged);
    g_hNoDamage.AddChangeHook(OnNoDamageChanged);
    g_hAllowHide.AddChangeHook(OnAllowHideChanged);
    
    // Create config file if it doesn't exist
    AutoExecConfig(true, "random", "timer");
    
    // Event hooks
    HookEvent("player_spawn", Event_PlayerSpawn_Post, EventHookMode_Post);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

    AddNormalSoundHook(NormalSHook);
    AddAmbientSoundHook(AmbientSHook);
    
    AddTempEntHook("Shotgun Shot", CSS_Hook_ShotgunShot);
    
    Handle hGameData = LoadGameConfigFile("soundscapeupdate.games");
    if (!hGameData)
        SetFailState("Failed to load soundscapeupdate gamedata.");
        
    g_hSoundscapeUpdate = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_CBaseEntity);
    //g_hSoundscapeUpdate = DHookCreateFromConf(hGameData, "CEnvSoundscape__UpdateForPlayer");
    if(!g_hSoundscapeUpdate)
	{
		delete hGameData;
		SetFailState("Failed to setup detour for CEnvSoundscape__UpdateForPlayer");
	}
    
    if (!DHookSetFromConf(g_hSoundscapeUpdate, hGameData, SDKConf_Signature, "CEnvSoundscape::UpdateForPlayer"))
    {
		delete hGameData;
		SetFailState("Failed to signature for CEnvSoundscape__UpdateForPlayer from gamedata.");
	}
    
     DHookAddParam(g_hSoundscapeUpdate, HookParamType_Object, 32, DHookPass_ByRef|DHookPass_ODTOR|DHookPass_OASSIGNOP);
    
    if(!DHookEnableDetour(g_hSoundscapeUpdate, false, SoundscapeUpdateForPlayer))
	{
		delete hGameData;
		SetFailState("Failed to detour CEnvSoundscape__UpdateForPlayer.");
	}
    
    delete hGameData;
    
    // Command hooks
    AddCommandListener(DropItem, "drop");
    
    // Player commands
    RegConsoleCmdEx("sm_hide", SM_Hide, "Toggles hide");
    RegConsoleCmdEx("sm_unhide", SM_Hide, "Toggles hide");
    RegConsoleCmdEx("sm_keys", SM_Keys, "Toggles showing pressed keys");
    RegConsoleCmdEx("sm_pad", SM_Keys, "Toggles showing pressed keys");
    RegConsoleCmdEx("sm_showkeys", SM_Keys, "Toggles showing pressed keys");
    RegConsoleCmdEx("sm_spec", SM_Spec, "Be a spectator");
    RegConsoleCmdEx("sm_spectate", SM_Spec, "Be a spectator");
    RegConsoleCmdEx("sm_maptime", SM_Maptime, "Shows how long the current map has been on.");
    RegConsoleCmdEx("sm_sound", SM_Sound, "Choose different sounds to stop when they play.");
    RegConsoleCmdEx("sm_sounds", SM_Sound, "Choose different sounds to stop when they play.");
    RegConsoleCmdEx("sm_specinfo", SM_Specinfo, "Shows who is spectating you.");
    RegConsoleCmdEx("sm_specs", SM_Specinfo, "Shows who is spectating you.");
    RegConsoleCmdEx("sm_speclist", SM_Specinfo, "Shows who is spectating you.");
    RegConsoleCmdEx("sm_spectators", SM_Specinfo, "Shows who is spectating you.");
    RegConsoleCmdEx("sm_normalspeed", SM_Normalspeed, "Sets your speed to normal speed.");
    RegConsoleCmdEx("sm_speed", SM_Speed, "Changes your speed to the specified value.");
    RegConsoleCmdEx("sm_setspeed", SM_Speed, "Changes your speed to the specified value.");
    RegConsoleCmdEx("sm_slow", SM_Slow, "Sets your speed to slow (0.5)");
    RegConsoleCmdEx("sm_fast", SM_Fast, "Sets your speed to fast (2.0)");
    RegConsoleCmdEx("sm_lowgrav", SM_Lowgrav, "Lowers your gravity.");
    RegConsoleCmdEx("sm_normalgrav", SM_Normalgrav, "Sets your gravity to normal.");
    
    // Admin commands
    RegAdminCmd("sm_move", SM_Move, ADMFLAG_GENERIC, "For getting players out of places they are stuck in");
    RegAdminCmd("sm_hudfuck", SM_Hudfuck, ADMFLAG_GENERIC, "Removes a player's hud so they can only leave the server/game through task manager (Use only on players who deserve it)");
    
    // Client settings
    g_hSettingsCookie = RegClientCookie("timer", "Timer settings", CookieAccess_Public);
    
    // Makes FindTarget() work properly..
    LoadTranslations("common.phrases");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Native functions
    CreateNative("GetClientSettings", Native_GetClientSettings);
    CreateNative("SetClientSettings", Native_SetClientSettings);
    
    // Forwards
    g_fwdChatChanged = CreateGlobalForward("OnTimerChatChanged", ET_Event, Param_Cell, Param_String);
    
    return APLRes_Success;
}

/*
public OnAllPluginsLoaded()
{
    if(LibraryExists("gunjump"))
    {
        g_TimerGunJump = true;
    }
}
*/

public void OnMapStart()
{
    //set map start time
    g_fMapStart = GetEngineTime();
}

public void OnClientPutInServer(int client)
{
    // for !hide
    if(g_hAllowHide.BoolValue)
    {
        SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
    }
    
    // prevents damage
    if(g_hNoDamage.BoolValue)
    {
        SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    }
}

public void OnNoDamageChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            if(newValue[0] == '0')
            {
                SDKUnhook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
            }
            else
            {
                SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
            }
        }
    }
}

public void OnAllowHideChanged(Handle convar, const char[] oldValue, const char[] newValue)
{    
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            if(newValue[0] == '0')
            {
                SDKUnhook(client, SDKHook_SetTransmit, Hook_SetTransmit);
            }
            else
            {
                SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
            }
        }
    }
}

public void OnClientDisconnect_Post(int client)
{
    CheckHooks();
}

public void OnClientCookiesCached(int client)
{    
    // get client settings
    char cookies[16];
    GetClientCookie(client, g_hSettingsCookie, cookies, sizeof(cookies));
    
    if(strlen(cookies) == 0)
    {
        g_Settings[client] = SHOW_HINT|AUTO_BHOP|KH_TIMELEFT|KH_SYNC|KH_RECORD|KH_BEST|KH_SPECS;
    }
    else
    {
        g_Settings[client] = StringToInt(cookies);
    }
    
    
    if((g_Settings[client] & STOP_GUNS) && g_bHooked == false)
    {
        g_bHooked = true;
    }
}

public void OnConfigsExecuted()
{
    // load timer message colors
    g_MessageStart.GetString(g_msg_start, sizeof(g_msg_start));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(0);
    Call_PushString(g_msg_start);
    Call_Finish();
    
    g_MessageVar.GetString(g_msg_varcol, sizeof(g_msg_varcol));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(1);
    Call_PushString(g_msg_varcol);
    Call_Finish();
    
    g_MessageText.GetString(g_msg_textcol, sizeof(g_msg_textcol));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(2);
    Call_PushString(g_msg_textcol);
    Call_Finish();
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

public void OnMessageStartChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    g_MessageStart.GetString(g_msg_start, sizeof(g_msg_start));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(0);
    Call_PushString(g_msg_start);
    Call_Finish();
    ReplaceString(g_msg_start, sizeof(g_msg_start), "^", "\x07", false);
}

public void OnMessageVarChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    g_MessageVar.GetString(g_msg_varcol, sizeof(g_msg_varcol));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(1);
    Call_PushString(g_msg_varcol);
    Call_Finish();
    ReplaceString(g_msg_varcol, sizeof(g_msg_varcol), "^", "\x07", false);
}

public void OnMessageTextChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    g_MessageText.GetString(g_msg_textcol, sizeof(g_msg_textcol));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(2);
    Call_PushString(g_msg_textcol);
    Call_Finish();
    ReplaceString(g_msg_textcol, sizeof(g_msg_textcol), "^", "\x07", false);
}

public Action Timer_StopMusic(Handle timer, any data)
{
    int ientity;
    char sSound[128];
    for (int i = 0; i < g_iNumSounds; i++)
    {
        ientity = EntRefToEntIndex(g_iSoundEnts[i]);
        
        if (ientity != INVALID_ENT_REFERENCE)
        {
            for(int client=1; client<=MaxClients; client++)
            {
                if(IsClientInGame(client))
                {
                    if(g_Settings[client] & STOP_MUSIC)
                    {
                        GetEntPropString(ientity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
                        EmitSoundToClient(client, sSound, ientity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);
                    }
                }
            }
        }
    }
}

// Credits to GoD-Tony for everything related to stopping gun sounds
public Action CSS_Hook_ShotgunShot(const char[] te_name, const int[] Players, int numClients, float delay)
{
    if(!g_bHooked)
        return Plugin_Continue;
    
    // Check which clients need to be excluded.
    int newTotal = 0, client, i;
    int[] newClients = new int[MaxClients];
    
    for (i = 0; i < numClients; i++)
    {
        client = Players[i];
        
        if (!(g_Settings[client] & STOP_GUNS))
        {
            newClients[newTotal++] = client;
        }
    }
    
    // No clients were excluded.
    if (newTotal == numClients)
        return Plugin_Continue;
    
    // All clients were excluded and there is no need to broadcast.
    else if (newTotal == 0)
        return Plugin_Stop;
    
    // Re-broadcast to clients that still need it.
    float vTemp[3];
    TE_Start("Shotgun Shot");
    TE_ReadVector("m_vecOrigin", vTemp);
    TE_WriteVector("m_vecOrigin", vTemp);
    TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
    TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
    TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
    TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
    TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
    TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
    TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
    TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
    TE_Send(newClients, newTotal, delay);
    
    return Plugin_Stop;
}

void CheckHooks()
{
    bool bShouldHook = false;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            if(g_Settings[i] & STOP_GUNS)
            {
                bShouldHook = true;
                break;
            }
        }
    }
    
    // Fake (un)hook because toggling actual hooks will cause server instability.
    g_bHooked = bShouldHook;
}

public Action AmbientSHook(char sample[PLATFORM_MAX_PATH], int &entity, float &volume, int &level, int &pitch, float pos[3], int &flags, float &delay)
{
    // Stop music next frame
    CreateTimer(0.0, Timer_StopMusic);
}

public MRESReturn SoundscapeUpdateForPlayer(int pThis, Handle hParams)
{
    int client = DHookGetParamObjectPtrVar(hParams, 1, 0, ObjectValueType_CBaseEntityPtr);

	if(!IsValidEntity(pThis) || !IsValidEdict(pThis))
		return MRES_Ignored;
		
	char sScape[64];
		
	GetEdictClassname(pThis, sScape, sizeof(sScape));
	
	if(!StrEqual(sScape,"env_soundscape") && !StrEqual(sScape,"env_soundscape_triggerable") && !StrEqual(sScape,"env_soundscape_proxy"))
		return MRES_Ignored;
	
	if(0 < client <= MaxClients && g_Settings[client] & STOP_MUSIC)
	{
        DHookSetParamObjectPtrVar(hParams, 1, 28, ObjectValueType_Bool, false); //bInRange
		return MRES_Supercede;
	}
		
	return MRES_Ignored;
}
 
public Action NormalSHook(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if(IsValidEntity(entity) && IsValidEdict(entity))
    {
        char sClassName[128];
        GetEntityClassname(entity, sClassName, sizeof(sClassName));
        
        int iSoundType;
        if(StrEqual(sClassName, "func_door"))
            iSoundType = STOP_DOORS;
        else if(strncmp(sample, "weapons", 7) == 0 || strncmp(sample[1], "weapons", 7) == 0)
            iSoundType = STOP_GUNS;
        else
            return Plugin_Continue;
        
        for (int i = 0; i < numClients; i++)
        {
            if(g_Settings[clients[i]] & iSoundType)
            {
                // Remove the client from the array.
                for (int j = i; j < numClients-1; j++)
                {
                    clients[j] = clients[j+1];
                }
                numClients--;
                i--;
            }
        }
        
        return (numClients > 0) ? Plugin_Changed : Plugin_Stop;
    }
    
    return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if(g_WeaponDespawn.BoolValue == true)
    {
        if(IsValidEdict(entity) && IsValidEntity(entity))
        {
            CreateTimer(1.0, KillEntity, EntIndexToEntRef(entity));
        }
    }
}
 
public Action KillEntity(Handle timer, any ref)
{
    // anti-weapon spam
    int ent = EntRefToEntIndex(ref);
    if(IsValidEdict(ent) && IsValidEntity(ent))
    {
        char entClassname[128];
        GetEdictClassname(ent, entClassname, sizeof(entClassname));
        if(StrContains(entClassname, "weapon_") != -1 || StrContains(entClassname, "item_") != -1)
        {
            int m_hOwnerEntity = GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity");
            if(m_hOwnerEntity == -1)
                AcceptEntityInput(ent, "Kill");
        }
    }
}
 
public Action Event_PlayerSpawn_Post(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    // no block
    if(IsFakeClient(client))
        SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
    
    return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    // Ents are recreated every round.
    g_iNumSounds = 0;
    
    // Find all ambient sounds played by the map.
    char sSound[PLATFORM_MAX_PATH];
    int entity = INVALID_ENT_REFERENCE;
    
    while ((entity = FindEntityByClassname(entity, "ambient_generic")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
        
        int len = strlen(sSound);
        if (len > 4 && (StrEqual(sSound[len-3], "mp3") || StrEqual(sSound[len-3], "wav")))
        {
            g_iSoundEnts[g_iNumSounds++] = EntIndexToEntRef(entity);
        }
    }
}

// drop any weapon
public Action DropItem(int client, const char[] command, int argc)
{
    int weaponIndex = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
    
    // For gun jump plugin, prevent dropping weapons required for the style
    if(weaponIndex != -1)
    {
        int Style = GetClientStyle(client);
        int Type  = GetClientTimerType(client);
        
        StyleConfig Config;

        Style_GetConfig(Style, Config);
        
        if(Config.GunJump && Config.AllowType[Type])
        {
            char sWeapon[64];
            GetEntityClassname(weaponIndex, sWeapon, sizeof(sWeapon));
            
            if(StrEqual(Config.GunJump_Weapon, sWeapon))
                return Plugin_Handled;
        }
    }
    
    // Allow ghosts to drop all weapons and allow players if the cvar allows them to
    if(g_hAllowKnifeDrop.BoolValue || IsFakeClient(client))
    {
        if(weaponIndex != -1)
        {
            CS_DropWeapon(client, weaponIndex, true, false);
        }
        
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}
 
// kill weapon and weapon attachments on drop
public Action CS_OnCSWeaponDrop(int client, int weaponIndex)
{
    if(weaponIndex != -1)
    {
        AcceptEntityInput(weaponIndex, "KillHierarchy");
        AcceptEntityInput(weaponIndex, "Kill");
    }
}

// Tells a player who is spectating them
public Action SM_Specinfo(int client, int args)
{
    if(IsPlayerAlive(client))
    {
        ShowSpecinfo(client, client);
    }
    else
    {
        int Target       = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        int ObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
            
        if((0 < Target <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5))
        {
            ShowSpecinfo(client, Target);
        }
        else
        {
            PrintColorText(client, "%s%sYou are not spectating anyone.",
                g_msg_start,
                g_msg_textcol);
        }
    }
    
    return Plugin_Handled;
}

void ShowSpecinfo(int client, int target)
{
    char[][] sNames = new char[MaxClients + 1][MAX_NAME_LENGTH];
    int index;
    bool bClientHasAdmin = GetUserAdmin(client).HasFlag(Admin_Generic, Access_Effective);
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            if(!bClientHasAdmin && GetUserAdmin(i).HasFlag(Admin_Generic, Access_Effective))
            {
                continue;
            }
                
            if(!IsPlayerAlive(i))
            {
                int iTarget      = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
                int ObserverMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
                
                if((ObserverMode == 4 || ObserverMode == 5) && (iTarget == target))
                {
                    GetClientName(i, sNames[index++], MAX_NAME_LENGTH);
                }
            }
        }
    }
    
    char sTarget[MAX_NAME_LENGTH];
    GetClientName(target, sTarget, sizeof(sTarget));
    
    if(index != 0)
    {
        Panel menu = new Panel();
        
        char sTitle[64];
        Format(sTitle, sizeof(sTitle), "Spectating %s", sTarget);
        menu.DrawText(sTitle);
        menu.DrawText(" ");
        
        for(int i = 0; i < index; i++)
        {
            menu.DrawText(sNames[i]);
        }
        
        menu.DrawText(" ");
        menu.DrawText("0. Close");
        
        menu.Send(client, Menu_SpecInfo, 10);
    }
    else
    {
        PrintColorText(client, "%s%s%s%s has no spectators.",
            g_msg_start,
            g_msg_varcol,
            sTarget,
            g_msg_textcol);
    }
}

public int Menu_SpecInfo(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_End)
        delete menu;
}

// Hide other players
public Action SM_Hide(int client, int args)
{
    SetClientSettings(client, GetClientSettings(client) ^ HIDE_PLAYERS);
    
    if(g_Settings[client] & HIDE_PLAYERS)
    {
        PrintColorText(client, "%s%sPlayers not in your team are now %sinvisible",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol);
    }
    else
    {
        PrintColorText(client, "%s%sPlayers not in your team are now %svisible",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol);
    }
    
    return Plugin_Handled;
}

// Spectate command
public Action SM_Spec(int client, int args)
{
    StopTimer(client);
    ForcePlayerSuicide(client);
    ChangeClientTeam(client, 1);
    if(args != 0)
    {
        char arg[128];
        GetCmdArgString(arg, sizeof(arg));
        int target = FindTarget(client, arg, false, false);
        if(target != -1)
        {
            if(client != target)
            {
                if(IsPlayerAlive(target))
                {
                    SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);
                }
                else
                {
                    char name[MAX_NAME_LENGTH];
                    GetClientName(target, name, sizeof(name));
                    PrintColorText(client, "%s%s%s %sis not alive.", 
                        g_msg_start,
                        g_msg_varcol,
                        name,
                        g_msg_textcol);
                }
            }
            else
            {
                PrintColorText(client, "%s%sYou can't spectate yourself.",
                    g_msg_start,
                    g_msg_textcol);
            }
        }
    }
    return Plugin_Handled;
}

// Move stuck players
public Action SM_Move(int client, int args)
{
    if(args != 0)
    {
        char name[MAX_NAME_LENGTH];
        GetCmdArgString(name, sizeof(name));
        
        int Target = FindTarget(client, name, true, false);
        
        if(Target != -1)
        {
            float angles[3];
            float pos[3];
            GetClientEyeAngles(Target, angles);
            GetAngleVectors(angles, angles, NULL_VECTOR, NULL_VECTOR);
            GetEntPropVector(Target, Prop_Send, "m_vecOrigin", pos);
            
            for(int i=0; i<3; i++)
                pos[i] += (angles[i] * 50);
            
            TeleportEntity(Target, pos, NULL_VECTOR, NULL_VECTOR);
            
            LogMessage("%L moved %L", client, Target);
        }
    }
    else
    {
        PrintToChat(client, "[SM] Usage: sm_move <target>");
    }
    
    return Plugin_Handled;
}

// Punish players
public Action SM_Hudfuck(int client, int args)
{
    char arg[250];
    GetCmdArgString(arg, sizeof(arg));
    
    int target = FindTarget(client, arg, false, false);
    
    if(target != -1)
    {
        SetEntProp(target, Prop_Send, "m_iHideHUD", HUD_FUCK);
        
        char targetname[MAX_NAME_LENGTH];
        GetClientName(target, targetname, sizeof(targetname));
        PrintColorTextAll("%s%s%s %shas been HUD-FUCKED for their negative actions", 
            g_msg_start,
            g_msg_varcol,
            targetname,
            g_msg_textcol);
        
        // Log the hudfuck event
        LogMessage("%L executed sm_hudfuck command on %L", client, target);
    }
    else
    {
        Menu menu = new Menu(Menu_HudFuck);
        menu.SetTitle("Select player to HUD FUCK");
        
        char sAuth[32];
        char sDisplay[64];
        char sInfo[8];
        for(int iTarget = 1; iTarget <= MaxClients; iTarget++)
        {
            if(IsClientInGame(iTarget))
            {
                GetClientAuthId(iTarget, AuthId_Steam2, sAuth, sizeof(sAuth));
                Format(sDisplay, sizeof(sDisplay), "%N <%s>", iTarget, sAuth);
                IntToString(GetClientUserId(iTarget), sInfo, sizeof(sInfo));
                menu.AddItem(sInfo, sDisplay);
            }
        }
        
        menu.ExitBackButton = true;
        menu.ExitButton = true;
        menu.Display(client, MENU_TIME_FOREVER);
    }
    return Plugin_Handled;
}

public int Menu_HudFuck(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        int target = GetClientOfUserId(StringToInt(info));
        if(target != 0)
        {
            PrintColorTextAll("%s%s%N %shas been HUD-FUCKED for their negative actions", 
                g_msg_start,
                g_msg_varcol,
                target,
                g_msg_textcol);
            SetEntProp(target, Prop_Send, "m_iHideHUD", HUD_FUCK);
            
            // Log the hudfuck event
            LogMessage("%L executed sm_hudfuck command on %L", param1, target);
        }
        else
        {
            PrintColorText(param1, "%s%sTarget not in game",
                g_msg_start,
                g_msg_textcol);
        }
    }
    else if(action == MenuAction_End)
        delete menu;
}

// Display current map session time
public Action SM_Maptime(int client, int args)
{
    float mapTime = GetEngineTime() - g_fMapStart;
    int hours, minutes, seconds;
    hours    = RoundToFloor(mapTime/3600);
    mapTime -= (hours * 3600);
    minutes  = RoundToFloor(mapTime/60);
    mapTime -= (minutes * 60);
    seconds  = RoundToFloor(mapTime);
    
    PrintColorText(client, "%sMaptime: %s%d%s %s, %s%d%s %s, %s%d%s %s", 
        g_msg_textcol,
        g_msg_varcol,
        hours,
        g_msg_textcol,
        (hours==1)?"hour":"hours", 
        g_msg_varcol,
        minutes,
        g_msg_textcol,
        (minutes==1)?"minute":"minutes", 
        g_msg_varcol,
        seconds, 
        g_msg_textcol,
        (seconds==1)?"second":"seconds");
}

// Show player key presses
public Action SM_Keys(int client, int args)
{
    SetClientSettings(client, GetClientSettings(client) ^ SHOW_KEYS);
    
    if(g_Settings[client] & SHOW_KEYS)
    {
        PrintColorText(client, "%s%sShowing key presses",
            g_msg_start,
            g_msg_textcol);
    }
    else
    {
        PrintCenterText(client, "");
        
        PrintColorText(client, "%s%sNo longer showing key presses",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

void GetKeysMessage(int client, int mouse, char[] sKeys, int maxlen)
{
    int buttons = GetClientButtons(client);
    
    char sForward[1];
    char sBack[1];
    char sMoveleft[2];
    char sMoveright[2];
    char sTurnLeft[8];
    char sTurnRight[8];
    
    if(buttons & IN_FORWARD)
        sForward[0] = 'W';
    else
        sForward[0] = 32;
        
    if(buttons & IN_MOVELEFT)
    {
        sMoveleft[0] = 'A';
        sMoveleft[1] = 0;
    }
    else
    {
        sMoveleft[0] = 32;
        sMoveleft[1] = 32;
    }
    
    if(buttons & IN_MOVERIGHT)
    {
        sMoveright[0] = 'D';
        sMoveright[1] = 0;
    }
    else
    {
        sMoveright[0] = 32;
        sMoveright[1] = 32;
    }
    
    if(mouse < 0)
    {
        FormatEx(sTurnLeft, sizeof(sTurnLeft), "←");
    }
    else
    {
        FormatEx(sTurnLeft, sizeof(sTurnLeft), "    ");
    }
    
    if(mouse > 0)
    {
        FormatEx(sTurnRight, sizeof(sTurnRight), "→");
    }
    else
    {
        FormatEx(sTurnRight, sizeof(sTurnRight), "    ");
    }
    
    if(buttons & IN_BACK)
        sBack[0] = 'S';
    else
        sBack[0] = 32;
    
    Format(sKeys, maxlen, "   %s\n%s%s     %s%s\n    %s", sForward, sTurnLeft, sMoveleft, sMoveright, sTurnRight, sBack);
    
    if(buttons & IN_DUCK)
        Format(sKeys, maxlen, "%s\nDUCK", sKeys);
    else
        Format(sKeys, maxlen, "%s\n ", sKeys);
        
    if(g_hKeysShowsJumps.BoolValue)
    {
        if(buttons & IN_JUMP)
            Format(sKeys, maxlen, "%s\nJUMP", sKeys);
        else
            Format(sKeys, maxlen, "%s\n ", sKeys);
    }
}

// Open sound control menu
public Action SM_Sound(int client, int args)
{
    Menu menu = new Menu(Menu_StopSound);
    menu.SetTitle("Control Sounds");
    
    char sInfo[16];
    IntToString(STOP_DOORS, sInfo, sizeof(sInfo));
    menu.AddItem(sInfo, (g_Settings[client] & STOP_DOORS)?"Door sounds: Off":"Door sounds: On");
    
    IntToString(STOP_GUNS, sInfo, sizeof(sInfo));
    menu.AddItem(sInfo, (g_Settings[client] & STOP_GUNS)?"Gun sounds: Off":"Gun sounds: On");
    
    IntToString(STOP_MUSIC, sInfo, sizeof(sInfo));
    menu.AddItem(sInfo, (g_Settings[client] & STOP_MUSIC)?"Music: Off":"Music: On");
    
    IntToString(STOP_RECSND, sInfo, sizeof(sInfo));
    menu.AddItem(sInfo, (g_Settings[client] & STOP_RECSND)?"WR sound: Off":"WR sound: On");
    
    IntToString(STOP_PBSND, sInfo, sizeof(sInfo));
    menu.AddItem(sInfo, (g_Settings[client] & STOP_PBSND)?"Personal best sound: Off":"Personal best sound: On");
    
    IntToString(STOP_FAILSND, sInfo, sizeof(sInfo));
    menu.AddItem(sInfo, (g_Settings[client] & STOP_FAILSND)?"No new time sound: Off":"No int time sound: On");
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
    
    return Plugin_Handled;
}

public int Menu_StopSound(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        int setting = StringToInt(info);
        SetClientSettings(param1, GetClientSettings(param1) ^ setting);
        
        if(setting == STOP_GUNS)
            CheckHooks();
        
        if(setting == STOP_MUSIC && (g_Settings[param1] & STOP_MUSIC))
        {
            int ientity;
            char sSound[128];
            for (int i = 0; i < g_iNumSounds; i++)
            {
                ientity = EntRefToEntIndex(g_iSoundEnts[i]);
                
                if (ientity != INVALID_ENT_REFERENCE)
                {
                    GetEntPropString(ientity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
                    EmitSoundToClient(param1, sSound, ientity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);
                }
            }
        }
        
        FakeClientCommand(param1, "sm_sound");
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
}

public Action SM_Speed(int client, int args)
{
    if(args == 1)
    {
        // Get the specified speed
        char sArg[250];
        GetCmdArgString(sArg, sizeof(sArg));
        
        float fSpeed = StringToFloat(sArg);
        
        // Check if the speed value is in a valid range
        if(!(0 <= fSpeed <= 100))
        {
            PrintColorText(client, "%s%sYour speed must be between 0 and 100",
                g_msg_start,
                g_msg_textcol);
            return Plugin_Handled;
        }
        
        StopTimer(client);
        
        // Set the speed
        SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", fSpeed);
        
        // Notify them
        PrintColorText(client, "%s%sSpeed changed to %s%f%s%s",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            fSpeed,
            g_msg_textcol,
            (fSpeed != 1.0)?" (Default is 1)":" (Default)");
    }
    else
    {
        // Show how to use the command
        PrintColorText(client, "%s%sExample: sm_speed 2.0",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_Fast(int client, int args)
{
    StopTimer(client);
    
    // Set the speed
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 2.0);
    
    return Plugin_Handled;
}

public Action SM_Slow(int client, int args)
{
    StopTimer(client);
    
    // Set the speed
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 0.5);
    
    return Plugin_Handled;
}

public Action SM_Normalspeed(int client, int args)
{
    StopTimer(client);
    
    // Set the speed
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
    
    return Plugin_Handled;
}

public Action SM_Lowgrav(int client, int args)
{
    StopTimer(client);
    
    SetEntityGravity(client, 0.6);
    
    PrintColorText(client, "%s%sUsing low gravity. Use !normalgrav to switch back to normal gravity.",
        g_msg_start,
        g_msg_textcol);
}

public Action SM_Normalgrav(int client, int args)
{
    SetEntityGravity(client, 0.0);
    
    PrintColorText(client, "%s%sUsing normal gravity.",
        g_msg_start,
        g_msg_textcol);
}

public Action Hook_SetTransmit(int entity, int client)
{
    int target = client;
    if(!IsPlayerAlive(client))
    {
        int target2 = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        
        if(0 < target2 <= MaxClients && !IsFakeClient(target2))
            target = target2;
    }

    if(client != entity && target != entity && (0 < entity <= MaxClients) && IsPlayerAlive(target))
    {
        if((g_Settings[client] & HIDE_PLAYERS) && Timer_GetPartner(entity) != Timer_GetPartner(Timer_GetPartner(target)))
            return Plugin_Handled;
        
        //if(GetEntityMoveType(entity) == MOVETYPE_NOCLIP && !IsFakeClient(entity))
        //    return Plugin_Handled;
        
        if(!IsPlayerAlive(entity))
            return Plugin_Handled;
        
        if(IsFakeClient(entity))
            return Plugin_Handled;
            
        if(IsBeingTimed(target, TIMER_SOLOBONUS) != IsBeingTimed(entity, TIMER_SOLOBONUS))
            return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public Action Trikz_CheckSolidity(int ent1, int ent2) 
{
    if (1 <= ent1 < MaxClients && 1 <= ent2 < MaxClients && ((Timer_GetPartner(ent1) != Timer_GetPartner(Timer_GetPartner(ent2))&& (g_Settings[ent1] & HIDE_PLAYERS)) || (Timer_GetPartner(ent2) != Timer_GetPartner(Timer_GetPartner(ent1)) && (g_Settings[ent2] & HIDE_PLAYERS))))
    {
        return Plugin_Handled;
    }
    
    return Plugin_Continue; 
}

public Action Hook_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
    if(g_GameType == GameType_CSS)
    {
        SetEntPropVector(victim, Prop_Send, "m_vecPunchAngle", NULL_VECTOR);
        SetEntPropVector(victim, Prop_Send, "m_vecPunchAngleVel", NULL_VECTOR);
    }
    
    /*
    if(g_TimerGunJump == true)
    {
        if(Timer_IsGunJump())
        {
            return Plugin_Continue;
        }
    }
    */
    
    return Plugin_Handled;
}
 
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& mdnum, int& tickcount, int& seed, int mouse[2])
{    
    // keys check
    if(g_Settings[client] & SHOW_KEYS)
    {
        if((g_hAllowKeysAlive.BoolValue && IsPlayerAlive(client)) || !IsPlayerAlive(client))
        {
            char keys[64];
            if(IsPlayerAlive(client))
            {
                GetKeysMessage(client, mouse[0], keys, sizeof(keys));
                PrintCenterText(client, keys);
            }
            else
            {
                int Target      = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
                int ObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
                
                if((0 < Target <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5))
                {
                    GetKeysMessage(Target, mouse[0], keys, sizeof(keys));
                    PrintCenterText(client, keys);
                }
            }
        }
    }
}

// get a player's settings
public int Native_GetClientSettings(Handle plugin, int numParams)
{
    return g_Settings[GetNativeCell(1)];
}

// set a player's settings
public int Native_SetClientSettings(Handle plugin, int numParams)
{
    int client         = GetNativeCell(1);
    g_Settings[client] = GetNativeCell(2);
    
    if(AreClientCookiesCached(client))
    {
        char sSettings[16];
        IntToString(g_Settings[client], sSettings, sizeof(sSettings));
        SetClientCookie(client, g_hSettingsCookie, sSettings);
    }
}
