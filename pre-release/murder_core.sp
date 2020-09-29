#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <steamworks>
#include <cstrike>
#include <csgo_colors>	
#include <smlib>
#include <clientprefs>

#undef  REQUIRE_PLUGIN 
#include <murder>
#define  REQUIRE_PLUGIN

int 	RagdollPlayer[MAXPLAYERS+1],
		MinPlayersToPlaying,
		sizeArray_Names = 0,
		sizeArray_Models = 0,
		sizeArray_Sounds = 0,
		iOldButtons[MAXPLAYERS+1],
		m_flSimulationTime = -1,
		m_flProgressBarStartTime = -1,
		m_iProgressBarDuration = -1,
		m_iBlockingUseActionInProgress = -1,
		g_iIsAliveOffset,
		HideRagdoll_Price;
bool 	MurderEnable,
		bKnifeUse[MAXPLAYERS+1];
char 	szNameList[PLATFORM_MAX_PATH][64],
		szModelList[PLATFORM_MAX_PATH][128],
		RoundSoundList[PLATFORM_MAX_PATH][128];
Handle 	TeamPlayer,
		HUDTimer[MAXPLAYERS+1],
		TimerGetKnife[MAXPLAYERS+1];

bool 	g_InUse[MAXPLAYERS+1],
		g_InAttack2[MAXPLAYERS+1],
		g_InAttack1[MAXPLAYERS+1],
		g_InReload[MAXPLAYERS+1];
Handle 	CDTimer_Voice[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name 		= "Murder | Ядро плагина",
	author 		= "Rustgame",
	description = "Murder - Является игровым режимом, где простым очевидцами придется выяснить кто убийца, и не стать его жертвой.",
};

public void OnPluginStart()
{
	LoadTranslations("murder.phrases");

	PrintToServer("[ Murder ][ Core ] StartPlugin");
	TeamPlayer = RegClientCookie("team", "", CookieAccess_Private);

	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Pre);
	HookEvent("player_shoot", OnPlayerShoot); 

	AddCommandListener(ToggleFlashlight, "+lookatweapon");
	AddCommandListener(ScoreOff, "+score");

	m_flProgressBarStartTime 		= FindSendPropInfo("CCSPlayer", "m_flProgressBarStartTime");
	m_iProgressBarDuration 			= FindSendPropInfo("CCSPlayer", "m_iProgressBarDuration");
	m_flSimulationTime 				= FindSendPropInfo("CBaseEntity", "m_flSimulationTime");
	m_iBlockingUseActionInProgress 	= FindSendPropInfo("CCSPlayer", "m_iBlockingUseActionInProgress");
	g_iIsAliveOffset 				= FindSendPropInfo("CCSPlayerResource", "m_bAlive");
	if (g_iIsAliveOffset == -1)
		SetFailState("CCSPlayerResource.m_bAlive offset is invalid"); 

	char 	szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/configs.ini"); KeyValues KV_Config = new KeyValues("Murder"); KV_Config.ImportFromFile(szPath);
	MinPlayersToPlaying = KV_Config.GetNum("MinPlayersToPlaying");
	KV_Config.GetString("RoundStart", 		RoundSoundList[0], sizeof(RoundSoundList));
	KV_Config.GetString("RoundWinMurder", 	RoundSoundList[1], sizeof(RoundSoundList));
	KV_Config.GetString("RoundNoWinMurder", RoundSoundList[2], sizeof(RoundSoundList));
	HideRagdoll_Price 	= KV_Config.GetNum("HideRagdoll_Price");

	PrintToServer(RoundSoundList[0]);
	PrintToServer(RoundSoundList[1]);
	PrintToServer(RoundSoundList[2]);
	LoadConfig_Names();

	RegConsoleCmd("sm_du", Stuck);
	RegConsoleCmd("sm_team", GetTeam);

	for(int i = 1; i <= GetClientCount(); ++i) 
	{
		if (IsValidClient(i))
		{
			if (HUDTimer[i] == null)
			{
				HUDTimer[i] = CreateTimer(1.0, HUD, i, TIMER_REPEAT);
			}
		}
	}

	CreateTimer(1.0, StartThink);
}

public Action StartThink(Handle timer)
{
	int CSPlayerManagerIndex = FindEntityByClassname(0, "cs_player_manager");
	SDKHook(CSPlayerManagerIndex, SDKHook_ThinkPost, OnThinkPost);
}

