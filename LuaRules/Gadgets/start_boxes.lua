if not gadgetHandler:IsSyncedCode() or VFS.FileExists("mission.lua") then return end

function gadget:GetInfo() return {
	name     = "Startbox handler",
	desc     = "Handles startboxes",
	author   = "Sprung",
	date     = "2015-05-19",
	license  = "PD",
	layer    = -1,
	enabled  = true,
} end

local gaiaAllyTeamID = select(6, Spring.GetTeamInfo(Spring.GetGaiaTeamID()))
local shuffleMode = Spring.GetModOptions().shuffle or "off"

VFS.Include ("LuaRules/Utilities/startbox_utilities.lua")

--[[ expose a randomness seed
this is so that LuaUI can reproduce randomness in the box config as otherwise they use different seeds
afterwards, reseed with a secret seed to prevent LuaUI from reproducing the randomness used for shuffling ]]

-- turns out synced RNG is seeded only *after* the game starts so we have to hack ourselves another source of randomness
-- this makes the shuffle result discoverable through a widget with some extra work - hopefully the engine gets fixed sometime
local public_seed = 123 * string.len(Spring.GetModOptions().commandertypes or "some string")
local private_seed = math.random(13,37) * public_seed

Spring.SetGameRulesParam("public_random_seed", public_seed)
local startboxConfig = ParseBoxes()
math.randomseed(private_seed)

GG.startBoxConfig = startboxConfig

local function CheckStartbox (boxID, x, z)
	if not boxID then
		return true
	end

	local box = startboxConfig[boxID] and startboxConfig[boxID].boxes
	if not box then
		return true
	end

	for i = 1, #box do
		local x1, z1, x2, z2, x3, z3 = unpack(box[i])
		if (cross_product(x, z, x1, z1, x2, z2) <= 0
		and cross_product(x, z, x2, z2, x3, z3) <= 0
		and cross_product(x, z, x3, z3, x1, z1) <= 0
		) then
			return true
		end
	end

	return false
end

-- name, elo, clanShort, clanLong, isAI
local function GetPlayerInfo (teamID)
	local _,playerID,_,isAI = Spring.GetTeamInfo(teamID)

	if isAI then
		return select(2, Spring.GetAIInfo(teamID)), -1000, "", "", true
	end

	local name = Spring.GetPlayerInfo(playerID) or "?"
	local customKeys = select(10, Spring.GetPlayerInfo(playerID)) or {}
	local clanShort = customKeys.clan     or ""
	local clanLong  = customKeys.clanfull or ""
	local elo       = customKeys.elo      or "0"
	return name, tonumber(elo), clanShort, clanLong, false
end

