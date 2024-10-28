bdt = LibStub("AceAddon-3.0"):NewAddon("bdt", "AceConsole-3.0", "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local ACD = LibStub("AceConfigDialog-3.0")

--... is passed into every lua file of an addon and contains the addonname as in the toc file and an empty table that is shared over all lua files of the addon.
local addonName, bdtns = ...

--damit ich die debugnachrichten leichter deaktivieren (und wenns ma fertig ist löschen) kann
local function debugMsg(msg)
	if playerName == "Grmlgrr" or playerName == "Grumlgrr" or playerName == "Grömlgrr" then
		bdt:Print(msg)
	end
end



-- prints all table entries (should work for subtables too) --- maybe deactivate this in the end, dunno if needed when done
local function printAllTableEntries(table)
	for k, v in pairs(table) do
		if type(v) ~= "table" then
			debugMsg(k.." = "..v)
		else
			printAllTableEntries(v)
		end
	end	
end

--checks if a table with no Integer Keys is empty
function isTableEmpty(tbl)
    for _ in pairs(tbl) do
        return false
    end
    return true
end
--checks if a variable is a POSITIVE integer
local function isInteger(a)
	if type(a) == "number" then
		return a == math.floor(a)
	elseif type(a) == "string" then
		return a:match("^%d+$")
	else
		return false
	end
end

--checks if a variable is a string
local function isString(a)
	return type(a) == "string"
end

--splits a String into subStrings at Spaces and returns a table of substrings in order
local function splitString(string)
	local subStrings = {}
	for i in string.gmatch(string, "%S+") do
		table.insert(subStrings, i)
	end
	return subStrings
end

--generates a Session ID in hexadecimal - hope this is done okish, no clue though
local function generateSessionId()
	return string.format("%x", tostring(math.random(100000,999999)..math.floor(GetTime())))
end

--extracts sessionId from a sent string (everything before the @@)
local function extractSessionId(string)
	local position, _ = string.find(string, "@@")
	string = string.sub(string, 1, position - 1)
	return string
end

--schreibt Fehlermeldungen ins Standardchatfenster (Umlaute werden nicht richtig angezeigt!)
local errormsgTimes = {}
local function errormsg(msg)
	--clearing the table of outdated entries (currently 3 seconds no-spam-window for each error msg)
	for k, v in pairs(errormsgTimes) do
		-- the 3 is the 3 second no-spam-time
		if v + 3 <= GetTime() then
			errormsgTimes[k] = nil
		end
	end
	--display error in default chatframe if it is no spam (see clearing above)
	if msg and isString(msg) and not errormsgTimes[msg] then
		DEFAULT_CHAT_FRAME:AddMessage(msg, 1.0, 0.1, 0.1, 53, 5)
		--saving time in table to prevent spamming
		errormsgTimes[msg] = GetTime()		
	end
end

--ersetzt %LVLMIN, %LVLMAX and %CODEWORT mit den aktuellen Werten in der Datenbank
local function advertiseMessageReplaces(msg)
	local newMsg = ""
	newMsg = string.gsub(msg, "%%LVLMIN", bdt.db.profile.lvlMin)
	newMsg = string.gsub (newMsg, "%%LVLMAX", bdt.db.profile.lvlMax)
	newMsg = string.gsub (newMsg, "%%CODEWORT", bdt.db.profile.advertiseKeyword)
	return newMsg
end

--convert the string in the options into a usable table
local function createSyncMatesTable(string)	
	local subStrings = {}
	string = string.gsub(string, " ", "")
	string = string.gsub(string, ",", " ")
	for i in string.gmatch(string, "%S+") do
		table.insert(subStrings, i)
	end
	return subStrings
end

--convert SyncMates table to string
local function createSyncMatesString(table)
	local string = ""
	if not isTableEmpty(table) then
		for i = 1, #table, 1 do
			string = string..","..table[i]
		end
		string = string.sub(string, 2)
		return string
	end	
end

local function isSyncMate(name)
	for k, v in pairs(bdt.db.global.syncMates) do
		if v == name then
			return true
		end
	end
	return false
end

local function createBdtrecipientsdatabaseString()
	string = ""
	for k, v in pairs(bdtrecipientsdatabase) do
		string = string..k.." = "
		for l, w in ipairs(v) do
			string = string..w.." "
		end
		string = string.."\n"
	end
	return string
end

local function showMailboxButtons(value)
	if value == true then
		bdtns.advertisingButton:Show()
		bdtns.sendBagsButton:Show()
	elseif value == false then
		bdtns.advertisingButton:Hide()
		bdtns.sendBagsButton:Hide()

	end
end

--variables for frames which open/close status I monitor
local bankOpen = false
local mailboxOpen = false

local adActive = false
local adActivationTime = 0

local guildMemberLevels = {}

local recipientsList = {}
local sendMailSuccessActivator = false
local sendMailFrameCounter = 0
local bagsInMail = 0

local date = ""
local time = ""
local fullTimestamp = ""

local currentTimers = {}

local playerName = GetUnitName("player")

local sessionIds = {}
local latestSync = ""

local function updateGuildMemberLevels()
	if IsInGuild() == 1 then
        GuildRoster()
        
        local name, level, _
        for i = 1, GetNumGuildMembers() do
            name, _, _, level, _, _, _, _, _, _, _  = GetGuildRosterInfo(i)
            guildMemberLevels[name] = level
        end
    end
end

--frames which I check if they are open or closed
local monitoredOpenClosedFrames = {
	["BANKFRAME_OPENED"] = function() bankOpen = true end,
	["BANKFRAME_CLOSED"] = function() bankOpen = false end,
	["MAIL_SHOW"] = function() mailboxOpen = true end,
	["MAIL_CLOSED"] = function() mailboxOpen = false end,
}


SLASH_BAGDONATIONTRACKER1, SLASH_BAGDONATIONTRACKER2, SLASH_BAGDONATIONTRACKER3 = "/bdt", "/bdtinfo", "/bagdonationtracker"
SLASH_BAGDONATIONTRACKERDATABASE1, SLASH_BAGDONATIONTRACKERDATABASE2, SLASH_BAGDONATIONTRACKERDATABASE3, SLASH_BAGDONATIONTRACKERDATABASE4 = "/bdtdb", "/bagdonationtrackerdb", "/bdtrecipientsdatabase", "/bagdonationtrackerdatabase"
SLASH_BAGDONATIONTRACKERADVERTISE1, SLASH_BAGDONATIONTRACKERADVERTISE2, SLASH_BAGDONATIONTRACKERADVERTISE3, SLASH_BAGDONATIONTRACKERADVERTISE4 = "/bdtad", "/bdtadvertise", "/bagdonationtrackerad", "/bagdonationtrackeradvertise"
SLASH_BAGDONATIONTRACKERSTART1, SLASH_BAGDONATIONTRACKERSTART2, SLASH_BAGDONATIONTRACKERSTART3, SLASH_BAGDONATIONTRACKERSTART4 = "/bdtstart", "/bagdonationtrackerstart", "/bdtgo", "/bagdonationtrackergo"
SLASH_BAGDONATIONTRACKERADDTOLIST1 = "/bdtaddtolist"


--checks if value is a valid  itemID of a tradeable bag
local function validateBagType(val)
	if isInteger(val) then
		for i = 1, #bdt.db.global.allBagTypes, 1 do
			if val == bdt.db.global.allBagTypes[i] then
				return true
			end
		end
	end
	return false
end


--deletes all entries in recipientsList, that appear in the database with max or higher amount of bags donated
local function cleanRecipientsList()
	--bdtrecipientsdatabase entries
	for k, v in pairs(recipientsList) do
		if bdtrecipientsdatabase[k] and bdtrecipientsdatabase[k][1] >= bdt.db.profile.donationSize then
			recipientsList[k] = nil
		end
	end
end

--sets date variable in YEAR-MONTH-DAY format
local function setDate()
	date = select(4, CalendarGetDate()).."-"..select(2, CalendarGetDate()).."-"..select(3, CalendarGetDate())
end

--sets time variable in HOUR:MINUTE format
local function setTime()
	time = select(1, GetGameTime())..":"..select(2, GetGameTime())
end

--sets FullTimestamp (and Time and Date in the process)
local function setFullTimestamp()
	local _, month, day, year = CalendarGetDate()
	local hour, minute = GetGameTime()
	setDate()
	setTime()
	if string.len(month) < 2 then
		month = "0"..month
	end
	if string.len(day) < 2 then
		day = "0"..day
	end
	if string.len(hour) < 2 then
		hour = "0"..hour
	end
	if string.len(minute) < 2 then
		minute = "0"..minute
	end
	fullTimestamp = year..month..day..hour..minute
	return true			
end

--sends bags via mail. if returns false, there are no more bags left after. if trü, there MAY be bags left
local function sendBags(partialBagEntitlement, recipient, level)
	--CASE 1
	if partialBagEntitlement then

		for x = 0,4 do
			--debugMsg(x.."bagcycle")
			--cycles through all slots in that bag
			for y = 1, GetContainerNumSlots(x) do
				for z = 1, #bdt.db.profile.bagTypes, 1 do
					if GetContainerItemID(x, y) == bdt.db.profile.bagTypes[z] and (bagsInMail + bdtrecipientsdatabase[recipient][1]) < bdt.db.profile.donationSize then
						--debugMsg("pickupandstuff")
						PickupContainerItem(x, y)
						ClickSendMailItemButton()
						bagsInMail = bagsInMail + 1
					end
				end
			end
		end



		--now there should be either 4 bags in the mail or all remaining bags if there are less than 4



		if (bagsInMail + bdtrecipientsdatabase[recipient][1]) == bdt.db.profile.donationSize then
			debugMsg("sendmail")
			SendMail(recipient, bdt.db.profile.mailSubject, bdt.db.profile.mailBody)
			SendChatMessage(bdt.db.profile.successChatMsg ,"WHISPER" ,nil , recipient)
			debugMsg("sendsuccesschatmsgto "..recipient)

			-- the Database key = Name, 1 = amount of bags donated, 2 = Date Donated, 3 = Time Donated, 4 = Level when donated, 5 = type of bags donated (subtable), 6 = comment 7 = timestamp for sync (yearmonthdayhourminute with 0s, e.g. 202409262220 for 26.09.2024 22:20), 8 = *ursprünglich* erhalten von
			local tempBagsReceived = bdtrecipientsdatabase[recipient][1]
			bdtrecipientsdatabase[recipient] = {bagsInMail + tonumber(tempBagsReceived), date, time, level, 21841, "partial donations, date+time is for latest", fullTimestamp, playerName}

			recipientsList[recipient] = nil
			tempBagsReceived = nil
			bagsInMail = 0

			--should start the sending to consecutive recipients
			debugMsg("registeredevent")
			bdtns.b:RegisterEvent("MAIL_SEND_SUCCESS")
			return true

		elseif (bagsInMail + bdtrecipientsdatabase[recipient][1]) < bdt.db.profile.donationSize and bagsInMail > 0 then
			debugMsg("sendpartialmail")
			SendMail(recipient, bdt.db.profile.mailSubject, bdt.db.profile.mailBody)
			SendChatMessage(bdt.db.profile.partialSuccessChatMsg ,"WHISPER" ,nil , recipient)
			debugMsg("sendsuccesschatmsgto "..recipient.." (partial)")

			-- the Database key = Name, 1 = amount of bags donated, 2 = Date Donated, 3 = Time Donated, 4 = Level when donated, 5 = type of bags donated (subtable), 6 = comment 7 = timestamp for sync (yearmonthdayhourminute with 0s, e.g. 202409262220 for 26.09.2024 22:20), 8 = *ursprünglich* erhalten von
			local tempBagsReceived = bdtrecipientsdatabase[recipient][1]
			bdtrecipientsdatabase[recipient] = {bagsInMail + tonumber(tempBagsReceived), date, time, level, 21841, "partial donations, date+time is for latest", fullTimestamp, playerName}

			recipientsList[recipient] = nil
			tempBagsReceived = nil
			bagsInMail = 0

			return false
		end

		--CASE 2
	elseif not partialBagEntitlement then

		for x = 0,4 do
			--debugMsg(x.."bagcycle")
			--cycles through all slots in that bag
			for y = 1, GetContainerNumSlots(x) do
				for z = 1, #bdt.db.profile.bagTypes, 1 do
					if GetContainerItemID(x, y) == bdt.db.profile.bagTypes[z] and bagsInMail < bdt.db.profile.donationSize then
						--debugMsg("pickupandstuff")
						PickupContainerItem(x, y)
						ClickSendMailItemButton()
						bagsInMail = bagsInMail + 1
					end
				end
			end
		end



		--now there should be either 4 bags in the mail or all remaining bags if there are less than 4



		if bagsInMail == bdt.db.profile.donationSize then
			debugMsg("sendmail")
			SendMail(recipient, bdt.db.profile.mailSubject, bdt.db.profile.mailBody)
			SendChatMessage(bdt.db.profile.successChatMsg ,"WHISPER" ,nil , recipient)
			debugMsg("sendsuccesschatmsgto "..recipient)

			-- the Database key = Name, 1 = amount of bags donated, 2 = Date Donated, 3 = Time Donated, 4 = Level when donated, 5 = type of bags donated (subtable), 6 = comment 7 = timestamp for sync (yearmonthdayhourminute with 0s, e.g. 202409262220 for 26.09.2024 22:20), 8 = *ursprünglich* erhalten von
			bdtrecipientsdatabase[recipient] = {bagsInMail, date, time, level, 21841, "", fullTimestamp, playerName}

			recipientsList[recipient] = nil
			bagsInMail = 0

			--should start the sending to consecutive recipients
			debugMsg("registeredevent")
			bdtns.b:RegisterEvent("MAIL_SEND_SUCCESS")
			return true

		elseif bagsInMail < bdt.db.profile.donationSize and bagsInMail > 0 then
			debugMsg("sendpartialmail")
			SendMail(recipient, bdt.db.profile.mailSubject, bdt.db.profile.mailBody)
			SendChatMessage(bdt.db.profile.partialSuccessChatMsg ,"WHISPER" ,nil , recipient)
			debugMsg("sendsuccesschatmsgto "..recipient.." (partial)")

			-- the Database key = Name, 1 = amount of bags donated, 2 = Date Donated, 3 = Time Donated, 4 = Level when donated, 5 = type of bags donated (subtable), 6 = comment 7 = timestamp for sync (yearmonthdayhourminute with 0s, e.g. 202409262220 for 26.09.2024 22:20), 8 = *ursprünglich* erhalten von
			bdtrecipientsdatabase[recipient] = {bagsInMail, date, time, level, 21841, "", fullTimestamp, playerName}

			recipientsList[recipient] = nil
			bagsInMail = 0
			return false

		end
	end
	--bagsInMail == 0
	return false
end

-- Standardwerte für die BagDonationTrackerDB
local defaults = {
	profile = {
		showMailboxButtons = true,
		lvlMin = 7,
		lvlMax = 79,
		mailSubject = "!!!Taschenlieferung!!! Viel Spaß mit den neuen Taschen!",
		mailBody = "",
		donationSize = 4,
		bagTypes = {
			21841, -- Netherweave Bag
			--4500, -- Traveler's Backpack
		},
		advertiseMessage = "Ich verschenke 16 slot Taschen an Spieler von Level %LVLMIN bis %LVLMAX. Bitte flüstert mich in den nächsten 2 Minuten mit AUSCHLIEßLICH dem folgenden Codewort an, den Rest macht dieses Addon: {rt1}%CODEWORT{rt1}",
		advertiseKeyword = "taschen",
		successChatMsg = "Taschen sind auf dem Weg",
		partialSuccessChatMsg = "Taschen sind auf dem Weg. Es waren allerdings nicht mehr genügend übrig, melde dich gerne beim nächsten Mal nochmal um die restlichen zu erhalten",
		failChatMsg = "Sorry, es waren nicht mehr genug Taschen für dich übrig. Probier es gerne beim nochmal beim nächsten Mal",
		allowSync = false,
	},
	global = {
		allBagTypes = {
			21841,	--Netherweave Bag
			4500,	--Traveler's Bagpack
			41599,	--Frostweave Bag
			804,
			805,
			828,
			856,
			857,
			932,
			933,
			1470,
			1623,
			1652,
			1685,
			1725,
			1977,
			2101,
			2102,
			2657,
			3233,
			3914,
			4238,
			4240,
			4241,
			4245,
			4496,
			4497,
			4498,
			4499,
			5081,
			5439,
			5441,
			5571,
			5572,
			5573,
			5574,
			5575,
			5576,
			5762,
			5763,
			5764,
			5765,
			7278,
			7279,
			7371,
			7372,
			8217,
			8218,
			10050,
			10051,
			11362,
			11363,
			14046,
			14155,
			14156,
			19291,
			21340,
			21341,
			21342,
			21843,
			21858,
			21872,
			21876,
			22246,
			22248,
			22249,
			22250,
			22251,
			22252,
			23774,
			23775,
			24270,
			29540,
			30744,
			30745,
			30746,
			30747,
			30748,
			34099,
			34100,
			34105,
			34106,
			34482,
			34490,
			38082,
			38225,
			38307,
			38347,
			38399,
			39489,
			41597,
			41598,
			41600,
			44446,
			44447,
			44448,
			45773,
			51809
		},	-- contains all tradable bags' itemIDs sorted from low to high, but most common 3 bags at the start
		syncMates = {
			"Grmlgrr",
		},
		currentSyncMate = {1},
		latestSyncs = {
			["Grmlgrr"] = 0,
		},
	}

}


--this is for timing (should fire every frame or so)
local timeElapsed = 0
function OnUpdatea (self, elapsed)	--elapsed is in seconds
	timeElapsed = timeElapsed + elapsed
	if timeElapsed > 0.1 then
		timeElapsed = 0
		-- checking if the 120 second advertise-time is over
		if adActive == true then
			if adActivationTime + 120 <= GetTime() then
				adActive = false
				bdt:Print("Charakternamen gesammelt, bitte öffne einen Briefkasten (und vllt. deine Bank) und gib '/bdtstart' ein um die Taschen zu verschicken")
				SendChatMessage("Die Zeit ist um, Anfragen wurden gesammelt. Die Taschen werden gleich abgeschickt und sind in 1h von jedem Briefkasten abholbar - Empfänger bekommen eine Nachricht bei Versand","GUILD")

			end
		end
	end
end

--for mailing
function OnEventbHook(self, event, arg1)
	sendMailSuccessActivator = true
end

function OnUpdateb(self, elapsed)
	if sendMailSuccessActivator == true then
		if sendMailFrameCounter >= 5 then
			debugMsg("counter over limit")
			sendMailFrameCounter = 0
			sendMailSuccessActivator = false

			debugMsg("eventstuff started")


			--similar routine to /bdtstart first iteration
			setFullTimestamp()
			local recipient = ""
			local level = 0
			--cycles through all bags x is bagID, y is Slot in current bag and z are the allowed bag ItemIDs
			if not isTableEmpty(recipientsList) then
				debugMsg("still stuff left in the list")
				
				for k, v in pairs(recipientsList) do
					recipient = k
					level = v
					break
				end

				
				if sendBags(bdtrecipientsdatabase[recipient], recipient, level) then

					-- just exits the function, the "true" means there MAY be bags left
					return true
				else
					debugMsg("nomorebags")
					-- send whisper to unserved (remaining) recipients
					for l, w in pairs(recipientsList) do
						SendChatMessage(bdt.db.profile.failChatMsg ,"WHISPER" ,nil ,l)
					end

					recipientsList = {}

					debugMsg("unregisterevent via Eventhook")
					bdtns.b:UnregisterEvent("MAIL_SEND_SUCCESS")
					bdt:Print("Fertig mit Senden. Du kannst wieder die Kontrolle übernehmen")
					-- just exits the function, the "false" means no more bags left
					return false

				end


			else
				debugMsg("unregisterevent via Eventhook - empty table")
				bdtns.b:UnregisterEvent("MAIL_SEND_SUCCESS")
			end
		else
			sendMailFrameCounter = sendMailFrameCounter + 1
		end
	end
end

--for populating recipientsList
local function OnEventc(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13) --arg1 msg, arg2 authorname, arg12 authorGUID
	if adActive == true and string.lower(arg1) == bdt.db.profile.advertiseKeyword then
		if guildMemberLevels[arg2] then
			if guildMemberLevels[arg2] >= bdt.db.profile.lvlMin and guildMemberLevels[arg2] <= bdt.db.profile.lvlMax then
				recipientsList[arg2] = guildMemberLevels[arg2]
				SendChatMessage("Anfrage wurde registriert", "WHISPER", nil, arg2)
			else
				SendChatMessage("Dein Level ist zu hoch oder zu niedrig um Taschen von mir zu bekommen, sorry", "WHISPER", nil, arg2)
			end
		else
			debugMsg("ist nicht in der Gilde")
		end		
	end
end

--for open/closed status of bank, mailbox and other stuff
function OnEventd(self, event, arg1)
	if monitoredOpenClosedFrames[event] then
		monitoredOpenClosedFrames[event]()
	end
end


function SlashCmdList.BAGDONATIONTRACKER(msg, editbox)
	bdt.Print("Werte und Einstellungen findest du unter Interface->Addons->BagDonationTracker, auch die folgenden bdtad und bdtstart können dort via Button ausgeführt werden")
	bdt:Print("Gib '/bdtdb CHARNAME' ein, um zu sehen ob CHARNAME in der Datenbank ist und alle gespeicherten Infos zu ihm zu erhalten")
	bdt:Print("Gib '/bdtad CODEWORT' ein, um eine Nachricht im Gildenchat zu senden um für 1 Minute Spielernamen zu sammeln, die Taschen möchten (diejenigen, die dir das Codewort zuflüstern. Diese werden dann von '/bdtstart' verwendet")
	bdt:Print("Gib '/bdtstart' ein, um das Schenken zu starten (Briefkasten muss auf sein, bitte mach nichts, bis der Vorgang durch ist")
end

-- the Database key = Name, 1 = amount of bags donated, 2 = Date Donated, 3 = Time Donated, 4 = Level when donated, 5 = type of bags donated (subtable), 6 = comment 7 = timestamp for sync (yearmonthdayhourminute with 0s, e.g. 202409262220 for 26.09.2024 22:20), 8 = *ursprünglich* erhalten von
function SlashCmdList.BAGDONATIONTRACKERDATABASE(msg, editbox)
	if not isTableEmpty(bdtrecipientsdatabase) and msg == "printdb" then
		local tempPrintString = ""
		for k, v in pairs(bdtrecipientsdatabase) do
			for i = 1, 8, 1 do
				tempPrintString = tempPrintString.." "..v[i]
			end
			bdt:Print(k..": "..tempPrintString)
			tempPrintString = ""
		end
	end
	if msg == "delete" then
		bdtrecipientsdatabase = {}
	elseif msg == "recipientslist" then
		for k, v in pairs(recipientsList) do
			bdt:Print(tostring(k).." "..tostring(v).." ".."recipientsList")
		end
	elseif msg == "testrecipientslist" then
		recipientsList = {
			["Ashaina"] = 54,
			["Grblgrr"] = 56,
			["Stablgrr"] = 12,
		}

	elseif msg == "cleanRecipientsList()" then
		cleanRecipientsList()

	end

end

function SlashCmdList.BAGDONATIONTRACKERADVERTISE(msg, editbox)
	if adActive == false then
		adActive = true
		adActivationTime = GetTime()
		updateGuildMemberLevels()
		SendChatMessage(advertiseMessageReplaces(bdt.db.profile.advertiseMessage),"GUILD")
	else
		bdt:Print("Interessentensuche bereits aktiv")
	end
end

function SlashCmdList.BAGDONATIONTRACKERSTART(msg, editbox)
	setFullTimestamp()
	local recipient = ""
	local level = 0
	if mailboxOpen then
		--amount of bags in the mail that is currently sent
		cleanRecipientsList()
		debugMsg("List cleaned")
		--checks if there are recipients (left) in the list
		if not isTableEmpty(recipientsList) then
			debugMsg("still stuff left in the list")

			--sending to one person and then starting the sending to consecutive recipients if there are more than 1
			
			for k, v in pairs(recipientsList) do
				recipient = k
				level = v
				break
			end

			if sendBags(bdtrecipientsdatabase[recipient], recipient, level) then

				-- just exits the function, the "true" means there MAY be bags left
				return true
			else
				debugMsg("nomorebags")
				-- send whisper to unserved (remaining) recipients
				for l, w in pairs(recipientsList) do
					SendChatMessage(bdt.db.profile.failChatMsg ,"WHISPER" ,nil ,l)
				end

				recipientsList = {}
				bdt:Print("Fertig mit Senden. Du kannst wieder die Kontrolle übernehmen")
				return false
			end


		else		--no recipients in the list
			bdt:Print("Keine Empfänger in der Liste")
		end

	else
		bdt:Print("Bitte öffne den Briefkasten und versuchs nochmal")
	end
end

function SlashCmdList.BAGDONATIONTRACKERADDTOLIST(msg, editbox)
	if msg and msg ~= "" then
		local subStrings = splitString(msg)
		if #subStrings == 2 then
			recipientsList[subStrings[1]] = tonumber(subStrings[2])
		end
	end
	debugMsg("addtolist executed")
end


--Used for receiving database data for synchronizing Databases. Fires on receiving an Addonmessage with the prefix "bdtDbSync"
function bdt:bdtDbSyncReceived(msg, type, sender)

	--checks if sender is SyncMate
	if isSyncMate(sender) then
		debugMsg("msg="..msg)
		if string.find(msg, "SYNCREQUEST@") then --checks if its a Sync-request
			msg = string.gsub(msg, "SYNCREQUEST@", "")


			--DEBUGSTUFF
			if sessionIds[sender] then
				debugMsg("sessionIds[sender]="..sessionIds[sender])
			end


			if bdt.syncOptions.args.startSync.disabled == false and not sessionIds[sender] then -- checks if this is NOT a returning request for the own request
				if bdt.db.profiles.allowSync == true then --checks if syncing is allowed right now
					bdt.syncOptions.args.startSync.disabled = true
					AceConfigRegistry:NotifyChange("bdtSync")

					sessionIds[sender] = extractSessionId(msg)
					local temp, _ = string.gsub(msg, sessionIds[sender].."@@", "")
					latestSync = tonumber(temp)

					--sends back a syncrequest to A
					if not bdt.db.global.latestSyncs[sender] or bdt.db.global.latestSyncs[sender] == "" then
						bdt.db.global.latestSyncs[sender] = 0
					end
					bdt:SendCommMessage("bdtDbSync", "SYNCREQUEST@"..sessionIds[sender].."@@"..bdt.db.global.latestSyncs[sender], "WHISPER", sender)
					currentTimers["syncRequest"] = bdt:ScheduleTimer(bdt.requestTimedOut, 5, sender)

					--prepare new Entries since last sync and send them to A and start Timer
					local newEntries = {}
					for k, v in pairs(bdtrecipientsdatabase) do
						if tonumber(v[7]) > latestSync then
							newEntries[k] = bdtrecipientsdatabase[k]
						end
					end
					bdt:SendCommMessage("bdtDbSync", "NEWENTRIES@"..sessionIds[sender].."@@"..bdt:Serialize(newEntries), "WHISPER", sender)
					currentTimers["newEntries"] = bdt:ScheduleTimer(bdt.requestTimedOut, 60, sender)
				end
			elseif string.find(msg, sessionIds[sender].."@@") then --checks if this is the returning request (correct sessionId), so stop the timer and send stoptimer request for B
				bdt:CancelTimer(currentTimers["syncRequest"])
				bdt:SendCommMessage("bdtDbSync", "STOPTIMER@"..sessionIds[sender].."@@".."syncRequest", "WHISPER", sender)
				local temp, _ = string.gsub(msg, sessionIds[sender].."@@", "")
				latestSync = tonumber(temp)

				--prepare new Entries since last sync and send them to B and start Timer
				local newEntries = {}
				for k, v in pairs(bdtrecipientsdatabase) do
					if tonumber(v[7]) > latestSync then
						newEntries[k] = bdtrecipientsdatabase[k]
					end
				end
				bdt:SendCommMessage("bdtDbSync", "NEWENTRIES@"..sessionIds[sender].."@@"..bdt:Serialize(newEntries), "WHISPER", sender)
				debugMsg("bdt:Serialize(newEntries)="..bdt:Serialize(newEntries))
				debugMsg(printAllTableEntries(newEntries))
				currentTimers["newEntries"] = bdt:ScheduleTimer(bdt.requestTimedOut, 60, sender)
			end
		elseif string.find(msg, "STOPTIMER@") then -- checks if its a stoptimer-request
			msg = string.gsub(msg, "STOPTIMER@", "")
			if string.find(msg, sessionIds[sender].."@@") then -- checks for correct sessionId
				msg = string.gsub(msg, sessionIds[sender].."@@", "")
				--stops the sent timer
				bdt:CancelTimer(currentTimers[msg])
				if msg == "newEntries" then
					sessionIds[sender] = nil
				end
			end
		elseif string.find(msg, "NEWENTRIES@") then -- checks if its a datasend
			msg = string.gsub(msg, "NEWENTRIES@", "")
			if string.find(msg, sessionIds[sender].."@@") then -- checks for correct sessionId
				msg = string.gsub(msg, sessionIds[sender].."@@", "") -- only serialized stuff should be left
				local deserializeWorked, receivedNewEntries = bdt:Deserialize(msg)
				debugMsg("receivedNewEntries="..tostring(receivedNewEntries))
				if deserializeWorked == true then --Deserialze worked, putting Data into own Database
					for k, v in pairs(receivedNewEntries) do
						if bdtrecipientsdatabase[k] then -- Eintrag existiert schon - Taschenmenge addieren und Vermerk hinzufügen
							bdtrecipientsdatabase[k][1] = bdtrecipientsdatabase[k][1] + receivedNewEntries[k][1]
							bdtrecipientsdatabase[k][6] = bdtrecipientsdatabase[k][6].." --"..receivedNewEntries[k][1].." Taschen hinzugefügt von "..receivedNewEntries[k][8]
						else -- Eintrag einfügen
							bdtrecipientsdatabase[k] = v
						end
					end
					--send STOPTIMER and resets receivedNewEntries + SessionId
					receivedNewEntries = nil
					bdt:SendCommMessage("bdtDbSync", "STOPTIMER@"..sessionIds[sender].."@@".."newEntries", "WHISPER", sender)
					bdt.syncOptions.args.startSync.disabled = false
					AceConfigRegistry:NotifyChange("bdtSync")

					--sets latest sync Timestamp
					setFullTimestamp()
					bdt.db.global.latestSyncs[sender] = fullTimestamp



					printAllTableEntries(bdtrecipientsdatabase)


				else -- Deserialze didnt work for some reason
					bdt:errormsg("Fehler bei der Entserialisierung der empfangenen Sync-Daten: "..receivedNewEntries)
				end
			end
		end
	end
end


--executed on button startSync button click
function bdt.startSync()
	--sets latestSync to 0, if never synced with that char before
	if not bdt.db.global.latestSyncs[bdt.db.global.syncMates[bdt.db.global.currentSyncMate]] or bdt.db.global.latestSyncs[bdt.db.global.syncMates[bdt.db.global.currentSyncMate]] == "" then
		bdt.db.global.latestSyncs[bdt.db.global.syncMates[bdt.db.global.currentSyncMate]] = 0
	end
	sessionIds[bdt.db.global.syncMates[bdt.db.global.currentSyncMate]] = generateSessionId()
	bdt:SendCommMessage("bdtDbSync", "SYNCREQUEST@"..sessionIds[bdt.db.global.syncMates[bdt.db.global.currentSyncMate]].."@@"..bdt.db.global.latestSyncs[bdt.db.global.syncMates[bdt.db.global.currentSyncMate]], "WHISPER", bdt.db.global.syncMates[bdt.db.global.currentSyncMate])
	currentTimers["syncRequest"] = bdt:ScheduleTimer(bdt.requestTimedOut, 5, bdt.db.global.syncMates[bdt.db.global.currentSyncMate])
	bdt.syncOptions.args.startSync.disabled = true
	AceConfigRegistry:NotifyChange("bdtSync")
	
end
function bdt.requestTimedOut(receiver)
	debugMsg("bdt.requestTimedOut called")
	bdt.syncOptions.args.startSync.disabled = false
	AceConfigRegistry:NotifyChange("bdtSync")
	sessionIds[receiver] = nil
end

-- Optionen für Interface->Addons->BagDonationTracker Einstellungen
options = {
	type = "group",
	args = {
		startAdvertising = {
			name = "Interessenten sammeln",
			desc = "Schreibt die eingestellte Chatnachricht in den Gildenchat und sammelt automatisch Interessenten, die einen mit dem Codewort angeflüstert haben.\nSpieler außerhalb des angegebenen Levelbereichs werden herausgefiltert.",
			type = "execute",
			order = 3,
			func = SlashCmdList.BAGDONATIONTRACKERADVERTISE,
		},
		showMailboxButtons = {
			name = "Briefkasten-Buttons anzeigen",
			desc = "Blendet die Buttons über dem Briefkasten-Fenster ein",
			type = "toggle",
			order = 5,
			set = function(info, value) showMailboxButtons(value) bdt.db.profile.showMailboxButtons = value end,
			get = function(info) return bdtns.advertisingButton:IsShown() and bdtns.sendBagsButton:IsShown() end,
		},
		lineBreakOne = {
			name = "",
			type = "description",
			order = 7,
		},
		lvlMin = {
			name = "Mindestlevel",
			desc = "Spieler unter diesem Level werden keine Taschen erhalten\n(in der Regel um zu Verhindern, dass frisch erstellte Twinks Taschen zum verkaufen abgreifen)",
			type = "range",
			order = 10,
			min = 1,
			max = 80,
			step = 1,
			validate = function(info, value) if value <= bdt.db.profile.lvlMax then return true else errormsg("Wert muss unter Maximallevel sein.") return false end end,
			set = function(info, value) bdt.db.profile.lvlMin = value end,
			get = function(info) return bdt.db.profile.lvlMin end,
		},
		lvlMax = {
			name = "Maximallevel",
			desc = "Spieler über diesem Level werden keine Taschen erhalten\n(in der Regel um Charaktere auszuschließen, die bereits über ausreichend eigene Ressourcen verfügen sollten, sich selbst mit Taschen zu versorgen",
			type = "range",
			order = 20,
			min = 1,
			max = 80,
			step = 1,
			validate = function(info, value) if value >= bdt.db.profile.lvlMin then return true else errormsg("Wert muss über Minimallevel sein.") return false end end,
			set = function(info, value) bdt.db.profile.lvlMax = value end,
			get = function(info) return bdt.db.profile.lvlMax end,
		},
		donationSize = {
			name = "Anzahl Taschen pro Charakter",
			desc = "Die Anzahl an Taschen, die jeder Charakter maximal erhalten wird.\n(In der Regel 4, damit es für das Inventar reicht)",
			type = "range",
			order = 25,
			min = 1,
			max = 11,
			step = 1,
			set = function(info, value) bdt.db.profile.donationSize = value end,
			get = function(info) return bdt.db.profile.donationSize end,
		},

		mailSubject = {
			name = "Brief: Betreff",
			desc = "Die Nachricht, die im Betreff jedes Briefs mit automatisch verschickten Taschen stehen wird.",
			type = "input",
			width = "full",
			order = 30,
			set = function(info, value) bdt.db.profile.mailSubject = value end,
			get = function(info) return bdt.db.profile.mailSubject end,
		},
		mailBody = {
			name = "Brief: Text",
			desc = "Die Nachricht, die im eigentlichen Brief mit automatisch verschickten Taschen stehen wird. (Kann auch leer sein)",
			type = "input",
			width = "full",
			order = 40,
			multiline = 4,
			set = function(info, value) bdt.db.profile.mailBody = value end,
			get = function(info) return bdt.db.profile.mailBody end,					
		},
		advertiseMessage = {
			name = "Nachricht fürs Interessenten sammeln",
			desc = "%LVLMIN, %LVLMAX und %CODEWORT können (und sollten) als dynamische Platzhalter verwendet werden.\nDiese Nachricht wird im Gildenchat gesendet, wenn man auf den 'Interessenten sammeln' Button drückt.\nNach Möglichkeit bitte die %XYZ Platzhalter verwenden, damit die Gilde nicht versehentlich falsche Infos erhält!",
			type = "input",
			width = "full",
			order = 43,
			multiline = 4,
			set = function(info, value) bdt.db.profile.advertiseMessage = value end,
			get = function(info) return bdt.db.profile.advertiseMessage end,
		},
		advertiseKeyword = {
			name = "Codewort fürs Interessenten sammeln",
			desc = "Nur 1 Wort eingeben bitte, Groß- und Kleinschreibung ist egal. Beim drücken auf den 'Interessenten sammeln' Button, werden Charakternamen gesammelt von den Leute, die einen mit AUSSCLHIEßLICH diesem Wort anflüstern.\n(Etwas intelligentere Filterung ist noch irgendwo auf der to-do Liste)",
			type = "input",
			width = "full",
			order = 45,
			set = function(info, value) bdt.db.profile.advertiseKeyword = string.lower(value) end,
			get = function(info) return bdt.db.profile.advertiseKeyword end,
		},
		successChatMsg = {
			name = "Flüsternachricht beim Versenden",
			desc = "Bitte möglichst kurz!\nMit dieser Nachricht wird jeder Spieler angeflüstert, dem mit dem 'Taschen verschicken' Button Taschen geschickt werden.\nSie wird außerdem in der Nachricht zitiert, die der 'Interessenten sammeln' Button am ENDE des Sammel-zeitraums (aktuell 2 Minuten) in den Gildenchat schreibt.",
			type = "input",
			width = "full",
			order = 50,
			set = function(info, value) bdt.db.profile.successChatMsg = value end,
			get = function(info) return bdt.db.profile.successChatMsg end,
		},
		partialSuccessChatMsg = {
			name = "Flüsternachricht bei Teilsendungen",
			desc = "Wenn weniger als 4 Taschen übrig sind, werden diese mit dieser Nachricht gesendet, damit der Empfänger sich beim nächsten Mal nochmal für die restlichen Taschen melden kann",
			type = "input",
			width = "full",
			order = 55,
			set = function(info, value) bdt.db.profile.partialSuccessChatMsg = value end,
			get = function(info) return bdt.db.profile.partialSuccessChatMsg end,
		},
		failChatMsg = {
			name = "Flüsternachricht bei zu wenig Taschen",
			desc = "Mit dieser Nachricht wird jeder Spieler angeflüstert, dem mit dem 'Taschen verschicken' Button KEINE Taschen geschickt wurden, weil nicht genug Taschen vorhanden waren.",
			type = "input",
			width = "full",
			order = 60,
			set = function(info, value) bdt.db.profile.failChatMsg = value end,
			get = function(info) return bdt.db.profile.failChatMsg end,
		}
	}
}


function bdt:OnInitialize()
	debugMsg("Hello World! bdt Initialize started")
	setFullTimestamp()

	--creates the database that I use for everything except the recipientsdatabase, using the values specified in the "defaults table as defaults (those are not saved in the file)
	bdt.db = LibStub("AceDB-3.0"):New("BagDonationTrackerDB", defaults)

	-- the Database key = Name, 1 = amount of bags donated, 2 = Date Donated, 3 = Time Donated, 4 = Level when donated, 5 = type of bags donated (subtable), 6 = comment 7 = timestamp for sync (yearmonthdayhourminute with 0s, e.g. 202409262220 for 26.09.2024 22:20), 8 = *ursprünglich* erhalten von
	if bdtrecipientsdatabase == nil or type(bdtrecipientsdatabase) ~= "table" then
		bdtrecipientsdatabase = {}
	end


	--Profiloptionen. (keine Ahnung, obs smarter wäre, die einfach als local variable in der Initialize funktion zu speichern. Hab Angst, dass es Zugriffsprobleme geben könnte)
	bdt.syncOptions = {
		type = "group",
		args = {
			startSync = {
				name = "Starte Datenbank Synchronisation",
				desc = "Startet Datenbank Synchronisation mit dem ausgewählten Spieler, FALLS dieser den Haken bei Datenbank Synchronisation gesetzt hat und online ist.",
				type = "execute",
				disabled = false,
				order = 10,
				func = bdt.startSync,
			},
			syncMate = {
				name = "Synchonisationspartner",
				desc = "Beim Klicken auf 'Starte Datenbank Synchronisation' wird mit diesem Spieler synchronisiert.",
				type = "select",
				order = 20,
				values = function() return bdt.db.global.syncMates end,	--needs to be in a function, otherwise it doesnt update properly with syncMates inputs
				set = function(info, value) bdt.db.global.currentSyncMate = value end,
				get = function(info) return bdt.db.global.currentSyncMate end,
			},
			allowSync = {
				name = "Synchonisationsanfragen annehmen",
				desc = "Wenn deaktiviert, kann niemand mit dir die Datenbank synchronisieren. In Raids und BGs u.U. deaktivieren um mögliche Lags zu verhindern.",
				type = "toggle",
				width = "full",
				order = 30,
				set = function(info, value) bdt.db.profiles.allowSync = value end,
				get = function(info) return bdt.db.profiles.allowSync end,					
			},
			syncMates = {
				name = "Synchronisationspartner (zum Datenbank synchronisieren)",
				desc = "Mehrere Charaktere bitte mit ',' trennen, Leerzeichen werden komplett ignoriert.",
				type = "input",
				width = "full",
				order = 100,
				set = function(info, value) bdt.db.global.syncMates = createSyncMatesTable(value) end,
				get = function(info) return createSyncMatesString(bdt.db.global.syncMates) end,					
			},
		},
	}
	bdt.dbOptions = {
		type = "group",
		args = {
			description = {
				name = "Name = Taschenanzahl, Datum, Zeit, Level, Taschentyp (ItemID), Kommentar, Zeitstempel, Schenkender\n!!!Änderungen hier nicht möglich!!!",
				type = "description",
				order = 10,
				fontSize = "small",
			},
			database = {
				name = "",
				desc = "TaschenID und Timestamp sind eher für Addoninterne Dinge. TaschenID 21841 sind Netherstofftaschen.",
				type = "input",
				--disabled = true,
				width = "full",
				order = 20,
				multiline = 3000,
				set = function(info, value) end,
				get = function(info) return createBdtrecipientsdatabaseString() end,
			},
		},
	}
	bdt.profileOptions = {}

	--sets up the table for saving profiles I think
	bdt.profileOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	--some shit with the options, maybe links the actual option tables with Names for easier use or so? No clue...
	AceConfig:RegisterOptionsTable("BagDonationTracker", options)
	AceConfig:RegisterOptionsTable("Datenbank Synchronisation", bdt.syncOptions)
	AceConfig:RegisterOptionsTable("Datenbank", bdt.dbOptions)
	AceConfig:RegisterOptionsTable("bdtProfiles", bdt.profileOptions)

	--puts the options defined in the "options" table into the Interface->Addons options Interface
	ACD:AddToBlizOptions("BagDonationTracker")
	ACD:AddToBlizOptions("Datenbank Synchronisation", "Datenbank Synchronisation", "BagDonationTracker")
	ACD:AddToBlizOptions("Datenbank", "Datenbank", "BagDonationTracker")
	ACD:AddToBlizOptions("bdtProfiles", "Profiles", "BagDonationTracker")

	--register AceComm-3.0 prefixes for database synchronization
	bdt:RegisterComm("bdtDbSync", bdt.bdtDbSyncReceived)

	--shows MailboxButtons or not depending on settings
	showMailboxButtons(bdt.db.profile.showMailboxButtons)



	--TESTING STARTS HERE thanks chatgpt :P (creates a sample Database for testing. !!!OVERWRITES EXISTING DATABASE, HANDLE WITH CARE!!!)
	--[[
	if playerName == "Grmlgrr" then
	bdtrecipientsdatabase = {
	["apple"] = {3, "2023-09-14", "13:45", 35, 21841, "", "202309141345"},
	["banana"] = {1, "2021-06-20", "09:30", 12, 21841, "A tropical fruit.", "202106200930"},
	["cat"] = {2, "2022-11-05", "08:15", 29, 21841, "Small domestic animal.", "202211050815"},
	["dog"] = {4, "2020-01-30", "17:00", 50, 21841, "", "202001301700"},
	["elephant"] = {2, "2019-12-18", "06:45", 47, 21841, "Largest land mammal.", "201912180645"},
	["flower"] = {1, "2021-04-12", "11:25", 20, 21841, "", "202104121125"},
	["guitar"] = {3, "2023-08-08", "14:50", 60, 21841, "Musical instrument.", "202308081450"},
	["house"] = {4, "2022-02-14", "21:10", 33, 21841, "", "202202142110"},

	["island"] = {2, "2018-07-21", "12:00", 15, 21841, "Land surrounded by water.", "201807211200"},
	["jungle"] = {1, "2020-10-10", "05:40", 7, 21841, "", "202010100540"},
	["kite"] = {3, "2022-05-22", "15:35", 27, 21841, "Flies in the wind.", "202205221535"},
	["lemon"] = {4, "2019-03-11", "16:25", 70, 21841, "", "201903111625"},
	["mountain"] = {2, "2023-07-09", "07:55", 55, 21841, "Tall natural elevation.", "202307090755"},
	["night"] = {1, "2021-12-30", "18:10", 40, 21841, "", "202112301810"},
	["ocean"] = {4, "2020-09-25", "22:50", 72, 21841, "", "202009252250"},
	["piano"] = {3, "2022-03-15", "13:35", 53, 21841, "A large musical instrument.", "202203151335"},
	["queen"] = {1, "2023-01-01", "10:10", 25, 21841, "", "202301011010"},
	["river"] = {2, "2018-08-17", "09:00", 19, 21841, "", "201808170900"},
	["sun"] = {4, "2021-11-02", "08:30", 79, 21841, "Star of the solar system.", "202111020830"},
	["tree"] = {3, "2020-06-13", "07:45", 66, 21841, "", "202006130745"}

	}
	for k, v in pairs(bdtrecipientsdatabase) do
	bdtrecipientsdatabase[k][8] = "Grmlgrr"
	end
	else
	bdtrecipientsdatabase = {
	["apple"] = {1, "2024-01-10", "14:25", 15, 21841, "A fruit that keeps the doctor away.", "202401101425"},
	["banana"] = {3, "2022-03-09", "09:15", 45, 21841, "", "202203090915"},
	["car"] = {2, "2020-08-22", "16:45", 32, 21841, "A four-wheeled vehicle.", "202008221645"},
	["desk"] = {4, "2021-07-13", "12:30", 25, 21841, "", "202107131230"},
	["elephant"] = {3, "2022-11-19", "07:15", 41, 21841, "", "202211190715"},
	["flower"] = {2, "2021-09-05", "17:00", 60, 21841, "Plants with colorful blooms.", "202109051700"},
	["guitar"] = {1, "2023-10-12", "08:20", 29, 21841, "", "202310120820"},
	["hat"] = {4, "2019-05-25", "13:35", 52, 21841, "Something worn on the head.", "201905251335"},
	["island"] = {3, "2022-04-17", "10:45", 19, 21841, "", "202204171045"},
	["jungle"] = {2, "2020-06-09", "15:30", 67, 21841, "Dense forest in a tropical region.", "202006091530"},
	["kite"] = {1, "2018-08-23", "16:05", 34, 21841, "", "201808231605"},

	["lemon"] = {4, "2021-02-11", "11:25", 58, 21841, "A sour citrus fruit.", "202102111125"},
	["mountain"] = {2, "2023-03-07", "05:50", 40, 21841, "", "202303070550"},
	["notebook"] = {3, "2021-12-01", "09:40", 12, 21841, "A tool used for writing.", "202112010940"},
	["ocean"] = {1, "2019-07-21", "19:30", 75, 21841, "", "201907211930"},
	["piano"] = {4, "2020-05-12", "14:15", 18, 21841, "", "202005121415"},
	["queen"] = {2, "2021-01-18", "10:10", 55, 21841, "A female monarch.", "202101181010"},
	["river"] = {3, "2023-09-28", "08:25", 49, 21841, "", "202309280825"},
	["shoe"] = {1, "2020-11-14", "07:35", 21, 21841, "Footwear for protection and comfort.", "202011140735"},
	["tree"] = {4, "2019-10-19", "16:50", 64, 21841, "", "201910191650"},
	["umbrella"] = {2, "2022-12-30", "13:05", 22, 21841, "Provides shelter from rain.", "202212301305"},
	["vase"] = {1, "2020-02-14", "09:20", 37, 21841, "", "202002140920"},
	["window"] = {4, "2019-09-09", "11:55", 73, 21841, "", "201909091155"},
	["xylophone"] = {3, "2023-06-25", "18:45", 27, 21841, "A musical instrument with bars.", "202306251845"}

	}
	for k, v in pairs(bdtrecipientsdatabase) do
	bdtrecipientsdatabase[k][8] = "Grumlgrr"
	end




	end
	--]]
end




-- this has to be last, as functions need to be defined, before they can be referenced

-- for timing (should trigger every frame)
bdtns.a = CreateFrame("Frame")
bdtns.a:SetScript("OnUpdate", OnUpdatea)

-- for mailboxstuff
bdtns.b = CreateFrame("Frame")
bdtns.b:HookScript("OnEvent", OnEventbHook)
bdtns.b:SetScript("OnUpdate", OnUpdateb)

-- for recipientsList
bdtns.c = CreateFrame("Frame")
bdtns.c:RegisterEvent("CHAT_MSG_WHISPER")
bdtns.c:SetScript("OnEvent", OnEventc)

-- for checking open/closed status of bank, mailbox and stuff
bdtns.d = CreateFrame("Frame")
bdtns.d:RegisterEvent("MAIL_SHOW")
bdtns.d:RegisterEvent("MAIL_CLOSED")
bdtns.d:RegisterEvent("BANKFRAME_OPENED")
bdtns.d:RegisterEvent("BANKFRAME_CLOSED")
bdtns.d:SetScript("OnEvent", OnEventd)

-- for the database sending, receiving and merging
bdtns.g = CreateFrame("Frame")
bdtns.g:RegisterEvent("CHAT_MSG_ADDON")
bdtns.g:SetScript("OnEvent", OnEventg)

bdtns.advertisingButton = CreateFrame("Button", "AdvertisingButton", MailFrame, "UIPanelButtonTemplate")
bdtns.advertisingButton:SetSize(155, 25)
bdtns.advertisingButton:SetText("Interessenten sammeln")
bdtns.advertisingButton:SetPoint("BOTTOMLEFT", MailFrame, "TOPLEFT", 65, -14)
bdtns.advertisingButton:SetScript("OnClick", SlashCmdList.BAGDONATIONTRACKERADVERTISE)

bdtns.sendBagsButton = CreateFrame("Button", "SendBagsButton", MailFrame, "UIPanelButtonTemplate")
bdtns.sendBagsButton:SetSize(140, 25)
bdtns.sendBagsButton:SetText("Taschen verschicken")
bdtns.sendBagsButton:SetPoint("BOTTOMLEFT", bdtns.advertisingButton, "BOTTOMRIGHT", -5, 0)
bdtns.sendBagsButton:SetScript("OnClick", SlashCmdList.BAGDONATIONTRACKERSTART)