#include <clientprefs>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <sdktools>
#include <smlib>
#include <morecolors>
#include <sendproxy>
#include <dhooks>
#include <trikz_solid>
#include <bTimes-timer>
#include <bTimes-teams>
#include <bTimes-core>
#include <bTimes-zones>

#pragma newdecls required

#define CSF_BLOCK 1
#define CSF_AUTOSWITCH 1 << 1
#define CSF_AUTOFLASH 1 << 2

public Plugin myinfo = 
{
    name = "trikz_menu",
    author = "george, ici",
    description = "a cool menu for nerds",
    version = "1.1",
    url = ""
}

bool g_bAutoFlash[MAXPLAYERS+1];
bool g_bAutoSwitch[MAXPLAYERS+1];
bool g_bBlock[MAXPLAYERS+1];
bool g_bNotSolid[4096];

float g_fLastTouch[MAXPLAYERS+1];

Handle g_hStorageCookie;
Handle g_hTimers[MAXPLAYERS+1];

int g_offset;
bool g_bMapLoad = false;

int g_ammoOffset = -1;
int g_hMyWeapons = -1;

float g_fCheckpoints[MAXPLAYERS+1][2][3][3];
float g_fCheckpointStamina[MAXPLAYERS+1][2][2];

bool g_bSetCheckpoint[MAXPLAYERS+1][2];

bool g_bSaveAngles[MAXPLAYERS+1];
bool g_bSaveVelocity[MAXPLAYERS+1];

int g_LastUsedTp[MAXPLAYERS+1];

Handle g_hDetonate;

public void OnPluginStart()
{
    g_hStorageCookie = RegClientCookie("TrikzPreference", "A cookie storing the trikz preferences.", CookieAccess_Private);

    g_offset = FindSendPropInfo("CBaseCombatWeapon", "m_hOwnerEntity");

    RegConsoleCmd("sm_trikz", SM_Trikz, "Opens the trikz menu.");
    RegConsoleCmd("sm_t", SM_Trikz, "Opens the trikz menu.");
    RegConsoleCmd("sm_cp", SM_CP, "Opens the checkpoints menu.");
    RegConsoleCmd("sm_save", SM_Save, "Saves a checkpoint.");
    RegConsoleCmd("sm_tele", SM_Tele, "Teleports to a checkpoint.");
    RegConsoleCmd("sm_tpto", SM_TpTo, "Teleport to players.");
    RegConsoleCmd("sm_switch", SM_Switch, "Toggles block.");
    RegConsoleCmd("sm_block", SM_Switch, "Toggles block.");
    RegConsoleCmd("sm_flash", SM_Flash, "Gives you a flash.");

    //HookEvent("weapon_fire", Event_WeaponFire);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    
    g_ammoOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo");

    if(g_ammoOffset == -1)
    {
        SetFailState("Failed to find m_iAmmo offset");
    }

    g_hMyWeapons = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");  

    if(g_hMyWeapons == -1)
    {
        SetFailState("Failed to find m_hMyWeapons offset");
    }
    
    Handle hGameData = LoadGameConfigFile("fbdetonate.games");
    if (!hGameData)
        SetFailState("Failed to load fbdetonate gamedata.");
        
    g_hDetonate = DHookCreateFromConf(hGameData, "CFlashbangProjectile__Detonate");
    if(!g_hDetonate)
    {
        delete hGameData;
        SetFailState("Failed to setup detour for CEnvSoundscape__UpdateForPlayer");
    }
    
    if(!DHookEnableDetour(g_hDetonate, false, FlashbangDetonate))
    {
        delete hGameData;
        SetFailState("Failed to detour CFlashbangProjectile__Detonate.");
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_PreThinkPost, OnClientPreThinkPost);
    SendProxy_Hook(client, "m_CollisionGroup", Prop_Int, ProxyCallback);
    
    g_bSetCheckpoint[client][0] = false;
    g_bSetCheckpoint[client][1] = false;
    g_LastUsedTp[client] = 0;

    SDKHook(client, SDKHook_Touch, OnPlayerTouch);
}

public Action OnPlayerTouch(int client, int other)
{
    if(g_bBlock[client] && other <= MaxClients && other > 0 && g_bBlock[other])
        g_fLastTouch[client] = GetGameTime();
        
    return Plugin_Continue;
}