-- returns full name and short name (mostly for clans, eg. "Mean Machines" vs "MM")
local function GetTeamNames (allyTeamID)
	if allyTeamID == gaiaAllyTeamID then
		return "Neutral", "Neutral" -- more descriptive than "Gaia"
	end

	local teamList = Spring.GetTeamList(allyTeamID) or {}
	if #teamList == 0 then
		return "Empty", "Empty"
	end

	local clanShortName, clanLongName
	local clanFirst = true
	local leaderName = ""
	local leaderElo = -2000
	local bots = 0
	local humans = 0
	for i = 1, #teamList do
		local name, elo, clanShort, clanLong, isAI = GetPlayerInfo(teamList[i])
		if clanFirst then
			clanShortName = clanShort
			clanLongName  = clanLong
			clanFirst = false
		else
			if not isAI and clanShort ~= clanShortName then
				clanShortName = ""
				clanLongName = ""
			end
		end

		if elo > leaderElo then
			leaderName = name
			leaderElo = elo
		end

		if isAI then
			bots = bots + 1
		else
			humans = humans + 1
		end
	end

	if humans == 1 then
		return leaderName, leaderName
	end

	if humans == 0 then
		return "AI", "AI"
	end

	if clanShortName ~= "" then
		return clanLongName, clanShortName
	end

	if ((shuffleMode == "off")
		or (GetTeamCount() == 2 and shuffleMode == "shuffle")
		or (#startboxConfig == 1 and shuffleMode == "allshuffle")) -- actually means # == 2 since it counts from 0
	then
		local boxID = Spring.GetTeamRulesParam(teamList[1], "start_box_id")
		if boxID then
			local box = startboxConfig[boxID]
			if box.nameLong and box.nameShort then
				return box.nameLong, box.nameShort
			end
		end
	end

	return ("Team " .. leaderName), leaderName
end

function gadget:Initialize()

	Spring.SetGameRulesParam("startbox_max_n", #startboxConfig)
	Spring.SetGameRulesParam("startbox_recommended_startpos", 1)

	local rawBoxes = GetRawBoxes()
	for box_id, polygons in pairs(rawBoxes) do
		Spring.SetGameRulesParam("startbox_n_" .. box_id, #polygons)
		for i = 1, #polygons do
			local polygon = polygons[i]
			Spring.SetGameRulesParam("startbox_polygon_" .. box_id .. "_" .. i, #polygons[i])
			for j = 1, #polygons[i] do
				Spring.SetGameRulesParam("startbox_polygon_x_" .. box_id .. "_" .. i .. "_" .. j, polygons[i][j][1])
				Spring.SetGameRulesParam("startbox_polygon_z_" .. box_id .. "_" .. i .. "_" .. j, polygons[i][j][2])
			end
		end
	end
	
	for box_id, box in pairs(startboxConfig) do
		local startposes = box.startpoints
		Spring.SetGameRulesParam("startpos_n_" .. box_id, #startposes)
		for i = 1, #startposes do
			Spring.SetGameRulesParam("startpos_x_" .. box_id .. "_" .. i, startposes[i][1])
			Spring.SetGameRulesParam("startpos_z_" .. box_id .. "_" .. i, startposes[i][2])
		end
	end

	math.randomseed(private_seed)

	-- filter out fake teams (empty or Gaia)
	local allyTeamList = Spring.GetAllyTeamList()
	local actualAllyTeamList = {}
	for i = 1, #allyTeamList do
		local teamList = Spring.GetTeamList(allyTeamList[i]) or {}
		if ((#teamList > 0) and (allyTeamList[i] ~= gaiaAllyTeamID)) then
			actualAllyTeamList[#actualAllyTeamList+1] = {allyTeamList[i], math.random()}
		end
	end

	if (shuffleMode == "off") then

		for i = 1, #allyTeamList do
			local allyTeamID = allyTeamList[i]
			local boxID = allyTeamList[i]
			if startboxConfig[boxID] then
				local teamList = Spring.GetTeamList(allyTeamID) or {}
				for j = 1, #teamList do
					Spring.SetTeamRulesParam(teamList[j], "start_box_id", boxID)
				end
			end
		end

	elseif (shuffleMode == "shuffle") then

		local randomizedSequence = {}
		for i = 1, #actualAllyTeamList do
			randomizedSequence[#randomizedSequence + 1] = {actualAllyTeamList[i][1], math.random()}
		end
		table.sort(randomizedSequence, function(a, b) return (a[2] < b[2]) end)

		for i = 1, #actualAllyTeamList do
			local allyTeamID = actualAllyTeamList[i][1]
			local boxID = randomizedSequence[i][1]
			if startboxConfig[boxID] then
				local teamList = Spring.GetTeamList(allyTeamID) or {}
				for j = 1, #teamList do
					Spring.SetTeamRulesParam(teamList[j], "start_box_id", boxID)
				end
			end
		end

	elseif (shuffleMode == "allshuffle") then

		local randomizedSequence = {}
		for id in pairs(startboxConfig) do
			randomizedSequence[#randomizedSequence + 1] = {id, math.random()}
		end
		table.sort(randomizedSequence, function(a, b) return (a[2] < b[2]) end)
		table.sort(actualAllyTeamList, function(a, b) return (a[2] < b[2]) end)

		for i = 1, #actualAllyTeamList do
			local allyTeamID = actualAllyTeamList[i][1]
			local boxID = randomizedSequence[i] and randomizedSequence[i][1]
			if boxID and startboxConfig[boxID] then
				local teamList = Spring.GetTeamList(allyTeamID) or {}
				for j = 1, #teamList do
					Spring.SetTeamRulesParam(teamList[j], "start_box_id", boxID)
				end
			end
		end
	end

	for i = 1, #allyTeamList do
		local allyTeamID = allyTeamList[i]
		local longName, shortName = GetTeamNames(allyTeamID)
		Spring.SetGameRulesParam("allyteam_short_name_" .. allyTeamID, shortName)
		Spring.SetGameRulesParam("allyteam_long_name_"  .. allyTeamID, longName)
	end
end

GG.CheckStartbox = CheckStartbox

function gadget:AllowStartPosition(x, y, z, playerID, readyState)
	if (x == 0 and z == 0) then
		-- engine default startpos
		return false
	end

	if (playerID == 255) then
		return true -- custom AI, can't know which team it is on so allow it to place anywhere for now and filter invalid positions later
	end

	local teamID = select(4, Spring.GetPlayerInfo(playerID))
	local boxID = Spring.GetTeamRulesParam(teamID, "start_box_id")

	if (not boxID) or CheckStartbox(boxID, x, z) then
		Spring.SetTeamRulesParam (teamID, "valid_startpos", 1)
		return true
	else
		return false
	end
end

function gadget:RecvSkirmishAIMessage(teamID, dataStr)
	local command = "ai_is_valid_startpos:"
	if not dataStr:find(command,1,true) then return end

	local xz = dataStr:sub(command:len()+1)
	local slash = xz:find("/",1,true)
	if not slash then return end

	local x = tonumber(xz:sub(1, slash-1))
	local z = tonumber(xz:sub(slash+1))
	if not x or not z then return end

	local boxID = Spring.GetTeamRulesParam(teamID, "start_box_id")
	if (not boxID) or CheckStartbox(boxID, x, z) then
		return "1"
	else
		return "0"
	end
end
