#pragma dynamic 131072
#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = 
{
    name = "[bTimes] Ranks",
    author = "blacky",
    description = "Controls server rankings",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sourcemod>
#include <sdkhooks>
#include <bTimes-ranks>
#include <bTimes-timer>
#include <bTimes-random>
#include <bTimes-zones>

#undef REQUIRE_PLUGIN
#include <scp>

#pragma newdecls required

#define CC_HASCC 1<<0
#define CC_MSGCOL 1<<1
#define CC_NAME 1<<2

enum
{
    GameType_CSS,
    GameType_CSGO
};

int g_GameType;

Database g_DB;
ArrayList g_MapList;

ArrayList g_hMapsDone[MAX_TYPES][MAX_STYLES],
    g_hMapsDoneresultsRef[MAX_TYPES][MAX_STYLES],
    g_hRecordListID[MAX_TYPES][MAX_STYLES],
    g_hRecordListCount[MAX_TYPES][MAX_STYLES];
    
int g_RecordCount[MAXPLAYERS + 1],
    g_iMVPs_offset;
bool g_bStatsLoaded;

ArrayList g_hRanksPlayerID[MAX_TYPES][MAX_STYLES],
    g_hRanksPoints[MAX_TYPES][MAX_STYLES],
    g_hRanksNames[MAX_TYPES][MAX_STYLES];

int g_Rank[MAXPLAYERS + 1][MAX_TYPES][MAX_STYLES],
    g_Points[MAXPLAYERS + 1][MAX_TYPES][MAX_STYLES];

char g_msg_start[128],
    g_msg_varcol[128],
    g_msg_textcol[128];

// Chat ranks
ArrayList g_hChatRanksRanges,
    g_hChatRanksNames;
    
// Custom chat
ArrayList g_hCustomSteams,
    g_hCustomNames,
    g_hCustomMessages,
    g_hCustomUse;

int g_ClientUseCustom[MAXPLAYERS + 1];
    
bool g_bNewMessage;
    
// Settings
ConVar g_hUseCustomChat,
    g_hUseChatRanks,
    g_hAllChat;
    
// Points recalculation
int g_RecalcTotal,
    g_RecalcProgress;

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
    
    // Cvars
    g_hUseCustomChat  = CreateConVar("timer_enablecc", "1", "Allows specific players to use custom chat. Enabled by !enablecc <steamid> command.", 0, true, 0.0, true, 1.0);
    g_hUseChatRanks   = CreateConVar("timer_chatranks", "1", "Allows players to use chat ranks specified in sourcemod/configs/timer/ranks.cfg", 0, true, 0.0, true, 1.0);
    g_hAllChat        = CreateConVar("timer_allchat", "1", "Enable's allchat", 0, true, 0.0, true, 1.0);
    
    AutoExecConfig(true, "ranks", "timer");
    
    // Commands
    RegConsoleCmdEx("sm_ccname", SM_ColoredName, "Change colored name.");
    RegConsoleCmdEx("sm_ccmsg", SM_ColoredMsg, "Change the color of your messages.");
    RegConsoleCmdEx("sm_cchelp", SM_Colorhelp, "For help on creating a custom name tag with colors and a color message.");
    
    RegConsoleCmdEx("sm_rankings", SM_Rankings, "Shows the chat ranking tags and the ranks required to get them.");
    RegConsoleCmdEx("sm_ranks", SM_Rankings, "Shows the chat ranking tags and the ranks required to get them.");
    RegConsoleCmdEx("sm_chatranks", SM_Rankings, "Shows the chat ranking tags and the ranks required to get them.");
    
    // Admin commands
    RegAdminCmd("sm_enablecc", SM_EnableCC, ADMFLAG_ROOT, "Enable custom chat for a specified SteamID.");
    RegAdminCmd("sm_disablecc", SM_DisableCC, ADMFLAG_ROOT, "Disable custom chat for a specified SteamID.");
    RegAdminCmd("sm_cclist", SM_CCList, ADMFLAG_CHEATS, "Shows a list of players with custom chat privileges.");
    RegAdminCmd("sm_recalcpts", SM_RecalcPts, ADMFLAG_CHEATS, "Recalculates all the points in the database.");
    
    // Admin
    RegAdminCmd("sm_reloadranks", SM_ReloadRanks, ADMFLAG_CHEATS, "Reloads chat ranks.");
    
    // Chat ranks
    g_hChatRanksRanges = new ArrayList(2);
    g_hChatRanksNames  = new ArrayList(ByteCountToCells(256));
    LoadChatRanks();
    
    // Custom chat ranks
    g_hCustomSteams      = new ArrayList(ByteCountToCells(32));
    g_hCustomNames       = new ArrayList(ByteCountToCells(128));
    g_hCustomMessages    = new ArrayList(ByteCountToCells(256));
    g_hCustomUse            = new ArrayList();
    
    // Makes FindTarget() work properly
    LoadTranslations("common.phrases");
    
    // Command listeners
    AddCommandListener(Command_Say, "say");
    
    g_iMVPs_offset = FindSendPropInfo("CCSPlayerResource", "m_iMVPs");
    
    g_MapList = new ArrayList(ByteCountToCells(64));
    ReadMapList(g_MapList);
    
    RegAdminCmd("sm_showcycle", SM_ShowCycle, ADMFLAG_GENERIC);
}

