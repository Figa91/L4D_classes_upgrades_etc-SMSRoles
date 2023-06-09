#define PLUGIN_VERSION 		"1.2"

/*=======================================================================================
	Plugin Info:

*	Name	:	[L4D & L4D2] Ammo Pile Spawner
*	Author	:	SilverShot
*	Descrp	:	Spawns ammo piles.
*	Link	:	http://forums.alliedmods.net/showthread.php?t=221111

========================================================================================
	Change Log:

1.2 (20-Jul-2013)
	- Fixed a bug which broke spawning some ammo piles.

1.1 (19-Jul-2013)
	- Added command "sm_ammo_spawn_clear" to remove ammo piles spawned by this plugin from the map.
	- Changed command "sm_ammo_spawn_kill" to "sm_ammo_spawn_wipe"
	- Removed Sort_Random workaround, plugin requires SourceMod version 1.4.7 or higher.

1.0 (18-Jul-2013)
	- Initial release.

========================================================================================
	Thanks:

	This plugin was made using source code from the following plugins.
	If I have used your code and not credited you, please let me know.

*	"Zuko & McFlurry" for "[L4D2] Weapon/Zombie Spawner" - Modified SetTeleportEndPoint function.
	http://forums.alliedmods.net/showthread.php?t=109659

======================================================================================*/

#pragma semicolon 			1

#include <sourcemod>
#include <sdktools>

#define CVAR_FLAGS			FCVAR_PLUGIN|FCVAR_NOTIFY
#define CHAT_TAG			"\x04[\x05AmmoPile\x04] \x01"
#define CONFIG_SPAWNS		"data/l4d_ammo_spawn.cfg"
#define MAX_SPAWNS			2

#define MODEL_AMMO_L4D			"models/props_unique/spawn_apartment/coffeeammo.mdl"
#define MODEL_AMMO_L4D1			"models/props/terror/Ammo_Can.mdl"
#define MODEL_AMMO_L4D2			"models/props/terror/ammo_stack.mdl"
#define MODEL_AMMO_L4D3			"models/props/de_prodigy/ammo_can_02.mdl"
#define SOUND_COMMON			"physics/concrete/concrete_break3.wav"
#define SOUND_COMMON2			"items/itempickup.wav"

static	Handle:g_hCvarMPGameMode, Handle:g_hCvarModes, Handle:g_hCvarModesOff, Handle:g_hCvarModesTog, Handle:g_hCvarAllow,
		Handle:g_hCvarGlow, Handle:g_hCvarGlowCol, Handle:g_hCvarRandom,
		bool:g_bCvarAllow, g_iCvarGlow, g_iCvarGlowCol, g_iCvarRandom,
		Handle:g_hMenuAng, Handle:g_hMenuPos, bool:g_bLeft4Dead2, bool:g_bLoaded, g_iPlayerSpawn, g_iRoundStart,
		g_iSpawnCount, g_iSpawns[MAX_SPAWNS][3];
		
new parenting[MAXPLAYERS+1];



// ====================================================================================================
//					PLUGIN INFO / START / END
// ====================================================================================================
public Plugin:myinfo =
{
	name = "[L4D2] Ammo Pile Spawner",
	author = "SilverShot",
	description = "Spawns ammo piles.",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=221111"
}

