/**
 * Maps I'd use:
 * https://steamcommunity.com/sharedfiles/filedetails/?id=646308893
 * https://steamcommunity.com/sharedfiles/filedetails/?id=464720915
 * https://steamcommunity.com/sharedfiles/filedetails/?id=475916587
 * https://steamcommunity.com/sharedfiles/filedetails/?id=381587877
 * https://steamcommunity.com/sharedfiles/filedetails/?id=449180221
 */

#pragma semicolon 1

#define PLUGIN_AUTHOR "Yimura"
#define PLUGIN_VERSION "0.1.0"

#define TEAM_SPEC 1
#define TEAM_T 2
#define TEAM_CT 3

#define STATE_NONE 0
#define STATE_MAP_LOADED 1
#define STATE_WARMUP 2
#define STATE_PREP 3
#define STATE_ACTIVE 4
#define STATE_1V1 5
#define STATE_END 6

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <smlib>

#pragma newdecls required

bool
    g_bDebug = false,

    g_bPluginState = false,
    g_bSetCvars = false,

    g_bWarmup = false,

    g_bDefaultSolidTeammates = false,

    g_bDefaultDeathDropGun = false,
    g_bDefaultDeathDropDefuser = false,
    g_bDefaultDeathDropGrenade = false,

    g_bDefaultPlayerCashCV = false,
    g_bDefaultTeamCashCV = false;

ConVar
    g_cvPluginState,

    g_cvMMRoundTime,
    g_cvSetupTimer,

    g_cvIgnoreRoundWinCondition,
    g_cvTeamBalance,

    g_cvFreezeTime,
    g_cvRestartGame,

    g_cvDeathDropGun,
    g_cvDeathDropDefuser,
    g_cvDeathDropGrenade,

    g_cvSolidTeammates,
    g_cvBuyTime,

    g_cvRoundTime,
    g_cvRoundTimeDefuse,
    g_cvRoundTimeHostage,

    g_cvPlayerCashAward,
    g_cvTeamCashAward;

/*float
    g_fMikeSpeed = 400.0,
    g_fSurvivorSpeed = 320.0,

    g_fMikeDefSpeed = 400.0;*/

Handle
    g_hPrepareGameTimer = INVALID_HANDLE,
    //g_hEndGameTimer = INVALID_HANDLE,
    g_hSlowDownTimer = INVALID_HANDLE;

int
    g_iGameState = STATE_NONE,

    g_iDefaultBuyTime = -1,
    g_iDefaultTeamBalance = -1,

    g_iDefaultRoundTime = -1,
    g_iDefaultRoundDefuseTime = -1,
    g_iDefaultRoundHostageTime = -1,

    g_iMike,
    g_iSetupTimer;

public Plugin myinfo = {
        name = "[CS:GO] Mike Myers",
        author = PLUGIN_AUTHOR,
        description = "",
        version = PLUGIN_VERSION,
        url = ""
};