public Action ProxyCallback(int entity, const char[] propname, int &iValue, int element)
{
    if(g_bBlock[entity] && !IsBeingTimed(entity, TIMER_SOLOBONUS) && (GetGameTime() - g_fLastTouch[entity]) < 0.15)
    {
        iValue = 5;
    }
    else
    {
        iValue = 2;
    }
    return Plugin_Changed;
}

public Action FlashProxyCallback(int entity, const char[] propname, int &iValue, int element)
{
    iValue = 2;
    return Plugin_Changed;
}

public void OnClientPreThinkPost(int client)
{
    if(g_bAutoFlash[client])
    {        
        char sWeapon[64];
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"); 
        //if(IsFakeClient(client) && GetClientFlashBangs(client) == 0)
        //{
        //    GiveFlash(client);
        //}
        if(IsValidEdict(weapon))
        {
            GetEdictClassname(weapon, sWeapon, sizeof(sWeapon));
            if (StrEqual(sWeapon, "weapon_flashbang")) {
                float fThrowTime = GetEntPropFloat(weapon, Prop_Send, "m_fThrowTime");
    
                if(fThrowTime && (fThrowTime > 0.0) && (fThrowTime < GetGameTime()))
                {
                    //the flashbang has literally been thrown this frame in postthink, as we are in postthinkpost we should be able to give a flashbang right now
                    GiveFlash(client);
                    //GiveFlash(client);
            
                    if(g_bAutoSwitch[client])
                    {
                        RequestFrame(FlashbangSwitch_Callback, client);
                    }
                }
            }
        }
    }
}

public void FlashbangSwitch_Callback(any client) {
    if(IsValidClient(client))
    {
        FakeClientCommand(client, "use weapon_knife");
        FakeClientCommand(client, "use weapon_flashbang");
    }
}

public void OnMapStart()
{
    g_bMapLoad = false;
    CreateTimer(3.0, Timer_MapLoad);
}

public Action Timer_MapLoad(Handle timer, any data)
{
    g_bMapLoad = true;
}

public MRESReturn FlashbangDetonate(int pThis)
{
    if(IsValidEntity(pThis))
    {
        AcceptEntityInput(pThis, "kill");
        return MRES_Supercede;
    }
    
    return MRES_Ignored;
}

public void OnEntityCreated(int edict, const char[] classname)
{
    if(0 <= edict < 4096)
        g_bNotSolid[edict] = false;
        
    if (g_bMapLoad) {
        if (IsValidEdict(edict)) {
            if (StrEqual(classname, "weapon_flashbang")) {
                CreateTimer(0.25, Timer_RemoveFlash, edict);
            }
        }
        
        if (IsValidEdict(edict) && StrEqual(classname, "flashbang_projectile"))
        {
            SDKHook(edict, SDKHook_SpawnPost, OnFlashSpawned);
            SDKHook(edict, SDKHook_SetTransmit, FlashTransmit);
            g_bNotSolid[edict] = true;
        }
    }
}

public Action FlashTransmit(int entity, int client)
{
    static int owner;
    static int partner;

    if(1 <= client <= MaxClients && IsPlayerAlive(client))
    {
        owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
        partner = Timer_GetPartner(owner);
        
        if(Timer_GetPartner(Timer_GetPartner(client)) != partner && client != owner)
            return Plugin_Handled; 
    }
    
    return Plugin_Continue;
}

public Action OnFlashSpawned(int entity)
{
    SendProxy_Hook(entity, "m_CollisionGroup", Prop_Int, FlashProxyCallback);
    return Plugin_Continue;
}

public Action Timer_RemoveFlash(Handle timer, any edict)
{
    if (IsValidEdict(edict)) {
        char sEdictName[32];
        GetEdictClassname(edict, sEdictName, sizeof(sEdictName));
        if (StrEqual(sEdictName, "weapon_flashbang")) {
            if (GetEntDataEnt2(edict, g_offset) == -1) {
                AcceptEntityInput(edict, "kill");
            }
        }
    }
}