public Action SM_ShowCycle(int client, int args)
{
    int iSize = g_MapList.Length;
    
    if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
        ReplyToCommand(client, "[SM] See your console for the map cycle");
    
    char sMapName[64];
    for(int idx; idx < iSize; idx++)
    {
        g_MapList.GetString(idx, sMapName, sizeof(sMapName));
        PrintToConsole(client, sMapName);
    }
    
    return Plugin_Handled;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if(StrContains(classname, "_player_manager") != -1)
    {
        SDKHook(entity, SDKHook_ThinkPost, PlayerManager_OnThinkPost);
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("DB_UpdateRanks", Native_UpdateRanks);
    CreateNative("Timer_EnableCustomChat", Native_EnableCustomChat);
    CreateNative("Timer_DisableCustomChat", Native_DisableCustomChat);
    CreateNative("Timer_SteamIDHasCustomChat", Native_SteamIDHasCustomChat);
    CreateNative("Timer_OpenStatsMenu", Native_OpenStatsMenu);
    
    return APLRes_Success;
}

public void OnMapStart()
{    
    if(g_MapList != INVALID_HANDLE)
        delete g_MapList;
    
    g_MapList = new ArrayList(ByteCountToCells(64));
    ReadMapList(g_MapList);
    
    CreateTimer(1.0, UpdateDeaths, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientAuthorized(int client, const char[] auth)
{
    int idx = g_hCustomSteams.FindString(auth);
    if(idx != -1)
    {
        g_ClientUseCustom[client]  = g_hCustomUse.Get(idx);
    }
}

public bool OnClientConnect(int client)
{
    g_ClientUseCustom[client] = 0;
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            g_Rank[client][Type][Style]   = 0;
            g_Points[client][Type][Style] = 0;
            g_RecordCount[client]         = 0;
        }
    }
    
    return true;
}

public int OnPlayerIDLoaded(int client)
{
    SetClientRank(client);
    SetRecordCount(client);
}

public void OnMapTimesLoaded()
{
    DB_LoadStats();
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

public void OnStylesLoaded()
{
    RegConsoleCmdPerStyle("rank", SM_Rank, "Show your rank for {Type} timer on {Style} style.");
    RegConsoleCmdPerStyle("mapsleft", SM_Mapsleft, "Show maps left for {Type} timer on {Style} style.");
    RegConsoleCmdPerStyle("mapsdone", SM_Mapsdone, "Show maps done for {Type} timer on {Style} style.");
    RegConsoleCmdPerStyle("top", SM_Top, "Show list of top players for {Type} timer on {Style} style.");
    RegConsoleCmdPerStyle("topwr", SM_TopWorldRecord, "Show who has the most records for {Type} timer on {Style} style.");
    RegConsoleCmdPerStyle("stats", SM_Stats, "Shows a player's stats for {Type} timer on {Style} style.");
    
    for(int Type; Type < MAX_TYPES; Type++)
    {
        for(int Style; Style < MAX_STYLES; Style++)
        {
            g_hRanksPlayerID[Type][Style] = new ArrayList();
            g_hRanksPoints[Type][Style]   = new ArrayList();
            g_hRanksNames[Type][Style]    = new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
            
            g_hRecordListID[Type][Style]    = new ArrayList();
            g_hRecordListCount[Type][Style] = new ArrayList();
            
            g_hMapsDone[Type][Style]        = new ArrayList();
            g_hMapsDoneresultsRef[Type][Style] = new ArrayList();
        }
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

public Action Command_Say(int client, const char[] command, int argc)
{
    if(g_hAllChat.BoolValue)
    {
        g_bNewMessage = true;
    }
}

public Action OnChatMessage(int &author, Handle recipients, char[] name, char[] message)
{
    GetChatName(author, name, MAXLENGTH_NAME);
    GetChatMessage(author, message, MAXLENGTH_MESSAGE);
    
    if(g_bNewMessage == true)
    {
        if(GetMessageFlags() & CHATFLAGS_ALL && !IsPlayerAlive(author))
        {
            for(int client = 1; client <= MaxClients; client++)
            {
                if(IsClientConnected(client) && IsClientInGame(client) && IsPlayerAlive(client))
                {
                    PushArrayCell(recipients, client);
                }
            }
        }
        g_bNewMessage = false;
    }
    
    return Plugin_Changed;
}

void FormatTag(int client, char[] buffer, int maxlength)
{
    ReplaceString(buffer, maxlength, "{team}", "\x03", true);
    ReplaceString(buffer, maxlength, "^", "\x07", true);
    
    int rand[3];
    char sRandHex[15];
    while(StrContains(buffer, "{rand}", true) != -1)
    {
        for(int i=0; i<3; i++)
            rand[i] = GetRandomInt(0, 255);
        
        FormatEx(sRandHex, sizeof(sRandHex), "\x07%02X%02X%02X", rand[0], rand[1], rand[2]);
        ReplaceStringEx(buffer, maxlength, "{rand}", sRandHex);
    }
    
    ReplaceString(buffer, maxlength, "{norm}", "\x01", true);
    
    if(0 < client <= MaxClients)
    {
        char sName[MAX_NAME_LENGTH];
        GetClientName(client, sName, sizeof(sName));
        ReplaceString(buffer, maxlength, "{name}", sName, true);
    }
}

void GetChatName(int client, char[] buffer, int maxlength)
{    
    if((g_ClientUseCustom[client] & CC_HASCC) && (g_ClientUseCustom[client] & CC_NAME) && g_hUseCustomChat.BoolValue)
    {
        char sAuth[32];
        GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
        
        int idx = g_hCustomSteams.FindString(sAuth);
        if(idx != -1)
        {
            g_hCustomNames.GetString(idx, buffer, maxlength);
            FormatTag(client, buffer, maxlength);
        }
    }
    else if(g_hUseChatRanks.BoolValue)
    {
        int iSize = g_hChatRanksRanges.Length;
        for(int i=0; i<iSize; i++)
        {
            if(g_hChatRanksRanges.Get(i, 0) <= g_Rank[client][TIMER_MAIN][0] <= g_hChatRanksRanges.Get(i, 1))
            {
                g_hChatRanksNames.GetString(i, buffer, maxlength);
                FormatTag(client, buffer, maxlength);
                return;
            }
        }
    }
}

void GetChatMessage(int client, char[] message, int maxlength)
{
    if((g_ClientUseCustom[client] & CC_HASCC) && (g_ClientUseCustom[client] & CC_MSGCOL) && g_hUseCustomChat.BoolValue)
    {
        char sAuth[32];
        GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
        
        int idx = g_hCustomSteams.FindString(sAuth);
        if(idx != -1)
        {
            char buffer[MAXLENGTH_MESSAGE];
            g_hCustomMessages.GetString(idx, buffer, MAXLENGTH_MESSAGE);
            FormatTag(client, buffer, maxlength);
            Format(message, maxlength, "%s%s", buffer, message);
        }
    }
}

public Action SM_RecalcPts(int client, int args)
{
    Menu menu = new Menu(Menu_RecalcPts);
    
    menu.SetTitle("Recalculating the points takes a while.\nAre you sure you want to do this?");
    
    menu.AddItem("y", "Yes");
    menu.AddItem("n", "No");
    
    menu.Display(client, MENU_TIME_FOREVER);
    
    return Plugin_Handled;
}

public int Menu_RecalcPts(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        
        if(info[0] == 'y')
        {
            RecalcPoints(param1);
        }
    }
    else if(action == MenuAction_End)
        delete menu;
}

void RecalcPoints(int client)
{
    PrintColorTextAll("%s%sRecalculating the ranks, see console for progress.",
        g_msg_start,
        g_msg_textcol);
    
    char query[128];
    FormatEx(query, sizeof(query), "SELECT MapName, MapID FROM maps");
    
    g_DB.Query(RecalcPoints_Callback, query, client);
}

public void RecalcPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results != INVALID_HANDLE)
    {
        int rows = results.RowCount;
        char sMapName[64];
        char query[128];
        
        g_RecalcTotal    = rows * 4;
        g_RecalcProgress = 0;
        
        for(int i = 0; i < rows; i++)
        {
            results.FetchRow();
            
            results.FetchString(0, sMapName, sizeof(sMapName));
            
            if(g_MapList.FindString(sMapName) != -1)
            {
                int TotalStyles = Style_GetTotal();
                
                for(int Type = 0; Type < MAX_TYPES; Type++)
                {
                    for(int Style = 0; Style < TotalStyles; Style++)
                    {
                        if(Style_IsEnabled(Style) && Style_IsTypeAllowed(Style, Type))
                        {
                            UpdateRanks(sMapName, Type, Style, true);
                        }
                    }
                }
            }
            else
            {
                FormatEx(query, sizeof(query), "UPDATE times SET Points = 0 WHERE MapID = %d",
                    results.FetchInt(1));
                    
                DataPack pack = new DataPack();
                pack.WriteString(sMapName);
                    
                g_DB.Query(RecalcPoints_Callback2, query, pack);
            }
        }
    }
    else
    {
        LogError(error);
    }
}

public void RecalcPoints_Callback2(Database db, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        
        char sMapName[64];
        data.ReadString(sMapName, sizeof(sMapName));
        
        g_RecalcProgress += 4;
        
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientInGame(client))
            {
                if(!IsFakeClient(client))
                {
                    PrintToConsole(client, "[%.1f%%] %s's points deleted.",
                        float(g_RecalcProgress)/float(g_RecalcTotal) * 100.0,
                        sMapName);
                }
            }
        }
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