public void OnClientDisconnect(iClient)
{
	if (M_IsMurder(iClient))
	{
		CGOPrintToChatAll("%t", "MurderLeave");
		ServerCommand("mp_restartgame 1");
	}
}

public Action GetTeam(iClient, Args)
{
	char Team[32];
	GetClientCookie(iClient, TeamPlayer, Team, sizeof(Team));
	CGOPrintToChatAll("%N - %s", iClient, Team);
}

public Action Stuck(iClient, Args)
{
	int aim = GetClientAimTarget(iClient, false);
	if (aim > MaxClients)
	{
		char 	class[128];
		GetEntityClassname(aim, class, sizeof(class));
		
	}
}
public void OnThinkPost(entity) 
{
	if (entity >=0)
	{
		decl isAlive[65];
    
		GetEntDataArray(entity, g_iIsAliveOffset, isAlive, 65);
		for (new i = 1; i <= MaxClients; ++i)
		{
			if (IsValidClient(i))
			{
				isAlive[i] = true;
			}
		}
		SetEntDataArray(entity, g_iIsAliveOffset, isAlive, 65);
	}
} 

public void Voice(iClient){float Pos[3]; int iRandom = GetRandomInt(1, 16); char path[128]; GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", Pos); Format(path, sizeof(path), "*/murder/voice/vo_%i.wav", iRandom); EmitAmbientSound(path, Pos, iClient, 140, _, 0.4);}
public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max)
{
	CreateNative("M_GetTeam", Native_M_GetTeam);
	CreateNative("M_MurderEnable", Native_M_MurderEnable);
	CreateNative("M_IsMurder", Native_M_IsMurder);
	MarkNativeAsOptional("M_GetCountLoot");
	MarkNativeAsOptional("M_SetCountLoot");
	MarkNativeAsOptional("M_GetCountLoots");

	return APLRes_Success;
}
public int Native_M_IsMurder(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	char Team[32];
	GetClientCookie(iClient, TeamPlayer, Team, sizeof(Team));
	if (StrEqual(Team, "team1"))
	{
		return true
	}
	else
	{
		return false
	}
}
public int Native_M_GetTeam(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	char Team[32];
	GetClientCookie(iClient, TeamPlayer, Team, sizeof(Team));
	ReplaceString(Team, sizeof(Team), "team", "");
	int iTeam = StringToInt(Team);
	return iTeam;
}
public void LoadConfig_Sound()
{
	char 	szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/sounds.ini"); KeyValues KV_Sounds = new KeyValues("Sounds"); KV_Sounds.ImportFromFile(szPath); 
	KV_Sounds.Rewind();
	KV_Sounds.GotoFirstSubKey(false)
	PrintToServer("______________[ LogsUpload Sounds ]______________");
	while(KV_Sounds.GotoNextKey(false))
	{
		char 	sSectionName[64],
				szPathS[64]; 
		KV_Sounds.GetSectionName(sSectionName, sizeof(sSectionName)); 
		Format(szPathS, sizeof(szPathS), "*/%s", sSectionName);
		PrecacheSound(szPathS);
		sizeArray_Sounds++;
		PrintToServer("| > %s Loading!", sSectionName);
		Format(szPathS, sizeof(szPathS), "sound/%s", sSectionName);
		AddFileToDownloadsTable(szPathS);
	}

	PrintToServer("_________________________________________________");

	delete KV_Sounds;
}
public void LoadConfig_Names()
{
	char 	szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/names.ini");
	KeyValues KV_Names = new KeyValues("Male");
	KV_Names.ImportFromFile(szPath);
	KV_Names.Rewind();
	KV_Names.GotoFirstSubKey(false)
	PrintToServer("______________[ LogsUpload Names ]______________");
	while(KV_Names.GotoNextKey(false))
	{
		char sSectionName[64];
		KV_Names.GetSectionName(sSectionName, sizeof(sSectionName));
		szNameList[sizeArray_Names] = sSectionName;
		sizeArray_Names++;
		PrintToServer("| > Имя: %s Loading!", sSectionName);
	}
	PrintToServer("________________________________________________");
	PrintToServer("Имен: %i шт", sizeArray_Names);

	delete KV_Names;
}

