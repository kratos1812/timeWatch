#pragma semicolon 1

#define PLUGIN_VERSION "1.00"
#define DEFAULT_TIMER_FLAGS (TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE)
#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma newdecls required

Database 	g_hDatabase = null;

char 		g_sSteamId64[MAXPLAYERS + 1][32];

int 		g_iPlayerUId[MAXPLAYERS + 1];
int 		g_iPlayedSeconds[MAXPLAYERS + 1][4];

Handle		g_hTimeManageTimer[MAXPLAYERS + 1];

Menu 		g_hTopsMenu = null;
Menu 		g_hMainMenu = null;

public Plugin myinfo = 
{
	name = "Time Watch",
	author = "kRatoss",
	description = "Monitors the time spent playing",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/profiles/76561198090457091"
};

public void OnPluginStart()
{
	CreateConVar("sm_timewatch_plugin_versoin", PLUGIN_VERSION, "Actual Plugin Version");
	AutoExecConfig(true);
	
	Database.Connect(SQLT_OnConnect, "timeWatch");
	
	RegConsoleCmd("sm_timewatch", Command_TimeWatch, "Open Main Menu for timeWatch");
	RegConsoleCmd("sm_time", Command_Time, "Open Main Menu for timeWatch");
	RegConsoleCmd("sm_ore", Command_Time, "Open Main Menu for timeWatch");
}

public void OnMapStart()
{
	g_hTopsMenu = new Menu(MenuHandler_TopsMenu);
	g_hTopsMenu.SetTitle("================\nTimeWatch Tops Menu\n================");
	g_hTopsMenu.AddItem("1", "Top Players Overall");
	g_hTopsMenu.AddItem("2", "Top Players CT");
	g_hTopsMenu.AddItem("3", "Top Players TR");
	g_hTopsMenu.AddItem("4", "Top Players SPEC");
	g_hTopsMenu.AddItem("5", "Top Players CT+TR");
	g_hTopsMenu.AddItem("6", "Top Players This Week");
	SetMenuExitBackButton(g_hTopsMenu, true);
	
	g_hMainMenu = new Menu(MenuHandler_MainMenu);
	g_hMainMenu.SetTitle("================\nTimeWatch Main Menu\n================");
	g_hMainMenu.AddItem("1", "See Your Stats");
	g_hMainMenu.AddItem("3", "See Players's Stats");
	g_hMainMenu.AddItem("2", "See the Top Players");
	
	CreateTimer(60.0, Timer_UpdateDataForAllClient, _, DEFAULT_TIMER_FLAGS);
}

public void OnMapEnd()
{
	delete g_hTopsMenu;
}

public Action Command_TimeWatch(int client, int args)
{
	if(client < 1)
		return Plugin_Handled;
		
	if(!IsClientInGame(client))
		return Plugin_Handled;
	
	g_hMainMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public Action Command_Time(int client, int Args)
{
	if(client < 1)
		return Plugin_Handled;
		
	if(!IsClientInGame(client))
		return Plugin_Handled;
	
	char query[160];
	FormatEx(query, sizeof(query), "SELECT SUM(`time_team_spec` + `time_team_none` + `time_team_t` + `time_team_ct`) as total FROM `timeWatch` WHERE `player_id` = '%i';", g_iPlayerUId[client]);
	g_hDatabase.Query(SQLT_SelectPlayerTotalTime, query, client);
		
	return Plugin_Handled;
}

public int MenuHandler_MainMenu(Menu menuHandle, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char selection[2];
			char query[100];
			GetMenuItem(menuHandle, param2, selection, sizeof(selection));
			switch(StringToInt(selection))
			{
				case 1:
				{
					FormatEx(query, sizeof(query), "SELECT * FROM `timeWatch` WHERE `player_id` = '%i';", g_iPlayerUId[param1]);
					g_hDatabase.Query(SQLT_SelectPlayerData, query, param1);
				}
				case 2:
				{
					g_hTopsMenu.Display(param1, MENU_TIME_FOREVER);
				}
				case 3:
				{
					g_hDatabase.Query(SQLT_OnSelectAllPlayers, "SELECT `uId`, `player_name` FROM `timeWatch_players` ORDER BY `last_time_joined` DESC;", param1);
				}
			}
		}
	}
}