public Action SM_Rank(int client, int args)
{
    int Type, Style;
    if(GetTypeStyleFromCommand("rank", Type, Style))
    {
        if(!IsSpamming(client))
        {
            SetIsSpamming(client, 1.0);
            if(args == 0)
            {
                DB_ShowRank(client, client, Type, Style);
            }
            else
            {
                char targetName[128];
                GetCmdArgString(targetName, sizeof(targetName));
                int target = FindTarget(client, targetName, true, false);
                if(target != -1)
                    DB_ShowRank(client, target, Type, Style);
            }
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Top(int client, int args)
{
    int Type, Style;
    if(GetTypeStyleFromCommand("top", Type, Style))
    {
        if(!IsSpamming(client))
        {
            SetIsSpamming(client, 1.0);
            
            DB_ShowTopAllSpec(client, Type, Style);
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Mapsleft(int client, int args)
{
    int Type, Style;
    if(GetTypeStyleFromCommand("mapsleft", Type, Style))
    {
        if(!IsSpamming(client))
        {
            SetIsSpamming(client, 1.0);
            
            if(args == 0)
            {
                DB_ShowMapsleft(client, client, Type, Style);
            }
            else
            {
                char targetName[128];
                GetCmdArgString(targetName, sizeof(targetName));
                int target = FindTarget(client, targetName, true, false);
                if(target != -1)
                    DB_ShowMapsleft(client, target, Type, Style);
            }
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Mapsdone(int client, int args)
{
    int Type, Style;
    if(GetTypeStyleFromCommand("mapsdone", Type, Style))
    {
        if(!IsSpamming(client))
        {
            SetIsSpamming(client, 1.0);
            
            int PlayerID;
            if(args == 0)
            {
                PlayerID = GetPlayerID(client);
                
                if(PlayerID != 0)
                {
                    DB_ShowMapsdone(client, PlayerID, Type, Style);
                }
                else
                {
                    PrintColorText(client, "%s%sYou have not been authorized by the timer yet.",
                        g_msg_start,
                        g_msg_textcol);
                }
            }
            else
            {
                char targetName[128];
                GetCmdArgString(targetName, sizeof(targetName));
                int target = FindTarget(client, targetName, true, false);
                if(target != -1)
                {
                    PlayerID = GetPlayerID(target);
                    
                    if(PlayerID != 0)
                    {
                        DB_ShowMapsdone(client, PlayerID, Type, Style);
                    }
                    else
                    {
                        PrintColorText(client, "%s%s%N%s has not been authorized by the timer yet.",
                            g_msg_start,
                            g_msg_varcol,
                            target,
                            g_msg_textcol);
                    }
                }
            }
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Stats(int client, int args)
{
    int Type, Style;
    if(GetTypeStyleFromCommand("stats", Type, Style))
    {
        if(!IsSpamming(client))
        {
            SetIsSpamming(client, 1.0);
            
            int PlayerID;
            
            if(args == 0)
            {
                PlayerID = GetPlayerID(client);
                
                if(PlayerID != 0)
                {
                    OpenStatsMenu(client, PlayerID, Type, Style);
                }
                else
                {
                    PrintColorText(client, "%s%sYou have not been authorized by the timer yet.",
                        g_msg_start,
                        g_msg_textcol);
                }
            }
            else
            {
                char targetName[128];
                GetCmdArgString(targetName, sizeof(targetName));
                int target = FindTarget(client, targetName, true, false);
                if(target != -1)
                {
                    PlayerID = GetPlayerID(target);
                    
                    if(PlayerID != 0)
                    {
                        OpenStatsMenu(client, PlayerID, Type, Style);
                    }
                    else
                    {
                        PrintColorText(client, "%s%s%N%s has not been authorized by the timer yet.",
                            g_msg_start,
                            g_msg_varcol,
                            target,
                            g_msg_textcol);
                    }
                }
            }
        }
    }
    
    return Plugin_Handled;
}

void OpenStatsMenu(int client, int PlayerID, int Type, int Style)
{
    int Rank = g_hRanksPlayerID[Type][Style].FindValue(PlayerID);
    if(Rank != -1)
    {
        Rank++;
        Menu menu = new Menu(Menu_Stats);
        
        char sName[MAX_NAME_LENGTH];
        char sAuth[32];
        char sType[32];
        char sStyle[32];
        GetNameFromPlayerID(PlayerID, sName, sizeof(sName));
        GetSteamIDFromPlayerID(PlayerID, sAuth, sizeof(sAuth));
        GetTypeName(Type, sType, sizeof(sType));
        GetStyleName(Style, sStyle, sizeof(sStyle));
        
        menu.SetTitle("Stats for %s (%s)\n--------------------------------\n", sName, sAuth);
        
        // Get Record count
        int RecordCount;
        int idx = g_hRecordListID[Type][Style].FindValue(PlayerID);
        if(idx != -1)
        {
            RecordCount = g_hRecordListCount[Type][Style].Get(idx);
        }
        
        // Get maps done
        ArrayList hCell = g_hMapsDone[Type][Style].Get(PlayerID);
        
        int MapsDone;
        if(hCell != INVALID_HANDLE)
            MapsDone = hCell.Length;
        
        int TotalMaps;
        if(Type == TIMER_MAIN)
            TotalMaps = GetTotalZonesAllMaps(MAIN_START);
        else if(Type == TIMER_SOLOBONUS)
            TotalMaps = GetTotalZonesAllMaps(SOLOBONUS_START);
        else
            TotalMaps = GetTotalZonesAllMaps(BONUS_START);
            
        float fCompletion = float(MapsDone) / float(TotalMaps) * 100.0;
        
        // Get rank info
        int TotalRanks = g_hRanksPlayerID[Type][Style].Length;
        float fPoints = g_hRanksPoints[Type][Style].Get(Rank - 1);
        
        char sDisplay[256];
        FormatEx(sDisplay, sizeof(sDisplay), "%s [%s]\nWorld Records: %d\n \nMaps done: %d / %d (%.1f%%)\n \nRank: %d / %d (%d Pts.)\n--------------------------------",
            sType,
            sStyle,
            RecordCount,
            MapsDone,
            TotalMaps,
            fCompletion,
            Rank,
            TotalRanks,
            RoundToFloor(fPoints));
        
        char sInfo[32];
        FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", PlayerID, Type, Style);
        menu.AddItem(sInfo, sDisplay);
        
        for(int lType; lType < MAX_TYPES; lType++)
        {
            GetTypeName(lType, sType, sizeof(sType));
            for(int lStyle; lStyle < MAX_STYLES; lStyle++)
            {
                if(lType == Type && lStyle == Style)
                    continue;
                
                if(Style_IsEnabled(lStyle) && Style_IsTypeAllowed(lStyle, lType))
                {
                    GetStyleName(lStyle, sStyle, sizeof(sStyle));
                    
                    FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", PlayerID, lType, lStyle);
                    FormatEx(sDisplay, sizeof(sDisplay), "%s [%s]", sType, sStyle);
                    
                    menu.AddItem(sInfo, sDisplay);
                }
            }
        }
        
        menu.Display(client, MENU_TIME_FOREVER);
    }
    else
    {
        if(g_bStatsLoaded == false)
        {
            PrintColorText(client, "%s%sThe stats have not been loaded yet.",
                g_msg_start,
                g_msg_textcol);
        }
        else
        {
            char sType[32];
            char sStyle[32];
            GetTypeName(Type, sType, sizeof(sType));
            GetStyleName(Style, sStyle, sizeof(sStyle));
            
            char slType[32];
            char slStyle[32];
            for(int lType; lType < MAX_TYPES; lType++)
            {
                GetTypeName(lType, slType, sizeof(slType));
                
                for(int lStyle; lStyle < MAX_STYLES; lStyle++)
                {
                    if(Style_IsEnabled(lStyle) && Style_IsTypeAllowed(lStyle, lType))
                    {
                        GetStyleName(lStyle, slStyle, sizeof(slStyle));
                        
                        if((Rank = g_hRanksPlayerID[lType][lStyle].FindValue(PlayerID)) != -1)
                        {
                            PrintColorText(client, "%s%sCouldn't find stats for [%s%s%s] - [%s%s%s], showing stats for [%s%s%s] - [%s%s%s] instead.",
                                g_msg_start,
                                g_msg_textcol,
                                g_msg_varcol,
                                sType,
                                g_msg_textcol,
                                g_msg_varcol,
                                sStyle,
                                g_msg_textcol,
                                g_msg_varcol,
                                slType,
                                g_msg_textcol,
                                g_msg_varcol,
                                slStyle,
                                g_msg_textcol);
                            
                            OpenStatsMenu(client, PlayerID, lType, lStyle);
                            return;
                        }
                    }
                }
            }
            
            PrintColorText(client, "%s%sThe player you specified is unranked.",
                g_msg_start,
                g_msg_textcol);
        }
    }
}

public int Menu_Stats(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        char sInfoExploded[3][16];
        ExplodeString(info, ";", sInfoExploded, sizeof(sInfoExploded), sizeof(sInfoExploded[]));
        
        OpenStatsMenu(param1, StringToInt(sInfoExploded[0]), StringToInt(sInfoExploded[1]), StringToInt(sInfoExploded[2]));
    }
    else if (action == MenuAction_End)
        delete menu;
}

public int Native_OpenStatsMenu(Handle plugin, int numParams)
{
    OpenStatsMenu(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), GetNativeCell(4));
}

public Action SM_TopWorldRecord(int client, int args)
{
    int Type, Style;
    
    if(GetTypeStyleFromCommand("topwr", Type, Style))
    {
        char sType[32];
        GetTypeName(Type, sType, sizeof(sType));
        
        char sStyle[32];
        GetStyleName(Style, sStyle, sizeof(sStyle));
        
        int iSize = g_hRecordListID[Type][Style].Length;
        if(iSize > 0)
        {
            Menu menu = new Menu(Menu_RecordCount);
            menu.SetTitle("World Record Count [%s] - [%s]", sType, sStyle);
            
            int PlayerID, RecordCount;
            char sInfo[32];
            char sDisplay[64];
            char sName[MAX_NAME_LENGTH];
            for(int idx; idx < iSize; idx++)
            {
                PlayerID    = g_hRecordListID[Type][Style].Get(idx);
                RecordCount = g_hRecordListCount[Type][Style].Get(idx);
                
                FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", PlayerID, Type, Style);
                
                GetNameFromPlayerID(PlayerID, sName, sizeof(sName));
                FormatEx(sDisplay, sizeof(sDisplay), "#%d: %s (%d)", idx + 1, sName, RecordCount);
                
                menu.AddItem(sInfo, sDisplay);
            }
            
            menu.Display(client, MENU_TIME_FOREVER);
        }
        else
        {
            PrintColorText(client, "%s%s[%s%s%s] - [%s%s%s] There are no world records on any map.",
                g_msg_start,
                g_msg_textcol,
                g_msg_varcol,
                sType,
                g_msg_textcol,
                g_msg_varcol,
                sStyle,
                g_msg_textcol);
        }
    }
    
    return Plugin_Handled;
}

public int Menu_RecordCount(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));
        
        char sInfoExploded[3][16];
        ExplodeString(sInfo, ";", sInfoExploded, sizeof(sInfoExploded), sizeof(sInfoExploded[]));
        
        OpenStatsMenu(param1, StringToInt(sInfoExploded[0]), StringToInt(sInfoExploded[1]), StringToInt(sInfoExploded[2]));
    }
    else if(action == MenuAction_End)
        delete menu;
}

public Action SM_ColoredName(int client, int args)
{    
    if(!IsSpamming(client))
    {
        SetIsSpamming(client, 1.0);
        
        if(g_ClientUseCustom[client] & CC_HASCC)
        {
            char query[512];
            char sAuth[32];
            GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
            
            if(args == 0)
            {
                // Get new ccname setting
                g_ClientUseCustom[client] ^= CC_NAME;
                
                // Acknowledge change to client
                if(g_ClientUseCustom[client] & CC_NAME)
                {
                    PrintColorText(client, "%s%sColored name enabled.",
                        g_msg_start,
                        g_msg_textcol);
                }
                else
                {
                    PrintColorText(client, "%s%sColored name disabled.",
                        g_msg_start,
                        g_msg_textcol);
                }
                
                // Set the new ccname setting
                int idx = g_hCustomSteams.FindString(sAuth);
                
                if(idx != -1)
                    g_hCustomUse.Set(idx, g_ClientUseCustom[client]);
                
                // Format the query
                FormatEx(query, sizeof(query), "UPDATE players SET ccuse=%d WHERE SteamID='%s'",
                    g_ClientUseCustom[client],
                    sAuth);
            }
            else
            {
                // Get new ccname
                char sArg[250];
                GetCmdArgString(sArg, sizeof(sArg));
                char[] sEscapeArg = new char[(strlen(sArg)*2)+1];
                
                // Escape the ccname for SQL insertion
                SQL_LockDatabase(g_DB);
                g_DB.Escape(sArg, sEscapeArg, (strlen(sArg)*2)+1);
                SQL_UnlockDatabase(g_DB);
                
                // Modify player's ccname
                int idx = g_hCustomSteams.FindString(sAuth);
                
                if(idx != -1)
                    g_hCustomNames.SetString(idx, sEscapeArg);
                
                // Prepare query
                FormatEx(query, sizeof(query), "UPDATE players SET ccname='%s' WHERE SteamID='%s'",
                    sEscapeArg,
                    sAuth);
                    
                PrintColorText(client, "%s%sColored name set to %s%s",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol,
                    sArg);
            }
            
            // Execute query
            g_DB.Query(ColoredName_Callback, query);
        }
    }
    return Plugin_Handled;
}

public void ColoredName_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == INVALID_HANDLE)
    {
        LogError(error);
    }
}

public Action SM_ColoredMsg(int client, int args)
{    
    if(!IsSpamming(client))
    {
        SetIsSpamming(client, 1.0);
        if(g_ClientUseCustom[client] & CC_HASCC)
        {
            char query[512];
            char sAuth[32];
            GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
            
            if(args == 0)
            {
                g_ClientUseCustom[client] ^= CC_MSGCOL;
                
                int idx = g_hCustomSteams.FindString(sAuth);
                
                if(idx != -1)
                    g_hCustomUse.Set(idx, g_ClientUseCustom[client]);
                
                FormatEx(query, sizeof(query), "UPDATE players SET ccuse=%d WHERE SteamID='%s'",
                    g_ClientUseCustom[client],
                    sAuth);
                    
                if(g_ClientUseCustom[client] & CC_MSGCOL)
                    PrintColorText(client, "%s%sColored message enabled.",
                        g_msg_start,
                        g_msg_textcol);
                else
                    PrintColorText(client, "%s%sColored message disabled.",
                        g_msg_start,
                        g_msg_textcol);
            }
            else
            {
                char sArg[128];
                GetCmdArgString(sArg, sizeof(sArg));
                char[] sEscapeArg = new char[(strlen(sArg)*2)+1];
                
                SQL_LockDatabase(g_DB);
                g_DB.Escape(sArg, sEscapeArg, (strlen(sArg)*2)+1);
                SQL_UnlockDatabase(g_DB);
                    
                int idx = g_hCustomSteams.FindString(sAuth);
                
                if(idx != -1)
                    g_hCustomMessages.SetString(idx, sEscapeArg);
                
                FormatEx(query, sizeof(query), "UPDATE players SET ccmsgcol='%s' WHERE SteamID='%s'",
                    sEscapeArg,
                    sAuth);
                    
                PrintColorText(client, "%s%sColored message set to %s%s",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol,
                    sArg);
            }
            
            // Execute query
            g_DB.Query(ColoredName_Callback, query);
        }
    }
    
    return Plugin_Handled;
}

public Action SM_Colorhelp(int client, int args)
{
    if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
    {
        PrintColorText(client, "%s%sLook in console for help with custom color chat.",
            g_msg_start,
            g_msg_textcol);
    }
    
    PrintToConsole(client, "\nsm_ccname <arg> to set your name.");
    PrintToConsole(client, "sm_ccname without an argument to turn colored name off.\n");
    
    PrintToConsole(client, "sm_ccmsg <arg> to set your message.");
    PrintToConsole(client, "sm_ccmsg without an argument to turn colored message off.\n");
    
    PrintToConsole(client, "Custom chat functions:");
    PrintToConsole(client, "'^' followed by a hexadecimal code to use any custom color.");
    PrintToConsole(client, "{name} will be replaced with your steam name.");
    PrintToConsole(client, "{team} will be replaced with your team color.");
    PrintToConsole(client, "{rand} will be replaced with a random color.");
    PrintToConsole(client, "{norm} will be replaced with normal chat-yellow color.\n");
    
    return Plugin_Handled;
}

public Action SM_ReloadRanks(int client, int args)
{
    LoadChatRanks();
    
    PrintColorText(client, "%s%sChat ranks reloaded.",
        g_msg_start,
        g_msg_textcol);
    
    return Plugin_Handled;
}

public Action SM_EnableCC(int client, int args)
{
    char sArg[256];
    GetCmdArgString(sArg, sizeof(sArg));
    
    if(StrContains(sArg, "STEAM_0:") != -1)
    {
        char query[256];
        FormatEx(query, sizeof(query), "SELECT User, ccuse FROM players WHERE SteamID='%s'",
            sArg);
            
        DataPack pack = new DataPack();
        pack.WriteCell(client);
        pack.WriteString(sArg);
            
        g_DB.Query(EnableCC_Callback1, query, pack);
    }
    else
    {
        ReplyToCommand(client, "sm_enablecc example: \"sm_enablecc STEAM_0:1:12345\"",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public void EnableCC_Callback1(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    
    if(results != INVALID_HANDLE)
    {
        pack.Reset();
        int client = pack.ReadCell();
        
        char sAuth[32];
        pack.ReadString(sAuth, sizeof(sAuth));
        
        if(results.RowCount > 0)
        {
            results.FetchRow();
            
            char sName[MAX_NAME_LENGTH];
            results.FetchString(0, sName, sizeof(sName));
            
            int ccuse = results.FetchInt(1);
            
            if(!(ccuse & CC_HASCC))
            {
                PrintColorText(client, "%s%sA player with the name '%s%s%s' <%s%s%s> will be given custom chat privileges.",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol,
                    sName,
                    g_msg_textcol,
                    g_msg_varcol,
                    sAuth,
                    g_msg_textcol);
                
                EnableCustomChat(sAuth);
            }
            else
            {
                PrintColorText(client, "%s%sA player with the given SteamID '%s%s%s' (name '%s%s%s') already has custom chat privileges.",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol,
                    sAuth,
                    g_msg_textcol,
                    g_msg_varcol,
                    sName,
                    g_msg_textcol);
            }
        }
        else
        {
            PrintColorText(client, "%s%sNo player in the database found with '%s%s%s' as their SteamID.",
                g_msg_start,
                g_msg_textcol,
                g_msg_varcol,
                sAuth,
                g_msg_textcol);
        }
    }
    else
    {
        LogError(error);
    }
    
    delete pack;
}

void EnableCustomChat(const char[] sAuth)
{
    if(g_hCustomSteams.FindString(sAuth) != -1)
    {
        ThrowError("SteamID <%s> already has custom chat privileges.", sAuth);
    }
    
    // Check and enable cc for any clients in the game
    char sAuth2[32];
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            GetClientAuthId(client, AuthId_Steam2, sAuth2, sizeof(sAuth2));
            if(StrEqual(sAuth, sAuth2))
            {
                g_ClientUseCustom[client]  = CC_HASCC|CC_MSGCOL|CC_NAME;
                
                PrintColorText(client, "%s%sYou have been given custom chat privileges. Type sm_cchelp or ask for help to learn how to use it.",
                    g_msg_start,
                    g_msg_textcol);
                    
                break;
            }
        }
    }
    
    char query[512];
    FormatEx(query, sizeof(query), "UPDATE players SET ccuse=%d, ccname='{rand}{name}', ccmsgcol='^FFFFFF' WHERE SteamID='%s'",
        CC_HASCC|CC_MSGCOL|CC_NAME,
        sAuth);
    g_DB.Query(EnableCC_Callback, query);
    
    g_hCustomSteams.PushString(sAuth);
    g_hCustomNames.PushString("{rand}{name}");
    g_hCustomMessages.PushString("^FFFFFF");
    g_hCustomUse.Push(CC_HASCC|CC_MSGCOL|CC_NAME);
}

public void EnableCC_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == INVALID_HANDLE)
    {
        LogError(error);
    }
}

public Action SM_DisableCC(int client, int args)
{
    char sArg[256];
    GetCmdArgString(sArg, sizeof(sArg));
    
    if(StrContains(sArg, "STEAM_0:") != -1)
    {
        char query[256];
        FormatEx(query, sizeof(query), "SELECT User, ccuse FROM players WHERE SteamID='%s'",
            sArg);
            
        DataPack pack = new DataPack();
        pack.WriteCell(client);
        pack.WriteString(sArg);
            
        g_DB.Query(DisableCC_Callback1, query, pack);
    }
    else
    {
        PrintColorText(client, "%s%ssm_disablecc example: \"sm_disablecc STEAM_0:1:12345\"",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public void DisableCC_Callback1(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    
    if(results != INVALID_HANDLE)
    {
        pack.Reset();
        int client = pack.ReadCell();
        
        char sAuth[32];
        pack.ReadString(sAuth, sizeof(sAuth));
        
        if(results.RowCount > 0)
        {
            results.FetchRow();
            
            char sName[MAX_NAME_LENGTH];
            results.FetchString(0, sName, sizeof(sName));
            
            int ccuse = results.FetchInt(1);
            
            if(ccuse & CC_HASCC)
            {
                PrintColorText(client, "%s%sA player with the name '%s%s%s' <%s%s%s> will have their custom chat privileges removed.",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol,
                    sName,
                    g_msg_textcol,
                    g_msg_varcol,
                    sAuth,
                    g_msg_textcol);
                
                DisableCustomChat(sAuth);
            }
            else
            {
                PrintColorText(client, "%s%sA player with the given SteamID '%s%s%s' (name '%s%s%s') doesn't have custom chat privileges to remove.",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol,
                    sAuth,
                    g_msg_textcol,
                    g_msg_varcol,
                    sName,
                    g_msg_textcol);
            }
        }
        else
        {
            PrintColorText(client, "%s%sNo player in the database found with '%s%s%s' as their SteamID.",
                g_msg_start,
                g_msg_textcol,
                g_msg_varcol,
                sAuth,
                g_msg_textcol);
        }
    }
    else
    {
        LogError(error);
    }
}

void DisableCustomChat(const char[] sAuth)
{
    int idx = g_hCustomSteams.FindString(sAuth);    
    if(idx != -1)
    {
        g_hCustomSteams.Erase(idx);
        g_hCustomNames.Erase(idx);
        g_hCustomMessages.Erase(idx);
        g_hCustomUse.Erase(idx);
        
        char query[512];
        FormatEx(query, sizeof(query), "UPDATE players SET ccuse=0 WHERE SteamID='%s'",
            sAuth);
        g_DB.Query(DisableCC_Callback, query);
    }
    
    // Check and disable cc for any clients in the game
    char sAuth2[32];
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            GetClientAuthId(client, AuthId_Steam2, sAuth2, sizeof(sAuth2));
            if(StrEqual(sAuth, sAuth2))
            {
                g_ClientUseCustom[client]  = 0;
                
                PrintColorText(client, "%s%sYou have lost your custom chat privileges.",
                    g_msg_start,
                    g_msg_textcol);
            }
        }
    }
}

public void DisableCC_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == INVALID_HANDLE)
    {
        LogError(error);
    }
}

public Action SM_CCList(int client, int args)
{
    if(!IsSpamming(client))
    {
        SetIsSpamming(client, 1.0);
        
        char query[512];
        FormatEx(query, sizeof(query), "SELECT SteamID, User, ccname, ccmsgcol, ccuse FROM players WHERE ccuse != 0");
        g_DB.Query(CCList_Callback, query, client);
    }
    
    return Plugin_Handled;
}

public void CCList_Callback(Database db, DBResultSet results, const char[] error, any client)
{
    if(results != INVALID_HANDLE)
    {
        Menu menu = new Menu(Menu_CCList);
        menu.SetTitle("Players with custom chat privileges");
        
        char sAuth[32], sName[MAX_NAME_LENGTH], sCCName[128], sCCMsg[256], info[512], display[70];
        
        int ccuse;
        
        int rows = results.RowCount;
        for(int i=0; i<rows; i++)
        {
            results.FetchRow();
            
            results.FetchString(0, sAuth, sizeof(sAuth));
            results.FetchString(1, sName, sizeof(sName));
            results.FetchString(2, sCCName, sizeof(sCCName));
            results.FetchString(3, sCCMsg, sizeof(sCCMsg));
            ccuse = results.FetchInt(4);
            
            FormatEx(info, sizeof(info), "%s%%%s%%%s%%%s%%%d",
                sAuth, 
                sName,
                sCCName,
                sCCMsg,
                ccuse);
                
            FormatEx(display, sizeof(display), "<%s> - %s",
                sAuth,
                sName);
                
            menu.AddItem(info, display);
        }
        
        menu.ExitButton = true;
        menu.Display(client, MENU_TIME_FOREVER);
        
    }
    else
    {
        LogError(error);
    }
}

public int Menu_CCList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[512];
        menu.GetItem(param2, info, sizeof(info));
        
        char expInfo[5][256];
        ExplodeString(info, "\%", expInfo, 5, 256);
        ReplaceString(expInfo[2], 256, "{name}", expInfo[1]);
        ReplaceString(expInfo[2], 256, "{team}", "\x03");
        ReplaceString(expInfo[2], 256, "^", "\x07");

        ReplaceString(expInfo[3], 256, "^", "\x07");
        
        PrintColorText(param1, "%sSteamID          : %s%s", g_msg_textcol, g_msg_varcol, expInfo[0]);
        PrintColorText(param1, "%sName               : %s%s", g_msg_textcol, g_msg_varcol, expInfo[1]);
        PrintColorText(param1, "%sCCName          : %s%s", g_msg_textcol, g_msg_varcol, expInfo[2]);
        PrintColorText(param1, "%sCCMessage      : %s%sExample text", g_msg_textcol, g_msg_varcol, expInfo[3]);
        
        int ccuse = StringToInt(expInfo[4]);
        PrintColorText(param1, "%sUses CC Name: %s%s", g_msg_textcol, g_msg_varcol, (ccuse & CC_NAME)?"Yes":"No");
        PrintColorText(param1, "%sUses CC Msg   : %s%s", g_msg_textcol, g_msg_varcol, (ccuse & CC_MSGCOL)?"Yes":"No");
    }
    else if (action == MenuAction_End)
        delete menu;
}

public Action SM_Rankings(int client, int args)
{
    int iSize = g_hChatRanksNames.Length;
    
    char sChatRank[MAXLENGTH_NAME];
    
    for(int i=0; i<iSize; i++)
    {
        g_hChatRanksNames.GetString(i, sChatRank, MAXLENGTH_NAME);
        FormatTag(client, sChatRank, MAXLENGTH_NAME);
        
        PrintColorText(client, "%s%5d %s-%s %5d%s: %s",
            g_msg_varcol,
            g_hChatRanksRanges.Get(i, 0),
            g_msg_textcol,
            g_msg_varcol,
            g_hChatRanksRanges.Get(i, 1),
            g_msg_textcol,
            sChatRank);
    }
    
    return Plugin_Handled;
}

public Action UpdateDeaths(Handle timer, any data)
{
    for(int client=1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            if(IsPlayerAlive(client))
            {
                if(IsFakeClient(client))
                {
                    SetEntProp(client, Prop_Data, "m_iDeaths", 0);
                }
                else
                {
                    SetEntProp(client, Prop_Data, "m_iDeaths", g_Rank[client][TIMER_MAIN][0]);
                }
            }
        }
    }
}