new bool:CheckAssault[MAXPLAYERS + 1] = false;
new bool:b_ExpertDifficulty;
new AmmoSpawnCounter;
new Handle:h_Difficulty;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	decl String:sGameName[12];
	GetGameFolderName(sGameName, sizeof(sGameName));
	if( strcmp(sGameName, "left4dead", false) == 0 ) g_bLeft4Dead2 = false;
	else if( strcmp(sGameName, "left4dead2", false) == 0 ) g_bLeft4Dead2 = true;
	else
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public OnPluginStart()
{
	g_hCvarAllow =		CreateConVar(	"l4d_ammo_spawn_allow",			"1",			"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarGlow =		CreateConVar(	"l4d_ammo_spawn_glow",			"0",			"0=Off, Sets the max range at which the ammo pile glows.", CVAR_FLAGS );
	g_hCvarGlowCol =	CreateConVar(	"l4d_ammo_spawn_glow_color",	"255 0 0",		"0=Default glow color. Three values between 0-255 separated by spaces. RGB: Red Green Blue.", CVAR_FLAGS );
	g_hCvarModes =		CreateConVar(	"l4d_ammo_spawn_modes",			"",				"Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).", CVAR_FLAGS );
	g_hCvarModesOff =	CreateConVar(	"l4d_ammo_spawn_modes_off",		"",				"Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).", CVAR_FLAGS );
	g_hCvarModesTog =	CreateConVar(	"l4d_ammo_spawn_modes_tog",		"0",			"Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", CVAR_FLAGS );
	g_hCvarRandom =		CreateConVar(	"l4d_ammo_spawn_random",		"-1",			"-1=All, 0=None. Otherwise randomly select this many ammo piles to spawn from the maps confg.", CVAR_FLAGS );
	CreateConVar(						"l4d_ammo_spawn_version",		PLUGIN_VERSION, "Ammo Pile Spawner plugin version.", CVAR_FLAGS|FCVAR_REPLICATED|FCVAR_DONTRECORD);
	AutoExecConfig(true,				"l4d_ammo_spawn");

	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	HookConVarChange(g_hCvarMPGameMode,		ConVarChanged_Allow);
	HookConVarChange(g_hCvarAllow,			ConVarChanged_Allow);
	HookConVarChange(g_hCvarModes,			ConVarChanged_Allow);
	HookConVarChange(g_hCvarModesOff,		ConVarChanged_Allow);
	HookConVarChange(g_hCvarModesTog,		ConVarChanged_Allow);
	HookConVarChange(g_hCvarRandom,			ConVarChanged_Cvars);
	HookEvent("player_death", event_PlayerDeath);
	//HookEvent("round_end", round_end);
	HookEvent("round_start", Event_RoundRest);
	HookEvent("map_transition", Event_RoundRest, EventHookMode_Pre);
	HookEvent("finale_win", Event_RoundRest);
	HookEvent("mission_lost", Event_RoundRest);
	HookEvent("player_bot_replace", Event_BotReplacedPlayer);
	HookEvent("bot_player_replace", bot_player_replace );//игрок заменил бота.

	RegAdminCmd("sm_ammo_spawn",			CmdSpawnerTemp,		ADMFLAG_ROOT, 	"Spawns a temporary ammo pile at your crosshair. Usage: sm_ammo_spawn [1=L4D model, 2=L4D2 model, 2=L4D2 Crate]");
	RegAdminCmd("sm_ammo_spawn_save",		CmdSpawnerSave,		ADMFLAG_ROOT, 	"Spawns an ammo pile at your crosshair and saves to config. Usage: sm_ammo_spawn_save [1=L4D model, 2=L4D2 model, 2=L4D2 Crate]");
	RegAdminCmd("sm_ammo_spawn_del",		CmdSpawnerDel,		ADMFLAG_ROOT,	"Removes the ammo pile you are pointing at and deletes from the config if saved.");
	RegAdminCmd("sm_ammo_spawn_clear",		CmdSpawnerClear,	ADMFLAG_ROOT, 	"Removes all ammo piles spawned by this plugin from the current map.");
	RegAdminCmd("sm_ammo_spawn_wipe",		CmdSpawnerWipe,		ADMFLAG_ROOT, 	"Removes all ammo piles from the current map and deletes them from the config.");
	RegAdminCmd("sm_ammo_spawn_glow",		CmdSpawnerGlow,		ADMFLAG_ROOT, 	"Toggle to enable glow on all ammo piles to see where they are placed.");
	RegAdminCmd("sm_ammo_spawn_list",		CmdSpawnerList,		ADMFLAG_ROOT, 	"Display a list ammo pile positions and the total number of.");
	RegAdminCmd("sm_ammo_spawn_tele",		CmdSpawnerTele,		ADMFLAG_ROOT, 	"Teleport to an ammo pile (Usage: sm_ammo_spawn_tele <index: 1 to MAX_SPAWNS (32)>).");
	RegAdminCmd("sm_ammo_spawn_ang",		CmdSpawnerAng,		ADMFLAG_ROOT, 	"Displays a menu to adjust the ammo pile angles your crosshair is over.");
	RegAdminCmd("sm_ammo_spawn_pos",		CmdSpawnerPos,		ADMFLAG_ROOT, 	"Displays a menu to adjust the ammo pile origin your crosshair is over.");
	//RegConsoleCmd("sm_ammos", OnBotKillPlayer, "Spawns a temporary ammo.");
	RegConsoleCmd("sm_ammo", SpawnAmmoForAll, "Spawns a temporary ammo.");
	h_Difficulty = FindConVar("z_difficulty");
	HookConVarChange(h_Difficulty, ConVarChange_GameDifficulty);
	
	LoadTranslations("ammo_spawn.phrases");
}

public OnPluginEnd()
{
	ResetPlugin();
}

public OnMapStart()
{
	//g_BeamSprite = PrecacheModel("materials/sprites/glow08.vmt");
	//g_HaloSprite = PrecacheModel("materials/sprites/glow08.vmt");
	//g_SteamSprite = PrecacheModel("materials/sprites/glow08.vmt");
	//g_LightningSprite = PrecacheModel("sprites/lgtning.vmt");
	PrecacheModel(MODEL_AMMO_L4D, true);
	PrecacheModel(MODEL_AMMO_L4D1, true);
	PrecacheModel("models/props_equipment/sleeping_bag3.mdl", true);
	if( g_bLeft4Dead2 ) PrecacheModel(MODEL_AMMO_L4D2, true);
	if( g_bLeft4Dead2 ) PrecacheModel(MODEL_AMMO_L4D3, true);
	AmmoSpawnCounter = 1;
	PrecacheSound (SOUND_COMMON, true);
	PrecacheSound (SOUND_COMMON2, true);
	PrecacheSound ("player/jumplanding.wav", true);
}

public OnMapEnd()
{
	ResetPlugin(false);
}

GetColor(Handle:cvar)
{
	decl String:sTemp[12], String:sColors[3][4];
	GetConVarString(cvar, sTemp, sizeof(sTemp));
	ExplodeString(sTemp, " ", sColors, 3, 4);

	new color;
	color = StringToInt(sColors[0]);
	color += 256 * StringToInt(sColors[1]);
	color += 65536 * StringToInt(sColors[2]);
	return color;
}

public Action:round_start(Handle:event, const String:name[], bool:dontBroadcast)
{
	AmmoSpawnCounter = 1;
}
// ====================================================================================================
//					CVARS
// ====================================================================================================
public OnConfigsExecuted()
	IsAllowed();

public ConVarChanged_Cvars(Handle:convar, const String:oldValue[], const String:newValue[])
	GetCvars();

public ConVarChanged_Allow(Handle:convar, const String:oldValue[], const String:newValue[])
	IsAllowed();

GetCvars()
{
	g_iCvarGlow = GetConVarInt(g_hCvarGlow);
	g_iCvarGlowCol = GetColor(g_hCvarGlowCol);
	g_iCvarRandom = GetConVarInt(g_hCvarRandom);
}

IsAllowed()
{
	new bool:bCvarAllow = GetConVarBool(g_hCvarAllow);
	new bool:bAllowMode = IsAllowedGameMode();
	GetCvars();

	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true )
	{
		LoadSpawns();
		g_bCvarAllow = true;
		HookEvent("player_spawn",		Event_PlayerSpawn,	EventHookMode_PostNoCopy);
		HookEvent("round_start",		Event_RoundStart,	EventHookMode_PostNoCopy);
		HookEvent("mission_lost",			Event_RoundEnd,		EventHookMode_PostNoCopy);
	}

	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false) )
	{
		ResetPlugin();
		g_bCvarAllow = false;
		UnhookEvent("player_spawn",		Event_PlayerSpawn,	EventHookMode_PostNoCopy);
		UnhookEvent("round_start",		Event_RoundStart,	EventHookMode_PostNoCopy);
		UnhookEvent("mission_lost",		Event_RoundEnd,		EventHookMode_PostNoCopy);
	}
}

static g_iCurrentMode;

bool:IsAllowedGameMode()
{
	if( g_hCvarMPGameMode == INVALID_HANDLE )
		return false;

	new iCvarModesTog = GetConVarInt(g_hCvarModesTog);
	if( iCvarModesTog != 0 )
	{
		g_iCurrentMode = 0;

		new entity = CreateEntityByName("info_gamemode");
		DispatchSpawn(entity);
		HookSingleEntityOutput(entity, "OnCoop", OnGamemode, true);
		HookSingleEntityOutput(entity, "OnSurvival", OnGamemode, true);
		HookSingleEntityOutput(entity, "OnVersus", OnGamemode, true);
		HookSingleEntityOutput(entity, "OnScavenge", OnGamemode, true);
		AcceptEntityInput(entity, "PostSpawnActivate");
		AcceptEntityInput(entity, "Kill");

		if( g_iCurrentMode == 0 )
			return false;

		if( !(iCvarModesTog & g_iCurrentMode) )
			return false;
	}

	decl String:sGameModes[64], String:sGameMode[64];
	GetConVarString(g_hCvarMPGameMode, sGameMode, sizeof(sGameMode));
	Format(sGameMode, sizeof(sGameMode), ",%s,", sGameMode);

	GetConVarString(g_hCvarModes, sGameModes, sizeof(sGameModes));
	if( strcmp(sGameModes, "") )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) == -1 )
			return false;
	}

	GetConVarString(g_hCvarModesOff, sGameModes, sizeof(sGameModes));
	if( strcmp(sGameModes, "") )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) != -1 )
			return false;
	}

	return true;
}

public OnGamemode(const String:output[], caller, activator, Float:delay)
{
	if( strcmp(output, "OnCoop") == 0 )
		g_iCurrentMode = 1;
	else if( strcmp(output, "OnSurvival") == 0 )
		g_iCurrentMode = 2;
	else if( strcmp(output, "OnVersus") == 0 )
		g_iCurrentMode = 4;
	else if( strcmp(output, "OnScavenge") == 0 )
		g_iCurrentMode = 8;
}