public int MenuHandler_TopsMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char selection[2];
			char query[200];
			GetMenuItem(menu, param2, selection, sizeof(selection));
			switch(StringToInt(selection))
			{
				case 1:
				{
					FormatEx(query, sizeof(query), "SELECT SUM( `time_team_none` + `time_team_spec` + `time_team_t` + `time_team_ct` ) AS total, player_id FROM `timeWatch` GROUP BY player_id ORDER BY total DESC");
					g_hDatabase.Query(SQLT_OnSelectTopPlayers, query, param1);
				}
				case 2:
				{
					FormatEx(query, sizeof(query), "SELECT SUM( `time_team_ct`) AS total, player_id FROM `timeWatch` GROUP BY player_id ORDER BY total DESC");
					g_hDatabase.Query(SQLT_OnSelectTopPlayers, query, param1);
				}
				case 3:
				{
					FormatEx(query, sizeof(query), "SELECT SUM( `time_team_t`) AS total, player_id FROM `timeWatch` GROUP BY player_id ORDER BY total DESC");
					g_hDatabase.Query(SQLT_OnSelectTopPlayers, query, param1);
				}
				case 4:
				{
					FormatEx(query, sizeof(query), "SELECT SUM( `time_team_spec`) AS total, player_id FROM `timeWatch` GROUP BY player_id ORDER BY total DESC");
					g_hDatabase.Query(SQLT_OnSelectTopPlayers, query, param1);
				}
				case 5:
				{
					FormatEx(query, sizeof(query), "SELECT SUM( `time_team_ct` + `time_team_t`) AS total, player_id FROM `timeWatch` GROUP BY player_id ORDER BY total DESC");
					g_hDatabase.Query(SQLT_OnSelectTopPlayers, query, param1);
				}
				case 6:
				{
					g_hDatabase.Query(SQLT_OnSelectTopPlayers, "SELECT SUM(`time_team_none` + `time_team_spec` + `time_team_t` + `time_team_ct`) AS total, `player_id` FROM timeWatch WHERE `date_string` > DATE_SUB(NOW(), INTERVAL 7 DAY) GROUP BY `player_id` ORDER BY total DESC LIMIT 7", param1);
				}
			}
		}
	}
	if(param2 == MenuCancel_ExitBack)
		g_hMainMenu.Display(param1, MENU_TIME_FOREVER);
}

public void SQLT_OnSelectAllPlayers(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);

	if(client > 0 && IsClientInGame(client))
	{
		Menu menu = new Menu(MenuHandler_PlayersMenuHandler);
		menu.SetTitle("================\nnSelect a Player\n================");
		SetMenuExitBackButton(menu, true);
		
		char player_name[MAX_NAME_LENGTH];
		char player_string_id[4];
		int player_id;
		
		while(results.FetchRow())
		{
			player_id = results.FetchInt(0);
			results.FetchString(1, player_name, sizeof(player_name));
			IntToString(player_id, player_string_id, sizeof(player_string_id));
			menu.AddItem(player_string_id, player_name);
		}
		
		menu.Display(client, MENU_TIME_FOREVER);
	}
}

public int MenuHandler_PlayersMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char selection[4];
			char query[200];
			GetMenuItem(menu, param2, selection, sizeof(selection));
			
			FormatEx(query, sizeof(query), "SELECT `time_team_none`, `time_team_spec`, `time_team_t`, `time_team_ct`, `player_id` FROM `timeWatch` WHERE `player_id` = '%i'", StringToInt(selection));
			g_hDatabase.Query(SQLT_SpecificPlayerData, query, param1);
		}
		case MenuCancel_Exit:delete menu;
	}
	
	if(param2 == MenuCancel_ExitBack)
		g_hMainMenu.Display(param1, MENU_TIME_FOREVER);
}