void LoadChatRanks()
{
    // Check if timer config path exists
    char sPath[PLATFORM_MAX_PATH];
    
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/timer");
    if(!DirExists(sPath))
    {
        CreateDirectory(sPath, 511);
    }
    
    // If it doesn't exist, create a default ranks config
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/timer/ranks.cfg");
    if(!FileExists(sPath))
    {
        File hFile = OpenFile(sPath, "w");
        hFile.WriteLine("//\"Range\"     \"Tag/Name\"");
        hFile.WriteLine("\"0-0\"     \"[Unranked] {name}\"");
        hFile.WriteLine("\"1-1\"     \"[Master] {name}\"");
        hFile.WriteLine("\"2-2\"     \"[Champion] {name}\"");
        delete hFile;
    }
    
    // init chat ranks
    g_hChatRanksRanges.Clear();
    g_hChatRanksNames.Clear();
    
    // Read file lines and get chat ranks and ranges out of them
    char line[PLATFORM_MAX_PATH];
    char oldLine[PLATFORM_MAX_PATH];
    char sRange[PLATFORM_MAX_PATH];
    char sName[PLATFORM_MAX_PATH];
    char expRange[2][128];
    int idx, Range[2];
    
    File hFile = OpenFile(sPath, "r");
    while(!hFile.EndOfFile())
    {
        hFile.ReadLine(line, sizeof(line));
        ReplaceString(line, sizeof(line), "\n", "");
        if(line[0] != '/' && line[1] != '/' && strlen(line) > 2)
        {
            if(!StrEqual(line, oldLine))
            {
                idx = BreakString(line, sRange, sizeof(sRange));
                BreakString(line[idx], sName, sizeof(sName));
                ExplodeString(sRange, "-", expRange, 2, 128);
                
                Range[0] = StringToInt(expRange[0]);
                Range[1] = StringToInt(expRange[1]);
                g_hChatRanksRanges.PushArray(Range);
                
                g_hChatRanksNames.PushString(sName);
            }
        }
        Format(oldLine, sizeof(oldLine), line);
    }
    
    delete hFile;
}