public void LoadConfig_Models()
{
	char 	szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/models.ini"); KeyValues KV_Models = new KeyValues("Models"); KV_Models.ImportFromFile(szPath); 
	KV_Models.Rewind();
	KV_Models.GotoFirstSubKey(false)
	PrintToServer("______________[ LogsUpload Models ]______________");
	while(KV_Models.GotoNextKey(false))
	{
		char sSectionName[64]; 
		KV_Models.GetSectionName(sSectionName, sizeof(sSectionName)); 
		szModelList[sizeArray_Models] = sSectionName; 
		PrecacheModel(sSectionName);
		sizeArray_Models++;
		PrintToServer("| > %s Loading!", sSectionName);
		AddFileToDownloadsTable(sSectionName);
	}

	PrintToServer("_________________________________________________");

	delete KV_Models;
}

public Action OnPlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
    SetEntProp(iClient, Prop_Send, "m_iHideHUD", 1<<12);
}
public int Native_M_MurderEnable(Handle hPlugin, int iNumParams){return MurderEnable;}
public void OnClientPostAdminCheck(iClient){SetClientCookie(iClient, TeamPlayer, "team3"); HUDTimer[iClient] = CreateTimer(1.0, HUD, iClient, TIMER_REPEAT);}
public Action HUD(Handle timer, iClient)
{
	if(IsValidClient(iClient))
	{
		if(IsPlayerAlive(iClient))
		{
			char 	Team[64],
					HEXColorTeam[32],
					TeamText[64];
			GetClientCookie(iClient, TeamPlayer, Team, sizeof(Team));
			if (StrEqual(Team, "team1"))
			{
				Format(TeamText, sizeof(TeamText), "%t", "tMurder"); 
				HEXColorTeam = "#ff0000";
			}
			else if(StrEqual(Team, "team2"))
			{
				Format(TeamText, sizeof(TeamText), "%t", "tPolice"); 
				HEXColorTeam = "#0000ff";
			}
			else
			{
				Format(TeamText, sizeof(TeamText), "%t", "noMurder");
				HEXColorTeam = "#00ffff";
			}

			char StringText[2048];	
			Format(StringText, sizeof(StringText), "<font color='#fff'>______________</font>[ <font color='#ff0000'>Murder</font> ]<font color='#fff'>______________</font>\
				\n%t<font color='%s'>%s</font> \	
				\n%t <font color='#9900ff'>%i шт.</font>", "HRole", HEXColorTeam, TeamText, "HEvidence", M_GetCountLoot(iClient));
			PrintHintText(iClient, StringText);

			
			SetHudTextParams(0.012, 0.48, 5.0, 255,255,255, 255, 0, 0.0, 0.5, 0.1);
			ShowHudText(iClient, -1, "Улик на локации: %i", M_GetCountLoots());
			SetHudTextParams(0.012, 0.5, 5.0, 255,255,255, 255, 0, 0.0, 0.5, 0.1);
			ShowHudText(iClient, -1, "%t R", "Voice");
			if (M_IsMurder(iClient))
			{
				SetHudTextParams(0.012, 0.52, 5.0, 255,255,255, 255, 0, 0.0, 0.5, 0.1);
				if(bKnifeUse[iClient])
				{
					ShowHudText(iClient, -1, "%t", "HideKnife");
				}
				else
				{
					ShowHudText(iClient, -1, "%t", "UseKnife");
				}

				SetHudTextParams(0.012, 0.54, 5.0, 255,255,255, 255, 0, 0.0, 0.5, 0.1);
				ShowHudText(iClient, -1, "Спрятать тело: E + %i Улик(и)", HideRagdoll_Price);
			}
		}
	}
	else
	{
		HUDTimer[iClient] = null;
	}
}
public Action EventItemPickup(iClient, Entity)
{
	char 	Team[32],
			Weapon[64];
	GetEntityClassname(Entity, Weapon, sizeof(Weapon));
	GetClientCookie(iClient, TeamPlayer, Team, sizeof(Team));
	if (StrEqual(Weapon, "weapon_deagle") && StrEqual(Team, "team1")){return Plugin_Handled;}

	return Plugin_Continue;
}
	
public void OnMapStart()
{
	Handle 	HideName  = FindConVar("mp_playerid"), LimitTeam = FindConVar("mp_limitteams"), EnemyKill = FindConVar("mp_teammates_are_enemies"), WarTimers = FindConVar("mp_warmuptime");
	SetConVarInt(HideName, 2); SetConVarInt(LimitTeam, 30); SetConVarInt(EnemyKill, 1); SetConVarInt(WarTimers, 0);
	LoadConfig_Models();
	LoadConfig_Sound();
	CreateTimer(10.0, CheckAccessPlaying, _, TIMER_REPEAT);
}
public Action CheckAccessPlaying(Handle timer){if (GetClientCount() >= MinPlayersToPlaying){MurderEnable = true; return Plugin_Stop;}else{MurderEnable = false; CGOPrintToChatAll("%t", "ChatNoPlayers", MinPlayersToPlaying); return Plugin_Continue;}}
public Action ToggleFlashlight(iClient, const char[] CMD, Args){SetEntProp(iClient, Prop_Send, "m_fEffects", GetEntProp(iClient, Prop_Send, "m_fEffects") ^ 4);}
public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int 	iClient = GetClientOfUserId(GetEventInt(event, "userid"));
	int 	iAttacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	char 	Team[256],
			TeamA[32];
	GetClientCookie(iClient, TeamPlayer, Team, sizeof(Team));
	GetClientCookie(iAttacker, TeamPlayer, TeamA, sizeof(TeamA));
	SetEntProp(iClient, Prop_Data, "m_iFrags", 0);
	SetEntProp(iClient, Prop_Data, "m_iDeaths", 0);
	SetEntProp(iAttacker, Prop_Data, "m_iFrags", 0);
	SetEntProp(iAttacker, Prop_Data, "m_iDeaths", 0);
	if (StrEqual(Team, "team1"))
	{
		EmitSoundToAll(RoundSoundList[2],_,_,_,_,0.2);
		CS_TerminateRound(5.0, CSRoundEnd_CTStoppedEscape, false);
		CGOPrintToChatAll("%t", "noMurderWin")
		Format(Team, sizeof(Team), "%t", "MurderBy");
		CGOPrintToChatAll("%s %N", Team, iClient);
		return Plugin_Changed;
	}
	else
	{
		if (!StrEqual(TeamA, "team1"))
		{
			ForcePlayerSuicide(iAttacker);
			CGOPrintToChat(iAttacker, "%t", "rdmKill");
		}
	}

	int iAlive = 0;

	for(int i = 1; i <= MaxClients; ++i)
	{	
		if (IsValidClient(i) && IsPlayerAlive(i))
		{
			iAlive++;
		}
	}

	if (iAlive <= 1)
	{
		CS_TerminateRound(5.0, CSRoundEnd_CTStoppedEscape, false);
		CGOPrintToChatAll("%t", "MurderWin");
		EmitSoundToAll(RoundSoundList[1],_,_,_,_,0.2);
	}

	int iRagdoll = GetEntPropEnt(iClient, Prop_Send, "m_hRagdoll");
	if (iRagdoll > 0)
		AcceptEntityInput(iRagdoll, "Kill");
	CreateDeathRagdoll(iClient);
	SetEventBroadcast(event, true);

	return Plugin_Changed;
}

