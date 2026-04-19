#include <sourcemod>
#include <sdktools>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define GAMECONF "norespawn.games"

ConVar cvObjectiveRespawns;
ConVar cvSurvivalRespawns;

#define PLUGIN_DESCRIPTION "Toggle player respawning in objective mode and survival"
#define PLUGIN_VERSION "2.0.0"

public Plugin myinfo =
{
	name		= "No Respawning",
	author		= "Dysphie",
	description = PLUGIN_DESCRIPTION,
	version		= PLUGIN_VERSION,
	url			= ""
};

#define STATE_NMS_WARMUP 1

bool g_GameRulesPropsAvailable;

public void OnPluginStart()
{
	GameData gamedata = new GameData(GAMECONF);
	if (!gamedata)
		SetFailState("Failed to get gamedata: " ... GAMECONF);

	g_GameRulesPropsAvailable = GetFeatureStatus(FeatureType_Native, "GameRules_GetProp") == FeatureStatus_Available;

	RegDetour(gamedata, "CNMRiH_GameRules::RespawnDeadPlayers", CNMRiH_GameRules__RespawnDeadPlayers, Hook_Pre);
	RegDetour(gamedata, "COverlord_Wave_Controller::SpawnNewPlayers", COverlord_Wave_Controller__SpawnNewPlayers, Hook_Pre);
	RegDetour(gamedata, "CNMRiH_WaveGameRules::CouldJoinServerAndSpawn", CNMRiH_WaveGameRules__CouldJoinServerAndSpawn, Hook_Pre);
	RegDetour(gamedata, "CNMRiH_WaveGameRules::FPlayerCanRespawn", CNMRiH_WaveGameRules__FPlayerCanRespawn, Hook_Pre);
	delete gamedata;

	CreateConVar("norespawn_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION,
    	FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	cvObjectiveRespawns = CreateConVar("sm_allow_nmo_respawns", "0", "Allow players to respawn in objective mode");
	cvSurvivalRespawns = CreateConVar("sm_allow_nms_respawns", "0", "Allow players to respawn in survival mode");

	// Save to and read convars from cfg/sourcemod
	AutoExecConfig(true, "norespawn");
}

// This is continuously called in NMS
// Returning false prevents dead players from respawning on resupply waves
MRESReturn CNMRiH_WaveGameRules__FPlayerCanRespawn(DHookReturn ret)
{
	if (!cvSurvivalRespawns.BoolValue)
	{
		// Don't eat the function during warmup or the player will be stuck in spec
		if (g_GameRulesPropsAvailable && GameRules_GetProp("_roundState") == STATE_NMS_WARMUP) {
			return MRES_Ignored;
		}

		ret.Value = false;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

// This is continuously called in NMS. The return value defines
// whether "spawning:active" should be appended to the server tags
MRESReturn CNMRiH_WaveGameRules__CouldJoinServerAndSpawn(DHookReturn ret)
{
	if (!cvSurvivalRespawns.BoolValue)
	{
		ret.Value = false;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

// This is called at the start of NMS waves
// Returning false prevents newjoiners from respawning
MRESReturn COverlord_Wave_Controller__SpawnNewPlayers()
{
	return MRES_Supercede;
}

// This is called at the start of NMS waves and when "RespawnPlayers" inputs are sent to spawnpoints
// Returning false prevents dead players from respawning
MRESReturn CNMRiH_GameRules__RespawnDeadPlayers()
{
	if ((IsGamemodeSurvival() && !cvSurvivalRespawns.BoolValue) || !cvObjectiveRespawns.BoolValue)
	{
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

bool IsGamemodeSurvival()
{
	char mapName[5];
	GetCurrentMap(mapName, sizeof(mapName));
	return StrEqual(mapName, "nms_", false);
}

void RegDetour(GameData gamedata, const char[] name, DHookCallback callback, HookMode mode = Hook_Pre)
{
	DynamicDetour detour = DynamicDetour.FromConf(gamedata, name);
	if (!detour) {
		SetFailState("Failed to detour %s. Plugin needs an update", name);
	}

	detour.Enable(mode, callback);
	delete detour;
}