public void OnClientCookiesCached(int client)
{
    if(IsValidClient(client))
    {
        char sValue[8];
        GetClientCookie(client, g_hStorageCookie, sValue, sizeof(sValue));

        int inte = (sValue[0] != '\0' && StringToInt(sValue));

        g_bAutoFlash[client] = ((inte & CSF_AUTOFLASH) == 1);
        g_bAutoSwitch[client] = ((inte & CSF_AUTOSWITCH) == 1);
        g_bBlock[client] = ((inte & CSF_BLOCK) == 1);
        if(!g_bBlock[client] && !IsFakeClient(client))
        {
            SetAlpha(client,100);
        }
        OpenTrikzMenu(client);
        
        g_hTimers[client] = INVALID_HANDLE;
        
        if(IsFakeClient(client))
        {
            g_bAutoFlash[client] = true;
            g_bAutoSwitch[client] = true;
        }
    }
}

void SaveTrikzPref(int client)
{
    if (AreClientCookiesCached(client))
    {
        char sValue[8];
        
        int iValue = 0;
        
        if(g_bBlock[client])
        {
            iValue = CSF_BLOCK;
        }
        if(g_bAutoFlash[client])
        {
            iValue |= CSF_AUTOFLASH;
        }
        if(g_bAutoSwitch[client])
        {
            iValue |= CSF_AUTOSWITCH;
        }
        
        IntToString(iValue, sValue, sizeof(sValue));
 
        SetClientCookie(client, g_hStorageCookie, sValue);
    }
}

public Action SM_Trikz(int client, int args)
{
    if(AreClientCookiesCached(client))
    {
        OpenTrikzMenu(client);
    }
}

public Action SM_CP(int client, int args)
{
    if(AreClientCookiesCached(client))
    {
        OpenCheckpointsMenu(client);
    }
}

public Action SM_Switch(int client, int args)
{
    if(AreClientCookiesCached(client))
    {
        ToggleBlock(client);
    }
}

int OpenTrikzMenu(int client)
{
    Handle menu = CreateMenu(Menu_Trikz, MENU_ACTIONS_DEFAULT);
    SetMenuTitle(menu, "Trikz Menu\n \n");
    char text[32];
    
    if (g_bAutoSwitch[client])
    {
        text = "Disable Autoswitch";
    }
    else
    {
        text = "Enable Autoswitch";
    }
    AddMenuItem(menu, "autoswitch", text);
    
    if (g_bAutoFlash[client])
    {
        text = "Disable Autoflash";
    }
    else
    {
        text = "Enable Autoflash";
    }
    AddMenuItem(menu, "autoflash", text);
    
    if (g_bBlock[client])
    {
        text = "Disable Block \n ";
    }
    else
    {
        text = "Enable Block \n ";
    }
    AddMenuItem(menu, "block", text);
    
    AddMenuItem(menu, "flash", "Give Flash \n ");
    
    AddMenuItem(menu, "checkpoints", "Open Checkpoint Menu");
    AddMenuItem(menu, "tpto", "Teleport to Player");
    
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_Trikz(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "autoswitch", true))
        {
            g_bAutoSwitch[param1] = !g_bAutoSwitch[param1];
            if(g_bAutoSwitch[param1])
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] Enabled Autoswitch.");
            }
            else
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] Disabled Autoswitch.");
            }
            SaveTrikzPref(param1);
            OpenTrikzMenu(param1);
        }
        else if (StrEqual(info, "autoflash", true))
        {
            g_bAutoFlash[param1] = !g_bAutoFlash[param1];
            if(g_bAutoFlash[param1])
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] Enabled Autoflash.");
            }
            else
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] Disabled Autoflash.");
            }
            if(g_bAutoFlash[param1] && (GetClientFlashBangs(param1) == 0))
            {
                GiveFlash(param1);
            }
            SaveTrikzPref(param1);
            OpenTrikzMenu(param1);
        }
        else if (StrEqual(info, "flash", true))
        {
            if(GetClientFlashBangs(param1) == 0)
                GiveFlash(param1);
                
            OpenTrikzMenu(param1);
        }
        else if (StrEqual(info, "block", true))
        {
            ToggleBlock(param1);
            OpenTrikzMenu(param1);
        }
        else if (StrEqual(info, "checkpoints", true))
        {
            OpenCheckpointsMenu(param1);
        }
        else if (StrEqual(info, "tpto", true))
        {
            OpenTeleportMenu(param1, true);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    return 0;
}