public Action ScoreOff(iClient, const char[] CMD, Args){return Plugin_Handled;}
public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsValidClient(iClient)) return Plugin_Continue;

	char 	Team[32];
	GetClientCookie(iClient, TeamPlayer, Team, sizeof(Team));
	if (StrEqual(Team, "team1"))
	{
		if (!g_InAttack2[iClient] && buttons & IN_ATTACK2)
		{
			if (bKnifeUse[iClient] == true)
			{
				char W[32];
				GetClientWeapon(iClient, W, sizeof(W));
				Client_RemoveWeapon(iClient, "weapon_knife", false);
				bKnifeUse[iClient]=false;
				TimerGetKnife[iClient] = INVALID_HANDLE;
			}
			else
			{	
				if (TimerGetKnife[iClient] == null)
				{
					TimerGetKnife[iClient] 	= CreateTimer(2.0, GiveWeapon, iClient);
					float flGameTime 		= GetGameTime();
					SetEntData(iClient, m_iProgressBarDuration, 2, 4, true);
					SetEntDataFloat(iClient, m_flProgressBarStartTime, flGameTime - (float(2) - 2.0), true);
					SetEntDataFloat(iClient, m_flSimulationTime, flGameTime + 2.0, true);
					SetEntData(iClient, m_iBlockingUseActionInProgress, 0, 4, true);
				}
				else
				{
					SetEntDataFloat(iClient, m_flProgressBarStartTime, 0.0, true);
					SetEntData(iClient, m_iProgressBarDuration, 0, 1, true);
					delete TimerGetKnife[iClient];
				}
			}
			
			g_InAttack2[iClient] 		= true;
		}
		else if(g_InAttack2[iClient] && !(buttons & IN_ATTACK2))
		{
			g_InAttack2[iClient] = false;
		}
	}

	if (!g_InAttack1[iClient] && buttons & IN_ATTACK)
		{
			int aim = GetClientAimTarget(iClient, false);
			if (aim > MaxClients)
			{
				char class[128];
				GetEntityClassname(aim, class, sizeof(class));
				if (StrEqual(class, "prop_ragdoll"))
				{
					SetEntProp(aim, Prop_Data, "m_CollisionGroup", 1);
					CreateTimer(2.0, SetSolid, aim);
				}
				
				g_InAttack1[iClient] 		= true;
			}
		}
		else if(g_InAttack1[iClient] && !(buttons & IN_ATTACK))
		{
			g_InAttack1[iClient] = false;
		}

	if (!g_InReload[iClient] && buttons & IN_RELOAD)
	{
		if(IsPlayerAlive(iClient))
		{
			g_InReload[iClient] = true;

			if (CDTimer_Voice[iClient] == null)
			{
				Voice(iClient);
				CDTimer_Voice[iClient] = CreateTimer(2.0, VoiceEnable, iClient);
			}
		}
	}
	else if(g_InReload[iClient] && !(buttons & IN_RELOAD))
	{
		g_InReload[iClient] = false;
	}

	if(buttons & IN_SCORE && !(iOldButtons[iClient] & IN_SCORE))
	{
		StartMessageOne("ServerRankRevealAll", iClient, USERMSG_BLOCKHOOKS);
		EndMessage();
	}

	iOldButtons[iClient] = buttons;

	if (!g_InUse[iClient] && buttons & IN_USE)
	{
		g_InUse[iClient] = true;
		int aim = GetClientAimTarget(iClient, false);
		if (aim > MaxClients)
		{
			char class[128];
			GetEntityClassname(aim, class, sizeof(class));
			if (StrEqual(class, "prop_ragdoll", false))
			{
				int owner = GetClientOfUserId(GetEntProp(aim, Prop_Send, "m_hOwnerEntity"));
				char Tr[64];
				Format(Tr, sizeof(Tr), "%t ", "OwnerRandoll", owner);
				if (owner <= 0) CGOPrintToChat(iClient, "%t", "OwnerRandollDIS"); else CGOPrintToChat(iClient, "%s %N", Tr, owner);

				if (M_IsMurder(iClient) && M_GetCountLoot(iClient)>=HideRagdoll_Price)
				{	
					CGOPrintToChat(iClient, "{RED}Murder | {DEFAULT}Вы спрятали труп!");
					RemoveEntity(aim);
					M_TakeLoot(iClient, HideRagdoll_Price);
				}
				
			}
		}
	}
	else if(g_InUse[iClient] && !(buttons & IN_USE))
	{
		g_InUse[iClient] = false;
	}

	return Plugin_Continue;
}