void LoadCustomChat()
{    
    char query[512];
    FormatEx(query, sizeof(query), "SELECT SteamID, ccname, ccmsgcol, ccuse FROM players WHERE ccuse != 0");
    g_DB.Query(LoadCustomChat_Callback, query);
}

public void LoadCustomChat_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results != INVALID_HANDLE)
    {        
        char sAuth[32];
        char sName[128];
        char sMsg[256];
        int rows = results.RowCount;
        
        for(int i=0; i<rows; i++)
        {
            results.FetchRow();
            
            results.FetchString(0, sAuth, sizeof(sAuth));
            results.FetchString(1, sName, sizeof(sName));
            results.FetchString(2, sMsg, sizeof(sMsg));
            
            g_hCustomSteams.PushString(sAuth);
            g_hCustomNames.PushString(sName);
            g_hCustomMessages.PushString(sMsg);
            g_hCustomUse.Push(results.FetchInt(3));
        }
    }
    else
    {
        LogError(error);
    }
}

public int Native_EnableCustomChat(Handle plugin, int numParams)
{
    char sAuth[32];
    GetNativeString(1, sAuth, sizeof(sAuth));
    
    EnableCustomChat(sAuth);
}

public int Native_DisableCustomChat(Handle plugin, int numParams)
{
    char sAuth[32];
    GetNativeString(1, sAuth, sizeof(sAuth));
    
    DisableCustomChat(sAuth);
}

public int Native_SteamIDHasCustomChat(Handle plugin, int numParams)
{
    char sAuth[32];
    GetNativeString(1, sAuth, sizeof(sAuth));
    
    return g_hCustomSteams.FindString(sAuth) != -1;
}