public void OnPluginStart()
{
    if (GetEngineVersion() != Engine_CSGO)
        SetFailState("[MM] This plugin was made to be ran on CS:GO only!");

    CreateConVar("sm_mikemyers_version", PLUGIN_VERSION, "Mike Myers Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    g_cvPluginState = CreateConVar("sm_mm_enable", "1", "Enable/Disable Mike Myers gamemode", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvMMRoundTime = CreateConVar("sm_mm_roundtime", "5", "Set the round time before the CT's win.", FCVAR_NOTIFY, true, 0.0, true, 25.0);
    g_cvSetupTimer = CreateConVar("sm_mm_preptimer", "30", "Preparation timer before Mike Myers will be chosen.", FCVAR_NOTIFY, true, 0.0, true, 60.0);

    // Generic Source Events
    HookEvent("player_team", OnPlayerChangeTeam);

    HookEvent("round_start", OnRoundStart);
    HookEvent("round_end", OnRoundEnd);
    HookEvent("round_start", PreRoundStart, EventHookMode_Pre);

    HookEvent("round_announce_warmup", OnWarmupStart, EventHookMode_Post);
    HookEvent("round_announce_match_start", OnWarmupEnd);

    HookEvent("player_spawn", OnPlayerSpawn);
    HookEvent("player_spawn", PrePlayerSpawn, EventHookMode_Pre);
    HookEvent("player_death", OnPlayerDeath);
    HookEvent("player_death", PrePlayerDeath, EventHookMode_Pre);

    if (g_bDebug)
        RegConsoleCmd("sm_mm_gamestate", Command_GameState, "Print out the current active gamestate");
    RegAdminCmd("sm_mm_respawn", Command_Respawn, ADMFLAG_ROOT, "Respawn a player that was unfairly killed.");

    int pluginEnabled = g_cvPluginState.IntValue;
    if (pluginEnabled == 1)
        g_bPluginState = true;
    else
        g_bPluginState = false;

    AddCommandListener(OnCommandDropWeapon, "drop");

    g_cvPluginState.AddChangeHook(OnPluginStateToggled);

    g_cvPlayerCashAward = FindConVar("mp_playercashawards");
    g_cvTeamCashAward = FindConVar("mp_teamcashawards");

    g_cvRoundTimeDefuse = FindConVar("mp_roundtime_defuse");
    g_cvRoundTimeHostage = FindConVar("mp_roundtime_hostage");
    g_cvRoundTime = FindConVar("mp_roundtime");

    g_cvBuyTime = FindConVar("mp_buytime");

    g_cvFreezeTime = FindConVar("mp_freezetime");
    g_cvRestartGame = FindConVar("mp_restartgame");

    g_cvDeathDropGun = FindConVar("mp_death_drop_gun");
    g_cvDeathDropDefuser = FindConVar("mp_death_drop_defuser");
    g_cvDeathDropGrenade = FindConVar("mp_death_drop_grenade");

    g_cvSolidTeammates = FindConVar("mp_solid_teammates");

    g_cvTeamBalance = FindConVar("mp_autoteambalance");
    g_cvIgnoreRoundWinCondition = FindConVar("mp_ignore_round_win_conditions");

    for (int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
			continue;
		OnClientPutInServer(i);
	}
}

public void OnPluginEnd()
{
    ResetCvars();
}

/**
 * Public Events
 */
public void OnMapStart()
{
    if (!g_bPluginState) return;

    g_iGameState = STATE_MAP_LOADED;
}

public void OnMapEnd()
{
    g_iGameState = STATE_NONE;

    ResetCvars();
}

public void OnClientPutInServer(int client)
{
    if (!g_bPluginState) return;

    SDKHook(client, SDKHook_OnTakeDamage, SDK_OnTakeDamage);
    SDKHook(client, SDKHook_WeaponDrop, SDK_OnWeaponDrop);
}

/**
 * CommandListeners
 */
Action OnCommandDropWeapon(int client, const char[] command, int args)
{
    if (!g_bPluginState || g_iGameState != STATE_ACTIVE) return Plugin_Continue;

    return Plugin_Stop;
}

/**
 * SDK Hooks
 */
Action SDK_OnWeaponDrop(int client, int weapon)
{
    if (!g_bPluginState || g_iGameState != STATE_ACTIVE) return Plugin_Continue;

    return Plugin_Continue;
}
Action SDK_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!g_bPluginState || g_iGameState != STATE_ACTIVE) return Plugin_Continue;

    if (IsValidClient(attacker))
    {
        int team = GetClientTeam(attacker);

        if (IsValidClient(victim))
        {
            int otherTeam = GetClientTeam(victim);
            if (otherTeam == TEAM_T && team == TEAM_CT && g_iGameState != STATE_1V1)
            {
                if (g_hSlowDownTimer != INVALID_HANDLE) {
                    KillTimer(g_hSlowDownTimer);
                    g_hSlowDownTimer = INVALID_HANDLE;
                }

                SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.8);
                g_hSlowDownTimer = CreateTimer(2.0, Timer_RestoreSpeed, victim);
            }
        }

        if (team == TEAM_CT && g_iGameState != STATE_1V1) {
            return Plugin_Stop;
        }
    }

    char cWeapon[32];
    if(inflictor > 0 && inflictor <= MaxClients)
	{
		int weapon = GetEntPropEnt(inflictor, Prop_Send, "m_hActiveWeapon");
		GetEdictClassname(weapon, cWeapon, 32);
	}

    if(StrContains(cWeapon, "knife") == -1 || !IsValidClient(attacker) || !IsValidClient(victim))
	   return Plugin_Continue;

    damage = float(GetClientHealth(victim) + GetClientArmor(victim));

    return Plugin_Changed;
}