bool IsValidClient(int client, bool alive = false)
{
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) || (alive && !IsPlayerAlive(client)) ) 
        return false; 
     
    return true; 
}  

void SetAlpha(int target, int alpha)
{        
    SetEntityRenderMode(target, RENDER_TRANSCOLOR);
    SetEntityRenderColor(target, 255, 255, 255, alpha);    
}

/*public Action:Event_WeaponFire(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event,"userid"));
    decl String:weapon[20];
    GetEventString(event,"weapon",weapon,sizeof(weapon));
    
    if (StrEqual(weapon,"flashbang"))
    {
        if(g_bAutoFlash[client])
        {
            GiveFlash(client);
            
            if(g_bAutoSwitch[client])
            {
                CreateTimer(0.15, SelectFlash, client);
            }
        }
    }
}*/

public Action Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event,"userid"));
    
    if(GetClientTeam(client) >= 2 && !IsFakeClient(client))
    {
        if(AreClientCookiesCached(client))
        {
            if(g_bBlock[client])
            {
                SetAlpha(client,255);
            }
            else
            {
                SetAlpha(client,100);
            }
        }
    }
}

void ToggleBlock(int client)
{
    if(IsFakeClient(client)) return
    
    if (IsPlayerAlive(client))
    {
        if (g_bBlock[client])
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] Disabled block.");
            SetAlpha(client,100);
            g_bBlock[client] = false;
        }
        else
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] Enabled block.");
            SetAlpha(client,255);
            g_bBlock[client] = true;
        }
    }
    SaveTrikzPref(client);
}

public Action Trikz_CheckSolidity(int ent1, int ent2) 
{
    static int owner;
    static int partner;

    if (1 <= ent1 <= MaxClients && 1 <= ent2 <= MaxClients && (!g_bBlock[ent2] || !g_bBlock[ent1] || IsBeingTimed(ent1, TIMER_SOLOBONUS) || IsBeingTimed(ent2, TIMER_SOLOBONUS)))
    {
        return Plugin_Handled; 
    } 
    else if(g_bNotSolid[ent2] && 1 <= ent1 <= MaxClients)
    {
        owner = GetEntPropEnt(ent2, Prop_Data, "m_hOwnerEntity");
        partner = Timer_GetPartner(owner);
        
        if(!g_bBlock[ent1] || IsBeingTimed(ent1, TIMER_SOLOBONUS) || Timer_GetPartner(Timer_GetPartner(ent1)) != partner)
        {
            return Plugin_Handled; 
        }
    }
    else if(g_bNotSolid[ent1] && 1 <= ent2 <= MaxClients)
    {
        owner = GetEntPropEnt(ent1, Prop_Data, "m_hOwnerEntity");
        partner = Timer_GetPartner(owner);
        
        if(!g_bBlock[ent2] || IsBeingTimed(ent2, TIMER_SOLOBONUS) || Timer_GetPartner(Timer_GetPartner(ent2)) != partner)
        {
            return Plugin_Handled; 
        }
    }
    else if(g_bNotSolid[ent1] && g_bNotSolid[ent2])
    {
        owner = GetEntPropEnt(ent1, Prop_Data, "m_hOwnerEntity");
        partner = GetEntPropEnt(ent2, Prop_Data, "m_hOwnerEntity");
        
        if((Timer_GetPartner(owner) != 0 || Timer_GetPartner(partner) != 0) && owner != partner && Timer_GetPartner(owner) != partner)
        {
            return Plugin_Handled;
        }
    }
    
    //else
    //{
    //    g_bNotSolid[ent1] = false;
    //    g_bNotSolid[ent2] = false;
    //} 
    return Plugin_Continue; 
}

public void OnClientDisconnect(int client)
{
    if (!IsFakeClient(client) && (g_hTimers[client] && g_hTimers[client] != INVALID_HANDLE))
    {
        CloseHandle(g_hTimers[client]);
        g_hTimers[client] = INVALID_HANDLE;
    }
}