void DB_ShowRank(int client, int target, int Type, int Style)
{
    if(g_Rank[target][Type][Style] != 0)
    {
        PrintColorText(client, "%s%s%N%s is ranked %s%d%s of %s%d%s players with %s%.1f%s points.",
            g_msg_start,
            g_msg_varcol,
            target,
            g_msg_textcol,
            g_msg_varcol,
            g_Rank[target][Type][Style],
            g_msg_textcol,
            g_msg_varcol,
            g_hRanksPlayerID[Type][Style].Length,
            g_msg_textcol,
            g_msg_varcol,
            g_hRanksPoints[Type][Style].Get(g_Rank[target][Type][Style] - 1),
            g_msg_textcol);
    }
    else
    {
        PrintColorText(client, "%s%s%N%s is not ranked yet.",
            g_msg_start,
            g_msg_varcol,
            target,
            g_msg_textcol);
    }
}

public void DB_ShowRank_Callback(Database db, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        int client = data.ReadCell();
        int target = data.ReadCell();
        
        char sTarget[MAX_NAME_LENGTH];
        GetClientName(target, sTarget, sizeof(sTarget));
        
        results.FetchRow();
        
        if(results.FetchInt(0) != 0)
        {
            int Rank         = results.FetchInt(0);
            int Total        = results.FetchInt(1);
            float Points = results.FetchFloat(2);
            
            PrintColorText(client, "%s%s%s%s is ranked %s%d%s of %s%d%s players with %s%.1f%s points.",
                g_msg_start,
                g_msg_varcol,
                sTarget,
                g_msg_textcol,
                g_msg_varcol,
                Rank,
                g_msg_textcol,
                g_msg_varcol,
                Total,
                g_msg_textcol,
                g_msg_varcol,
                Points,
                g_msg_textcol);
        }
        else
        {
            PrintColorText(client, "%s%s%s%s is not ranked yet.",
                g_msg_start,
                g_msg_varcol,
                sTarget,
                g_msg_textcol);
        }
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

public int Menu_ShowTopAll(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_End)
        delete menu;
}

void DB_ShowTopAllSpec(int client, int Type, int Style)
{    
    char sType[32];
    GetTypeName(Type, sType, sizeof(sType));
    AddBracketsToString(sType, sizeof(sType));
    
    char sStyle[32];
    GetStyleName(Style, sStyle, sizeof(sStyle));
    AddBracketsToString(sStyle, sizeof(sStyle));
    
    int iSize = g_hRanksPlayerID[Type][Style].Length;
    if(iSize > 0)
    {
        Menu menu = new Menu(Menu_ShowTop);
        menu.SetTitle("Top 100 Players %s - %s\n--------------------------------------", sType, sStyle);
        
        char sDisplay[64];
        char sInfo[16];
        
        for(int idx; idx < iSize && idx < 100; idx++)
        {
            g_hRanksNames[Type][Style].GetString(idx, sDisplay, sizeof(sDisplay));
            Format(sDisplay, sizeof(sDisplay), "#%d: %s (%d Pts.)", idx + 1, sDisplay, RoundToNearest(g_hRanksPoints[Type][Style].Get(idx)));
            
            FormatEx(sInfo, sizeof(sInfo), "%d;%d;%d", g_hRanksPlayerID[Type][Style].Get(idx), Type, Style);
            
            if(((idx + 1) % 7) == 0 || (idx + 1) == iSize)
                Format(sDisplay, sizeof(sDisplay), "%s\n--------------------------------------", sDisplay);
            
            menu.AddItem(sInfo, sDisplay);
        }
        
        menu.Display(client, MENU_TIME_FOREVER);
    }
    else
    {
        PrintColorText(client, "%s%s%s %s-%s %s %sThere are no ranked players yet.",
            g_msg_start,
            g_msg_varcol,
            sType,
            g_msg_textcol,
            g_msg_varcol,
            sStyle,
            g_msg_textcol);
    }
}

public int Menu_ShowTop(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));
        
        char sInfoExploded[3][16];
        ExplodeString(sInfo, ";", sInfoExploded, sizeof(sInfoExploded), sizeof(sInfoExploded[]));
        OpenStatsMenu(param1, StringToInt(sInfoExploded[0]), StringToInt(sInfoExploded[1]), StringToInt(sInfoExploded[2]));
    }
    if(action == MenuAction_End)
        delete menu;
}

void DB_ShowMapsleft(int client, int target, int Type, int Style)
{
    if(GetPlayerID(target) != 0)
    {
        DataPack pack = new DataPack();
        pack.WriteCell(GetClientUserId(client));
        pack.WriteCell(GetClientUserId(target));
        
        char sTarget[MAX_NAME_LENGTH];
        GetClientName(target, sTarget, sizeof(sTarget));
        pack.WriteString(sTarget);
        pack.WriteCell(Type);
        pack.WriteCell(Style);
        
        char query[512];
        if(Type == ALL && Style == ALL)
            Format(query, sizeof(query), "SELECT t2.MapName FROM (SELECT maps.MapID AS MapID1, t1.MapID AS MapID2 FROM maps LEFT JOIN (SELECT MapID FROM times WHERE PlayerID=%d) t1 ON maps.MapID=t1.MapID) AS t1, maps AS t2 WHERE t1.MapID1=t2.MapID AND t1.MapID2 IS NULL ORDER BY t2.MapName",
                GetPlayerID(target));
        else
            Format(query, sizeof(query), "SELECT t2.MapName FROM (SELECT maps.MapID AS MapID1, t1.MapID AS MapID2 FROM maps LEFT JOIN (SELECT MapID FROM times WHERE Type=%d AND Style=%d AND PlayerID=%d) t1 ON maps.MapID=t1.MapID) AS t1, maps AS t2 WHERE t1.MapID1=t2.MapID AND t1.MapID2 IS NULL ORDER BY t2.MapName",
                Type,
                Style,
                GetPlayerID(target));
        g_DB.Query(DB_ShowMapsLeft_Callback, query, pack);
    }
    else
    {
        if(client == target)
        {
            PrintColorText(client, "%s%sYour SteamID is not authorized. Steam servers may be down. If not, try reconnecting.",
                g_msg_start,
                g_msg_textcol);
        }
        else
        {
            char name[MAX_NAME_LENGTH];
            GetClientName(target, name, sizeof(name));
            
            PrintColorText(client, "%s%s%s's %sSteamID is not authorized. Steam servers may be down.", 
                g_msg_start,
                g_msg_varcol,
                name,
                g_msg_textcol);
        }
    }
}

