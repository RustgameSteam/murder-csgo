#if defined _murder_included_
   #endinput 
#endif 
#define _murder_included_

//		Murder - Core	| murder_core.smx

native bool M_MurderEnable(); 							// Вернет true если Murder запущен
native int 	M_GetTeam(int iClient);						// Вернет номер роли 1 - Murder, 2 - Police, 3 - noMurder
native bool M_IsMurder(int iClient);					// Вернет true если игрок является Murder

//		Murder - Loots 	| murder_loots.smx

native int M_GetCountLoot(int iClient);					// Вернет количество подобранных улик
native int M_SetCountLoot(int iClient, int iCount); 	// Установит указанное количество улик
native int M_GetCountLoots();							// Вернет количество улик на карте
public void M_GiveLoot(int iClient, int Count){int iCounts = M_GetCountLoot(iClient);M_SetCountLoot(iClient, iCounts+Count);} 	// Выдать определенное количество улик
public void M_TakeLoot(int iClient, int Count){int iCounts = M_GetCountLoot(iClient);M_SetCountLoot(iClient, iCounts-Count);}	// Отнять определенное количество улик
public void M_TakeAllLoots(int iClient){M_SetCountLoot(iClient, 0);}															// Отнять все улики у игрока

// 					Основное

stock bool CheckDistance(int iClient, int iTarget, int Distance)
{
	float iCD, iTD;
	GetClientAbsOrigin(iClient, iCD);
	GetClientAbsOrigin(attacker, iTD);
	int cDistance = GetVectorDistance(iCD, iTD);
	if (cDistance <= Distance){return true}else{return false;}
}

public bool TraceEntityFilterSolid(entity, contentsMask) 
{
	return entity > 1;
}

stock bool IsValidClient(iClient)
{
	if (iClient <= 0 || iClient > MaxClients)
	{
		return false;
	}

	if (!IsClientInGame(iClient) || !IsClientConnected(iClient))
	{
		return false;
	}

	return true;
}