stock int GetClientFlashBangs(int client)
{
    char weaponn[255];
    
    for(int i = 0, weapon; i < 128; i += 4)
    {
        weapon = GetEntDataEnt2(client, g_hMyWeapons + i);
        
        if(weapon != -1)
        {
            GetEdictClassname(weapon, weaponn, sizeof(weaponn));
            
            if(StrEqual(weaponn, "weapon_flashbang"))
            {
                int iPrimaryAmmoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", 4);
                int ammo = GetEntData(client, g_ammoOffset+(iPrimaryAmmoType*4));
                
                return ammo;
            }
        }
    }
    
    return 0;
}

/*public FlashbangAllow_Callback(any:client) {
    if(IsValidClient(client))
    {
        decl String:sWeapon[64];
        new weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"); 
        GetEdictClassname(weapon, sWeapon, sizeof(sWeapon));
        if (StrEqual(sWeapon, "weapon_flashbang")) {
            SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime()+0.5);
            SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime()+0.5);
        }
    }
}

public Action:SelectFlash(Handle:timer, any:client)
{
    if(IsValidClient(client))
    {
        FakeClientCommand(client, "use weapon_knife");
        FakeClientCommand(client, "use weapon_flashbang");
        RequestFrame(FlashbangAllow_Callback, client);
    }
    return Plugin_Stop;
}*/

void GiveFlash(int client)
{
    GivePlayerItem(client, "weapon_flashbang");
}

public void OnConfigsExecuted()
{
    ServerCommand("sv_ignoregrenaderadio 1");
}