/**
 * Match Events
 */
Action OnWarmupStart(Event event, const char[] name, bool dontBroadCast)
{
    if (!g_bPluginState) return Plugin_Continue;

    g_iGameState = STATE_WARMUP;

    return Plugin_Continue;
}
Action OnWarmupEnd(Event event, const char[] name, bool dontBroadCast)
{
    if (!g_bPluginState) return Plugin_Continue;

    g_bWarmup = false;

    return Plugin_Continue;
}

Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadCast)
{
    if (!g_bPluginState || (g_iGameState != STATE_ACTIVE && g_iGameState != STATE_PREP && g_iGameState != STATE_END)) return Plugin_Continue;
    int client = GetClientOfUserId(event.GetInt("userid", -1));
    if (client == -1) return Plugin_Continue;

    if (g_iGameState == STATE_ACTIVE) {
        ForcePlayerSuicide(client);

        return Plugin_Handled;
    }

    SetEntProp(client, Prop_Send, "m_bHasHelmet", 0);
    SetEntProp(client, Prop_Send, "m_ArmorValue", 0);
    SetEntProp(client, Prop_Send, "m_iAccount", 0);

    int iTeam = GetClientTeam(client);
    if (iTeam == TEAM_CT)
    {
        Client_RemoveAllWeapons(client);
        GivePlayerItem(client, "weapon_hkp2000");

        int iWeapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
        SetEntProp(iWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);
    }
    else if (iTeam == TEAM_T)
    {
        Client_RemoveAllWeapons(client);
        GivePlayerItem(client, "weapon_knife_t");
    }

    return Plugin_Continue;
}
Action PrePlayerSpawn(Event event, const char[] name, bool dontBroadCast)
{
    if (!g_bPluginState) return Plugin_Continue;

    if (g_iGameState == STATE_MAP_LOADED)
        g_bWarmup = true;

    return Plugin_Continue;
}
Action OnPlayerDeath(Event event, const char[] name, bool dontBroadCast)
{
    if (GetAlivePlayerCount() == 2 && GetAliveInTeam(TEAM_CT) == 1 && g_iGameState == STATE_ACTIVE)
    {
        int iLastSurvivor = GetLastSurvivorPlayer();
        if (iLastSurvivor == -1) return Plugin_Continue;

        g_iGameState = STATE_1V1;

        Client_RemoveAllWeapons(iLastSurvivor);
        GivePlayerItem(iLastSurvivor, "weapon_knife");
    }
    return Plugin_Continue;
}
Action PrePlayerDeath(Event event, const char[] name, bool dontBroadCast)
{
    if (!g_bPluginState || g_iGameState != STATE_ACTIVE) return Plugin_Continue;

    int
        victim = GetClientOfUserId(event.GetInt("userid")),
        attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (victim != attacker)
        event.BroadcastDisabled = true;

    if (attacker != 0 && IsValidClient(attacker) && !IsFakeClient(attacker))
        event.FireToClient(attacker);
    //if (g_bGameState && victim != g_iMike)
    //    ChangeClientTeam(victim, TEAM_SPEC);
    if (g_iGameState != STATE_ACTIVE && g_iGameState != STATE_END)
        CreateTimer(0.1, Timer_RespawnPlayer, victim);
    return Plugin_Continue;
}

