#include <sourcemod>
#include <vip_core>

#undef  REQUIRE_PLUGIN 
#include <murder>
#define  REQUIRE_PLUGIN

public Plugin:myinfo = 
{
	name = "[ Murder ][ Module ] VIP Give Loots",
	author = "Rustgame",
	description = "Выдача опр количества улик VIP Игроку",
};

new const String:g_sFeature[] = "mu_GiveLoots";
public OnPluginStart(){LoadTranslations("vip_modules.phrases");if(VIP_IsVIPLoaded()){VIP_OnVIPLoaded();}}
public OnPluginEnd(){if(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "VIP_UnregisterFeature") == FeatureStatus_Available){VIP_UnregisterFeature(g_sFeature);}}
public VIP_OnVIPLoaded(){VIP_RegisterFeature(g_sFeature, INT, _, OnItemToggle, OnItemDisplay);}
public bool:OnItemDisplay(iClient, const String:sFeatureName[], String:sDisplay[], iMaxLen)
{
	if(VIP_IsClientFeatureUse(iClient, sFeatureName))
	{
		int iCount = VIP_GetClientFeatureInt(iClient, sFeatureName);
		if(iCount != -1){FormatEx(sDisplay, iMaxLen, "%T [+%d]", sFeatureName, iClient, iCount);return true;}
	}

	return false;
}

public Action:OnItemToggle(iClient, const char[] sFeatureName, VIP_ToggleState:OldStatus, &VIP_ToggleState:NewStatus)
{
	if(NewStatus != ENABLED){return Plugin_Handled;}
	
	return Plugin_Continue;
}
public VIP_OnPlayerSpawn(iClient, iTeam, bool bIsVIP){if(bIsVIP){VIP_OnVIPClientLoaded(iClient);}}
public VIP_OnVIPClientLoaded(iClient){if(VIP_IsClientFeatureUse(iClient, g_sFeature)){int iCount = VIP_GetClientFeatureInt(iClient, g_sFeature);M_SetCountLoot(iClient, iCount);}}