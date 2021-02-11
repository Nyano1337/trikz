#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = 
{
    name = "[bTimes] Teams",
    author = ".george",
    description = "Trikz support and shit",
    version = VERSION,
    url = ""
}

#include <bTimes-teams>
#include <bTimes-timer>
#include <bTimes-zones>
#include <morecolors>
#include <sourcemod>
#include <sdktools>

#pragma newdecls required

int g_Partner[MAXPLAYERS + 1] = {0,...};
int g_LastUsed[MAXPLAYERS + 1];

Handle g_fwdOnTrikzNewPartner;
Handle g_fwdOnTrikzBreakup;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Natives
    CreateNative("Timer_GetPartner", Native_GetPartner);
    
    g_fwdOnTrikzNewPartner = CreateGlobalForward("OnTrikzNewPartner", ET_Event, Param_Cell, Param_Cell);
    g_fwdOnTrikzBreakup = CreateGlobalForward("OnTrikzBreakup", ET_Event, Param_Cell, Param_Cell);
    
    return APLRes_Success;
}

public void OnPluginStart()
{
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
    
    RegConsoleCmd("sm_partner", Command_Partner, "Request a Trikz Timer partner.");
    RegConsoleCmd("sm_breakup", Command_Breakup, "Break up your trikz team.");
    RegConsoleCmd("sm_unpartner", Command_Breakup, "Break up your trikz team.");
}

public void OnClientPutInServer(int client)
{
    g_LastUsed[client] = 0;
}

public int Native_GetPartner(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    if(0 < client <= MaxClients)
    {
        return g_Partner[client];
    }
    
    return 0;
}

public Action OnTimerStart_Pre(int client, int Type, int Style)
{
    if(Type != TIMER_SOLOBONUS)
    {
        if(g_Partner[client] == 0)
        {
            return Plugin_Handled;
        }
        
        if(Type == TIMER_MAIN)
        {
            if(Timer_InsideZone(client, MAIN_START) == -1)
            {
                return Plugin_Handled;
            }
            if(Timer_InsideZone(g_Partner[client], MAIN_START) == -1 && IsBeingTimed(g_Partner[client], TIMER_MAIN))
            {
                return Plugin_Handled;
            }
        }
        else if(Type == TIMER_BONUS)
        {
            if(Timer_InsideZone(client, BONUS_START) == -1)
            {
                return Plugin_Handled;
            }
            if(Timer_InsideZone(g_Partner[client], BONUS_START) == -1 && IsBeingTimed(g_Partner[client], TIMER_BONUS))
            {
                return Plugin_Handled;
            }
        }
    }
    return Plugin_Continue;
}


public void OnZoneEndTouch(int client, int Zone, int ZoneNumber)
{
    if((Zone == MAIN_START || Zone == BONUS_START))
    {
        if(g_Partner[client] == 0)
        {
            StopTimer(client);
        }
        
        if(!IsBeingTimed(g_Partner[client], TIMER_MAIN) && !IsBeingTimed(g_Partner[client], TIMER_BONUS))
        {
            StopTimer(client);
        }
    }
}

public void Event_PlayerDisconnect(Event event, char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (g_Partner[client])
    {
        if (IsValidEdict(g_Partner[client]))
        {
            CPrintToChat(g_Partner[client], "{default}[{red}Trikz{default}] Your team has been cancelled.");
        }
        
        Call_StartForward(g_fwdOnTrikzBreakup);
        Call_PushCell(client);
        Call_PushCell(g_Partner[client]);
        Call_Finish();
        
        StopTimer(g_Partner[client]);
        g_Partner[g_Partner[client]] = 0;
        g_Partner[client] = 0;
        StopTimer(client);
    }
}