// ====================================================================================================
//					EVENTS
// ====================================================================================================
public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	ResetPlugin(false);
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if( g_iPlayerSpawn == 1 && g_iRoundStart == 0 )
		CreateTimer(1.0, tmrStart);
	g_iRoundStart = 1;
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if( g_iPlayerSpawn == 0 && g_iRoundStart == 1 )
		CreateTimer(1.0, tmrStart);
	g_iPlayerSpawn = 1;
}

public Action:tmrStart(Handle:timer)
{
	ResetPlugin();
	LoadSpawns();
}



// ====================================================================================================
//					LOAD SPAWNS
// ====================================================================================================
LoadSpawns()
{
	if( g_bLoaded || g_iCvarRandom == 0 ) return;
	g_bLoaded = true;

	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", CONFIG_SPAWNS);
	if( !FileExists(sPath) )
		return;

	// Load config
	new Handle:hFile = CreateKeyValues("spawns");
	if( !FileToKeyValues(hFile, sPath) )
	{
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return;
	}

	// Check for current map in the config
	decl String:sMap[64];
	GetCurrentMap(sMap, 64);

	if( !KvJumpToKey(hFile, sMap) )
	{
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return;
	}

	// Retrieve how many ammo piles to display
	new iCount = KvGetNum(hFile, "num", 0);
	if( iCount == 0 )
	{
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return;
	}

	// Spawn only a select few ammo piles?
	new iIndexes[MAX_SPAWNS+1];
	if( iCount > MAX_SPAWNS )
		iCount = MAX_SPAWNS;


	// Spawn saved ammo piles or create random
	new iRandom = g_iCvarRandom;
	if( iRandom == -1 || iRandom > iCount)
		iRandom = iCount;
	if( iRandom != -1 )
	{
		for( new i = 1; i <= iCount; i++ )
			iIndexes[i-1] = i;

		SortIntegers(iIndexes, iCount, Sort_Random);
		iCount = iRandom;
	}

	// Get the ammo pile origins and spawn
	decl String:sTemp[10], Float:vPos[3], Float:vAng[3];
	new index, iMod;
	for( new i = 1; i <= iCount; i++ )
	{
		if( iRandom != -1 ) index = iIndexes[i-1];
		else index = i;

		IntToString(index, sTemp, sizeof(sTemp));

		if( KvJumpToKey(hFile, sTemp) )
		{
			KvGetVector(hFile, "ang", vAng);
			KvGetVector(hFile, "pos", vPos);
			iMod = KvGetNum(hFile, "mod");

			if( vPos[0] == 0.0 && vPos[0] == 0.0 && vPos[0] == 0.0 ) // Should never happen.
				LogError("Error: 0,0,0 origin. Iteration=%d. Index=%d. Random=%d. Count=%d.", i, index, iRandom, iCount);
			else
				CreateSpawn(vPos, vAng, index, iMod);
			KvGoBack(hFile);
		}
	}
	CloseHandle(hFile);
	hFile = INVALID_HANDLE;
}



// ====================================================================================================
//					CREATE SPAWN
// ====================================================================================================
CreateSpawn(const Float:vOrigin[3], const Float:vAngles[3], index = 0, model = 0)
{
	if( g_iSpawnCount >= MAX_SPAWNS )
		return;

	new iSpawnIndex = -1;
	for( new i = 0; i < MAX_SPAWNS; i++ )
	{
		if( g_iSpawns[i][0] == 0 )
		{
			iSpawnIndex = i;
			break;
		}
	}

	if( iSpawnIndex == -1 )
		return;

	new entity = CreateEntityByName("weapon_ammo_spawn");
	if( entity == -1 )
		ThrowError("Failed to create ammo pile.");

	g_iSpawns[iSpawnIndex][0] = EntIndexToEntRef(entity);
	g_iSpawns[iSpawnIndex][1] = index;
	g_iSpawns[iSpawnIndex][2] = CreateButton(entity);

	if( !g_bLeft4Dead2 ) model = 1;
	DispatchSpawn(entity);
	if( model == 2 )		SetEntityModel(entity, MODEL_AMMO_L4D2);
	else if( model == 3 )	SetEntityModel(entity, MODEL_AMMO_L4D3);
	else					SetEntityModel(entity, MODEL_AMMO_L4D);
	TeleportEntity(entity, vOrigin, vAngles, NULL_VECTOR);

	if( g_iCvarGlow )
	{
		SetEntProp(entity, Prop_Send, "m_nGlowRange", g_iCvarGlow);
		SetEntProp(entity, Prop_Send, "m_iGlowType", 1);
		SetEntProp(entity, Prop_Send, "m_glowColorOverride", g_iCvarGlowCol);
		AcceptEntityInput(entity, "StartGlowing");
	}
	GreenSmoke(entity);
	g_iSpawnCount++;
	BagColorChanger();
}