public void SQLT_SpecificPlayerData(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);

	if(client > 0 && IsClientInGame(client))
	{
		results.FetchRow();
		
		DataPack datapack = new DataPack();
		int none = results.FetchInt(0);
		int spec = results.FetchInt(1);
		int tr = results.FetchInt(2);
		int ct = results.FetchInt(3);
		int uId = results.FetchInt(4);
		
		char menu_item[64];
		char query[255];
		
		Menu menu = new Menu(MenuHandler_SpecificPlayerHandler);
		SetMenuExitBackButton(menu, true);

		_FormatTime(none, menu_item, sizeof(menu_item));
		Format(menu_item, sizeof(menu_item), "NONE: %s", menu_item);
		menu.AddItem("", menu_item, ITEMDRAW_DISABLED);
		
		_FormatTime(spec, menu_item, sizeof(menu_item));
		Format(menu_item, sizeof(menu_item), "SPEC: %s", menu_item);
		menu.AddItem("", menu_item, ITEMDRAW_DISABLED);
		
		_FormatTime(tr, menu_item, sizeof(menu_item));
		Format(menu_item, sizeof(menu_item), "TR: %s", menu_item);
		menu.AddItem("", menu_item, ITEMDRAW_DISABLED);
		
		_FormatTime(ct, menu_item, sizeof(menu_item));
		Format(menu_item, sizeof(menu_item), "CT: %s", menu_item);
		menu.AddItem("", menu_item, ITEMDRAW_DISABLED);
		
		WritePackCell(datapack, client);
		WritePackCell(datapack, menu);
		
		FormatEx(query, sizeof(query), "SELECT `player_name`, `player_steamid64` FROM timeWatch_players WHERE `uId` = '%i'", uId);
		g_hDatabase.Query(SQLT_FinishPlayerProfile, query, datapack);
	}
}

public void SQLT_FinishPlayerProfile(Database database, DBResultSet results, const char[] error, DataPack pack)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);

	pack.Reset();
	int client = pack.ReadCell();
	
	if(client > 0 && IsClientInGame(client))
	{
		results.FetchRow();
		
		Menu menu = pack.ReadCell();
		
		char player_name[MAX_NAME_LENGTH];
		char player_steamid64[30];
		
		results.FetchString(0, player_name, sizeof(player_name));
		menu.SetTitle("================\nProfile of %s\n================", player_name);
		
		results.FetchString(1, player_steamid64, sizeof(player_steamid64));
		menu.AddItem(player_steamid64, "Steam Profile ( Chat )");
		
		menu.Display(client, MENU_TIME_FOREVER);
	}
}

public void SQLT_OnSelectTopPlayers(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);

	if(client > 0 && IsClientInGame(client))
	{
		int time;
		int player_id;
		char query[100];
		
		Menu menu = new Menu(MenuHandler_TopPlayerMenuHandler);
		menu.SetTitle("================\nTop Players\n================");
		SetMenuExitBackButton(menu, true);
		
		while(results.FetchRow())
		{
			time = results.FetchInt(0);
			if(time > 0)
			{
				player_id = results.FetchInt(1);
				
				DataPack datapack = new DataPack();
				WritePackCell(datapack, client);
				WritePackCell(datapack, time);
				WritePackCell(datapack, menu);
				
				FormatEx(query, sizeof(query), "SELECT `player_steamid64`, `player_name` FROM `timeWatch_players` WHERE `uId` = '%i';", player_id);
				g_hDatabase.Query(SQLT_GetTopPlayerNames, query, datapack);		
			}
		}
	}
}

public int MenuHandler_TopPlayerMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	/*if(action == MenuAction_End)
		delete menu;
	*/
	if(param2 == MenuCancel_ExitBack)
		g_hTopsMenu.Display(param1, MENU_TIME_FOREVER);
}

public void SQLT_GetTopPlayerNames(Database database, DBResultSet results, const char[] error, DataPack pack)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);

	pack.Reset();
	int client = pack.ReadCell();
	int time = pack.ReadCell();
	Menu menu = pack.ReadCell();
	
	CloseHandle(pack);
	
	if(client > 0 && IsClientInGame(client))
	{
		while(results.FetchRow())
		{
			char steamid64[MAX_NAME_LENGTH];
			char player_name[MAX_NAME_LENGTH];
			char time_buffer[MAX_NAME_LENGTH];
			char menu_item[MAX_NAME_LENGTH * 2];
			
			results.FetchString(0, steamid64, sizeof(steamid64));
			results.FetchString(1, player_name, sizeof(player_name));
			
			_FormatTime(time, time_buffer, sizeof(time_buffer));
			FormatEx(menu_item, sizeof(menu_item), "%s\n Played for %s", player_name, time_buffer);
			
			menu.AddItem(steamid64, menu_item, ITEMDRAW_DISABLED);
		}
		menu.Display(client, MENU_TIME_FOREVER);
	}
}