public Action VoiceEnable(Handle timer, int iClient){CDTimer_Voice[iClient] = null; delete CDTimer_Voice[iClient];}
public Action GiveWeapon(Handle timer,int iClient){SetEntDataFloat(iClient, m_flProgressBarStartTime, 0.0, true); SetEntData(iClient, m_iProgressBarDuration, 0, 1, true); Client_GiveWeapon(iClient, "weapon_knife", true); bKnifeUse[iClient]=true;}
public void CreateDeathRagdoll(iClient)
{
	RagdollPlayer[iClient] = CreateEntityByName("prop_ragdoll");
	if (RagdollPlayer[iClient] == -1)
		return;
	
	char sModel[PLATFORM_MAX_PATH];
	GetClientModel(iClient, sModel, sizeof(sModel));
	DispatchKeyValue(RagdollPlayer[iClient], "model", sModel);
	DispatchSpawn(RagdollPlayer[iClient]);
	ActivateEntity(RagdollPlayer[iClient]);
	SetEntProp(RagdollPlayer[iClient], Prop_Send, "m_hOwnerEntity", GetClientUserId(iClient));
	SetEntProp(RagdollPlayer[iClient], Prop_Data, "m_CollisionGroup", 1);
	CreateTimer(2.0, SetSolid, RagdollPlayer[iClient]);
	float vec[3];
	GetClientAbsOrigin(iClient, vec);
	TeleportEntity(RagdollPlayer[iClient], vec, NULL_VECTOR, NULL_VECTOR);
}