public int Menu_Checkpoints(Handle menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "savecheck1", true))
        {
            if(IsPlayerAlive(param1))
            {
                GetEntPropVector(param1, Prop_Send, "m_vecOrigin", g_fCheckpoints[param1][0][0]);
                GetClientEyeAngles(param1, g_fCheckpoints[param1][0][1]);
                GetEntPropVector(param1, Prop_Data, "m_vecAbsVelocity", g_fCheckpoints[param1][0][2]);
                g_fCheckpointStamina[param1][0][0] = GetEntPropFloat(param1, Prop_Send, "m_flStamina");
                g_fCheckpointStamina[param1][0][1] = GetEntPropFloat(param1, Prop_Send, "m_flVelocityModifier");
                g_bSetCheckpoint[param1][0] = true;
                CPrintToChat(param1, "{default}[{red}Trikz{default}] Checkpoint 1 Saved.");
                OpenCheckpointsMenu(param1);
            }
            else
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] You must be alive to do this!");
            }
        }
        else if (StrEqual(info, "loadcheck1", true))
        {
            if(IsPlayerAlive(param1))
            {
                if(g_bSetCheckpoint[param1][0])
                {
                    if(g_bSaveAngles[param1] && g_bSaveVelocity[param1])
                    {
                        TeleportEntity(param1, g_fCheckpoints[param1][0][0], g_fCheckpoints[param1][0][1], g_fCheckpoints[param1][0][2]);
                    }
                    else if(g_bSaveVelocity[param1])
                    {
                        TeleportEntity(param1, g_fCheckpoints[param1][0][0], NULL_VECTOR, g_fCheckpoints[param1][0][2]);
                    }
                    else if(g_bSaveAngles[param1])
                    {
                        TeleportEntity(param1, g_fCheckpoints[param1][0][0], g_fCheckpoints[param1][0][1], view_as<float>({0.0,0.0,0.0}));
                    }
                    else
                    {
                        TeleportEntity(param1, g_fCheckpoints[param1][0][0], NULL_VECTOR, view_as<float>({0.0,0.0,0.0}));
                    }
                    
                    SetEntPropFloat(param1, Prop_Send, "m_flStamina", g_fCheckpointStamina[param1][0][0]);
                    SetEntPropFloat(param1, Prop_Send, "m_flVelocityModifier", g_fCheckpointStamina[param1][0][1]);
                    
                    StopTimer(param1);
                    OpenCheckpointsMenu(param1);
                }
                else
                {
                    CPrintToChat(param1, "{default}[{red}Trikz{default}] Checkpoint 1 does not exist.");
                    OpenCheckpointsMenu(param1);
                }
            }
            else
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] You must be alive to do this!");
            }
        }
        else if (StrEqual(info, "savecheck2", true))
        {
            if(IsPlayerAlive(param1))
            {
                GetEntPropVector(param1, Prop_Send, "m_vecOrigin", g_fCheckpoints[param1][1][0]);
                g_bSetCheckpoint[param1][1] = true;
                GetClientEyeAngles(param1, g_fCheckpoints[param1][1][1]);
                GetEntPropVector(param1, Prop_Data, "m_vecAbsVelocity", g_fCheckpoints[param1][1][2]);
                g_fCheckpointStamina[param1][1][0] = GetEntPropFloat(param1, Prop_Send, "m_flStamina");
                g_fCheckpointStamina[param1][1][1] = GetEntPropFloat(param1, Prop_Send, "m_flVelocityModifier");
                CPrintToChat(param1, "{default}[{red}Trikz{default}] Checkpoint 2 Saved.");
                OpenCheckpointsMenu(param1);
            }
            else
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] You must be alive to do this!");
            }
        }
        else if (StrEqual(info, "loadcheck2", true))
        {
            if(IsPlayerAlive(param1))
            {
                if(g_bSetCheckpoint[param1][1])
                {
                    if(g_bSaveAngles[param1] && g_bSaveVelocity[param1])
                    {
                        TeleportEntity(param1, g_fCheckpoints[param1][1][0], g_fCheckpoints[param1][1][1], g_fCheckpoints[param1][1][2]);
                    }
                    else if(g_bSaveVelocity[param1])
                    {
                        TeleportEntity(param1, g_fCheckpoints[param1][1][0], NULL_VECTOR, g_fCheckpoints[param1][1][2]);
                    }
                    else if(g_bSaveAngles[param1])
                    {
                        TeleportEntity(param1, g_fCheckpoints[param1][1][0], g_fCheckpoints[param1][1][1], view_as<float>({0.0,0.0,0.0}));
                    }
                    else
                    {
                        TeleportEntity(param1, g_fCheckpoints[param1][1][0], NULL_VECTOR, view_as<float>({0.0,0.0,0.0}));
                    }
                    
                    SetEntPropFloat(param1, Prop_Send, "m_flStamina", g_fCheckpointStamina[param1][1][0]);
                    SetEntPropFloat(param1, Prop_Send, "m_flVelocityModifier", g_fCheckpointStamina[param1][1][1]);
                
                    OpenCheckpointsMenu(param1);
                    StopTimer(param1);
                }
                else
                {
                    CPrintToChat(param1, "{default}[{red}Trikz{default}] Checkpoint 2 does not exist.");
                    OpenCheckpointsMenu(param1);
                }
            }
            else
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] You must be alive to do this!");
            }
        }
        else if (StrEqual(info, "toggleang", true))
        {
            g_bSaveAngles[param1] = !g_bSaveAngles[param1];
            OpenCheckpointsMenu(param1);
        }
        else if (StrEqual(info, "togglevel", true))
        {
            g_bSaveVelocity[param1] = !g_bSaveVelocity[param1];
            OpenCheckpointsMenu(param1);
        }
        else if (StrEqual(info, "back", true))
        {
            OpenTrikzMenu(param1);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    return false;
}

void OpenCheckpointsMenu(int client)
{
    Handle menu = CreateMenu(Menu_Checkpoints, MENU_ACTIONS_DEFAULT);
    SetMenuTitle(menu, "Checkpoint Menu\n \n");
    char text[32];
    
    AddMenuItem(menu, "savecheck1", "Save Checkpoint 1");
    AddMenuItem(menu, "loadcheck1", "Load Checkpoint 1 \n ");
    AddMenuItem(menu, "savecheck2", "Save Checkpoint 2");
    AddMenuItem(menu, "loadcheck2", "Load Checkpoint 2 \n ");
    if (g_bSaveAngles[client])
    {
        text = "Restore Angles: Yes";
    }
    else
    {
        text = "Restore Angles: No";
    }
    AddMenuItem(menu, "toggleang", text);
    
    if (g_bSaveVelocity[client])
    {
        text = "Restore Velocity: Yes \n ";
    }
    else
    {
        text = "Restore Velocity: No \n ";
    }
    AddMenuItem(menu, "togglevel", text);
    AddMenuItem(menu, "back", "Back to Trikz Menu");
    
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    SetEventBroadcast(event, true);
    return Plugin_Handled;
}