public GreenSmoke(entity)
{
	new new_entity = CreateEntityByName("env_smokestack");
	new Float:kit_location[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", kit_location);
	DispatchKeyValue(new_entity, "BaseSpread", "5");
	DispatchKeyValue(new_entity, "SpreadSpeed", "1");
	DispatchKeyValue(new_entity, "Speed", "30");
	DispatchKeyValue(new_entity, "StartSize", "10");
	DispatchKeyValue(new_entity, "EndSize", "1");
	DispatchKeyValue(new_entity, "Rate", "20");
	DispatchKeyValue(new_entity, "JetLength", "80");
	DispatchKeyValue(new_entity, "SmokeMaterial", "particle/SmokeStack.vmt");
	DispatchKeyValue(new_entity, "twist", "1");
	DispatchKeyValue(new_entity, "rendercolor", "0 255 0");
	DispatchKeyValue(new_entity, "renderamt", "255");
	DispatchKeyValue(new_entity, "roll", "0");
	DispatchKeyValue(new_entity, "InitialState", "1");
	DispatchKeyValue(new_entity, "angles", "0 0 0");
	DispatchKeyValue(new_entity, "WindSpeed", "1");
	DispatchKeyValue(new_entity, "WindAngle", "1");
	TeleportEntity(new_entity, kit_location, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(new_entity);
	AcceptEntityInput(new_entity, "TurnOn");
	SetVariantString("!activator");
	AcceptEntityInput(new_entity, "SetParent", entity, new_entity);
	SetVariantString("OnUser1 !self:TurnOff::10.0:-1");
	AcceptEntityInput(new_entity, "AddOutput");
	AcceptEntityInput(new_entity, "FireUser1");
	
	new iEnt = CreateEntityByName("light_dynamic");  
	DispatchKeyValue(iEnt, "_light", "0 255 0");  
	DispatchKeyValue(iEnt, "brightness", "0");  
	DispatchKeyValueFloat(iEnt, "spotlight_radius", 32.0);  
	DispatchKeyValueFloat(iEnt, "distance", 100.0);  
	DispatchKeyValue(iEnt, "style", "6");
	DispatchSpawn(iEnt);
	TeleportEntity(iEnt, kit_location, NULL_VECTOR, NULL_VECTOR);
	SetVariantString("!activator");
	new String:szTarget[32];
	Format(szTarget, sizeof(szTarget), "lighthealthkit_%d", new_entity);
	DispatchKeyValue(new_entity, "targetname", szTarget);
	SetVariantString(szTarget);
	AcceptEntityInput(iEnt, "SetParent");
	AcceptEntityInput(iEnt, "TurnOn");
	SetVariantString("OnUser1 !self:TurnOff::10.0:-1");
	AcceptEntityInput(iEnt, "AddOutput");
	AcceptEntityInput(iEnt, "FireUser1");
}

// ====================================================================================================
//					COMMANDS
// ====================================================================================================
//					sm_ammo_spawn
// ====================================================================================================

public ClientTakeAssault(client, args) 
{
	CheckAssault[client] = true;
	if (parenting[client]!=0) return;
	decl Float:VecOrigin[3], Float:VecAngles[3], Float:VecDirection[3];
	new index = CreateEntityByName ("prop_dynamic");
	if (index == -1)
	{
		ReplyToCommand(client, "[SM] Failed to create sleeping bag!");
		return;
	}
	SetEntityModel (index, "models/props_equipment/sleeping_bag3.mdl");
	DispatchSpawn(index);
	GetClientAbsOrigin(client, VecOrigin);
	GetClientEyeAngles(client, VecAngles);
	GetAngleVectors(VecAngles, VecDirection, NULL_VECTOR, NULL_VECTOR);
	VecOrigin[0] += VecDirection[0] * 32;
	VecOrigin[1] += VecDirection[1] * 32;
	VecOrigin[2] += VecDirection[2] * 1;   
	VecAngles[0] = 0.0;
	VecAngles[2] = 0.0;
	DispatchKeyValueVector(index, "Angles", VecAngles);
	TeleportEntity(index, VecOrigin, NULL_VECTOR, NULL_VECTOR);
	SetEntProp(index, Prop_Data, "m_CollisionGroup", 2);
	SetEntityRenderMode(index, RenderMode:3);
	//SetEntityRenderColor(index, 0, 0, 0, 255);
	decl String:sTemp[64];
	Format(sTemp, sizeof(sTemp), "mmg%d%d", index, client);
	DispatchKeyValue(client, "targetname", sTemp);
	SetVariantString(sTemp);
	AcceptEntityInput(index, "SetParent", index, index, 0);
	SetVariantString("eyes");
	AcceptEntityInput(index, "SetParentAttachment");
	VecOrigin[0]=-8.0;
	VecOrigin[1]=0.0;
	VecOrigin[2]=-16.0;
	VecAngles[0] = 90.0;
	VecAngles[1] = 0.0;
	VecAngles[2] = -180.0;
	TeleportEntity(index, VecOrigin, VecAngles, NULL_VECTOR);
	parenting[client]=EntIndexToEntRef(index);
	BagColorSwitch(client);
}

public ClientDropAssault(client, args) 
{
	CheckAssault[client] = false;
	
	if (parenting[client] !=0)
	{
		if(IsValidEntRef(parenting[client]))
		{
			AcceptEntityInput(parenting[client], "kill");
			DropBag(client);
		}
	}
	parenting[client]=0;
}

public event_PlayerDeath(Handle:event, const String:name[], bool:Broadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (CheckAssault[client])
	{
		CheckAssault[client] = false;
		if (parenting[client] !=0)
		{
			if(IsValidEntRef(parenting[client]))
			{
				AcceptEntityInput(parenting[client], "kill");
				DropBag(client);
			}
			parenting[client]=0;
		}
	}
}
DropBag(client)
{
	new index;
	decl Float:VecOrigin[3], Float:VecAngles[3], Float:VecDirection[3];
	index = CreateEntityByName ("prop_dynamic");
	if (index == -1)
	{
		ReplyToCommand(client, "[SM] Failed to create minigun!");
		return;
	}
	SetEntityModel (index, "models/props_equipment/sleeping_bag3.mdl");

	DispatchKeyValueFloat (index, "MaxPitch", 360.00);
	DispatchKeyValueFloat (index, "MinPitch", -360.00);
	DispatchKeyValueFloat (index, "MaxYaw", 90.00);
	SetEntProp(index, Prop_Data, "m_CollisionGroup", 2);
	DispatchSpawn(index);
	GetClientAbsOrigin(client, VecOrigin);
	GetClientEyeAngles(client, VecAngles);
	GetAngleVectors(VecAngles, VecDirection, NULL_VECTOR, NULL_VECTOR);
	VecOrigin[0] += VecDirection[0] * 40;
	VecOrigin[1] += VecDirection[1] * 40;
	VecOrigin[2] += VecDirection[2] * 1;   
	VecAngles[2] = GetRandomFloat(-80.0, -65.0);
	VecAngles[0] = GetRandomFloat(-75.0, 75.0);
	DispatchKeyValueVector(index, "Angles", VecAngles);
	DispatchSpawn(index);
	TeleportEntity(index, VecOrigin, NULL_VECTOR, NULL_VECTOR);
	new Float:pos2[3];
	
	TE_SetupDust(	VecOrigin,//pos - начальная позиция
					pos2,//pos - позиция направления (у нас на месте)
					200.0,//50.0 - размер облака
					5.5);//0.5 - скорость частиц в облаке.		  
	TE_SendToAll();
	EmitAmbientSound("player/jumplanding.wav",//назвать имя звукового файла в соответствии с папкой "sounds". 
                    VecOrigin,//координаты Происхождение звука.. откуда звук будет идти.. 
                    index,//индекс Entity ..чтоб звук прицепить к Entity.SOUND_FROM_WORLD
                    75,//Уровень громкости (от 0 до 255). 
                    SND_NOFLAGS,//Звуковые флаги .. думаю можно зделать так чтоб звук слышали Опр люди 
                    SNDVOL_NORMAL,//Объем звука (от 0.0 до 1.0). 
                    SNDPITCH_NORMAL,//Шаг Pitch Звука(от 0 до 255). 
                    0.0//Задержка воспроизведения. ЕХО  
                    );
	
	return;
}

public Action:SpawnAmmoForAll(client, args)
{
	if (client == 0 || !IsPlayerAlive(client) || GetClientTeam(client) != 2)
		return;
	if (CheckAssault[client])
		CmdSpawnerTemp(client, args);
	else PrintToChat(client, "%t", "OnlyAssault");
	//else PrintToChat(client, "\x05Зелёный эльф: \x04Доступно только \x03Штурмовику\x04.");
}

public Action:CmdSpawnerTemp(client, args)
{
	if( !client )
	{
		ReplyToCommand(client, "[Ammo Pile Spawner] Commands may only be used in-game on a dedicated server..");
		return Plugin_Handled;
	}
	else if( g_iSpawnCount >= MAX_SPAWNS )
	{
		//PrintToChat(client, "%sError: Cannot add anymore ammo piles. Used: (\x05%d/%d\x01).", CHAT_TAG, g_iSpawnCount, MAX_SPAWNS);
		PrintToChat(client, "%t", "AmmoUsed", g_iSpawnCount, MAX_SPAWNS);
		return Plugin_Handled;
	}

	new Float:vPos[3], Float:vAng[3];
	if( !SetTeleportEndPoint(client, vPos, vAng) )
	{
		PrintToChat(client, "%sCannot place ammo pile, please try again.", CHAT_TAG);
		return Plugin_Handled;
	}

	new iMod = 0;
	if( args == 1 )
	{
		decl String:sNum[8];
		GetCmdArg(1, sNum, sizeof(sNum));
		iMod = StringToInt(sNum);
	}

	CreateSpawn(vPos, vAng, 0, iMod);
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_ammo_spawn_save
// ====================================================================================================
public Action:CmdSpawnerSave(client, args)
{
	if( !client )
	{
		ReplyToCommand(client, "[Ammo Pile Spawner] Commands may only be used in-game on a dedicated server..");
		return Plugin_Handled;
	}
	else if( g_iSpawnCount >= MAX_SPAWNS )
	{
		//PrintToChat(client, "%sError: Cannot add anymore ammo piles. Used: (\x05%d/%d\x01).", CHAT_TAG, g_iSpawnCount, MAX_SPAWNS);
		PrintToChat(client, "%t", "AmmoUsed", g_iSpawnCount, MAX_SPAWNS);
		return Plugin_Handled;
	}

	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", CONFIG_SPAWNS);
	if( !FileExists(sPath) )
	{
		new Handle:hCfg = OpenFile(sPath, "w");
		WriteFileLine(hCfg, "");
		CloseHandle(hCfg);
		hCfg = INVALID_HANDLE;
	}

	// Load config
	new Handle:hFile = CreateKeyValues("spawns");
	if( !FileToKeyValues(hFile, sPath) )
	{
		PrintToChat(client, "%sError: Cannot read the ammo pile config, assuming empty file. (\x05%s\x01).", CHAT_TAG, sPath);
	}

	// Check for current map in the config
	decl String:sMap[64];
	GetCurrentMap(sMap, 64);
	if( !KvJumpToKey(hFile, sMap, true) )
	{
		PrintToChat(client, "%sError: Failed to add map to ammo pile spawn config.", CHAT_TAG);
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return Plugin_Handled;
	}

	// Retrieve how many ammo piles are saved
	new iCount = KvGetNum(hFile, "num", 0);
	if( iCount >= MAX_SPAWNS )
	{
		//PrintToChat(client, "%sError: Cannot add anymore ammo piles. Used: (\x05%d/%d\x01).", CHAT_TAG, iCount, MAX_SPAWNS);
		PrintToChat(client, "%t", "AmmoUsed", g_iSpawnCount, MAX_SPAWNS);
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return Plugin_Handled;
	}

	// Save count
	iCount++;
	KvSetNum(hFile, "num", iCount);

	decl String:sTemp[10];

	IntToString(iCount, sTemp, sizeof(sTemp));

	if( KvJumpToKey(hFile, sTemp, true) )
	{
		new Float:vPos[3], Float:vAng[3];
		// Set player position as ammo pile spawn location
		if( !SetTeleportEndPoint(client, vPos, vAng) )
		{
			PrintToChat(client, "%sCannot place ammo pile, please try again.", CHAT_TAG);
			CloseHandle(hFile);
			hFile = INVALID_HANDLE;
			return Plugin_Handled;
		}

		new iMod = 0;
		if( args == 1 )
		{
			decl String:sNum[8];
			GetCmdArg(1, sNum, sizeof(sNum));
			iMod = StringToInt(sNum);
		}

		// Save angle / origin
		KvSetVector(hFile, "ang", vAng);
		KvSetVector(hFile, "pos", vPos);
		KvSetNum(hFile, "mod", iMod);

		CreateSpawn(vPos, vAng, iCount, iMod);

		// Save cfg
		KvRewind(hFile);
		KeyValuesToFile(hFile, sPath);

		PrintToChat(client, "%s(\x05%d/%d\x01) - Saved at pos:[\x05%f %f %f\x01] ang:[\x05%f %f %f\x01]", CHAT_TAG, iCount, MAX_SPAWNS, vPos[0], vPos[1], vPos[2], vAng[0], vAng[1], vAng[2]);
	}
	else PrintToChat(client, "%s(\x05%d/%d\x01) - Failed to save ammo pile.", CHAT_TAG, iCount, MAX_SPAWNS);

	CloseHandle(hFile);
	hFile = INVALID_HANDLE;
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_ammo_spawn_del
// ====================================================================================================
public Action:CmdSpawnerDel(client, args)
{
	if( !g_bCvarAllow )
	{
		ReplyToCommand(client, "[Ammo Pile Spawner] Plugin turned off.");
		return Plugin_Handled;
	}

	if( !client )
	{
		ReplyToCommand(client, "[Ammo Pile Spawner] Commands may only be used in-game on a dedicated server..");
		return Plugin_Handled;
	}
	
	if(!CheckAssault[client]) return Plugin_Handled;

	new entity = GetClientAimTarget(client, false);
	if( entity == -1 ) return Plugin_Handled;
	entity = EntIndexToEntRef(entity);

	new cfgindex, index = -1;
	for( new i = 0; i < MAX_SPAWNS; i++ )
	{
		if( g_iSpawns[i][0] == entity )
		{
			index = i;
			break;
		}
	}

	if( index == -1 )
		return Plugin_Handled;

	cfgindex = g_iSpawns[index][1];
	if( cfgindex == 0 )
	{
		RemoveSpawn(index, true);
		return Plugin_Handled;
	}

	for( new i = 0; i < MAX_SPAWNS; i++ )
	{
		if( g_iSpawns[i][1] > cfgindex )
			g_iSpawns[i][1]--;
	}

	// Load config
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", CONFIG_SPAWNS);
	if( !FileExists(sPath) )
	{
		PrintToChat(client, "%sError: Cannot find the ammo pile config (\x05%s\x01).", CHAT_TAG, CONFIG_SPAWNS);
		return Plugin_Handled;
	}

	new Handle:hFile = CreateKeyValues("spawns");
	if( !FileToKeyValues(hFile, sPath) )
	{
		PrintToChat(client, "%sError: Cannot load the ammo pile config (\x05%s\x01).", CHAT_TAG, sPath);
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return Plugin_Handled;
	}

	// Check for current map in the config
	decl String:sMap[64];
	GetCurrentMap(sMap, 64);

	if( !KvJumpToKey(hFile, sMap) )
	{
		PrintToChat(client, "%sError: Current map not in the ammo pile config.", CHAT_TAG);
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return Plugin_Handled;
	}

	// Retrieve how many ammo piles
	new iCount = KvGetNum(hFile, "num", 0);
	if( iCount == 0 )
	{
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return Plugin_Handled;
	}

	new bool:bMove;
	decl String:sTemp[16];

	// Move the other entries down
	for( new i = cfgindex; i <= iCount; i++ )
	{
		IntToString(i, sTemp, sizeof(sTemp));

		if( KvJumpToKey(hFile, sTemp) )
		{
			if( !bMove )
			{
				bMove = true;
				KvDeleteThis(hFile);
				RemoveSpawn(index);
			}
			else
			{
				IntToString(i-1, sTemp, sizeof(sTemp));
				KvSetSectionName(hFile, sTemp);
			}
		}

		KvRewind(hFile);
		KvJumpToKey(hFile, sMap);
	}

	if( bMove )
	{
		iCount--;
		KvSetNum(hFile, "num", iCount);

		// Save to file
		KvRewind(hFile);
		KeyValuesToFile(hFile, sPath);

		PrintToChat(client, "%s(\x05%d/%d\x01) - ammo pile removed from config.", CHAT_TAG, iCount, MAX_SPAWNS);
	}
	else
		PrintToChat(client, "%s(\x05%d/%d\x01) - Failed to remove ammo pile from config.", CHAT_TAG, iCount, MAX_SPAWNS);

	CloseHandle(hFile);
	hFile = INVALID_HANDLE;
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_ammo_spawn_clear
// ====================================================================================================
public Action:CmdSpawnerClear(client, args)
{
	if( !client )
	{
		ReplyToCommand(client, "[Ammo Pile Spawner] Commands may only be used in-game on a dedicated server..");
		return Plugin_Handled;
	}

	ResetPlugin();

	PrintToChat(client, "%s(0/%d) - All ammo piles removed from the map.", CHAT_TAG, MAX_SPAWNS);
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_ammo_spawn_wipe
// ====================================================================================================
public Action:CmdSpawnerWipe(client, args)
{
	if( !client )
	{
		ReplyToCommand(client, "[Ammo Pile Spawner] Commands may only be used in-game on a dedicated server..");
		return Plugin_Handled;
	}

	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", CONFIG_SPAWNS);
	if( !FileExists(sPath) )
	{
		PrintToChat(client, "%sError: Cannot find the ammo pile config (\x05%s\x01).", CHAT_TAG, sPath);
		return Plugin_Handled;
	}

	// Load config
	new Handle:hFile = CreateKeyValues("spawns");
	if( !FileToKeyValues(hFile, sPath) )
	{
		PrintToChat(client, "%sError: Cannot load the ammo pile config (\x05%s\x01).", CHAT_TAG, sPath);
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return Plugin_Handled;
	}

	// Check for current map in the config
	decl String:sMap[64];
	GetCurrentMap(sMap, 64);

	if( !KvJumpToKey(hFile, sMap, false) )
	{
		PrintToChat(client, "%sError: Current map not in the ammo pile config.", CHAT_TAG);
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return Plugin_Handled;
	}

	KvDeleteThis(hFile);
	ResetPlugin();

	// Save to file
	KvRewind(hFile);
	KeyValuesToFile(hFile, sPath);
	CloseHandle(hFile);
	hFile = INVALID_HANDLE;
	PrintToChat(client, "%s(0/%d) - All ammo piles removed from config, add with \x05sm_ammo_spawn_save\x01.", CHAT_TAG, MAX_SPAWNS);
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_ammo_spawn_glow
// ====================================================================================================
public Action:CmdSpawnerGlow(client, args)
{
	static bool:glow;
	glow = !glow;
	PrintToChat(client, "%sGlow has been turned %s", CHAT_TAG, glow ? "on" : "off");

	VendorGlow(glow);
	return Plugin_Handled;
}

VendorGlow(glow)
{
	new ent;

	for( new i = 0; i < MAX_SPAWNS; i++ )
	{
		ent = g_iSpawns[i][0];
		if( IsValidEntRef(ent) )
		{
			SetEntProp(ent, Prop_Send, "m_iGlowType", 3);
			SetEntProp(ent, Prop_Send, "m_glowColorOverride", 65535);
			SetEntProp(ent, Prop_Send, "m_nGlowRange", glow ? 0 : 50);
			ChangeEdictState(ent, FindSendPropOffs("prop_dynamic", "m_nGlowRange"));
		}
	}
}

// ====================================================================================================
//					sm_ammo_spawn_list
// ====================================================================================================
public Action:CmdSpawnerList(client, args)
{
	decl Float:vPos[3];
	new count;
	for( new i = 0; i < MAX_SPAWNS; i++ )
	{
		if( IsValidEntRef(g_iSpawns[i][0]) )
		{
			count++;
			GetEntPropVector(g_iSpawns[i][0], Prop_Data, "m_vecOrigin", vPos);
			PrintToChat(client, "%s%d) %f %f %f", CHAT_TAG, i+1, vPos[0], vPos[1], vPos[2]);
		}
	}
	PrintToChat(client, "%sTotal: %d.", CHAT_TAG, count);
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_ammo_spawn_tele
// ====================================================================================================
public Action:CmdSpawnerTele(client, args)
{
	if( args == 1 )
	{
		decl String:arg[16];
		GetCmdArg(1, arg, 16);
		new index = StringToInt(arg) - 1;
		if( index > -1 && index < MAX_SPAWNS && IsValidEntRef(g_iSpawns[index][0]) )
		{
			decl Float:vPos[3];
			GetEntPropVector(g_iSpawns[index][0], Prop_Data, "m_vecOrigin", vPos);
			vPos[2] += 20.0;
			TeleportEntity(client, vPos, NULL_VECTOR, NULL_VECTOR);
			PrintToChat(client, "%sTeleported to %d.", CHAT_TAG, index + 1);
			return Plugin_Handled;
		}

		PrintToChat(client, "%sCould not find index for teleportation.", CHAT_TAG);
	}
	else
		PrintToChat(client, "%sUsage: sm_ammo_spawn_tele <index 1-%d>.", CHAT_TAG, MAX_SPAWNS);
	return Plugin_Handled;
}

// ====================================================================================================
//					MENU ANGLE
// ====================================================================================================
public Action:CmdSpawnerAng(client, args)
{
	ShowMenuAng(client);
	return Plugin_Handled;
}

ShowMenuAng(client)
{
	CreateMenus();
	DisplayMenu(g_hMenuAng, client, MENU_TIME_FOREVER);
}

public AngMenuHandler(Handle:menu, MenuAction:action, client, index)
{
	if( action == MenuAction_Select )
	{
		if( index == 6 )
			SaveData(client);
		else
			SetAngle(client, index);
		ShowMenuAng(client);
	}
}

SetAngle(client, index)
{
	new aim = GetClientAimTarget(client, false);
	if( aim != -1 )
	{
		new Float:vAng[3], entity;
		aim = EntIndexToEntRef(aim);

		for( new i = 0; i < MAX_SPAWNS; i++ )
		{
			entity = g_iSpawns[i][0];

			if( entity == aim  )
			{
				GetEntPropVector(entity, Prop_Send, "m_angRotation", vAng);

				if( index == 0 ) vAng[0] += 5.0;
				else if( index == 1 ) vAng[1] += 5.0;
				else if( index == 2 ) vAng[2] += 5.0;
				else if( index == 3 ) vAng[0] -= 5.0;
				else if( index == 4 ) vAng[1] -= 5.0;
				else if( index == 5 ) vAng[2] -= 5.0;

				TeleportEntity(entity, NULL_VECTOR, vAng, NULL_VECTOR);

				PrintToChat(client, "%sNew angles: %f %f %f", CHAT_TAG, vAng[0], vAng[1], vAng[2]);
				break;
			}
		}
	}
}

// ====================================================================================================
//					MENU ORIGIN
// ====================================================================================================
public Action:CmdSpawnerPos(client, args)
{
	ShowMenuPos(client);
	return Plugin_Handled;
}

ShowMenuPos(client)
{
	CreateMenus();
	DisplayMenu(g_hMenuPos, client, MENU_TIME_FOREVER);
}

public PosMenuHandler(Handle:menu, MenuAction:action, client, index)
{
	if( action == MenuAction_Select )
	{
		if( index == 6 )
			SaveData(client);
		else
			SetOrigin(client, index);
		ShowMenuPos(client);
	}
}

SetOrigin(client, index)
{
	new aim = GetClientAimTarget(client, false);
	if( aim != -1 )
	{
		new Float:vPos[3], entity;
		aim = EntIndexToEntRef(aim);

		for( new i = 0; i < MAX_SPAWNS; i++ )
		{
			entity = g_iSpawns[i][0];

			if( entity == aim  )
			{
				GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vPos);

				if( index == 0 ) vPos[0] += 0.5;
				else if( index == 1 ) vPos[1] += 0.5;
				else if( index == 2 ) vPos[2] += 0.5;
				else if( index == 3 ) vPos[0] -= 0.5;
				else if( index == 4 ) vPos[1] -= 0.5;
				else if( index == 5 ) vPos[2] -= 0.5;

				TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);

				PrintToChat(client, "%sNew origin: %f %f %f", CHAT_TAG, vPos[0], vPos[1], vPos[2]);
				break;
			}
		}
	}
}

SaveData(client)
{
	new entity, index;
	new aim = GetClientAimTarget(client, false);
	if( aim == -1 )
		return;

	aim = EntIndexToEntRef(aim);

	for( new i = 0; i < MAX_SPAWNS; i++ )
	{
		entity = g_iSpawns[i][0];

		if( entity == aim  )
		{
			index = g_iSpawns[i][1];
			break;
		}
	}

	if( index == 0 )
		return;

	// Load config
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s", CONFIG_SPAWNS);
	if( !FileExists(sPath) )
	{
		PrintToChat(client, "%sError: Cannot find the ammo pile spawner config (\x05%s\x01).", CHAT_TAG, CONFIG_SPAWNS);
		return;
	}

	new Handle:hFile = CreateKeyValues("spawns");
	if( !FileToKeyValues(hFile, sPath) )
	{
		PrintToChat(client, "%sError: Cannot load the ammo pile spawner config (\x05%s\x01).", CHAT_TAG, sPath);
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return;
	}

	// Check for current map in the config
	decl String:sMap[64];
	GetCurrentMap(sMap, 64);

	if( !KvJumpToKey(hFile, sMap) )
	{
		PrintToChat(client, "%sError: Current map not in the ammo pile spawner config.", CHAT_TAG);
		CloseHandle(hFile);
		hFile = INVALID_HANDLE;
		return;
	}

	decl Float:vAng[3], Float:vPos[3], String:sTemp[32];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vPos);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", vAng);

	IntToString(index, sTemp, sizeof(sTemp));
	if( KvJumpToKey(hFile, sTemp) )
	{
		KvSetVector(hFile, "ang", vAng);
		KvSetVector(hFile, "pos", vPos);

		// Save cfg
		KvRewind(hFile);
		KeyValuesToFile(hFile, sPath);

		PrintToChat(client, "%sSaved origin and angles to the data config", CHAT_TAG);
	}
}

CreateMenus()
{
	if( g_hMenuAng == INVALID_HANDLE )
	{
		g_hMenuAng = CreateMenu(AngMenuHandler);
		AddMenuItem(g_hMenuAng, "", "X + 5.0");
		AddMenuItem(g_hMenuAng, "", "Y + 5.0");
		AddMenuItem(g_hMenuAng, "", "Z + 5.0");
		AddMenuItem(g_hMenuAng, "", "X - 5.0");
		AddMenuItem(g_hMenuAng, "", "Y - 5.0");
		AddMenuItem(g_hMenuAng, "", "Z - 5.0");
		AddMenuItem(g_hMenuAng, "", "SAVE");
		SetMenuTitle(g_hMenuAng, "Set Angle");
		SetMenuExitButton(g_hMenuAng, true);
	}

	if( g_hMenuPos == INVALID_HANDLE )
	{
		g_hMenuPos = CreateMenu(PosMenuHandler);
		AddMenuItem(g_hMenuPos, "", "X + 0.5");
		AddMenuItem(g_hMenuPos, "", "Y + 0.5");
		AddMenuItem(g_hMenuPos, "", "Z + 0.5");
		AddMenuItem(g_hMenuPos, "", "X - 0.5");
		AddMenuItem(g_hMenuPos, "", "Y - 0.5");
		AddMenuItem(g_hMenuPos, "", "Z - 0.5");
		AddMenuItem(g_hMenuPos, "", "SAVE");
		SetMenuTitle(g_hMenuPos, "Set Position");
		SetMenuExitButton(g_hMenuPos, true);
	}
}



// ====================================================================================================
//					STUFF
// ====================================================================================================
bool:IsValidEntRef(entity)
{
	if( entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
		return true;
	return false;
}

ResetPlugin(bool:all = true)
{
	g_bLoaded = false;
	g_iSpawnCount = 0;
	g_iRoundStart = 0;
	g_iPlayerSpawn = 0;

	if( all )
		for( new i = 0; i < MAX_SPAWNS; i++ )
			RemoveSpawn(i);
}

RemoveSpawn(index, bool:grab = false)
{
	new entity = g_iSpawns[index][0];
	g_iSpawns[index][0] = 0;

	if( IsValidEntRef(entity) )
	{
		if (grab)
		{
			g_iSpawnCount--;
			AmmoSpawnCounter--;
			
			new Float:vPos[3];
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vPos);
			new Float:pos2[3];//pos - позиция
			TE_SetupDust(	vPos,//pos - начальная позиция
							pos2,//pos - позиция направления (у нас на месте)
							125.0,//50.0 - размер облака
							5.5);//0.5 - скорость частиц в облаке.		  
			TE_SendToAll();
			EmitSoundToAll(SOUND_COMMON2, entity, SNDCHAN_WEAPON);
		}
		AcceptEntityInput(entity, "kill");
		BagColorChanger();
	}
}



// ====================================================================================================
//					POSITION
// ====================================================================================================
SetTeleportEndPoint(client, Float:vPos[3], Float:vAng[3])
{
	ClientCommand(client, "vocalize PlayerSpotAmmo");
	GetClientAbsOrigin(client, vPos);
	GetClientAbsAngles(client, vAng);
	new c = MAX_SPAWNS - AmmoSpawnCounter;
	if (!b_ExpertDifficulty)
	{
		decl String:username[MAX_NAME_LENGTH];
		GetClientName(client, username, sizeof(username));
		if (c == 0) PrintToChatAll("%t", "LastAmmo", username);
		else PrintToChatAll("%t", "LeftAmmo", username, c);
	}
	AmmoSpawnCounter++;
	new Float:pos2[3];//pos - позиция
	TE_SetupDust(	vPos,//pos - начальная позиция
					pos2,//pos - позиция направления (у нас на месте)
					125.0,//50.0 - размер облака
					5.5);//0.5 - скорость частиц в облаке.		  
	TE_SendToAll();
	EmitSoundToAll(SOUND_COMMON, client, SNDCHAN_WEAPON);
	return true;
}

public ConVarChange_GameDifficulty(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (strcmp(oldValue, newValue) != 0)
	{
		decl String:s_GameDifficulty[16];
		GetConVarString(h_Difficulty, s_GameDifficulty, sizeof(s_GameDifficulty));
		if (strcmp(s_GameDifficulty, "hard", false) == 0) b_ExpertDifficulty = false;
		else if (strcmp(s_GameDifficulty, "impossible", false) == 0) b_ExpertDifficulty = true;
	}
}

CreateButton(entity)
{
	decl String:sTemp[16];
	new button;
	new bool:type=false;
	if(type)button = CreateEntityByName("func_button");
	else button = CreateEntityByName("func_button_timed"); 

	Format(sTemp, sizeof(sTemp), "target%d",  button );
	DispatchKeyValue(entity, "targetname", sTemp);
	DispatchKeyValue(button, "glow", sTemp);
	DispatchKeyValue(button, "rendermode", "3");
	DispatchKeyValue(button, "use_string", "Поднимаю...");
 
	if(type )
	{
		DispatchKeyValue(button, "spawnflags", "1025");
		DispatchKeyValue(button, "wait", "1");
	}
	else
	{
		DispatchKeyValue(button, "spawnflags", "0");
		DispatchKeyValue(button, "auto_disable", "1");
		Format(sTemp, sizeof(sTemp), "%f", 4.0);
		DispatchKeyValue(button, "use_time", sTemp);
	}
	DispatchSpawn(button);
	AcceptEntityInput(button, "Enable");
	ActivateEntity(button);

	Format(sTemp, sizeof(sTemp), "ft%d", button);
	DispatchKeyValue(entity, "targetname", sTemp);
	SetVariantString(sTemp);
	AcceptEntityInput(button, "SetParent", button, button, 0);
	TeleportEntity(button, Float:{0.0, 0.0, 0.0}, NULL_VECTOR, NULL_VECTOR);

	SetEntProp(button, Prop_Send, "m_nSolidType", 0, 1);
	SetEntProp(button, Prop_Send, "m_usSolidFlags", 4, 2);

	new Float:vMins[3] = {-15.0, -15.0, -15.0}, Float:vMaxs[3] = {15.0, 15.0, 15.0};
	SetEntPropVector(button, Prop_Send, "m_vecMins", vMins);
	SetEntPropVector(button, Prop_Send, "m_vecMaxs", vMaxs);

	if( type )
	{
		HookSingleEntityOutput(button, "OnPressed", OnPressed);
	}
	else
	{
		SetVariantString("OnTimeUp !self:Enable::1:-1");
		AcceptEntityInput(button, "AddOutput");
		HookSingleEntityOutput(button, "OnTimeUp", OnPressed);
	}
	return button;
}
public OnPressed(const String:output[], caller, activator, Float:delay)
{
	if (!CheckAssault[activator])
	{
		switch(GetRandomInt(0,1))
		{
			case 0:
			{
				switch (GetEntProp(activator, Prop_Send, "m_survivorCharacter"))
				{
					case 0: ClientCommand(activator, "vocalize conceptblock663");
					case 1: ClientCommand(activator, "vocalize conceptblock654");
					case 2: ClientCommand(activator, "vocalize crashcourser08");
					case 3: ClientCommand(activator, "vocalize c7m3_saferoom017b");
				}
			}
			case 1:
			{
				switch (GetEntProp(activator, Prop_Send, "m_survivorCharacter"))
				{
					case 0: ClientCommand(activator, "vocalize conceptblock715");
					case 1: ClientCommand(activator, "vocalize c7m3_saferoom016c");
					case 2: ClientCommand(activator, "vocalize introcrashr29");
					case 3: ClientCommand(activator, "vocalize introcrashr15");
				}
			}
		}
		return;
	}
	
	new find =- 1;
	for (new i=0; i<MAX_SPAWNS; i++)
	{
		if(caller == g_iSpawns[i][2])
		{
			find=i;
			break;
		}
	}
	if (find == -1) return;
	
	new cfgindex = g_iSpawns[find][1];
	if( cfgindex == 0 )
	{
		RemoveSpawn(find, true);
	}
	
	for( new i = 0; i < MAX_SPAWNS; i++ )
	{
		if( g_iSpawns[i][1] > cfgindex )
			g_iSpawns[i][1]--;
	}
}
public Action:Event_RoundRest(Handle:event, const String:name[], bool:dontBroadcast)
{
	AmmoSpawnCounter = 1;
	for (new iCid=1; iCid<=GetMaxClients(); iCid++)
	{
		if (parenting[iCid] !=0)
		{
			if(IsValidEntRef(parenting[iCid]))
			{
				AcceptEntityInput(parenting[iCid], "kill");
				if (IsPlayerAlive(iCid)) DropBag(iCid);
			}
		}
		parenting[iCid]=0;
	}
	return Plugin_Continue;
}
public Action:Event_BotReplacedPlayer(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "player"));
	
	if (IsDedicatedServer() && client ==0 || client < 0) return Plugin_Continue;
	if (client >GetMaxClients()) return Plugin_Continue;
	if (parenting[client]!=0)
	{
		if (IsValidEntRef(parenting[client]))
		{
			//AcceptEntityInput(parenting[client], "kill");
			SetEntityRenderColor(parenting[client], _, _, _, 0);
		}
		//parenting[client]=0;
	}
	return Plugin_Continue;
}
public bot_player_replace(Handle:Spawn_Event, const String:Spawn_Name[], bool:Spawn_Broadcast)
{
	//PrintToChatAll("bot_player_replace");
	new client = GetClientOfUserId(GetEventInt(Spawn_Event, "player"));
	if (parenting[client]!=0)
	{
		//PrintToChatAll("parenting[client]!=0");
		if (IsValidEntRef(parenting[client]))
		{
			//PrintToChatAll("IsValidEntRef");
			if (client > 0 && IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client))
			{
				//PrintToChatAll("IsPlayerAlive");
				//SetEntityRenderColor(parenting[client], _, _, _, 255);
				BagColorSwitch(client);
			}
			else if (!IsPlayerAlive(client))
			{
				//PrintToChatAll("DEAD!");
				AcceptEntityInput(parenting[client], "kill");
				parenting[client]=0;
			}
		}
	}
}
BagColorChanger()	
{
	for (new i=1; i<=GetMaxClients(); i++)
	{
		if (parenting[i] !=0)
		{
			if(IsValidEntRef(parenting[i])) BagColorSwitch(i);
		}
	}
}
BagColorSwitch(client)
{
	switch(g_iSpawnCount)
	{
		case 0: SetEntityRenderColor(parenting[client], 255, 255, 255, 255);
		case 1: SetEntityRenderColor(parenting[client], 80, 80, 80, 255);
		case 2: SetEntityRenderColor(parenting[client], 30, 30, 30, 255);
	}
}