void PartnerMenu(int client)
{
    Menu menu = new Menu(PartnerAsk_MenuHandler, MENU_ACTIONS_ALL);
    menu.SetTitle("Select A Partner", client);
    int amount;
    char Display[32];
    char ClientID[8];
    int i = 1;
    while (i <= MaxClients)
    {
        if (client != i)
        {
            if (IsValidClient(i) && !IsFakeClient(i) && IsPlayerAlive(i) && !IsClientSourceTV(i) && !g_Partner[i])
            {
                Format(Display, 32, "%N", i);
                Format(ClientID, 8, "%d", i);
                menu.AddItem(ClientID, Display, 0);
                amount++;
            }
        }
        i++;
    }
    menu.ExitButton = true;
    if (g_Partner[client])
    {
        CPrintToChat(client, "{default}[{red}Trikz{default}] You already have a partner, type !breakup to breakup.");
        delete menu;
    }
    else
    {
        if (0 < amount)
        {
            menu.Display(client, 0);
        }
        else
        {
            CPrintToChat(client, "{default}[{red}Trikz{default}] No Partners Available.");
            delete menu;
        }
    }
}

public int PartnerAsk_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            int Time = GetTime();
            if (Time - g_LastUsed[param1] <= 15.0)
            {
                CPrintToChat(param1, "{default}[{red}Trikz{default}] Please wait before inviting another person to play.");
                return;
            }
            g_LastUsed[param1] = Time;
            char info[32];
            menu.GetItem(param2, info, sizeof(info));
            int client = StringToInt(info, 10);

            if (IsValidClient(client) && IsValidClient(param1) && !g_Partner[client])
            {
                Menu menuask = new Menu(Partner_MenuHandler, MENU_ACTIONS_ALL);
                menuask.SetTitle("Partner with %N?", param1);
                char menuinfo[32];
                Format(menuinfo, 32, "%d", param1);
                menuask.AddItem(menuinfo, "Yes", 0);
                menuask.AddItem(menuinfo, "No", 0);
                menu.ExitButton = false;
                menuask.Display(client, 20);
            }
            else
            {
                if (g_Partner[param1])
                {
                    CPrintToChat(param1, "{default}[{red}Trikz{default}] You already have a partner.");
                }
            }
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
}

public int Partner_MenuHandler(Menu menuask, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[32];
            menuask.GetItem(param2, info, sizeof(info));
            int client = StringToInt(info, 10);
            switch (param2)
            {
                case 0:
                {
                    Call_StartForward(g_fwdOnTrikzNewPartner);
                    Call_PushCell(client);
                    Call_PushCell(param1);
                    Call_Finish();
                    
                    g_Partner[client] = param1;
                    g_Partner[param1] = client;
                    StopTimer(client);
                    StopTimer(param1);
                    CPrintToChat(param1, "{default}[{red}Trikz{default}] You are now partnered with %N.", client);
                    CPrintToChat(client, "{default}[{red}Trikz{default}] You are now partnered with %N.", param1);
                }
                case 1:
                {
                    CPrintToChat(client, "{default}[{red}Trikz{default}] %N has denied your partner request.", param1);
                }
            }
        }
        case MenuAction_End:
        {
            delete menuask;
        }
    }
}

public Action Command_Breakup(int client, int args)
{
    int other = g_Partner[client];
    if (!other)
    {
        CPrintToChat(client, "{default}[{red}Trikz{default}] You do not have a partner to breakup with.");
        return Plugin_Handled;
    }
    
    Call_StartForward(g_fwdOnTrikzBreakup);
    Call_PushCell(client);
    Call_PushCell(other);
    Call_Finish();
    
    g_Partner[other] = 0;
    StopTimer(other);
    g_Partner[client] = 0;
    StopTimer(client);
    CPrintToChat(client, "{default}[{red}Trikz{default}] Your team has been cancelled.");
    CPrintToChat(other, "{default}[{red}Trikz{default}] Your team has been cancelled.");
    return Plugin_Handled;
}

public Action Command_Partner(int client, int args)
{
    PartnerMenu(client);
    return Plugin_Handled;
}

bool IsValidClient(int client)
{
    if (!(0 < client < MaxClients) || !IsClientInGame(client))
    {
        return false;
    }
    return true;
}