Action PreRoundStart(Event event, const char[] name, bool dontBroadCast)
{
    if (g_bDebug)
        PrintToServer("[MM] Event: PreRoundStart, current gamestate %i", g_iGameState);

    if (!g_bPluginState || (g_iGameState != STATE_WARMUP && g_iGameState != STATE_MAP_LOADED)) return Plugin_Continue;

    if (g_iGameState == STATE_MAP_LOADED)
        g_bWarmup = true;

    if (g_iGameState == STATE_WARMUP)
        SetCvars();

    g_iGameState = STATE_PREP;

    if (g_bWarmup && g_iGameState == STATE_PREP)
    {
        g_bWarmup = false;
        g_iGameState = STATE_WARMUP;

        return Plugin_Continue;
    }

    for(int i = 1; i < MaxClients; i++)
    {
        if (IsValidClient(i))
        {
            int team = GetClientTeam(i);
            if (team == TEAM_T)
            {
                ChangeClientTeam(i, TEAM_CT);
                if (!IsPlayerAlive(i))
                    CS_RespawnPlayer(i);
            }
        }
    }

    g_cvRestartGame.SetInt(1);

    return Plugin_Continue;
}
Action OnRoundStart(Event event, const char[] name, bool dontBroadCast)
{
    if (g_bDebug)
            PrintToServer("[MM] Event: OnRoundStart, current gamestate %i", g_iGameState);

    if (!g_bPluginState || (g_iGameState != STATE_END && g_iGameState != STATE_PREP)) return Plugin_Continue;

    g_iGameState = STATE_PREP;
    if (g_hPrepareGameTimer != INVALID_HANDLE) KillTimer(g_hPrepareGameTimer);
    g_hPrepareGameTimer = CreateTimer(1.0, Timer_PrepareGame, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

    /*for(int client = 1; client < MaxClients; client++)
    {
        int iTeam = GetClientTeam(client);
        if (iTeam == TEAM_CT)
        {
            Client_RemoveAllWeapons(client);
            GivePlayerItem(client, "weapon_hkp2000");

            int iWeapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
            SetEntProp(iWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);
        }
        else if (iTeam == TEAM_T)
        {
            Client_RemoveAllWeapons(client);
            GivePlayerItem(client, "weapon_knife_t");
        }
    }*/

    return Plugin_Continue;
}
Action OnRoundEnd(Event event, const char[] name, bool dontBroadCast)
{
    if (g_bDebug)
            PrintToServer("[MM] Event: OnRoundEnd, current gamestate %i", g_iGameState);

    if (!g_bPluginState || g_iGameState == STATE_WARMUP || g_iGameState == STATE_MAP_LOADED || g_iGameState == STATE_PREP) return Plugin_Continue;

    g_iGameState = STATE_END;

    //KillTimer(g_hAmmoTimer);
    //KillTimer(g_hEndGameTimer);
    //g_hEndGameTimer = INVALID_HANDLE;
    if (g_hPrepareGameTimer != INVALID_HANDLE)
    {
        KillTimer(g_hPrepareGameTimer);
        g_hPrepareGameTimer = INVALID_HANDLE;
    }

    for(int i = 1; i < MaxClients; i++)
    {
        if (IsValidClient(i, false))
        {
            int team = GetClientTeam(i);
            if(team == TEAM_T)
                ChangeClientTeam(i, TEAM_CT);
        }
    }

    return Plugin_Continue;
}

Action OnPlayerChangeTeam(Event event, const char[] name, bool dontBroadCast)
{
    if (g_bDebug)
            PrintToServer("[MM] Event: OnPlayerChangeTeam, current gamestate %i", g_iGameState);

    if (!g_bPluginState || g_iGameState != STATE_ACTIVE || g_iGameState != STATE_END) return Plugin_Continue;

    event.BroadcastDisabled = true;

    int client = GetClientOfUserId(event.GetInt("userid", -1));

    CreateTimer(0.1, Timer_CheckTeam, client);

    return Plugin_Continue;
}

/**
 * ConVar Changes
 */
void OnPluginStateToggled(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_bPluginState != convar.BoolValue)
        g_bPluginState = !g_bPluginState;

    if (g_bPluginState)
        SetCvars();
    else
        ResetCvars();
}