public int Menu_AskTeleport(Handle menuask, MenuAction action, int param1, int param2)
{    
    switch(action)
    {
        case MenuAction_Select:
        {
            char info[32];
            GetMenuItem(menuask, param2, info, 32);
            
            int client = StringToInt(info);
            
            switch(param2)
            {
                case 0:
                {
                    if(IsValidClient(client, true) && IsValidClient(param1, true))
                    {
                        float fDestination[3];
                        GetEntPropVector(param1, Prop_Send, "m_vecOrigin", fDestination);
                        TeleportEntity(client, fDestination, NULL_VECTOR, view_as<float>({0.0,0.0,0.0}));
                        StopTimer(client);
                    }
                    
                    CPrintToChat(client, "{default}[{red}Trikz{default}] Teleport request accepted!");
                }
                
                case 1:
                {
                    CPrintToChat(client, "{default}[{red}Trikz{default}] Teleport request denied.");
                }
            }
        }
        
        case MenuAction_End:
        {
            CloseHandle(menuask);
        }
    }
    
    return 0;
}

void RequestTeleportToPlayer(int player, int ggoto)
{
    Handle menuask = CreateMenu(Menu_AskTeleport, MENU_ACTIONS_ALL);
    SetMenuTitle(menuask, "Teleport Request from %N:\n \n", player);

    char menuinfo[32];
                
    Format(menuinfo, 32, "%d", player);
    AddMenuItem(menuask, menuinfo, "Accept");
    AddMenuItem(menuask, menuinfo, "Deny");
                
    SetMenuExitButton(menuask, false);
                
    DisplayMenu(menuask, ggoto, 20);
}

public int Menu_TeleportToPlayer(Handle menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            int Time = GetTime();
            
            if(Time - g_LastUsedTp[param1] <= 10)
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] Please wait before requesting another teleport.");
                return 0;
            }
            
            g_LastUsedTp[param1] = Time;
            
            char info[32];
            
            GetMenuItem(menu, param2, info, 32);
            
            int client = StringToInt(info);
            
            if(IsValidClient(client, true) && IsValidClient(param1, true))
            {
                RequestTeleportToPlayer(param1, client);
            }
        }
        
        case MenuAction_Cancel:
        {
            if(param2 == MenuCancel_ExitBack)
            {
                OpenTrikzMenu(param1);
            }
            
        }
        
        case MenuAction_End:
        {
            CloseHandle(menu);
        }
    }
    
    return 0;
}

void OpenTeleportMenu(int client, bool submenu = false)
{
    Handle menu = CreateMenu(Menu_TeleportToPlayer, MENU_ACTIONS_ALL);
    SetMenuTitle(menu, "Request Teleport to Player:");
    
    int amount;
    
    char Display[MAX_NAME_LENGTH];
    char ClientID[8];
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(i == client)
        {
            continue;
        }
        
        if(IsValidClient(i, true) && !IsFakeClient(i) && !IsClientSourceTV(i))
        {
            Format(Display, MAX_NAME_LENGTH, "%N", i);
            Format(ClientID, 8, "%d", i);
            AddMenuItem(menu, ClientID, Display);
            
            amount++;
        }
    }
    
    if(submenu)
    {
        SetMenuExitBackButton(menu, true);
    }
    else
    {
        SetMenuExitButton(menu, true);
    }
    
    if(amount > 0)
    {
        DisplayMenu(menu, client, MENU_TIME_FOREVER);
    }
    else
    {
        CPrintToChat(client, "{default}[{red}Trikz{default}] No players to teleport to!");
        
        CloseHandle(menu);
    }
}

public Action SM_TpTo(int client, int args)
{
    if(AreClientCookiesCached(client))
    {
        if(!IsPlayerAlive(client))
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] You must be alive to use this command!");
            return Plugin_Handled;
        }
        
        if(args == 0)
        {
            OpenTeleportMenu(client,false);
            return Plugin_Handled;
        }
        else if(args > 1)
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] Usage: !tpto <player>");
            return Plugin_Handled;
        }
        
        char sTarget[32];
        int iTarget;
        
        GetCmdArg(1, sTarget, sizeof(sTarget));
        
        if ((iTarget = FindTarget(client, sTarget)) <= 0)
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] No target found.");
            return Plugin_Handled;
        }
        
        if(!IsPlayerAlive(iTarget))
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] Target is not alive!");
            return Plugin_Handled;
        }
        
        int Time = GetTime();
            
        if(Time - g_LastUsedTp[client] <= 10)
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] Please wait before requesting another teleport.");
            return Plugin_Handled;
        }
        
        g_LastUsedTp[client] = Time;
        
        CPrintToChat(client, "{default}[{red}Trikz{default}] Requesting a teleport to %N.", iTarget);
        
        RequestTeleportToPlayer(client, iTarget);
    }
    
    return Plugin_Handled;
}

