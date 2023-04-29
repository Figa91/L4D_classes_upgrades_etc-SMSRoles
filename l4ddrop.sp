#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <l4d_stocks>

#pragma semicolon 1

#define FL_PISTOL_PRIMARY (1<<6) //Is 1 when you have a primary weapon and dual pistols
#define FL_PISTOL (1<<7) //Is 1 when you have dual pistols
#define FAKS			1024
#define MAXENTITIES 	2048
#define MAX_SPAWNS		32
static g_iSpawns[MAX_SPAWNS][2];
public Plugin:myinfo = 
{
	name = "L4D Drop Weapon",
	author = "Frustian",
	description = "Allows players to drop the weapon they are holding, or another weapon they have",
	version = "1.1",
	url = ""
}
new Handle:g_hSpecify;
new Handle:h_Difficulty;
new Handle:h_ClientDropKit;
new bool:b_ExpertDifficulty;
new Handle:HP_Timer_OnWeaponCanUse[MAXPLAYERS+1];
new Handle:HP_Timer_OnWeaponCanUse2[MAXPLAYERS+1];
new bool:KitTimeOut[MAXENTITIES + 1];

public OnPluginStart()
{
	CreateConVar("l4d_drop_version", "1.1", "Drop Weapon Version",FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hSpecify = CreateConVar("l4d_drop_specify", "1", "Allow people to drop weapons they have, but are not using",FCVAR_PLUGIN|FCVAR_SPONLY);
	RegConsoleCmd("sm_drop", Command_Drop);
	RegConsoleCmd("sm_med", Command_Drop2);
	RegConsoleCmd("sm_fak", Command_Drop2);
	RegConsoleCmd("sm_kit", Command_Drop2);
	h_Difficulty = FindConVar("z_difficulty");
	HookEvent("item_pickup", event_ItemPickup);
	HookEvent("round_freeze_end", round_freeze_end);
	HookConVarChange(h_Difficulty, ConVarChange_GameDifficulty);
	h_ClientDropKit = CreateGlobalForward("ClientDropKit", ET_Ignore, Param_Cell, Param_Cell, Param_String);
	LoadTranslations("drop.phrases");
}
public OnMapStart()
{
	PrecacheModel("particle/SmokeStack.vmt");
}
public Action:Command_Drop2(client, args)
{
	if (client == 0 || GetClientTeam(client) != 2 || !IsPlayerAlive(client))
		return Plugin_Handled;
	ClientCommand(client, "slot4");
	//DropSlot(client, 3);
	CreateTimer(1.0, DropFAK_Timer, client);
	return Plugin_Handled;
}
public Action:DropFAK_Timer(Handle:timer, any:client) 
{ 
	DropSlot(client, 3);
} 
public Action:Command_Drop(client, args)
{
	if (client == 0 || !IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client))
		return Plugin_Handled;
	new String:weapon[32];
	if (args > 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_drop [weapon]");
		return Plugin_Handled;
	}
	if (args == 1)
	{
		if (GetConVarInt(g_hSpecify))
		{
			GetCmdArg(1, weapon, 32);
			if ((StrContains(weapon, "pump") != -1 || StrContains(weapon, "auto") != -1 || StrContains(weapon, "shot") != -1 || StrContains(weapon, "rifle") != -1 || StrContains(weapon, "smg") != -1 || StrContains(weapon, "uzi") != -1 || StrContains(weapon, "m16") != -1 || StrContains(weapon, "hunt") != -1) && GetPlayerWeaponSlot(client, 0) != -1)
				DropSlot(client, 0);
			else if ((StrContains(weapon, "pistol") != -1) && GetPlayerWeaponSlot(client, 1) != -1)
				DropSlot(client, 1);
			else if ((StrContains(weapon, "pipe") != -1 || StrContains(weapon, "mol") != -1) && GetPlayerWeaponSlot(client, 2) != -1)
				DropSlot(client, 2);
			else if ((StrContains(weapon, "kit") != -1 || StrContains(weapon, "pack") != -1 || StrContains(weapon, "med") != -1) && GetPlayerWeaponSlot(client, 3) != -1)
				DropSlot(client, 3);
			else if ((StrContains(weapon, "pill") != -1) && GetPlayerWeaponSlot(client, 4) != -1)
				DropSlot(client, 4);
			else
				PrintToChat(client, "%t", "drop_msg_1", weapon);
				//PrintToChat(client, "\x05Зелёный эльф: \x04Какой ещё \x03%s\x04! Мы же его ещё на прошлой карте пропили.", weapon);
		}
		else
			ReplyToCommand(client, "[SM] This server's settings do not allow you to drop a specific weapon.  Use sm_drop(/drop in chat) without a weapon name after it to drop the weapon you are holding.");
		return Plugin_Handled;
	}
	GetClientWeapon(client, weapon, 32);
	if (StrEqual(weapon, "weapon_pumpshotgun") || StrEqual(weapon, "weapon_autoshotgun") || StrEqual(weapon, "weapon_rifle") || StrEqual(weapon, "weapon_smg") || StrEqual(weapon, "weapon_hunting_rifle"))
		DropSlot(client, 0);
	else if (StrEqual(weapon, "weapon_pistol"))
		DropSlot(client, 1);
	else if (StrEqual(weapon, "weapon_pipe_bomb") || StrEqual(weapon, "weapon_molotov"))
		DropSlot(client, 2);
	else if (StrEqual(weapon, "weapon_first_aid_kit"))
		DropSlot(client, 3);
	else if (StrEqual(weapon, "weapon_pain_pills"))
		DropSlot(client, 4);
	return Plugin_Handled;
}
public DropSlot(client, slot)
{
	if (GetPlayerWeaponSlot(client, slot) > 0)
	{
		decl String:username[MAX_NAME_LENGTH];
		GetClientName(client, username, sizeof(username));
		new String:sWeapon[32];
		new ammo;
		new clip;
		new ammoOffset = FindSendPropInfo("CTerrorPlayer", "m_iAmmo");
		GetEdictClassname(GetPlayerWeaponSlot(client, slot), sWeapon, 32);
		if (slot == 0)
		{
			clip = GetEntProp(GetPlayerWeaponSlot(client, 0), Prop_Send, "m_iClip1");
			ClientCommand(client, "vocalize PlayerSpotOtherWeapon");
			if (StrEqual(sWeapon, "weapon_pumpshotgun"))
			{
				ammo = GetEntData(client, ammoOffset+(6*4));
				SetEntData(client, ammoOffset+(6*4), 0);
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_2", username);
				//PrintToChatAll("\x05Зелёный эльф: \x04Игрок \x03%N\x04 выкинул помповый дробовик.", client);
			}
			else if (StrEqual(sWeapon, "weapon_autoshotgun"))
			{
				ammo = GetEntData(client, ammoOffset+(6*4));
				SetEntData(client, ammoOffset+(6*4), 0);
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_22", username);
				//PrintToChatAll("\x05Зелёный эльф: \x04Игрок \x03%N\x04 выкинул автоматический  дробовик.", client);
			}
			else if (StrEqual(sWeapon, "weapon_smg"))
			{
				ammo = GetEntData(client, ammoOffset+(5*4));
				SetEntData(client, ammoOffset+(5*4), 0);
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_3", username);
				//PrintToChatAll("\x05Зелёный эльф: \x04Игрок \x03%N\x04 выкинул узи.", client);
			}
			else if (StrEqual(sWeapon, "weapon_rifle"))
			{
				ammo = GetEntData(client, ammoOffset+(3*4));
				SetEntData(client, ammoOffset+(3*4), 0);
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_4", username);
				//PrintToChatAll("\x05Зелёный эльф: \x04Игрок \x03%N\x04 выкинул М16.", client);
			}
			else if (StrEqual(sWeapon, "weapon_hunting_rifle"))
			{
				ammo = GetEntData(client, ammoOffset+(2*4));
				SetEntData(client, ammoOffset+(2*4), 0);
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_5", username);
				//PrintToChatAll("\x05Зелёный эльф: \x04Игрок \x03%N\x04 выкинул винтовку.", client);
			}
		}
		if (slot == 1)
		{
			if ((GetEntProp(client, Prop_Send, "m_iAddonBits") & (FL_PISTOL|FL_PISTOL_PRIMARY)) > 0)
			{
				clip = GetEntProp(GetPlayerWeaponSlot(client, 1), Prop_Send, "m_iClip1");
				RemovePlayerItem(client, GetPlayerWeaponSlot(client, 1));
				SetCommandFlags("give", GetCommandFlags("give") & ~FCVAR_CHEAT);
				FakeClientCommand(client, "give pistol", sWeapon);
				SetCommandFlags("give", GetCommandFlags("give") | FCVAR_CHEAT);
				if (clip < 15)
					SetEntProp(GetPlayerWeaponSlot(client, 1), Prop_Send, "m_iClip1", 0);
				else
					SetEntProp(GetPlayerWeaponSlot(client, 1), Prop_Send, "m_iClip1", clip-15);
				new index = CreateEntityByName(sWeapon);
				new Float:cllocation[3];
				GetEntPropVector(client, Prop_Send, "m_vecOrigin", cllocation);
				cllocation[2]+=20;
				TeleportEntity(index,cllocation, NULL_VECTOR, NULL_VECTOR);
				DispatchSpawn(index);
				ActivateEntity(index);
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_6", username);
				ClientCommand(client, "vocalize PlayerSpotPistol");
				//PrintToChatAll("\x05Зелёный эльф: \x04Игрок \x03%N\x04 выкинул пистолет.", client);
			}
			else 
				PrintToChat(client, "%t", "drop_msg_7");
				//PrintToChat(client, "\x05Зелёный эльф: \x04Это же наган твоей бабушки, твоя совесть не позволяет мне его выбросить.");
			return;
		}
		new index = CreateEntityByName(sWeapon);
		new Float:cllocation[3];
		new Float:kitangle[3] = {90.0, 0.0, 0.0};
		GetEntPropVector(client, Prop_Send, "m_vecOrigin", cllocation);
		cllocation[2]+=20;
		if (StrEqual(sWeapon, "weapon_first_aid_kit"))
		{
			TeleportEntity(index,cllocation, kitangle, NULL_VECTOR);
		}
		else
		{
			TeleportEntity(index,cllocation, NULL_VECTOR, NULL_VECTOR);
		}
		decl item; 
		DispatchSpawn(index);
		ActivateEntity(index);
		RemovePlayerItem(client, item = GetPlayerWeaponSlot(client, slot));
		AcceptEntityInput(item, "Kill");
		if (slot == 0)
		{
			SetEntProp(index, Prop_Send, "m_iExtraPrimaryAmmo", ammo);
			SetEntProp(index, Prop_Send, "m_iClip1", clip);
		}
		if (slot == 3)
		{
			if (StrEqual(sWeapon, "weapon_first_aid_kit"))
			{
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_8", username);
				ClientCommand(client, "vocalize PlayerSpotFirstAid");
				//PrintToChatAll("\x05Зелёный эльф: \x04Игрок \x03%N\x04 выкинул anтeчкy.", client);
				//FAK_Timer[index] = CreateTimer(1.0, MedKitRing, index, TIMER_REPEAT);
				Call_StartForward(h_ClientDropKit);
				Call_PushCell(client);
				Call_Finish();
				MedKitSmoke(index);
				StartTrigger(index);
				CreateTimer(15.0, Timer_KitReset, index);
				KitTimeOut[index] = true;
			}
		}
		if (slot == 2)
		{
			if (StrEqual(sWeapon, "weapon_pipe_bomb"))
			{
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_9", username);
				ClientCommand(client, "vocalize PlayerSpotGrenade");
			}
			else if (StrEqual(sWeapon, "weapon_molotov"))
			{
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_10", username);
				ClientCommand(client, "vocalize PlayerSpotMolotov");
			}
		}
		if (slot == 4)
		{
			if (StrEqual(sWeapon, "weapon_pain_pills"))
			{
				if (!b_ExpertDifficulty)PrintToChatAll("%t", "drop_msg_11", username);
				ClientCommand(client, "vocalize PlayerSpotPills");
			}
		}
	}
	else if (GetPlayerWeaponSlot(client, slot) < 1)
	{
		if (slot == 3)
		{
			PrintToChat(client, "У Вас нет аптечки!");
		}
	}
}
StartTrigger(item)
{
	new iSpawnIndex = -1;
	for( new i = 0; i < MAX_SPAWNS; i++ )
	{
		if( g_iSpawns[i][0] == 0 )
		{
			iSpawnIndex = i;
			break;
		}
	}
	if( iSpawnIndex == -1 ) return;
	
	new Float:kit_location[3];
	GetEntPropVector(item, Prop_Send, "m_vecOrigin", kit_location);
	
	new trigger_health = CreateEntityByName("trigger_multiple");
	DispatchKeyValue(trigger_health, "spawnflags", "1");
	DispatchKeyValue(trigger_health, "wait", "0");
	DispatchSpawn(trigger_health);
	ActivateEntity(trigger_health);
	TeleportEntity(trigger_health, kit_location, NULL_VECTOR, NULL_VECTOR);
	SetEntityModel(trigger_health, "models/error.mdl");
	SetEntPropVector(trigger_health, Prop_Send, "m_vecMins", Float: {-50.0, -50.0, -30.0});
	SetEntPropVector(trigger_health, Prop_Send, "m_vecMaxs", Float: {50.0, 50.0, 30.0});
	SetEntProp(trigger_health, Prop_Send, "m_nSolidType", 2);
	//AcceptEntityInput(trigger_health, "SetParent", item, trigger_health);
	HookSingleEntityOutput(trigger_health, "OnStartTouch", OnStartTouch);
	HookSingleEntityOutput(trigger_health, "OnEndTouch", OnEndTouch);
	
	SetParentEx(item, trigger_health);
	
	g_iSpawns[iSpawnIndex][0] = EntIndexToEntRef(item);
	g_iSpawns[iSpawnIndex][1] = EntIndexToEntRef(trigger_health);
}
public MedKitSmoke(index)
{
	new entity = CreateEntityByName("env_smokestack");
	new Float:kit_location[3];
	GetEntPropVector(index, Prop_Send, "m_vecOrigin", kit_location);
	DispatchKeyValue(entity, "BaseSpread", "5");
	DispatchKeyValue(entity, "SpreadSpeed", "1");
	DispatchKeyValue(entity, "Speed", "30");
	DispatchKeyValue(entity, "StartSize", "10");
	DispatchKeyValue(entity, "EndSize", "1");
	DispatchKeyValue(entity, "Rate", "20");
	DispatchKeyValue(entity, "JetLength", "80");
	DispatchKeyValue(entity, "SmokeMaterial", "particle/SmokeStack.vmt");
	DispatchKeyValue(entity, "twist", "1");
	DispatchKeyValue(entity, "rendercolor", "255 0 0");
	DispatchKeyValue(entity, "renderamt", "255");
	DispatchKeyValue(entity, "roll", "0");
	DispatchKeyValue(entity, "InitialState", "1");
	DispatchKeyValue(entity, "angles", "0 0 0");
	DispatchKeyValue(entity, "WindSpeed", "1");
	DispatchKeyValue(entity, "WindAngle", "1");
	TeleportEntity(entity, kit_location, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(entity);
	AcceptEntityInput(entity, "TurnOn");
	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", index, entity);
	SetVariantString("OnUser1 !self:TurnOff::15.0:-1");
	AcceptEntityInput(entity, "AddOutput");
	AcceptEntityInput(entity, "FireUser1");
	
	new iEnt = CreateEntityByName("light_dynamic");
	DispatchKeyValue(iEnt, "_light", "255 0 0");
	DispatchKeyValue(iEnt, "brightness", "0");
	DispatchKeyValueFloat(iEnt, "spotlight_radius", 32.0);
	DispatchKeyValueFloat(iEnt, "distance", 100.0);
	DispatchKeyValue(iEnt, "style", "6");
	DispatchSpawn(iEnt);
	TeleportEntity(iEnt, kit_location, NULL_VECTOR, NULL_VECTOR);
	SetVariantString("!activator");
	new String:szTarget[32];
	Format(szTarget, sizeof(szTarget), "lighthealthkit_%d", entity);
	DispatchKeyValue(entity, "targetname", szTarget);
	SetVariantString(szTarget);
	AcceptEntityInput(iEnt, "SetParent");
	AcceptEntityInput(iEnt, "TurnOn");
	SetVariantString("OnUser1 !self:TurnOff::15.0:-1");
	AcceptEntityInput(iEnt, "AddOutput");
	AcceptEntityInput(iEnt, "FireUser1");
}

public OnClientPostAdminCheck(client)
{
	ClientCommand(client, "bind f3 sm_drop");
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
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
public Action:Timer_KitReset(Handle:timer, any:item) 
{
	KitTimeOut[item] = false;
}
public event_ItemPickup(Handle:event, const String:name[], bool:Broadcast) 
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new String:iWeaponName[32];
	GetEventString(event, "item", iWeaponName, 32);
	
	if(StrContains(iWeaponName, "first_aid_kit", false) != -1)
	{
		new targetid = GetPlayerWeaponSlot(client, 3);
		targetid = EntIndexToEntRef(targetid);
		new arrindex = -1;
		for( new i = 0; i < MAX_SPAWNS; i++ )
		{
			if(g_iSpawns[i][0] == targetid)
			{
				arrindex = i;
				break;
			}
		}
		if (arrindex != -1)
		{
			new entity = g_iSpawns[arrindex][1];
			if (IsValidEntRef(entity))
			{
				AcceptEntityInput(entity, "kill");
				g_iSpawns[arrindex][1] = 0;
				g_iSpawns[arrindex][0] = 0;
			}
		}
	}
}
stock SetParentEx(iParent, iChild)
{
	SetVariantString("!activator");
	AcceptEntityInput(iChild, "SetParent", iParent, iChild);
}
// player "eyes" "righteye" "lefteye" "partyhat" "head" "flag"
// weapon "muzzle" "eject_brass"
stock SetParent(iParent, iChild, const String:szAttachment[] = "", Float:vOffsets[3] = {0.0,0.0,0.0})
{
	SetVariantString("!activator");
	AcceptEntityInput(iChild, "SetParent", iParent, iChild);

	if (szAttachment[0] != '\0') // Use at least a 0.01 second delay between SetParent and SetParentAttachment inputs.
	{
		SetVariantString(szAttachment); // "head"

		if (!AreVectorsEqual(vOffsets, Float:{0.0,0.0,0.0})) // NULL_VECTOR
		{
			decl Float:vPos[3];
			GetEntPropVector(iParent, Prop_Send, "m_vecOrigin", vPos);
			AddVectors(vPos, vOffsets, vPos);
			TeleportEntity(iChild, vPos, NULL_VECTOR, NULL_VECTOR);
			AcceptEntityInput(iChild, "SetParentAttachmentMaintainOffset", iParent, iChild);
		}
		else
		{
			AcceptEntityInput(iChild, "SetParentAttachment", iParent, iChild);
		}
	}
}
stock bool:AreVectorsEqual(Float:vVec1[3], Float:vVec2[3])
{
	return (vVec1[0] == vVec2[0] && vVec1[1] == vVec2[1] && vVec1[2] == vVec2[2]);
}
public OnStartTouch(const String:output[], ent, client, Float:delay)
{
	//PrintToChat(client, "Start Touch!");
	if (client && IsClientInGame(client) && GetClientTeam(client) == 2)
	{
		new Hp = GetEntProp(client, Prop_Data, "m_iHealth");
		new tempHp = L4D_GetPlayerTempHealth(client);
		new totalHp = Hp + tempHp;
		
		if (Hp > 1)
		{
			if (totalHp < 90)
			{
				EmitSoundToClient(client, "player/survivor/heal/bandaging_1.wav", _, _, SNDLEVEL_TRAFFIC, SND_NOFLAGS, 0.7, 100, _, NULL_VECTOR, NULL_VECTOR, false, 0.0);
				HP_StopTimer(client);
				HP_Timer_OnWeaponCanUse[client] = CreateTimer(1.0, HP_Timer_PermRegen, client, TIMER_REPEAT);
			}
		}
		else if (Hp <= 1)
		{
			if (totalHp < 90)
			{
				EmitSoundToClient(client, "player/survivor/heal/bandaging_1.wav", _, _, SNDLEVEL_TRAFFIC, SND_NOFLAGS, 0.7, 100, _, NULL_VECTOR, NULL_VECTOR, false, 0.0);
				HP_Timer_OnWeaponCanUse2[client] = CreateTimer(1.0, HP_Timer_BuffRegen, client, TIMER_REPEAT);
			}
			else if (totalHp >= 90 && !IsFakeClient(client) && GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) != 1 && GetEntProp(client, Prop_Send, "m_currentReviveCount") != 2)
			{
				new ReviveCount = GetEntProp(client, Prop_Send, "m_currentReviveCount");
				CheatCommand(client, "give", "health", "");
				SetEntityHealth(client, 15);
				SetEntPropFloat(client, Prop_Send, "m_healthBuffer", 85.0);
				SetEntProp(client, Prop_Send, "m_currentReviveCount", ReviveCount);
			}
		}
	}
}
public OnEndTouch(const String:output[], ent, client, Float:delay)
{
	//PrintToChat(client, "End Touch!");
	if (client && IsClientInGame(client))
	{
		HP_StopTimer(client);
		HP_StopTimer_3(client);
	}
}
HP_StopTimer(client)
{
	if (HP_Timer_OnWeaponCanUse[client] != INVALID_HANDLE)
	{
		KillTimer(HP_Timer_OnWeaponCanUse[client]);
		HP_Timer_OnWeaponCanUse[client] = INVALID_HANDLE;
	}
}
HP_StopTimer_3(client)
{
	if (HP_Timer_OnWeaponCanUse2[client] != INVALID_HANDLE)
	{
		KillTimer(HP_Timer_OnWeaponCanUse2[client]);
		HP_Timer_OnWeaponCanUse2[client] = INVALID_HANDLE;
	}
}
public Action:HP_Timer_PermRegen(Handle:timer, any:client)
{
	if (!client || !IsClientInGame(client) || GetClientTeam(client) != 2)
	{
		HP_Timer_OnWeaponCanUse[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	new hp = GetEntProp(client, Prop_Send, "m_iHealth") + 5;
	new tempHp = L4D_GetPlayerTempHealth(client);
	new totalHp = hp + tempHp;
	if (totalHp > 100) totalHp = 100;
	SetEntProp(client, Prop_Send, "m_iHealth", hp);
	if (totalHp < 100) return Plugin_Continue;
	HP_Timer_OnWeaponCanUse[client] = INVALID_HANDLE;
	return Plugin_Stop;
}
public Action:HP_Timer_BuffRegen(Handle:timer, any:client)
{
	if (!client || !IsClientInGame(client) || GetClientTeam(client) != 2)
	{
		HP_Timer_OnWeaponCanUse2[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	new Float:hp3 = 1.0*L4D_GetPlayerTempHealth(client) + 7.0;
	L4D_SetPlayerTempHealth(client, any:hp3);
	if (hp3 > 100.0) hp3 = 100.0;
	SetEntPropFloat(client, Prop_Send, "m_healthBuffer", hp3);
	if (hp3 < 100.0) return Plugin_Continue;
	
	if (!IsFakeClient(client) && GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) != 1 && GetEntProp(client, Prop_Send, "m_currentReviveCount") != 2)
	{
		new ReviveCount = GetEntProp(client, Prop_Send, "m_currentReviveCount");
		CheatCommand(client, "give", "health", "");
		SetEntityHealth(client, 15);
		SetEntPropFloat(client, Prop_Send, "m_healthBuffer", 85.0);
		SetEntProp(client, Prop_Send, "m_currentReviveCount", ReviveCount);
	}
	
	HP_Timer_OnWeaponCanUse2[client] = INVALID_HANDLE;
	return Plugin_Stop;
}
stock CheatCommand(client, String:command[], String:parameter1[], String:parameter2[])
{
	new userflags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	new flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s %s", command, parameter1, parameter2);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userflags);
}
bool:IsValidEntRef(entity)
{
	if(entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE) return true;
	return false;
}
public Action:round_freeze_end(Handle:event, const String:name[], bool:dontBroadcast)
{
	for(new i = 0; i < MAX_SPAWNS; i++)
	{
		g_iSpawns[i][0] = 0;
		g_iSpawns[i][1] = 0;
	}
}
public Action:OnWeaponCanUse(client, weapon)
{
	new String:iWeaponName[32];
	GetEdictClassname(weapon, iWeaponName, sizeof(iWeaponName));
	if (StrContains(iWeaponName, "weapon_first_aid_kit", false) != -1)
	{
		if (KitTimeOut[weapon]) return Plugin_Handled;
	}
	return Plugin_Continue;
}