public void DB_ShowMapsLeft_Callback(Database db, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        int clientUserId = data.ReadCell();
        int client       = GetClientOfUserId(clientUserId);
        int targetUserId = data.ReadCell();
        
        char sTarget[MAX_NAME_LENGTH];
        data.ReadString(sTarget, sizeof(sTarget));
        int Type        = data.ReadCell();
        int Style     = data.ReadCell();
        
        if(client != 0)
        {
            int rows = results.RowCount, count;
            char mapname[128];
            Menu menu = new Menu(Menu_ShowMapsleft);
            
            char sType[32];
            if(Type != ALL)
            {
                GetTypeName(Type, sType, sizeof(sType));
                StringToUpper(sType);
                AddBracketsToString(sType, sizeof(sType));
                AddSpaceToEnd(sType, sizeof(sType));
            }
            
            char sStyle[32];
            if(Style != ALL)
            {
                GetStyleName(Style, sStyle, sizeof(sStyle));
                
                Format(sStyle, sizeof(sStyle)," on %s", sStyle);
            }
            
            char title[128];
            if (rows > 0)
            {
                for(int itemnum=1; itemnum<=rows; itemnum++)
                {
                    results.FetchRow();
                    results.FetchString(0, mapname, sizeof(mapname));
                    if(g_MapList.FindString(mapname) != -1)
                    {
                        count++;
                        menu.AddItem(mapname, mapname);
                    }
                }
                
                if(clientUserId == targetUserId)
                {
                    Format(title, sizeof(title), "%d %sMaps left to complete%s",
                        count,
                        sType,
                        sStyle);
                }
                else
                {
                    Format(title, sizeof(title), "%d %sMaps left to complete%s for player %s",
                        count,
                        sType,
                        sStyle,
                        sTarget);
                }
                menu.SetTitle(title);
            }
            else
            {
                if(clientUserId == targetUserId)
                {
                    PrintColorText(client, "%s%s%s%sYou have no maps left to beat%s%s.", 
                        g_msg_start,
                        g_msg_varcol,
                        sType,
                        g_msg_textcol,
                        g_msg_varcol,
                        sStyle);
                }
                else
                {
                    PrintColorText(client, "%s%s has no maps left to beat%s.", 
                        g_msg_start,
                        g_msg_varcol,
                        sType,
                        sTarget,
                        g_msg_textcol,
                        g_msg_varcol,
                        sStyle);
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
    delete data;
}

public int Menu_ShowMapsleft(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[64];
        menu.GetItem(param2, info, sizeof(info));
        
        FakeClientCommand(param1, "sm_nominate %s", info);
    }
    else if (action == MenuAction_End)
        delete menu;
}

void DB_ShowMapsdone(int client, int PlayerID, int Type, int Style)
{
    Menu menu = new Menu(Menu_ShowMapsdone);
    
    char sType[32];
    GetTypeName(Type, sType, sizeof(sType));
    
    char sStyle[32];
    GetStyleName(Style, sStyle, sizeof(sStyle));
    
    char sName[MAX_NAME_LENGTH];
    GetNameFromPlayerID(PlayerID, sName, sizeof(sName));
    
    ArrayList hCell = g_hMapsDone[Type][Style].Get(PlayerID);
    
    if(hCell != INVALID_HANDLE)
    {
        int iSize = hCell.Length;
        char sMapName[64];
        char sTime[32];
        char sDisplay[128];
        for(int idx; idx < iSize; idx++)
        {
            GetMapNameFromMapId(hCell.Get(idx, 0), sMapName, sizeof(sMapName));
            int Position   = hCell.Get(idx, 1);
            float Time = hCell.Get(idx, 2);
            FormatPlayerTime(Time, sTime, sizeof(sTime), false, 1);
            
            FormatEx(sDisplay, sizeof(sDisplay), "%s: %s (#%d)", sMapName, sTime, Position);
            
            if(((idx + 1) % 7) == 0 || (idx + 1) == iSize)
                Format(sDisplay, sizeof(sDisplay), "%s\n--------------------------------------", sDisplay);
            
            menu.AddItem(sMapName, sDisplay);
        }

        int zone = MAIN_START;

        if(Type == TIMER_BONUS)
        {
            zone = BONUS_START;
        }
        else if(Type == TIMER_SOLOBONUS)
        {
            zone = SOLOBONUS_START;
        }
        
        menu.SetTitle("Maps done for %s [%s] - [%s]\n \nCompleted %d / %d\n-----------------------------------", sName, sType, sStyle, iSize, GetTotalZonesAllMaps(zone));
        
        menu.Display(client, MENU_TIME_FOREVER);
    }
    else
    {
        PrintColorText(client, "%s%s%s %shas no maps done.",
            g_msg_start,
            g_msg_varcol,
            sName,
            g_msg_textcol);
    }
}
 
public void Menu_ShowMapsdone_Callback(Database db, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        data.Reset();
        int client      = data.ReadCell();
        int target      = data.ReadCell();
        int Type        = data.ReadCell();
        int Style       = data.ReadCell();
       
        int rows = results.RowCount;
        
        char sType[32];
        if(Type != ALL)
        {
            GetTypeName(Type, sType, sizeof(sType));
            StringToUpper(sType);
            AddBracketsToString(sType, sizeof(sType));
            AddSpaceToEnd(sType, sizeof(sType));
        }
        
        char sStyle[32];
        if(Style != ALL)
        {
            GetStyleName(Style, sStyle, sizeof(sStyle));
            
            Format(sStyle, sizeof(sStyle)," on %s", sStyle);
        }
        
        if(rows != 0)
        {
            Menu menu = new Menu(Menu_ShowMapsdone);
            char sMapName[64];
            int mapsdone;
            
            for(int i=0; i<rows; i++)
            {
                results.FetchRow();
                
                results.FetchString(0, sMapName, sizeof(sMapName));
                
                if(g_MapList.FindString(sMapName) != -1)
                {
                    menu.AddItem(sMapName, sMapName);
                    mapsdone++;
                }
            }
            
            if(client == target)
            {
                menu.SetTitle("%s%d maps done%s",
                    sType,
                    mapsdone,
                    sStyle);
            }
            else
            {
                char sTargetName[MAX_NAME_LENGTH];
                GetClientName(target, sTargetName, sizeof(sTargetName));
                
                menu.SetTitle("%s%d maps done by %s%s",
                    sType,
                    mapsdone,
                    sTargetName,
                    sStyle);
            }
            
            menu.ExitButton = true;
            menu.Display(client, MENU_TIME_FOREVER);
        }
        else
        {
            if(client == target)
            {
                PrintColorText(client, "%s%s%s%sYou haven't finished any maps%s%s.",
                    g_msg_start,
                    g_msg_varcol,
                    sType,
                    g_msg_textcol,
                    g_msg_varcol,
                    sStyle);
            }
            else
            {
                char targetname[MAX_NAME_LENGTH];
                GetClientName(target, targetname, sizeof(targetname));
                    
                PrintColorText(client, "%s%s doesn't have any maps finished%s.",
                    g_msg_start,
                    g_msg_varcol,
                    sType,
                    targetname,
                    g_msg_textcol,
                    g_msg_varcol,
                    sStyle);
            }
        }
    }
    else
    {
        LogError(error);
    }
    delete data;
}
 
public int Menu_ShowMapsdone(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[64];
        menu.GetItem(param2, info, sizeof(info));
        
        FakeClientCommand(param1, "sm_nominate %s", info);
    }
    else if(action == MenuAction_End)
        delete menu;
}

public void OnTimesUpdated(const char[] sMapName, int Type, int Style, ArrayList Times)
{
    // Formula: (#Times - MapRank) * AverageTime / 10
    
    int Size = Times.Length;
    
    float fTimeSum;
    for(int idx; idx < Size; idx++)
        fTimeSum += view_as<float>(Times.Get(idx, 1));
    
    float fAverage = fTimeSum / float(Size);
    
    // Update points for all players
    int QuerySize = 250;
    for(int idx; idx < Size; idx++)
    {
        char[] query = new char[QuerySize];
        int fidx = idx;
        if(idx > 0)
        {
            if(Times.Get(idx - 1, 1) == Times.Get(idx, 1))
            {
                fidx = idx - 1;
            }
        }
        float fPoints = (float(Size) - float(fidx)) * fAverage / 10.0;
        FormatEx(query, QuerySize, "UPDATE times SET Points = %f ", fPoints);
        Format(query, QuerySize, "%s WHERE MapID = (SELECT MapID FROM maps WHERE MapName='%s') AND Type=%d AND Style=%d AND PlayerID=%d", query, sMapName, Type, Style, Times.Get(idx));
    
        g_DB.Query(TimesUpdated_Callback, query);
    }
}

public void TimesUpdated_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == INVALID_HANDLE)
        LogError(error);
}

void UpdateRanks(const char[] sMapName, int Type, int Style, bool recalc = false)
{
    char query[700];
    Format(query, sizeof(query), "UPDATE times SET Points = (SELECT t1.Rank FROM (SELECT count(*)*(SELECT AVG(Time) FROM times WHERE MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d)/10 AS Rank, t1.rownum FROM times AS t1, times AS t2 WHERE t1.MapID=t2.MapID AND t1.MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND t1.Type=t2.Type AND t1.Type=%d AND t1.Style=t2.Style AND t1.Style=%d AND t1.Time < t2.Time GROUP BY t1.PlayerID ORDER BY t1.Time) AS t1 WHERE t1.rownum=times.rownum) WHERE MapID=(SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1) AND Type=%d AND Style=%d",
        sMapName,
        Type,
        Style,
        sMapName,
        Type,
        Style,
        sMapName,
        Type,
        Style);
        
    PrintToServer(query);
    
    DataPack pack = new DataPack();
    pack.WriteCell(recalc);
    pack.WriteString(sMapName);
    pack.WriteCell(Type);
    pack.WriteCell(Style);
    
    g_DB.Query(DB_UpdateRanks_Callback, query, pack);
    
    //if(recalc == false)
    //{
    //    for(new client=1; client <= MaxClients; client++)
    //        DB_SetClientRank(client);
    //}
}

public int Native_UpdateRanks(Handle plugin, int numParams)
{
    char sMapName[128];
    GetNativeString(1, sMapName, sizeof(sMapName));
    
    UpdateRanks(sMapName, GetNativeCell(2), GetNativeCell(3));
}

public void DB_UpdateRanks_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    
    if(results != INVALID_HANDLE)
    {
        pack.Reset();
        bool recalc = view_as<bool>(pack.ReadCell());
        
        if(recalc == true)
        {
            char sMapName[64];
            pack.ReadString(sMapName, sizeof(sMapName));
            int Type  = pack.ReadCell();
            int Style = pack.ReadCell();
            
            char sType[16];
            GetTypeName(Type, sType, sizeof(sType));
            StringToUpper(sType);
            AddBracketsToString(sType, sizeof(sType));
            AddSpaceToEnd(sType, sizeof(sType));
            
            char sStyle[16];
            GetStyleName(Style, sStyle, sizeof(sStyle));
            StringToUpper(sStyle);
            AddBracketsToString(sStyle, sizeof(sStyle));
            
            g_RecalcProgress += 1;
            
            for(int client = 1; client <= MaxClients; client++)
            {
                if(IsClientInGame(client))
                {
                    if(!IsFakeClient(client))
                    {
                        PrintToConsole(client, "[%.1f%%] %s %s%s finished recalculation.",
                            float(g_RecalcProgress)/float(g_RecalcTotal) * 100.0,
                            sMapName,
                            sType[Type],
                            sStyle[Style]);
                    }
                }
            }
        }
    }
    else
    {
        LogError(error);
    }
    
    delete pack;
}

void SetClientRank(int client)
{
    int PlayerID = GetPlayerID(client);
    if(PlayerID != 0 && IsClientConnected(client) && !IsFakeClient(client))
    {        
        for(int Type; Type < MAX_TYPES; Type++)
        {
            for(int Style; Style < MAX_STYLES; Style++)
            {
                if(Style_IsEnabled(Style) && Style_IsTypeAllowed(Style, Type))
                {
                    g_Rank[client][Type][Style] = g_hRanksPlayerID[Type][Style].FindValue(PlayerID) + 1;
                }
            }
        }
    }
}