public Action SM_Save(int client, int args)
{
    int cp = 0;
    if(args == 1)
    {
        char sInt[1];
        
        GetCmdArg(1, sInt, sizeof(sInt));
        cp = StringToInt(sInt) - 1;
        if(cp > 1)
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] Usage: !save <1|2>");
            return Plugin_Handled;
        }
    }
    else if(args > 1)
    {
        CPrintToChat(client, "{default}[{red}Trikz{default}] Usage: !save <1|2>");
        return Plugin_Handled;
    }
    
    if(IsPlayerAlive(client))
    {
        GetEntPropVector(client, Prop_Send, "m_vecOrigin", g_fCheckpoints[client][cp][0]);
        GetClientEyeAngles(client, g_fCheckpoints[client][cp][1]);
        GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", g_fCheckpoints[client][cp][2]);
        g_fCheckpointStamina[client][cp][0] = GetEntPropFloat(client, Prop_Send, "m_flStamina");
        g_fCheckpointStamina[client][cp][1] = GetEntPropFloat(client, Prop_Send, "m_flVelocityModifier");
        g_bSetCheckpoint[client][cp] = true;
        CPrintToChat(client, "{default}[{red}Trikz{default}] Checkpoint %d Saved.", cp + 1);
    }
    else
    {
        CPrintToChat(client, "{default}[{red}Trikz{default}] You must be alive to do this!");
    }
    
    return Plugin_Handled;
}

public Action SM_Tele(int client, int args)
{
    int cp = 0;
    if(args == 1)
    {
        char sInt[1];
        
        GetCmdArg(1, sInt, sizeof(sInt));
        cp = StringToInt(sInt) - 1;
        if(cp > 1)
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] Usage: !tele <1|2>");
            return Plugin_Handled;
        }
    }
    else if(args > 1)
    {
        CPrintToChat(client, "{default}[{red}Trikz{default}] Usage: !tele <1|2>");
        return Plugin_Handled;
    }

    if(IsPlayerAlive(client))
    {
        if(g_bSetCheckpoint[client][cp])
        {
            if(g_bSaveAngles[client] && g_bSaveVelocity[client])
            {
                TeleportEntity(client, g_fCheckpoints[client][cp][0], g_fCheckpoints[client][cp][1], g_fCheckpoints[client][cp][2]);
            }
            else if(g_bSaveVelocity[client])
            {
                TeleportEntity(client, g_fCheckpoints[client][cp][0], NULL_VECTOR, g_fCheckpoints[client][cp][2]);
            }
            else if(g_bSaveAngles[client])
            {
                TeleportEntity(client, g_fCheckpoints[client][cp][0], g_fCheckpoints[client][cp][1], view_as<float>({0.0,0.0,0.0}));
            }
            else
            {
                TeleportEntity(client, g_fCheckpoints[client][cp][0], NULL_VECTOR, view_as<float>({0.0,0.0,0.0}));
            }
            
            SetEntPropFloat(client, Prop_Send, "m_flStamina", g_fCheckpointStamina[client][cp][0]);
            SetEntPropFloat(client, Prop_Send, "m_flVelocityModifier", g_fCheckpointStamina[client][cp][1]);
            
            StopTimer(client);
        }
        else
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] Checkpoint %d does not exist.", cp + 1);
        }
    }
    else
    {
        CPrintToChat(client, "{default}[{red}Trikz{default}] You must be alive to do this!");
    }
    
    return Plugin_Handled;
}

public Action SM_Flash(int client, int args)
{
    if(GetClientFlashBangs(client) == 0)
        GiveFlash(client);
    
    return Plugin_Handled;
}