public Action SetSolid(Handle timer, int Entity){SetEntProp(Entity, Prop_Data, "m_CollisionGroup", 6);}
public Action OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	//CreateTimer(10.0, CheckAccessPlaying, _, TIMER_REPEAT);
	int 	iRandom_Murder 	= GetRandomInt(1, GetClientCount()),
		 	iRandom_Police 	= GetRandomInt(1, GetClientCount());

	int ent = -1; 
	while ((ent = FindEntityByClassname(ent, "func_buyzone")) > 0){if (IsValidEntity(ent)){AcceptEntityInput(ent, "kill");}}
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "hostage_entity")) != -1){if (IsValidEntity(ent)){AcceptEntityInput(ent, "kill");}}

	for(int i = 1; i <= GetClientCount(); ++i) if (IsValidClient(i)) Client_RemoveAllWeapons(i);
	if (iRandom_Police == iRandom_Murder){iRandom_Police = GetRandomInt(0, GetClientCount());}

	for(int i = 1; i <= MAXPLAYERS; ++i)
	{
		if (IsValidClient(i))
		{
			float Pos[3]; 
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", Pos);
			EmitAmbientSound(RoundSoundList[0], Pos, i, 30, _, 1.0);
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
			SDKHook(i, SDKHook_WeaponEquip, EventItemPickup);
			OnClientPostAdminCheck(i);
			int iRandom_Name	= GetRandomInt(0, sizeArray_Names-1),
		 		iRandom_Models	= GetRandomInt(0, sizeArray_Models-1);
		 	SetClientInfo(i, "name", szNameList[iRandom_Name]);
			SetEntPropString(i, Prop_Data, "m_szNetname", szNameList[iRandom_Name]);
			CS_SetClientClanTag(i, "");

			SetEntityModel(i, szModelList[iRandom_Models]);
			int iMelee;
			if (iRandom_Murder == i)
			{
				SetClientCookie(i, TeamPlayer, "team1");
				iMelee = GivePlayerItem(i, "weapon_fists");
				EquipPlayerWeapon(i, iMelee);
				CGOPrintToChat(i, "%t", "cMurder");
			}
			else if (iRandom_Police == i)
			{
				SetClientCookie(i, TeamPlayer, "team2");
				iMelee = GivePlayerItem(i, "weapon_fists");
				GivePlayerItem(i, "weapon_revolver");
				EquipPlayerWeapon(i, iMelee);
				CGOPrintToChat(i, "%t", "cPolice");
			}
			else
			{
				SetClientCookie(i, TeamPlayer, "team3");
				iMelee = GivePlayerItem(i, "weapon_fists");
				EquipPlayerWeapon(i, iMelee);
				CGOPrintToChat(i, "%t", "cnoMurder");
			}
		}
	}
}
public Action OnRoundEnd(Handle:event, const String:name[], bool:dontBroadcast){for(int i = 1; i <= MaxClients; ++i){if (IsValidClient(i)) {SetClientCookie(i, TeamPlayer, "team3");}}}
public Action OnPlayerShoot(Event event, char[] name, bool dontBroadcast){int iClient = GetClientOfUserId(GetEventInt(event, "userid")); GetEntData(iClient, FindSendPropInfo("CCSPlayer", "m_iAmmo")+(1*4), 4); }

public Action OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
	char 	sWeapon[32];
	GetClientWeapon(inflictor, sWeapon, sizeof(sWeapon))
	if(StrEqual(sWeapon, "weapon_knife"))
	{
		damage = 99999.0;
	}

	if(StrEqual(sWeapon, "weapon_revolver"))
	{
		damage = 99999.0;
	}

	if(StrEqual(sWeapon, "weapon_fists"))
	{
		damage = 0.0;
	}

	return Plugin_Changed;
}