public void PlayerManager_OnThinkPost(int entity)
{
    int[] m_iMVPs = new int[MaxClients + 1];
    //GetEntDataArray(entity, g_iMVPs_offset, m_iMVPs, MaxClients);

    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsFakeClient(client) && GetPlayerID(client) != 0)
        {
            m_iMVPs[client] = g_RecordCount[client];
        }
    }
    
    SetEntDataArray(entity, g_iMVPs_offset, m_iMVPs, MaxClients + 1);
}

void SetRecordCount(int client)
{
    int idx = g_hRecordListID[TIMER_MAIN][0].FindValue(GetPlayerID(client));
    
    if(idx != -1)
    {
        g_RecordCount[client] = g_hRecordListCount[TIMER_MAIN][0].Get(idx);
    }
}

void DB_LoadStats()
{
    #if defined DEBUG
        LogMessage("Loading stats (Getting max PlayerID)");
    #endif
    
    char query[128];
    FormatEx(query, sizeof(query), "SELECT MAX(PlayerID) FROM times");
    g_DB.Query(LoadStats_Callback, query);
}

public void LoadStats_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results != INVALID_HANDLE)
    {
        #if defined DEBUG
            LogMessage("Loading stats (Selecting all times)");
        #endif
        
        if(results.RowCount != 0)
        {
            results.FetchRow();
            
            DataPack pack = new DataPack();
            pack.WriteCell(results.FetchInt(0));
            
            char query[256];
            FormatEx(query, sizeof(query), "SELECT t1.MapID, t1.Type, t1.Style, t1.PlayerID, t1.Time, t1.Points FROM times AS t1, maps AS t2 WHERE t1.MapID=t2.MapID ORDER BY t2.MapName, t1.Type, t1.Style, t1.Time");
            g_DB.Query(LoadStats_Callback2, query, pack);
        }
    }
    else
    {
        LogError(error);
    }
}

public void LoadStats_Callback2(Database db, DBResultSet results, const char[] error, any datapack)
{
    DataPack data = view_as<DataPack>(datapack);
    
    if(results != INVALID_HANDLE)
    {
        #if defined DEBUG
            LogMessage("Stats retrieved, importing to adt_array");
        #endif
        
        data.Reset();
        int MaxPlayerID = data.ReadCell();
        
        int iSize, idx;
        for(int Type; Type < MAX_TYPES; Type++)
        {
            for(int Style; Style < MAX_STYLES; Style++)
            {
                // Close old handles
                iSize = g_hMapsDoneresultsRef[Type][Style].Length;
                for(int i; i < iSize; i++)
                {
                    idx = g_hMapsDoneresultsRef[Type][Style].Get(0);
                    g_hMapsDoneresultsRef[Type][Style].Erase(0);
                    delete view_as<ArrayList>(g_hMapsDone[Type][Style].Get(idx));
                }
                
                g_hMapsDone[Type][Style].Clear();
                g_hMapsDone[Type][Style].Resize(MaxPlayerID + 1);
                
                for(int i; i < MaxPlayerID + 1; i++)
                {
                    g_hMapsDone[Type][Style].Set(i, 0);
                }
                
                g_hRecordListID[Type][Style].Clear();
                g_hRecordListCount[Type][Style].Clear();
            }
        }
        
        int Position;
        int lMapID, lType, lStyle;
        int MapID, Type, Style, PlayerID;
        float Time;
        char sMapName[64];
        
        while(results.FetchRow())
        {
            MapID    = results.FetchInt(0);
            Type     = results.FetchInt(1);
            Style    = results.FetchInt(2);
            PlayerID = results.FetchInt(3);
            Time     = results.FetchFloat(4);
            
            if(lMapID != MapID || lType != Type || lStyle != Style)
                Position = 0;
            Position++;
            
            //if(!(Style_IsEnabled(Style) && Style_IsTypeAllowed(Style, Type)))
            //    continue;
            
            GetMapNameFromMapId(MapID, sMapName, sizeof(sMapName));
            
            if(g_MapList.FindString(sMapName) == -1)
                continue;
            
            if(Position == 1 || (Type != TIMER_SOLOBONUS && Position == 2))
            {
                AddToRecordList(PlayerID, Type, Style);
            }
            
            if(g_hMapsDone[Type][Style].Get(PlayerID) == INVALID_HANDLE)
            {
                ArrayList hCell = new ArrayList(3);
                g_hMapsDone[Type][Style].Set(PlayerID, hCell);
                
                g_hMapsDoneresultsRef[Type][Style].Push(PlayerID);
            }
            
            ArrayList hCell = g_hMapsDone[Type][Style].Get(PlayerID);
            
            iSize = hCell.Length;
            hCell.Resize(iSize + 1);
            
            hCell.Set(iSize, MapID, 0);
            hCell.Set(iSize, Position, 1);
            hCell.Set(iSize, Time, 2);
            
            lMapID = MapID;
            lType  = Type;
            lStyle = Style;
        }
        
        for(int client = 1; client <= MaxClients; client++)
        {
            if(GetPlayerID(client) != 0)
            {
                SetRecordCount(client);
            }
        }
        
        DB_LoadRankList();
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

void AddToRecordList(int PlayerID, int Type, int Style)
{
    int idx = g_hRecordListID[Type][Style].FindValue(PlayerID);
    
    int RecordCount;
    
    if(idx == -1)
    {
        RecordCount = 1;
        
        int iSize = g_hRecordListID[Type][Style].Length;
        
        g_hRecordListID[Type][Style].Resize(iSize + 1);
        g_hRecordListCount[Type][Style].Resize(iSize + 1);
        
        g_hRecordListID[Type][Style].Set(iSize, PlayerID);
        g_hRecordListCount[Type][Style].Set(iSize, RecordCount);
    }
    else
    {
        RecordCount = g_hRecordListCount[Type][Style].Get(idx) + 1;
        g_hRecordListID[Type][Style].Erase(idx);
        g_hRecordListCount[Type][Style].Erase(idx);
        
        int iSize = g_hRecordListID[Type][Style].Length;
        
        for(int i; i < iSize; i++)
        {
            if(RecordCount > g_hRecordListCount[Type][Style].Get(i))
            {
                g_hRecordListID[Type][Style].ShiftUp(i);
                g_hRecordListCount[Type][Style].ShiftUp(i);
                
                g_hRecordListID[Type][Style].Set(i, PlayerID);
                g_hRecordListCount[Type][Style].Set(i, RecordCount);
                
                break;
            }
        }
    }
}

void DB_LoadRankList()
{    
    #if defined DEBUG
        LogMessage("Selecting rank list");
    #endif
    
    // Load ranks only for maps on the server
    int iSize = g_MapList.Length;
    int QuerySize = 220 + (iSize * 128);
    char[] query = new char[QuerySize];
    FormatEx(query, QuerySize, "SELECT t2.User, t1.PlayerID, SUM(t1.Points), t1.Type, t1.Style FROM times AS t1, players AS t2 WHERE t1.PlayerID=t2.PlayerID AND (");
    
    char sMapName[64];
    for(int idx; idx < iSize; idx++)
    {
        g_MapList.GetString(idx, sMapName, sizeof(sMapName));
        
        Format(query, QuerySize, "%st1.MapID = (SELECT MapID FROM maps WHERE MapName='%s' LIMIT 0, 1)", query, sMapName);
        
        if(idx < iSize - 1)
        {
            Format(query, QuerySize, "%s OR ", query);
        }
    }
    
    Format(query, QuerySize, "%s) GROUP BY t1.PlayerID, t1.Type, t1.Style ORDER BY t1.Type, t1.Style, SUM(t1.Points) DESC", query);
    
    g_DB.Query(LoadRankList_Callback, query);
}

public void LoadRankList_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results != INVALID_HANDLE)
    {
        #if defined DEBUG
            PrintToServer("Rank list selected, loading into adt_array");
        #endif
        
        for(int Type; Type < MAX_TYPES; Type++)
        {
            for(int Style; Style < MAX_STYLES; Style++)
            {
                if(Style_IsEnabled(Style) && Style_IsTypeAllowed(Style, Type))
                {
                    g_hRanksPlayerID[Type][Style].Clear();
                    g_hRanksPoints[Type][Style].Clear();
                    g_hRanksNames[Type][Style].Clear();
                }
            }
        }
        
        char sName[MAX_NAME_LENGTH];
        int PlayerID, Type, Style, iSize;
        float Points;
        
        while(results.FetchRow())
        {
            results.FetchString(0, sName, sizeof(sName));
            PlayerID = results.FetchInt(1);
            Points   = results.FetchFloat(2);
            Type     = results.FetchInt(3);
            Style    = results.FetchInt(4);
            
            if(!(Style_IsEnabled(Style) && Style_IsTypeAllowed(Style, Type)))
                continue;
            
            iSize = g_hRanksPlayerID[Type][Style].Length;
            
            g_hRanksNames[Type][Style].Resize(iSize + 1);
            g_hRanksNames[Type][Style].SetString(iSize, sName);
            
            g_hRanksPlayerID[Type][Style].Resize(iSize + 1);
            g_hRanksPlayerID[Type][Style].Set(iSize, PlayerID);
            
            g_hRanksPoints[Type][Style].Resize(iSize + 1);
            g_hRanksPoints[Type][Style].Set(iSize, Points);
        }
        
        for(int client = 1; client <= MaxClients; client++)
        {
            if(GetPlayerID(client) != 0)
            {
                SetClientRank(client);
            }
        }
        
        g_bStatsLoaded = true;
    }
    else
    {
        LogError(error);
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
    else
    {
        // Custom chat tags
        LoadCustomChat();
    }
}