public void SQLT_SelectPlayerTotalTime(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);

	if(client > 0 && IsClientInGame(client))
	{
		results.FetchRow();
		int total = results.FetchInt(0);
		char time[32];
		_FormatTime(total, time, sizeof(time));
		
		PrintToChatAll("★\x04[\x03TIMEWATCH\x04]\x05 Player\x09 %N\x05 has spent\x09 %s\x05 on this server.", client, time);
	}
}

public void SQLT_SelectPlayerData(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);

	if(client > 0 && IsClientInGame(client))
	{
		int none, spec, ct, t, count;
		char buffer[256];
		
		while(results.FetchRow())
		{
			none = none + results.FetchInt(3);
			spec = spec + results.FetchInt(4);
			t = t + results.FetchInt(5);
			ct = ct + results.FetchInt(6);
			count = count + 1;
		}
		
		Menu menu = new Menu(MenuHandler_LocalPlayerStats);
		menu.ExitBackButton = true;
		
		menu.SetTitle("================\nYou've been online\nfor at least 1 second\na day for %i Days\n================", results.RowCount);
	
		_FormatTime(ct, buffer, sizeof(buffer));
		Format(buffer, sizeof(buffer), "CT: %s", buffer);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);

		_FormatTime(t, buffer, sizeof(buffer));
		Format(buffer, sizeof(buffer), "TR: %s", buffer);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
	
		_FormatTime(none, buffer, sizeof(buffer));
		Format(buffer, sizeof(buffer), "NONE: %s", buffer);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);
		
		_FormatTime(spec, buffer, sizeof(buffer));
		Format(buffer, sizeof(buffer), "SPEC: %s", buffer);
		menu.AddItem("", buffer, ITEMDRAW_DISABLED);

		if(count == 0)
			_FormatTime(RoundToNearest(float((none + spec + ct + t) / 1)), buffer, sizeof(buffer));
		else 
			_FormatTime(RoundToNearest(float((none + spec + ct + t) / count)), buffer, sizeof(buffer));
			
		Format(buffer, sizeof(buffer), "AVG: %s", buffer);
		menu.AddItem("6", buffer, ITEMDRAW_DISABLED);
		
		DataPack datapack = new DataPack();
		WritePackCell(datapack, client);
		WritePackCell(datapack, menu);
		
		Format(buffer, sizeof(buffer), "SELECT SUM(`time_team_none` + `time_team_spec` + `time_team_t` + `time_team_ct`) AS total FROM timeWatch WHERE `date_string` > DATE_SUB(NOW(), INTERVAL 7 DAY) AND `player_id` = '%i' GROUP BY DAY(`date_string`) ORDER BY DAY(`date_string`) DESC LIMIT 7;", g_iPlayerUId[client]);
		g_hDatabase.Query(SQLT_SelectedPast7Days, buffer, datapack);
	}
}

public void SQLT_SelectedPast7Days(Database database, DBResultSet results, const char[] error, DataPack pack)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);
	
	pack.Reset();
	int client = pack.ReadCell();
	Menu menu = pack.ReadCell();
	CloseHandle(pack);
	
	if(client > 0 && IsClientInGame(client))
	{
		char menu_item[32];
		int sum = 0;
		while(results.FetchRow())
		{
			sum = sum + results.FetchInt(0);
		}
		_FormatTime(sum, menu_item, sizeof(menu_item));
		Format(menu_item, sizeof(menu_item), "Last Week: %s", menu_item);
		
		menu.AddItem("", menu_item, ITEMDRAW_DISABLED);
		menu.Display(client, MENU_TIME_FOREVER);
	}
}

public int MenuHandler_SpecificPlayerHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char selection[64];
			GetMenuItem(menu, param2, selection, sizeof(selection));
			
			PrintToChat(param1, "*\x04 https://steamcommunity.com/profiles/%s", selection);
			
		}
		case MenuAction_End:delete menu;
	}

	if(param2 == MenuCancel_ExitBack)
		g_hDatabase.Query(SQLT_OnSelectAllPlayers, "SELECT `uId`, `player_name` FROM `timeWatch_players` ORDER BY `last_time_joined` DESC;", param1);
}