void SetCvars()
{
    if (g_bSetCvars) return;
    g_bSetCvars = true;

    g_bDefaultPlayerCashCV = g_cvPlayerCashAward.BoolValue;
    g_cvPlayerCashAward.SetBool(false, true, false);

    g_bDefaultTeamCashCV = g_cvTeamCashAward.BoolValue;
    g_cvTeamCashAward.SetBool(false, true, false);

    g_iDefaultRoundTime = g_cvRoundTime.IntValue;
    g_cvRoundTime.SetInt(g_cvMMRoundTime.IntValue);
    g_iDefaultRoundDefuseTime = g_cvRoundTimeDefuse.IntValue;
    g_cvRoundTimeDefuse.SetInt(0, true, false);
    g_iDefaultRoundHostageTime = g_cvRoundTimeHostage.IntValue;
    g_cvRoundTimeHostage.SetInt(0, true, false);

    g_iDefaultTeamBalance = g_cvTeamBalance.IntValue;
    g_cvTeamBalance.SetInt(0, true, false);

    g_iDefaultBuyTime = g_cvBuyTime.IntValue;
    g_cvBuyTime.SetInt(0, true, false);

    g_cvFreezeTime.SetInt(1, true, false);

    g_iSetupTimer = g_cvSetupTimer.IntValue;

    g_bDefaultDeathDropGun = g_cvDeathDropGun.BoolValue;
    g_bDefaultDeathDropDefuser = g_cvDeathDropDefuser.BoolValue;
    g_bDefaultDeathDropGrenade = g_cvDeathDropGrenade.BoolValue;
    g_cvDeathDropGun.SetBool(false, true, false);
    g_cvDeathDropDefuser.SetBool(false, true, false);
    g_cvDeathDropGrenade.SetBool(false, true, false);

    g_bDefaultSolidTeammates = g_cvSolidTeammates.BoolValue;
    g_cvSolidTeammates.SetBool(false, true, false);
}

void ResetCvars()
{
    if (!g_bPluginState || !g_bSetCvars) return;
    g_bSetCvars = false;

    g_cvPlayerCashAward.SetBool(g_bDefaultPlayerCashCV, true, false);
    g_cvTeamCashAward.SetBool(g_bDefaultTeamCashCV, true, false);

    g_cvRoundTimeDefuse.SetInt(g_iDefaultRoundDefuseTime, true, false);
    g_cvRoundTimeHostage.SetInt(g_iDefaultRoundHostageTime, true, false);
    g_cvRoundTime.SetInt(g_iDefaultRoundTime, true, false);

    g_cvTeamBalance.SetInt(g_iDefaultTeamBalance, true, false);

    g_cvBuyTime.SetInt(g_iDefaultBuyTime, true, false);
    g_cvFreezeTime.SetInt(15, true, false);

    g_cvDeathDropGun.SetBool(g_bDefaultDeathDropGun, true, false);
    g_cvDeathDropDefuser.SetBool(g_bDefaultDeathDropDefuser, true, false);
    g_cvDeathDropGrenade.SetBool(g_bDefaultDeathDropGrenade, true, false);

    g_cvSolidTeammates.SetBool(g_bDefaultSolidTeammates, true, false);
}

/**
 * Functions
 */
bool IsValidClient(int client, bool bAlive = false)
{
	if(client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && (!bAlive || IsPlayerAlive(client)))
	   return true;
	return false;
}