public int MenuHandler_LocalPlayerStats(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
		delete menu;

	if(param2 == MenuCancel_ExitBack)
		g_hMainMenu.Display(param1, MENU_TIME_FOREVER);
}

public void SQLT_OnConnect(Database database, const char[] error, any data)
{
	if(database == null)
	{
		LogError("[DATABASE ERROR] Could Not Connect to DataBase. Error: \"%s\".", error);
		SetFailState("[DATABASE ERROR] %s", error);
	}
	
	g_hDatabase = database;
	g_hDatabase.Query(SQLT_OnTablesCreated,\
	"CREATE TABLE IF NOT EXISTS `timeWatch_players` (`uId` INT(16) PRIMARY KEY NOT NULL AUTO_INCREMENT, `player_steamid64` VARCHAR(32) NOT NULL, `player_name` VARCHAR(32) NOT NULL, `first_time_joined` INT(16), `last_time_joined` INT(16));");

	g_hDatabase.Query(SQLT_OnTablesCreated,\
	"CREATE TABLE IF NOT EXISTS `timeWatch` (`id` INT(16) PRIMARY KEY NOT NULL AUTO_INCREMENT, `player_id` INT(16), `date_string` VARCHAR(32), `time_team_none` INT(16) DEFAULT 0, `time_team_spec` INT(16) DEFAULT 0, `time_team_t` INT(16) DEFAULT 0, `time_team_ct` INT(16) DEFAULT 0);");
}

public void SQLT_OnTablesCreated(Database database, DBResultSet results, const char[] error, any data)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);
}

public void OnClientDisconnect(int client)
{
	if(g_hTimeManageTimer[client] != null)
	{
		delete g_hTimeManageTimer[client];
		g_hTimeManageTimer[client] = null;
	}
	g_iPlayerUId[client] = 0;
	
	for (int i = 0; i < 4; i++)
		g_iPlayedSeconds[client][i] = 0;
}

public void OnClientPostAdminCheck(int client)
{
	if(client >= 1 && client <= MaxClients)
	{
		if(g_hTimeManageTimer[client] != null)
		{
			delete g_hTimeManageTimer[client];
			g_hTimeManageTimer[client] = null;
		}
		
		g_hTimeManageTimer[client] = CreateTimer(1.0, Timer_ManageTimer, client, DEFAULT_TIMER_FLAGS);
		g_iPlayerUId[client] = 0;
		for (int i = 0; i < 4; i++)
			g_iPlayedSeconds[client][i] = 0;
		
		char query[100];
		GetClientAuthId(client, AuthId_SteamID64, g_sSteamId64[client], sizeof(g_sSteamId64[]));
		
		FormatEx(query, sizeof(query), "SELECT `uId` FROM `timeWatch_players` WHERE `player_steamid64` = '%s';", g_sSteamId64[client]);
		g_hDatabase.Query(SQLT_OnClientFullConnect, query, client);
	}
}

public void SQLT_OnClientFullConnect(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);
		
	if(client > 0 && IsClientInGame(client))
	{
		char name[MAX_NAME_LENGTH], query[300];
		GetClientName(client, name, sizeof(name));
		
		int len = strlen(name) * 2 + 1;
		char[] escaped_name = new char[len];
		g_hDatabase.Escape(name, escaped_name, len);
		
		results.FetchRow();
		if(results.RowCount == 0)
		{
			g_iPlayerUId[client] = 0;
			FormatEx(query, sizeof(query), "INSERT INTO `timeWatch_players` (`player_steamid64`, `player_name`, `first_time_joined` , `last_time_joined`) VALUES ('%s', '%s', '%i', '%i');", g_sSteamId64[client], escaped_name, GetTime(), GetTime());
			g_hDatabase.Query(SQLT_OnNewPlayerInserted, query, client);
		}
		else
		{
			g_iPlayerUId[client] = results.FetchInt(0);
			
			FormatEx(query, sizeof(query), "UPDATE `timeWatch_players` SET `player_name` = '%s', `last_time_joined` = '%i' WHERE player_steamid64 = '%s';", escaped_name, GetTime(), g_sSteamId64[client]);
			g_hDatabase.Query(SQLT_OnPlayerUpdated, query);
			
			FormatEx(query, sizeof(query), "SELECT `date_string` FROM `timeWatch` WHERE `player_id` = '%i' ORDER BY `date_string` DESC LIMIT 1;", g_iPlayerUId[client]);
			g_hDatabase.Query(SQLT_SelectClientDateString, query, client);
		}
	}
}