int GetAlivePlayerCount()
{
    int iPlayers = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i, true))
        {
            int team = GetClientTeam(i);
            if (team == TEAM_T || team == TEAM_CT) iPlayers++;
        }
    }
    return iPlayers;
}
int GetAliveInTeam(int iTeam)
{
    int iCTs = 0;
    for (int i = 1; i < MaxClients; i++)
    {
        if (IsValidClient(i, true))
        {
            int team = GetClientTeam(i);
            if (team == iTeam) iCTs++;
        }
    }
    return iCTs;
}
int GetLastSurvivorPlayer()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i, true))
        {
            int team = GetClientTeam(i);
            if (team == TEAM_CT)
                return i;
        }
    }
    return -1;
}
int GetRandomClient()
{
    int count = 0;
    int[] clients = new int[MaxClients];
    for (int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i, true))
        {
            int team = GetClientTeam(i);
            if (team == TEAM_CT) clients[count++] = i;
        }
    }
    return (count == 0) ? -1 : clients[GetRandomInt(0, count-1)];
}

/**
 * Timers
 */
Action Timer_CheckTeam(Handle timer, int client)
{
    int team = GetClientTeam(client);
    if (team == TEAM_T && client != g_iMike)
        ChangeClientTeam(client, TEAM_CT);
    //else if (g_iGameState == 2 && team == TEAM_CT && client != g_iMike)
    //    ChangeClientTeam(client, TEAM_T);

    if (team == TEAM_CT && (g_iGameState == STATE_PREP || g_iGameState == STATE_END) && !IsPlayerAlive(client))
        CS_RespawnPlayer(client);

    return Plugin_Stop;
}

Action Timer_PrepareGame(Handle timer)
{
    if (g_iSetupTimer % 10 == 0 && g_iSetupTimer != 0)
        PrintToChatAll("Mike Myers will be chosen in %i seconds!", g_iSetupTimer);

    if (g_iSetupTimer <= 15 && g_iSetupTimer != 0)
        PrintHintTextToAll("Mike Myers will be chosen in\n%i seconds", g_iSetupTimer);
    else if (g_iSetupTimer == 0)
        PrintHintTextToAll("");

    if (g_iSetupTimer == 0) {
        do
        {
            g_iMike = GetRandomClient();
        }
        while(g_iMike == -1);

        g_cvIgnoreRoundWinCondition.SetBool(true, false, false);
        ChangeClientTeam(g_iMike, TEAM_T);
        CS_RespawnPlayer(g_iMike);
        g_cvIgnoreRoundWinCondition.SetBool(false, false, false);

        //g_hEndGameTimer = CreateTimer(1.0, Timer_EndGame, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
        //g_hAmmoTimer = CreateTimer(60.0, Timer_ReplenishAmmo, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

        g_hPrepareGameTimer = INVALID_HANDLE;
        g_iGameState = STATE_ACTIVE;
        g_iSetupTimer = g_cvSetupTimer.IntValue;

        return Plugin_Stop;
    }
    else
        g_iSetupTimer--;
    return Plugin_Continue;
}

Action Timer_RespawnPlayer(Handle timer, int client)
{
    if (IsValidClient(client))
        CS_RespawnPlayer(client);

    return Plugin_Stop;
}

Action Timer_RestoreSpeed(Handle timer, int client)
{
    SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);

    g_hSlowDownTimer = INVALID_HANDLE;

    return Plugin_Stop;
}

/**
 * Plugin Commands
 */
Action Command_GameState(int client, int args)
{
    PrintToChat(client, "[MM] Current GameState: %i", g_iGameState);

    return Plugin_Handled;
}

Action Command_Respawn(int client, int args)
{
    if (args > 1) {
        ReplyToCommand(client, "Invalid amount of arguments.");

        return Plugin_Handled;
    }

    char cTarget[64];
    GetCmdArg(1, cTarget, sizeof(cTarget));
    int target = FindTarget(client, cTarget, false, false);

    CS_RespawnPlayer(target);

    return Plugin_Handled;
}