public void SQLT_OnNewPlayerInserted(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);
	
	if(client > 0 && IsClientInGame(client))
	{
		g_hDatabase.Query(SQLT_GetClientUId, "SELECT * FROM `timeWatch_players` ORDER BY `uid` DESC LIMIT 1", client);
	}
}

public void SQLT_GetClientUId(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);
	
	if(client > 0 && IsClientInGame(client))
	{
		char query[120];
		results.FetchRow();
		g_iPlayerUId[client] = results.FetchInt(0) + 1;
		FormatEx(query, sizeof(query), "SELECT `date_string` FROM `timeWatch` WHERE `player_id` = '%i' ORDER BY `date_string` DESC LIMIT 1;", g_iPlayerUId[client]);
		g_hDatabase.Query(SQLT_SelectClientDateString, query, client);
	}
}

public void SQLT_SelectClientDateString(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);
	
	if(client > 0 && IsClientInGame(client))
	{
		char query[100], curdate[14], date_string[14];
		FormatTime(curdate, sizeof(curdate), "%G-%m-%d", GetTime());
		results.FetchRow();
		if(results.RowCount > 0)
		{
			results.FetchString(0, date_string, sizeof(date_string));
			if(strcmp(date_string, curdate) != 0)
			{
				FormatEx(query, sizeof(query), "INSERT INTO `timeWatch`	(`player_id`, `date_string`) VALUES ('%i', '%s');", g_iPlayerUId[client], curdate);
				g_hDatabase.Query(SQLT_FinalInsert, query);	
			}	
		}
		else
		{
			FormatEx(query, sizeof(query), "INSERT INTO `timeWatch`	(`player_id`, `date_string`) VALUES ('%i', '%s');", g_iPlayerUId[client], curdate);
			g_hDatabase.Query(SQLT_FinalInsert, query);	
		}
	}
}

public void SQLT_FinalInsert(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);
}

public void SQLT_OnPlayerUpdated(Database database, DBResultSet results, const char[] error, int client)
{
	if(results == null)
		LogError("[DATABASE ERROR]: \"%s\".", error);
}

public Action Timer_ManageTimer(Handle timer, int client)
{
	if(client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		g_hTimeManageTimer[client] = null;
		return Plugin_Stop;
	}
	
	int team = GetClientTeam(client);
	g_iPlayedSeconds[client][team] = g_iPlayedSeconds[client][team] + 1;
	
	return Plugin_Continue;
}

public Action Timer_UpdateDataForAllClient(Handle timer)
{
	char query[255], curdate[12];
	FormatTime(curdate, sizeof(curdate), "%G-%m-%d", GetTime());
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			FormatEx(query, sizeof(query), "UPDATE `timeWatch` SET `time_team_none` = time_team_none + '%i', `time_team_spec` = time_team_spec + '%i', `time_team_t` = time_team_t + '%i', `time_team_ct` = time_team_ct + '%i' WHERE `player_id` = '%i' AND `date_string` = '%s';", \
			g_iPlayedSeconds[client][0], g_iPlayedSeconds[client][1], g_iPlayedSeconds[client][2], g_iPlayedSeconds[client][3], g_iPlayerUId[client], curdate);
			g_hDatabase.Query(SQLT_OnPlayerUpdated, query);
		}
	}
}

// https://github.com/Franc1sco/MostActive/blob/master/gameserver/addons/sourcemod/scripting/mostactive.sp#L579-L607
int _FormatTime(int time, char[] buffer, int buffer_size)
{
	int h = 0;
	int m = 0;
	int s = time;
	
	while(s > 3600)
	{
		h++;
		s -= 3600;
	}
	while(s > 60)
	{
		m++;
		s -= 60;
	}
	if(h >= 1){
		Format(buffer, buffer_size, "%d Hrs. %d Mins.", h, m, s);
	}
	else if(m >= 1){
		Format(buffer, buffer_size, "%d Mins. %d Secs.", m, s);
	}
	else{
		Format(buffer, buffer_size, "%d Secs.", s);
	}
}