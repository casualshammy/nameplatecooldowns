local _, addonTable = ...;
local L = addonTable.L;
local CDs = addonTable.CDs;
local Interrupts = addonTable.Interrupts;
local Resets = addonTable.Resets;
local Trinkets = addonTable.Trinkets;

--[===[@non-debug@
local buildTimestamp = "@project-version@";
--@end-non-debug@]===]

local RD = LibStub("LibRedDropdown-1.0");

local SML = LibStub("LibSharedMedia-3.0");
SML:Register("font", "NC_TeenBold", "Interface\\AddOns\\NameplateCooldowns\\media\\teen_bold.ttf", 255);

local SPELL_PVPADAPTATION = 195901;
local SPELL_PVPTRINKET = 42292;

local charactersDB = {};
local CDTimeCache = {};
local CDEnabledCache = {};
local SpellTextureByID = setmetatable({
	[SPELL_PVPTRINKET] =	1322720,
	[200166] =				1247262,
}, {
	__index = function(t, key)
		local texture = GetSpellTexture(key);
		t[key] = texture;
		return texture;
	end
});
local ElapsedTimer = 0;
local Nameplates = {};
local NameplatesVisible = {};
local LocalPlayerFullName = UnitName("player").." - "..GetRealmName();
local InstanceType = "none";
local GUIFrame, EventFrame, TestFrame, db, aceDB, ProfileOptionsFrame;

local _G, pairs, select, UIParent, string_match, string_gsub, string_find, bit_band, GetTime, table_contains_value, math_ceil, 	table_insert, table_sort, C_Timer_After =
	  _G, pairs, select, UIParent, strmatch,	   		gsub,	  strfind, bit.band, GetTime, 			 tContains,		 ceil,	table.insert, table.sort, C_Timer.After;
	  
local OnStartup, InitializeDB, AddButtonToBlizzOptions;
local AllocateIcon, ReallocateAllIcons, InitializeFrame, UpdateOnlyOneNameplate, Nameplate_SetBorder, Nameplate_SetCooldown, Nameplate_SortAuras, HideCDIcon, ShowCDIcon;
local OnUpdate;
local EnableTestMode, DisableTestMode;
local ShowGUI, InitializeGUI, GUICategory_General, GUICategory_Profiles, GUICategory_Other, OnGUICategoryClick, ShowGUICategory, RebuildDropdowns, CreateGUICategory;
local Print, deepcopy, table_contains_key, table_any;

-- // consts: you should not change existing values
local CONST_SORT_MODES = { "none", "trinket-interrupt-other", "interrupt-trinket-other", "trinket-other", "interrupt-other" };
local CONST_SORT_MODES_L = {
	[CONST_SORT_MODES[1]] = "none",
	[CONST_SORT_MODES[2]] = "trinkets, then interrupts, then other spells",
	[CONST_SORT_MODES[3]] = "interrupts, then trinkets, then other spells",
	[CONST_SORT_MODES[4]] = "trinkets, then other spells",
	[CONST_SORT_MODES[5]] = "interrupts, then other spells",
};
local INSTANCE_TYPE_UNKNOWN = "unknown";

-------------------------------------------------------------------------------------------------
----- Initialize
-------------------------------------------------------------------------------------------------
do

	local function ConvertDBToAceIfNeeded(t)
		if (NameplateCooldownsDB ~= nil and NameplateCooldownsDB[LocalPlayerFullName] ~= nil) then
			local oldTable = NameplateCooldownsDB[LocalPlayerFullName];
			for index, value in pairs(oldTable) do
				if (value ~= nil) then
					t[deepcopy(index)] = deepcopy(value);
				end
			end
			NameplateCooldownsDB[LocalPlayerFullName] = nil;
		end
	end
	
	local function MigrateDB(t)
		
	end
	
	local function AddToBlizzOptions()
		LibStub("AceConfig-3.0"):RegisterOptionsTable("NameplateCooldowns", {
			name = "NameplateCooldowns",
			type = "group",
			args = {
				openGUI = {
					type = 'execute',
					order = 1,
					name = 'Open config dialog',
					desc = nil,
					func = function()
						ShowGUI();
						if (GUIFrame) then
							InterfaceOptionsFrameCancel:Click();
						end
					end,
				},
			},
		});
		LibStub("AceConfigDialog-3.0"):AddToBlizOptions("NameplateCooldowns", "NameplateCooldowns");
		local profilesConfig = LibStub("AceDBOptions-3.0"):GetOptionsTable(aceDB);
		LibStub("AceConfig-3.0"):RegisterOptionsTable("NameplateCooldowns.profiles", profilesConfig);
		ProfileOptionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("NameplateCooldowns.profiles", "Profiles", "NameplateCooldowns");
	end

	local function ReloadDB()
		db = aceDB.profile;
		if (db.AddonEnabled) then
			EventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
			wipe(charactersDB);
		else
			EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
		end
		if (TestFrame and TestFrame:GetScript("OnUpdate") ~= nil) then
			DisableTestMode();
		end
		OnUpdate();
		if (GUIFrame) then
			for _, func in pairs(GUIFrame.OnDBChangedHandlers) do
				func();
			end
		end
	end
	
	function InitializeDB()
		-- // set defaults
		local aceDBDefaults = {
			profile = {
				CDsTable = { },
				IconSize = 26,
				IconXOffset = 0,
				IconYOffset = 30,
				FullOpacityAlways = false,
				ShowBorderTrinkets = true,
				ShowBorderInterrupts = true,
				BorderInterruptsColor = {1, 0.35, 0},
				BorderTrinketsColor = {1, 0.843, 0},
				Font = "NC_TeenBold",
				IconSortMode = CONST_SORT_MODES[1],
				AddonEnabled = true,
				ShowCooldownsOnCurrentTargetOnly = false,
				EnabledZoneTypes = { 
					["none"] =					true,
					[INSTANCE_TYPE_UNKNOWN] = 	true,
					["pvp"] = 					true,
					["arena"] = 				true,
					["party"] = 				true,
					["raid"] = 					true,
					["scenario"] = 				true,
				},
			},
		};
		aceDB = LibStub("AceDB-3.0"):New("NameplateCooldownsAceDB", aceDBDefaults);
		ConvertDBToAceIfNeeded(aceDB.profile);
		MigrateDB(aceDB.profile);
		AddToBlizzOptions();
		aceDB.RegisterCallback("NameplateCooldowns", "OnProfileChanged", ReloadDB);
		aceDB.RegisterCallback("NameplateCooldowns", "OnProfileCopied", ReloadDB);
		aceDB.RegisterCallback("NameplateCooldowns", "OnProfileReset", ReloadDB);
		db = aceDB.profile;
	end
	
	function OnStartup()
		InitializeDB();
		-- // remove non-existent spells
		local badSkills = {};
		for _, spellsByClass in pairs(CDs) do
			for spellID in pairs(spellsByClass) do
				if (GetSpellLink(spellID) == nil) then
					db.CDsTable[spellID] = nil;
					table.insert(badSkills, spellID);
					Print("This spell doesn't exist -->> "..spellID);
				end
			end
		end
		-- // add new spells to user's db
		for _, spellsByClass in pairs(CDs) do
			for spellID in pairs(spellsByClass) do
				if (db.CDsTable[spellID] == nil and not table_contains_value(badSkills, spellID)) then
					db.CDsTable[spellID] = true;
					Print(format(L["New spell has been added: %s"], GetSpellLink(spellID)));
				end
			end
		end
		-- // cache initialisation
		for _, spellsByClass in pairs(CDs) do
			for spellID, timeInSec in pairs(spellsByClass) do
				if (db.CDsTable[spellID] == true) then
					CDEnabledCache[spellID] = true;
				end
				CDTimeCache[spellID] = timeInSec;
			end
		end
		-- // starting OnUpdate()
		EventFrame:SetScript("OnUpdate", function(self, elapsed)
			ElapsedTimer = ElapsedTimer + elapsed;
			if (ElapsedTimer >= 1) then
				OnUpdate();
				ElapsedTimer = 0;
			end
		end);
		-- // starting listening for events
		if (db.AddonEnabled) then
			EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
		else
			Print(L["chat:addon-is-disabled-note"]);
		end
		if (db.ShowCooldownsOnCurrentTargetOnly) then
			EventFrame:RegisterEvent("PLAYER_TARGET_CHANGED");
			--Print(L["chat:enable-only-for-target-nameplate"]);
		end
		EventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED");
		EventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED");
		AddButtonToBlizzOptions();
		SLASH_NAMEPLATECOOLDOWNS1 = '/nc';
		SlashCmdList["NAMEPLATECOOLDOWNS"] = function(msg, editBox)
			if (msg == "t" or msg == "ver") then
				local c = UNKNOWN;
				if (IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) then
					c = "INSTANCE_CHAT";
				elseif (IsInRaid()) then
					c = "RAID";
				else
					c = "GUILD";
				end
				Print("Waiting for replies from " .. c);
				C_ChatInfo.SendAddonMessage("NC_prefix", "requesting", c);
			else
				ShowGUI();
			end
		end
		OnStartup = nil;
	end
		
	function AddButtonToBlizzOptions()
		local frame = CreateFrame("Frame", "NC_BlizzOptionsFrame", UIParent);
		frame.name = "NameplateCooldowns";
		InterfaceOptions_AddCategory(frame);
		local button = RD.CreateButton();
		button:SetParent(frame);
		button:SetText("/nc");
		button:SetWidth(80);
		button:SetHeight(40);
		button:SetPoint("CENTER", frame, "CENTER", 0, 0);
		button:SetScript("OnClick", function(self, ...)
			ShowGUI();
			if (GUIFrame) then
				InterfaceOptionsFrameCancel:Click();
			end
		end);
	end
	
end

-------------------------------------------------------------------------------------------------
----- Nameplates
-------------------------------------------------------------------------------------------------
do

	function AllocateIcon(frame)
		if (not frame.NCFrame) then
			frame.NCFrame = CreateFrame("frame", nil, db.FullOpacityAlways and UIParent or frame);
			frame.NCFrame:SetWidth(db.IconSize);
			frame.NCFrame:SetHeight(db.IconSize);
			frame.NCFrame:SetPoint("TOPLEFT", frame, db.IconXOffset, db.IconYOffset);
			frame.NCFrame:Show();
		end
		local texture = frame.NCFrame:CreateTexture(nil, "BORDER");
		texture:SetPoint("LEFT", frame.NCFrame, frame.NCIconsCount * db.IconSize, 0);
		texture:SetWidth(db.IconSize);
		texture:SetHeight(db.IconSize);
		texture:Hide();
		texture.cooldown = frame.NCFrame:CreateFontString(nil, "OVERLAY");
		texture.cooldown:SetTextColor(0.7, 1, 0);
		texture.cooldown:SetAllPoints(texture);
		texture.cooldown:SetFont(SML:Fetch("font", db.Font), math_ceil(db.IconSize - db.IconSize / 2), "OUTLINE");
		texture.border = frame.NCFrame:CreateTexture(nil, "OVERLAY");
		texture.border:SetTexture("Interface\\AddOns\\NameplateCooldowns\\media\\CooldownFrameBorder.tga");
		texture.border:SetVertexColor(1, 0.35, 0);
		texture.border:SetAllPoints(texture);
		texture.border:Hide();
		frame.NCIconsCount = frame.NCIconsCount + 1;
		tinsert(frame.NCIcons, texture);
	end
	
	function ReallocateAllIcons(clearSpells)
		for frame in pairs(Nameplates) do
			if (frame.NCFrame) then
				frame.NCFrame:SetPoint("TOPLEFT", frame, db.IconXOffset, db.IconYOffset);
				local counter = 0;
				for _, icon in pairs(frame.NCIcons) do
					icon:SetWidth(db.IconSize);
					icon:SetHeight(db.IconSize);
					icon:SetPoint("LEFT", frame.NCFrame, counter * db.IconSize, 0);
					icon.cooldown:SetFont(SML:Fetch("font", db.Font), math_ceil(db.IconSize - db.IconSize / 2), "OUTLINE");
					if (clearSpells) then
						HideCDIcon(icon);
					end
					counter = counter + 1;
				end
			end
		end
		if (clearSpells) then
			OnUpdate();
		end
	end
	
	local function GlobalFilterNameplate(unitName)
		if (not db.ShowCooldownsOnCurrentTargetOnly or UnitName("target") == unitName) then
			if (db.EnabledZoneTypes[InstanceType]) then
				return true;
			end
		end
		return false;
	end
	
	function UpdateOnlyOneNameplate(frame, name)
		local counter = 1;
		if (GlobalFilterNameplate(name)) then
			if (charactersDB[name]) then
				local currentTime = GetTime();
				local sortedCDs = Nameplate_SortAuras(charactersDB[name]);
				for _, spellInfo in pairs(sortedCDs) do
					local spellID = spellInfo.spellID;
					if (spellInfo.expires > currentTime) then
						if (counter > frame.NCIconsCount) then
							AllocateIcon(frame);
						end
						local icon = frame.NCIcons[counter];
						if (icon.spellID ~= spellID) then
							icon:SetTexture(SpellTextureByID[spellID]);
							icon.spellID = spellID;
							Nameplate_SetBorder(icon, spellID);
						end
						local remain = spellInfo.expires - currentTime;
						Nameplate_SetCooldown(icon, remain)
						if (not icon.shown) then
							ShowCDIcon(icon);
						end
						counter = counter + 1;
					else
						charactersDB[name][spellID] = nil;
					end
				end
			end
		end
		for k = counter, frame.NCIconsCount do
			local icon = frame.NCIcons[k];
			if (icon.shown) then
				HideCDIcon(icon);
			end
		end
	end
	
	function Nameplate_SetBorder(icon, spellID)
		if (db.ShowBorderInterrupts and table_contains_value(Interrupts, spellID)) then
			if (icon.borderState ~= 1) then
				icon.border:SetVertexColor(unpack(db.BorderInterruptsColor));
				icon.border:Show();
				icon.borderState = 1;
			end
		elseif (db.ShowBorderTrinkets and table_contains_value(Trinkets, spellID)) then
			if (icon.borderState ~= 2) then
				icon.border:SetVertexColor(unpack(db.BorderTrinketsColor));
				icon.border:Show();
				icon.borderState = 2;
			end
		elseif (icon.borderState ~= nil) then
			icon.border:Hide();
			icon.borderState = nil;
		end
	end
	
	function Nameplate_SetCooldown(icon, remain)
		if (remain >= 60) then
			icon.cooldown:SetText(math_ceil(remain/60).."m");
		else
			icon.cooldown:SetText(math_ceil(remain));
		end
	end
	
	function Nameplate_SortAuras(cds)
		local t = { };
		for spellID, spellInfo in pairs(cds) do
			if (spellID ~= nil) then
				table.insert(t, spellInfo);
			end
		end
		if (db.IconSortMode == CONST_SORT_MODES[1]) then
			-- // do nothing
		elseif (db.IconSortMode == CONST_SORT_MODES[2]) then
			table.sort(t, function(item1, item2)
				if (table_contains_value(Trinkets, item1.spellID)) then
					if (table_contains_value(Trinkets, item2.spellID)) then
						return item1.expires < item2.expires;
					else
						return true;
					end
				elseif (table_contains_value(Trinkets, item2.spellID)) then
					return false;
				elseif (table_contains_value(Interrupts, item1.spellID)) then
					if (table_contains_value(Interrupts, item2.spellID)) then
						return item1.expires < item2.expires;
					else
						return true;
					end
				elseif (table_contains_value(Interrupts, item2.spellID)) then
					return false;
				else
					return item1.expires < item2.expires;
				end
			end);
		elseif (db.IconSortMode == CONST_SORT_MODES[3]) then
			table.sort(t, function(item1, item2)
				if (table_contains_value(Interrupts, item1.spellID)) then
					if (table_contains_value(Interrupts, item2.spellID)) then
						return item1.expires < item2.expires;
					else
						return true;
					end
				elseif (table_contains_value(Interrupts, item2.spellID)) then
					return false;
				elseif (table_contains_value(Trinkets, item1.spellID)) then
					if (table_contains_value(Trinkets, item2.spellID)) then
						return item1.expires < item2.expires;
					else
						return true;
					end
				elseif (table_contains_value(Trinkets, item2.spellID)) then
					return false;
				else
					return item1.expires < item2.expires;
				end
			end);
		elseif (db.IconSortMode == CONST_SORT_MODES[4]) then
			table.sort(t, function(item1, item2)
				if (table_contains_value(Trinkets, item1.spellID)) then
					if (table_contains_value(Trinkets, item2.spellID)) then
						return item1.expires < item2.expires;
					else
						return true;
					end
				elseif (table_contains_value(Trinkets, item2.spellID)) then
					return false;
				else
					return item1.expires < item2.expires;
				end
			end);
		elseif (db.IconSortMode == CONST_SORT_MODES[5]) then
			table.sort(t, function(item1, item2)
				if (table_contains_value(Interrupts, item1.spellID)) then
					if (table_contains_value(Interrupts, item2.spellID)) then
						return item1.expires < item2.expires;
					else
						return true;
					end
				elseif (table_contains_value(Interrupts, item2.spellID)) then
					return false;
				else
					return item1.expires < item2.expires;
				end
			end);
		end
		return t;
	end
	
	function HideCDIcon(icon)
		icon.border:Hide();
		icon.borderState = nil;
		icon.cooldown:Hide();
		icon:Hide();
		icon.shown = false;
		icon.spellID = 0;
	end
	
	function ShowCDIcon(icon)
		icon.cooldown:Show();
		icon:Show();
		icon.shown = true;
	end
	
end

-------------------------------------------------------------------------------------------------
----- OnUpdates
-------------------------------------------------------------------------------------------------
do

	function OnUpdate()
		for frame, unitName in pairs(NameplatesVisible) do
			UpdateOnlyOneNameplate(frame, unitName);
		end
	end
	
end

-------------------------------------------------------------------------------------------------
----- Test mode
-------------------------------------------------------------------------------------------------
do

	local _t = 0;
	local _charactersDB;
	local _spellIDs = {2139, 108194, 100};
	
	local function refreshCDs()
		local cTime = GetTime();
		for _, unitName in pairs(NameplatesVisible) do
			if (not charactersDB[unitName]) then
				charactersDB[unitName] = {};
			end
			charactersDB[unitName][SPELL_PVPTRINKET] = { ["spellID"] = SPELL_PVPTRINKET, ["duration"] = CDTimeCache[SPELL_PVPTRINKET], ["expires"] = cTime + CDTimeCache[SPELL_PVPTRINKET] }; -- // 2m test
			for _, spellID in pairs(_spellIDs) do
				if (not charactersDB[unitName][spellID]) then
					charactersDB[unitName][spellID] = { ["spellID"] = spellID, ["duration"] = CDTimeCache[spellID], ["expires"] = cTime + CDTimeCache[spellID] };
				else
					if (cTime - charactersDB[unitName][spellID]["expires"] > 0) then
						charactersDB[unitName][spellID] = { ["spellID"] = spellID, ["duration"] = CDTimeCache[spellID], ["expires"] = cTime + CDTimeCache[spellID] };
					end
				end
			end
		end
	end
	
	function EnableTestMode()
		_charactersDB = deepcopy(charactersDB);
		if (not TestFrame) then
			TestFrame = CreateFrame("frame");
		end
		TestFrame:SetScript("OnUpdate", function(self, elapsed)
			_t = _t + elapsed;
			if (_t >= 2) then
				refreshCDs();
				_t = 0;
			end
		end);
		refreshCDs(); 	-- // for instant start
		OnUpdate();		-- // for instant start
	end
	
	function DisableTestMode()
		TestFrame:SetScript("OnUpdate", nil);
		charactersDB = deepcopy(_charactersDB);
		OnUpdate();		-- // for instant start
	end
	
end

-------------------------------------------------------------------------------------------------
----- GUI
-------------------------------------------------------------------------------------------------
do

	function ShowGUI()
		if (not InCombatLockdown()) then
			if (not GUIFrame) then
				InitializeGUI();
			end
			GUIFrame:Show();
			OnGUICategoryClick(GUIFrame.CategoryButtons[1]);
		else
			Print(L["Options are not available in combat!"]);
		end
	end
	
	local function GUICategory_Filters(index, value)
		local checkBoxEnableOnlyForTarget;
		
		-- // checkBoxEnableOnlyForTarget
		do
		
			checkBoxEnableOnlyForTarget = RD.CreateCheckBox();
			checkBoxEnableOnlyForTarget:SetText(L["options:general:enable-only-for-target-nameplate"]);
			checkBoxEnableOnlyForTarget:SetOnClickHandler(function(this)
				db.ShowCooldownsOnCurrentTargetOnly = this:GetChecked();
				if (db.ShowCooldownsOnCurrentTargetOnly) then
					EventFrame:RegisterEvent("PLAYER_TARGET_CHANGED");
				else
					EventFrame:UnregisterEvent("PLAYER_TARGET_CHANGED");
				end
				ReallocateAllIcons(true);
			end);
			checkBoxEnableOnlyForTarget:SetChecked(db.ShowCooldownsOnCurrentTargetOnly);
			checkBoxEnableOnlyForTarget:SetParent(GUIFrame.outline);
			checkBoxEnableOnlyForTarget:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 15, -15);
			table_insert(GUIFrame.Categories[index], checkBoxEnableOnlyForTarget);
			table_insert(GUIFrame.OnDBChangedHandlers, function() checkBoxEnableOnlyForTarget:SetChecked(db.ShowCooldownsOnCurrentTargetOnly); end);
			
		end
		
		-- // buttonInstances
		do
			
			local zoneTypes = {
				["none"] = 					L["instance-type:none"],
				[INSTANCE_TYPE_UNKNOWN] = 	L["instance-type:unknown"],
				["pvp"] = 					L["instance-type:pvp"],
				["arena"] = 				L["instance-type:arena"],
				["party"] = 				L["instance-type:party"],
				["raid"] = 					L["instance-type:raid"],
				["scenario"] = 				L["instance-type:scenario"],
			};
			local zoneIcons = {
				["none"] = 					SpellTextureByID[6711],
				[INSTANCE_TYPE_UNKNOWN] = 	SpellTextureByID[175697],
				["pvp"] = 					SpellTextureByID[232352],
				["arena"] = 				SpellTextureByID[270697],
				["party"] = 				SpellTextureByID[77629],
				["raid"] = 					SpellTextureByID[3363],
				["scenario"] = 				SpellTextureByID[77628],
			};
			
		
			local dropdownInstances = RD.CreateDropdownMenu();
			local buttonInstances = RD.CreateButton();
			buttonInstances:SetParent(GUIFrame.outline);
			buttonInstances:SetText(L["filters.instance-types"]);
			
			local function setEntries()
				local entries = { };
				for instanceType, instanceLocalizatedName in pairs(zoneTypes) do
					table_insert(entries, {
						["text"] = instanceLocalizatedName,
						["icon"] = zoneIcons[instanceType],
						["func"] = function(info)
							local btn = dropdownInstances:GetButtonByText(info.text);
							if (btn) then
								info.disabled = not info.disabled;
								btn:SetGray(info.disabled);
								db.EnabledZoneTypes[info.instanceType] = not info.disabled;
							end
							ReallocateAllIcons(true);
						end,
						["disabled"] = not db.EnabledZoneTypes[instanceType],
						["dontCloseOnClick"] = true,
						["instanceType"] = instanceType,
					});
				end
				table_sort(entries, function(item1, item2) return item1.instanceType < item2.instanceType; end);
				return entries;
			end
			
			buttonInstances:SetWidth(350);
			buttonInstances:SetHeight(40);
			buttonInstances:SetPoint("TOPLEFT", checkBoxEnableOnlyForTarget, "BOTTOMLEFT", 0, -5);
			buttonInstances:SetScript("OnClick", function(self, ...)
				if (dropdownInstances:IsVisible()) then
					dropdownInstances:Hide();
				else
					dropdownInstances:SetList(setEntries());
					dropdownInstances:SetParent(self);
					dropdownInstances:ClearAllPoints();
					dropdownInstances:SetPoint("TOP", self, "BOTTOM", 0, 0);
					dropdownInstances:Show();
				end
			end);
			buttonInstances:SetScript("OnHide", function() dropdownInstances:Hide(); end);
			table_insert(GUIFrame.Categories[index], buttonInstances);
			table_insert(GUIFrame.OnDBChangedHandlers, function() dropdownInstances:SetList(setEntries()); dropdownInstances:Hide(); end);
		
		end
		
	end
	
	function InitializeGUI()
		GUIFrame = CreateFrame("Frame", "NC_GUIFrame", UIParent);
		GUIFrame:SetHeight(400);
		GUIFrame:SetWidth(540);
		GUIFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 80);
		GUIFrame:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } 
		});
		GUIFrame:SetBackdropColor(0.25, 0.24, 0.32, 1);
		GUIFrame:SetBackdropBorderColor(0.1,0.1,0.1,1);
		GUIFrame:EnableMouse(1);
		GUIFrame:SetMovable(1);
		GUIFrame:SetFrameStrata("DIALOG");
		GUIFrame:SetToplevel(1);
		GUIFrame:SetClampedToScreen(1);
		GUIFrame:SetScript("OnMouseDown", function() GUIFrame:StartMoving(); end);
		GUIFrame:SetScript("OnMouseUp", function() GUIFrame:StopMovingOrSizing(); end);
		GUIFrame:Hide();
		
		GUIFrame.CategoryButtons = {};
		GUIFrame.ActiveCategory = 1;
		
		local header = GUIFrame:CreateFontString("NC_GUIHeader", "ARTWORK", "GameFontHighlight");
		header:SetFont(GameFontNormal:GetFont(), 22, "THICKOUTLINE");
		header:SetPoint("BOTTOM", GUIFrame, "TOP", 0, 0);
		header:SetText("NameplateCooldowns");
		
		GUIFrame.outline = CreateFrame("Frame", nil, GUIFrame);
		GUIFrame.outline:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = 1,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		});
		GUIFrame.outline:SetBackdropColor(0.1, 0.1, 0.2, 1);
		GUIFrame.outline:SetBackdropBorderColor(0.8, 0.8, 0.9, 0.4);
		GUIFrame.outline:SetPoint("TOPLEFT", 12, -12);
		GUIFrame.outline:SetPoint("BOTTOMLEFT", 12, 12);
		GUIFrame.outline:SetWidth(140);
		
		local closeButton = CreateFrame("Button", "NC_GUICloseButton", GUIFrame, "UIPanelButtonTemplate");
		closeButton:SetWidth(24);
		closeButton:SetHeight(24);
		closeButton:SetPoint("TOPRIGHT", 0, 22);
		closeButton:SetScript("OnClick", function() GUIFrame:Hide(); end);
		closeButton.text = closeButton:CreateFontString(nil, "ARTWORK", "GameFontNormal");
		closeButton.text:SetPoint("CENTER", closeButton, "CENTER", 1, -1);
		closeButton.text:SetText("X");
		
		local scrollFramesTipText = GUIFrame:CreateFontString("NC_GUIScrollFramesTipText", "OVERLAY", "GameFontNormal");
		scrollFramesTipText:SetPoint("CENTER", GUIFrame, "TOP", 70, -35);
		scrollFramesTipText:SetText(L["Click on icon to enable/disable tracking"]);
		
		GUIFrame.Categories = {};
		GUIFrame.SpellIcons = {};
		
		for index, value in pairs({L["General"], L["Filters"], L["Profiles"], L["WARRIOR"], L["DRUID"], L["PRIEST"], L["MAGE"], L["MONK"], L["HUNTER"], L["PALADIN"], L["ROGUE"], L["DEATHKNIGHT"], L["WARLOCK"], L["SHAMAN"], L["DEMONHUNTER"], L["MISC"]}) do
			local b = CreateGUICategory();
			b.index = index;
			b.text:SetText(value);
			if (index == 1) then
				b:LockHighlight();
				b.text:SetTextColor(1, 1, 1);
			end
			if (index < 4) then
				b:SetPoint("TOPLEFT", GUIFrame.outline, "TOPLEFT", 5, (index-1) * -18 - 6);
			else
				b:SetPoint("TOPLEFT", GUIFrame.outline, "TOPLEFT", 5, (index-1) * -18 - 26);
			end
			
			GUIFrame.Categories[index] = {};
			GUIFrame.OnDBChangedHandlers = { };
			
			if (value == L["General"]) then
				GUICategory_General(index, value);
			elseif (value == L["Filters"]) then
				GUICategory_Filters(index, value);
			elseif (value == L["Profiles"]) then
				GUICategory_Profiles(index, value);
			else
				GUICategory_Other(index, value);
			end
		end
	end

	function GUICategory_General(index, value)
		local buttonEnableDisableAddon = RD.CreateButton();
		buttonEnableDisableAddon:SetParent(GUIFrame);
		buttonEnableDisableAddon:SetText(db.AddonEnabled and L["options:general:disable-addon-btn"] or L["options:general:enable-addon-btn"]);
		buttonEnableDisableAddon:SetWidth(340);
		buttonEnableDisableAddon:SetHeight(20);
		buttonEnableDisableAddon:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 15, -5);
		buttonEnableDisableAddon:SetScript("OnClick", function(self, ...)
			if (db.AddonEnabled) then
				EventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
				wipe(charactersDB);
			else
				EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
			end
			OnUpdate();
			db.AddonEnabled = not db.AddonEnabled;
			buttonEnableDisableAddon.Text:SetText(db.AddonEnabled and L["options:general:disable-addon-btn"] or L["options:general:enable-addon-btn"]);
			Print(db.AddonEnabled and L["chat:addon-is-enabled"] or L["chat:addon-is-disabled"]);
		end);
		table.insert(GUIFrame.Categories[index], buttonEnableDisableAddon);
		table_insert(GUIFrame.OnDBChangedHandlers, function() buttonEnableDisableAddon.Text:SetText(db.AddonEnabled and L["options:general:disable-addon-btn"] or L["options:general:enable-addon-btn"]); end);
	
		local buttonSwitchTestMode = RD.CreateButton();
		buttonSwitchTestMode:SetParent(GUIFrame);
		buttonSwitchTestMode:SetText(L["Enable test mode (need at least one visible nameplate)"]);
		buttonSwitchTestMode:SetWidth(340);
		buttonSwitchTestMode:SetHeight(20);
		buttonSwitchTestMode:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 15, -30);
		buttonSwitchTestMode:SetScript("OnClick", function(self, ...)
			if (not TestFrame or not TestFrame:GetScript("OnUpdate")) then
				EnableTestMode();
				self.Text:SetText(L["Disable test mode"]);
			else
				DisableTestMode();
				self.Text:SetText(L["Enable test mode (need at least one visible nameplate)"]);
			end
		end);
		table.insert(GUIFrame.Categories[index], buttonSwitchTestMode);
		table_insert(GUIFrame.OnDBChangedHandlers, function() buttonSwitchTestMode.Text:SetText(L["Enable test mode (need at least one visible nameplate)"]); end);
		
		local sliderIconSize = RD.CreateSlider();
		sliderIconSize:SetParent(GUIFrame.outline);
		sliderIconSize:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 15, -60);
		sliderIconSize:SetHeight(100);
		sliderIconSize:SetWidth(340);
		sliderIconSize:GetTextObject():SetText(L["Icon size"]);
		sliderIconSize:GetBaseSliderObject():SetValueStep(1);
		sliderIconSize:GetBaseSliderObject():SetMinMaxValues(1, 50);
		sliderIconSize:GetBaseSliderObject():SetValue(db.IconSize);
		sliderIconSize:GetBaseSliderObject():SetScript("OnValueChanged", function(self, value)
			sliderIconSize:GetEditboxObject():SetText(tostring(math_ceil(value)));
			db.IconSize = math_ceil(value);
			ReallocateAllIcons(false);
		end);
		sliderIconSize:GetEditboxObject():SetText(tostring(db.IconSize));
		sliderIconSize:GetEditboxObject():SetScript("OnEnterPressed", function(self, value)
			if (sliderIconSize:GetEditboxObject():GetText() ~= "") then
				local v = tonumber(sliderIconSize:GetEditboxObject():GetText());
				if (v == nil) then
					sliderIconSize:GetEditboxObject():SetText(tostring(db.IconSize));
					Print(L["Value must be a number"]);
				else
					if (v > 50) then
						v = 50;
					end
					if (v < 1) then
						v = 1;
					end
					sliderIconSize:GetBaseSliderObject():SetValue(v);
				end
				sliderIconSize:GetEditboxObject():ClearFocus();
			end
		end);
		sliderIconSize:GetLowTextObject():SetText("1");
		sliderIconSize:GetHighTextObject():SetText("50");
		table.insert(GUIFrame.Categories[index], sliderIconSize);
		table_insert(GUIFrame.OnDBChangedHandlers, function() sliderIconSize:GetBaseSliderObject():SetValue(db.IconSize); sliderIconSize:GetEditboxObject():SetText(tostring(db.IconSize)); end);
		
		local sliderIconXOffset = RD.CreateSlider();
		sliderIconXOffset:SetParent(GUIFrame.outline);
		sliderIconXOffset:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 15, -115);
		sliderIconXOffset:SetHeight(100);
		sliderIconXOffset:SetWidth(155);
		sliderIconXOffset:GetTextObject():SetText(L["Icon X-coord offset"]);
		sliderIconXOffset:GetBaseSliderObject():SetValueStep(1);
		sliderIconXOffset:GetBaseSliderObject():SetMinMaxValues(-200, 200);
		sliderIconXOffset:GetBaseSliderObject():SetValue(db.IconXOffset);
		sliderIconXOffset:GetBaseSliderObject():SetScript("OnValueChanged", function(self, value)
			sliderIconXOffset:GetEditboxObject():SetText(tostring(math_ceil(value)));
			db.IconXOffset = math_ceil(value);
			ReallocateAllIcons(false);
		end);
		sliderIconXOffset:GetEditboxObject():SetText(tostring(db.IconXOffset));
		sliderIconXOffset:GetEditboxObject():SetScript("OnEnterPressed", function(self, value)
			if (sliderIconXOffset:GetEditboxObject():GetText() ~= "") then
				local v = tonumber(sliderIconXOffset:GetEditboxObject():GetText());
				if (v == nil) then
					sliderIconXOffset:GetEditboxObject():SetText(tostring(db.IconXOffset));
					Print(L["Value must be a number"]);
				else
					if (v > 200) then
						v = 200;
					end
					if (v < -200) then
						v = -200;
					end
					sliderIconXOffset:GetBaseSliderObject():SetValue(v);
				end
				sliderIconXOffset:GetEditboxObject():ClearFocus();
			end
		end);
		sliderIconXOffset:GetLowTextObject():SetText("-200");
		sliderIconXOffset:GetHighTextObject():SetText("200");
		table.insert(GUIFrame.Categories[index], sliderIconXOffset);
		table_insert(GUIFrame.OnDBChangedHandlers, function() sliderIconXOffset:GetBaseSliderObject():SetValue(db.IconXOffset); sliderIconXOffset:GetEditboxObject():SetText(tostring(db.IconXOffset)); end);
		
		local sliderIconYOffset = RD.CreateSlider();
		sliderIconYOffset:SetHeight(100);
		sliderIconYOffset:SetWidth(155);
		sliderIconYOffset:SetParent(GUIFrame.outline);
		sliderIconYOffset:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 200, -115);
		sliderIconYOffset:GetTextObject():SetText(L["Icon Y-coord offset"]);
		sliderIconYOffset:GetBaseSliderObject():SetValueStep(1);
		sliderIconYOffset:GetBaseSliderObject():SetMinMaxValues(-200, 200);
		sliderIconYOffset:GetBaseSliderObject():SetValue(db.IconYOffset);
		sliderIconYOffset:GetBaseSliderObject():SetScript("OnValueChanged", function(self, value)
			sliderIconYOffset:GetEditboxObject():SetText(tostring(math_ceil(value)));
			db.IconYOffset = math_ceil(value);
			ReallocateAllIcons(false);
		end);
		sliderIconYOffset:GetEditboxObject():SetText(tostring(db.IconYOffset));
		sliderIconYOffset:GetEditboxObject():SetScript("OnEnterPressed", function(self, value)
			if (sliderIconYOffset:GetEditboxObject():GetText() ~= "") then
				local v = tonumber(sliderIconYOffset:GetEditboxObject():GetText());
				if (v == nil) then
					sliderIconYOffset:GetEditboxObject():SetText(tostring(db.IconYOffset));
					Print(L["Value must be a number"]);
				else
					if (v > 200) then
						v = 200;
					end
					if (v < -200) then
						v = -200;
					end
					sliderIconYOffset:GetBaseSliderObject():SetValue(v);
				end
				sliderIconYOffset:GetEditboxObject():ClearFocus();
			end
		end);
		sliderIconYOffset:GetLowTextObject():SetText("-200");
		sliderIconYOffset:GetHighTextObject():SetText("200");
		table.insert(GUIFrame.Categories[index], sliderIconYOffset);
		table_insert(GUIFrame.OnDBChangedHandlers, function() sliderIconYOffset:GetBaseSliderObject():SetValue(db.IconYOffset); sliderIconYOffset:GetEditboxObject():SetText(tostring(db.IconYOffset)); end);
		
		local checkBoxFullOpacityAlways = RD.CreateCheckBox();
		checkBoxFullOpacityAlways:SetText(L["Always display CD icons at full opacity (ReloadUI is needed)"]);
		checkBoxFullOpacityAlways:SetOnClickHandler(function(this)
			db.FullOpacityAlways = this:GetChecked();
		end);
		checkBoxFullOpacityAlways:SetParent(GUIFrame.outline);
		checkBoxFullOpacityAlways:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 15, -185);
		checkBoxFullOpacityAlways:SetChecked(db.FullOpacityAlways);
		table.insert(GUIFrame.Categories[index], checkBoxFullOpacityAlways);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkBoxFullOpacityAlways:SetChecked(db.FullOpacityAlways); end);
		
		local checkBoxBorderTrinkets = RD.CreateCheckBoxWithColorPicker();
		checkBoxBorderTrinkets:SetText(L["Show border around trinkets"]);
		checkBoxBorderTrinkets:SetOnClickHandler(function(this)
			db.ShowBorderTrinkets = this:GetChecked();
			ReallocateAllIcons(true);
		end);
		checkBoxBorderTrinkets:SetParent(GUIFrame.outline);
		checkBoxBorderTrinkets:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 15, -235);
		checkBoxBorderTrinkets:SetChecked(db.ShowBorderTrinkets);
		checkBoxBorderTrinkets:SetColor(unpack(db.BorderTrinketsColor));
		checkBoxBorderTrinkets.ColorButton:SetScript("OnClick", function()
			ColorPickerFrame:Hide();
			local function callback(restore)
				local r, g, b;
				if (restore) then
					r, g, b = unpack(restore);
				else
					r, g, b = ColorPickerFrame:GetColorRGB();
				end
				db.BorderTrinketsColor = {r, g, b};
				checkBoxBorderTrinkets:SetColor(unpack(db.BorderTrinketsColor));
				ReallocateAllIcons(true);
			end
			ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = callback, callback, callback;
			ColorPickerFrame:SetColorRGB(unpack(db.BorderTrinketsColor));
			ColorPickerFrame.hasOpacity = false;
			ColorPickerFrame.previousValues = { unpack(db.BorderTrinketsColor) };
			ColorPickerFrame:Show();
		end);
		table.insert(GUIFrame.Categories[index], checkBoxBorderTrinkets);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkBoxBorderTrinkets:SetChecked(db.ShowBorderTrinkets); checkBoxBorderTrinkets:SetColor(unpack(db.BorderTrinketsColor)); end);
		
		local checkBoxBorderInterrupts = RD.CreateCheckBoxWithColorPicker();
		checkBoxBorderInterrupts:SetText(L["Show border around interrupts"]);
		checkBoxBorderInterrupts:SetOnClickHandler(function(this)
			db.ShowBorderInterrupts = this:GetChecked();
			ReallocateAllIcons(true);
		end);
		checkBoxBorderInterrupts:SetParent(GUIFrame.outline);
		checkBoxBorderInterrupts:SetPoint("TOPLEFT", GUIFrame.outline, "TOPRIGHT", 15, -255);
		checkBoxBorderInterrupts:SetChecked(db.ShowBorderInterrupts);
		checkBoxBorderInterrupts:SetColor(unpack(db.BorderInterruptsColor));
		checkBoxBorderInterrupts.ColorButton:SetScript("OnClick", function()
			ColorPickerFrame:Hide();
			local function callback(restore)
				local r, g, b;
				if (restore) then
					r, g, b = unpack(restore);
				else
					r, g, b = ColorPickerFrame:GetColorRGB();
				end
				db.BorderInterruptsColor = {r, g, b};
				checkBoxBorderInterrupts:SetColor(unpack(db.BorderInterruptsColor));
				ReallocateAllIcons(true);
			end
			ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = callback, callback, callback;
			ColorPickerFrame:SetColorRGB(unpack(db.BorderInterruptsColor));
			ColorPickerFrame.hasOpacity = false;
			ColorPickerFrame.previousValues = { unpack(db.BorderInterruptsColor) };
			ColorPickerFrame:Show();
		end);
		table.insert(GUIFrame.Categories[index], checkBoxBorderInterrupts);
		table_insert(GUIFrame.OnDBChangedHandlers, function() checkBoxBorderInterrupts:SetChecked(db.ShowBorderInterrupts); checkBoxBorderInterrupts:SetColor(unpack(db.BorderInterruptsColor)); end);
		
		local dropdownIconSortMode = CreateFrame("Frame", "NC.GUI.General.DropdownIconSortMode", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownIconSortMode, 300);
		dropdownIconSortMode:SetPoint("BOTTOMLEFT", GUIFrame.outline, "BOTTOMRIGHT", 10, 45);
		local info = {};
		dropdownIconSortMode.initialize = function()
			wipe(info);
			for _, sortMode in pairs(CONST_SORT_MODES) do
				info.text = CONST_SORT_MODES_L[sortMode];
				info.value = sortMode;
				info.func = function(self)
					db.IconSortMode = self.value;
					_G[dropdownIconSortMode:GetName().."Text"]:SetText(self:GetText());
				end
				info.checked = (db.IconSortMode == info.value);
				UIDropDownMenu_AddButton(info);
			end
		end
		_G[dropdownIconSortMode:GetName().."Text"]:SetText(CONST_SORT_MODES_L[db.IconSortMode]);
		dropdownIconSortMode.text = dropdownIconSortMode:CreateFontString("NC.GUI.General.DropdownIconSortMode.Label", "ARTWORK", "GameFontNormalSmall");
		dropdownIconSortMode.text:SetPoint("LEFT", 20, 15);
		dropdownIconSortMode.text:SetText(L["general.sort-mode"]);
		table.insert(GUIFrame.Categories[index], dropdownIconSortMode);
		table_insert(GUIFrame.OnDBChangedHandlers, function() _G[dropdownIconSortMode:GetName().."Text"]:SetText(CONST_SORT_MODES_L[db.IconSortMode]); end);
		
		local dropdownFont = CreateFrame("Frame", "NC_GUI_General_DropdownFont", GUIFrame, "UIDropDownMenuTemplate");
		UIDropDownMenu_SetWidth(dropdownFont, 300);
		dropdownFont:SetPoint("BOTTOMLEFT", GUIFrame.outline, "BOTTOMRIGHT", 10, 10);
		local info = {};
		dropdownFont.initialize = function()
			wipe(info);
			for idx, font in next, LibStub("LibSharedMedia-3.0"):List("font") do
				info.text = font;
				info.value = font;
				info.func = function(self)
					db.Font = self.value;
					ReallocateAllIcons(false);
					NC_GUI_General_DropdownFontText:SetText(self:GetText());
				end
				info.checked = font == db.Font;
				UIDropDownMenu_AddButton(info);
			end
		end
		NC_GUI_General_DropdownFontText:SetText(db.Font);
		dropdownFont.text = dropdownFont:CreateFontString("NC_GUI_General_DropdownFontNoteText", "ARTWORK", "GameFontNormalSmall");
		dropdownFont.text:SetPoint("LEFT", 20, 15);
		dropdownFont.text:SetText(L["Font:"]);
		table.insert(GUIFrame.Categories[index], dropdownFont);
		table_insert(GUIFrame.OnDBChangedHandlers, function() NC_GUI_General_DropdownFontText:SetText(db.Font); end);
		
	end
	
	function GUICategory_Profiles(index, value)
		local button = RD.CreateButton();
		button:SetParent(GUIFrame);
		button:SetText(L["Open profiles dialog"]);
		button:SetWidth(170);
		button:SetHeight(40);
		button:SetPoint("CENTER", GUIFrame, "CENTER", 70, 0);
		button:SetScript("OnClick", function(self, ...)
			InterfaceOptionsFrame_OpenToCategory(ProfileOptionsFrame);
			GUIFrame:Hide();
		end);
		table_insert(GUIFrame.Categories[index], button);
	end
	
	function GUICategory_Other(index, value)
		local scrollAreaBackground = CreateFrame("Frame", "NC_GUIScrollFrameBackground_"..tostring(index - 1), GUIFrame);
		scrollAreaBackground:SetPoint("TOPLEFT", GUIFrame, "TOPLEFT", 160, -60);
		scrollAreaBackground:SetPoint("BOTTOMRIGHT", GUIFrame, "BOTTOMRIGHT", -30, 15);
		scrollAreaBackground:SetBackdrop({
			bgFile = "Interface\\AddOns\\NameplateCooldowns\\media\\Smudge.tga",
			edgeFile = "Interface\\AddOns\\NameplateCooldowns\\media\\Border",
			tile = true, edgeSize = 3, tileSize = 1,
			insets = { left = 3, right = 3, top = 3, bottom = 3 }
		});
		local bRed, bGreen, bBlue = GUIFrame:GetBackdropColor();
		scrollAreaBackground:SetBackdropColor(bRed, bGreen, bBlue, 0.8)
		scrollAreaBackground:SetBackdropBorderColor(0.3, 0.3, 0.5, 1);
		scrollAreaBackground:Hide();
		table.insert(GUIFrame.Categories[index], scrollAreaBackground);
		
		local scrollArea = CreateFrame("ScrollFrame", "NC_GUIScrollFrame_"..tostring(index - 1), scrollAreaBackground, "UIPanelScrollFrameTemplate");
		scrollArea:SetPoint("TOPLEFT", scrollAreaBackground, "TOPLEFT", 5, -5);
		scrollArea:SetPoint("BOTTOMRIGHT", scrollAreaBackground, "BOTTOMRIGHT", -5, 5);
		scrollArea:Show();
		
		local scrollAreaChildFrame = CreateFrame("Frame", "NC_GUIScrollFrameChildFrame_"..tostring(index - 1), scrollArea);
		scrollArea:SetScrollChild(scrollAreaChildFrame);
		scrollAreaChildFrame:SetPoint("CENTER", GUIFrame, "CENTER", 0, 1);
		scrollAreaChildFrame:SetWidth(288);
		scrollAreaChildFrame:SetHeight(288);
		
		local spells = { };
		for spellID in pairs(CDs[value]) do
			local spellName, _, spellIcon = GetSpellInfo(spellID);
			if (spellName ~= nil) then
				table.insert(spells, { ["spellID"] = spellID, ["spellName"] = spellName, ["spellIcon"] = spellIcon });
			else
				Print(format(L["Unknown spell: %s"], spellID));
			end
		end
		table.sort(spells, function(item1, item2) return item1.spellName < item2.spellName end);
		
		local iterator = 1;
		for _, spellInfo in pairs(spells) do
			local spellItem = CreateFrame("button", nil, scrollAreaChildFrame, "SecureActionButtonTemplate");
			spellItem:SetHeight(20);
			spellItem:SetWidth(20);
			spellItem:SetPoint("TOPLEFT", 3, ((iterator - 1) * -22) - 10);
			
			spellItem.tex = spellItem:CreateTexture();
			spellItem.tex:SetAllPoints(spellItem);
			spellItem.tex:SetHeight(20);
			spellItem.tex:SetWidth(20);
			spellItem.tex:SetTexture(spellInfo.spellIcon);
			
			spellItem.Text = spellItem:CreateFontString(nil, "OVERLAY", "GameFontNormal");
			spellItem.Text:SetPoint("LEFT", 22, 0);
			spellItem.Text:SetText(spellInfo.spellName);
			spellItem:EnableMouse(true);
			
			spellItem:SetScript("OnEnter", function(self, ...)
				GameTooltip:SetOwner(spellItem, "ANCHOR_TOPRIGHT");
				GameTooltip:SetSpellByID(spellInfo.spellID);
				GameTooltip:Show();
			end)
			spellItem:SetScript("OnLeave", function(self, ...)
				GameTooltip:Hide();
			end)
			spellItem:SetScript("OnClick", function(self, ...)
				if (self.tex:GetAlpha() > 0.5) then
					db.CDsTable[spellInfo.spellID] = false;
					CDEnabledCache[spellInfo.spellID] = nil;
					self.tex:SetAlpha(0.3);
				else
					db.CDsTable[spellInfo.spellID] = true;
					CDEnabledCache[spellInfo.spellID] = true;
					self.tex:SetAlpha(1.0);
				end
			end)
			if (db.CDsTable[spellInfo.spellID] == true) then
				spellItem.tex:SetAlpha(1.0);
			else
				spellItem.tex:SetAlpha(0.3);
			end
			iterator = iterator + 1;
			spellItem.spellID = spellInfo.spellID;
			tinsert(GUIFrame.SpellIcons, spellItem);
			table_insert(GUIFrame.OnDBChangedHandlers, function() spellItem.tex:SetAlpha(db.CDsTable[spellInfo.spellID] and 1.0 or 0.3); end);
		end
	end
	
	function OnGUICategoryClick(self, ...)
		GUIFrame.CategoryButtons[GUIFrame.ActiveCategory].text:SetTextColor(1, 0.82, 0);
		GUIFrame.CategoryButtons[GUIFrame.ActiveCategory]:UnlockHighlight();
		GUIFrame.ActiveCategory = self.index;
		self.text:SetTextColor(1, 1, 1);
		self:LockHighlight();
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
		ShowGUICategory(GUIFrame.ActiveCategory);
	end
	
	function ShowGUICategory(index)
		for i, v in pairs(GUIFrame.Categories) do
			for k, l in pairs(v) do
				l:Hide();
			end
		end
		for i, v in pairs(GUIFrame.Categories[index]) do
			v:Show();
		end
		if (index > 3) then
			NC_GUIScrollFramesTipText:Show();
		else
			NC_GUIScrollFramesTipText:Hide();
		end
	end
	
	function RebuildDropdowns()
		local info = {};
		NC_GUIProfilesDropdownCopyProfile.myvalue = nil;
		UIDropDownMenu_SetText(NC_GUIProfilesDropdownCopyProfile, "");
		local initCopyProfile = function()
			wipe(info);
			for index in pairs(NameplateCooldownsDB) do
				if (index ~= LocalPlayerFullName) then
					info.text = index;
					info.func = function(self)
						NC_GUIProfilesDropdownCopyProfile.myvalue = index;
						UIDropDownMenu_SetText(NC_GUIProfilesDropdownCopyProfile, index);
					end
					info.notCheckable = true;
					UIDropDownMenu_AddButton(info);
				end
			end
		end
		UIDropDownMenu_Initialize(NC_GUIProfilesDropdownCopyProfile, initCopyProfile);
		
		NC_GUIProfilesDropdownDeleteProfile.myvalue = nil;
		UIDropDownMenu_SetText(NC_GUIProfilesDropdownDeleteProfile, "");
		local initDeleteProfile = function()
			wipe(info);
			for index in pairs(NameplateCooldownsDB) do
				info.text = index;
				info.func = function(self)
					NC_GUIProfilesDropdownDeleteProfile.myvalue = index;
					UIDropDownMenu_SetText(NC_GUIProfilesDropdownDeleteProfile, index);
				end
				info.notCheckable = true;
				UIDropDownMenu_AddButton(info);
			end
		end
		UIDropDownMenu_Initialize(NC_GUIProfilesDropdownDeleteProfile, initDeleteProfile);
	end
	
	function CreateGUICategory()
		local b = CreateFrame("Button", nil, GUIFrame.outline);
		b:SetWidth(GUIFrame.outline:GetWidth()-8);
		b:SetHeight(18);
		b:SetScript("OnClick", OnGUICategoryClick);
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");
		b:GetHighlightTexture():SetAlpha(0.7);
		b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal");
		b.text:SetPoint("LEFT", 3, 0);
		GUIFrame.CategoryButtons[#GUIFrame.CategoryButtons + 1] = b;
		return b;
	end
	
end

-------------------------------------------------------------------------------------------------
----- Useful stuff
-------------------------------------------------------------------------------------------------
do

	function Print(...)
		local text = "";
		for i = 1, select("#", ...) do
			text = text..tostring(select(i, ...)).." "
		end
		DEFAULT_CHAT_FRAME:AddMessage(format("NameplateCooldowns: %s", text), 0, 128, 128);
	end

	function deepcopy(object)
		local lookup_table = {}
		local function _copy(object)
			if type(object) ~= "table" then
				return object
			elseif lookup_table[object] then
				return lookup_table[object]
			end
			local new_table = {}
			lookup_table[object] = new_table
			for index, value in pairs(object) do
				new_table[_copy(index)] = _copy(value)
			end
			return setmetatable(new_table, getmetatable(object))
		end
		return _copy(object)
	end
	
	function table_contains_key(t, key)
		for index in pairs(t) do
			if (index == key) then
				return true;
			end
		end
		return false;
	end
	
	function table_any(t)
		for index in pairs(t) do
			return true;
		end
		return false;
	end
	
end

-------------------------------------------------------------------------------------------------
----- Frame for events
-------------------------------------------------------------------------------------------------
do

	local COMBATLOG_OBJECT_IS_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE;

	EventFrame = CreateFrame("Frame");
	EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
	EventFrame:SetScript("OnEvent", function(self, event, ...) self[event](...); end);
	
	EventFrame.COMBAT_LOG_EVENT_UNFILTERED = function()
		local cTime = GetTime();
		local _, eventType, _, _, srcName, srcFlags, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo();
		if (bit_band(srcFlags, COMBATLOG_OBJECT_IS_HOSTILE) ~= 0) then
			if (CDEnabledCache[spellID]) then
				if (eventType == "SPELL_CAST_SUCCESS" or eventType == "SPELL_AURA_APPLIED" or eventType == "SPELL_MISSED" or eventType == "SPELL_SUMMON") then
					local Name = string_match(srcName, "[%P]+");
					if (not charactersDB[Name]) then
						charactersDB[Name] = {};
					end
					local duration = CDTimeCache[spellID];
					local expires = cTime + duration;
					charactersDB[Name][spellID] = { ["spellID"] = spellID, ["duration"] = duration, ["expires"] = expires };
					for frame, charName in pairs(NameplatesVisible) do
						if (charName == Name) then
							UpdateOnlyOneNameplate(frame, charName);
							break;
						end
					end
				end
			end
			-- // resets
			if (table_contains_key(Resets, spellID)) then
				if (eventType == "SPELL_CAST_SUCCESS") then
					local Name = string_match(srcName, "[%P]+");
					if (charactersDB[Name]) then
						for _, v in pairs(Resets[spellID]) do
							charactersDB[Name][v] = nil;
						end
						for frame, charName in pairs(NameplatesVisible) do
							if (charName == Name) then
								UpdateOnlyOneNameplate(frame, charName);
								break;
							end
						end
					end
				end
			elseif (spellID == 102060) then	-- // let's start cd of spellid:6552 if warrior have used spellid:102060
				if (CDEnabledCache[6552] and eventType == "SPELL_CAST_SUCCESS") then
					local Name = string_match(srcName, "[%P]+");
					if (not charactersDB[Name]) then
						charactersDB[Name] = {};
					end
					local duration = CDTimeCache[6552];
					local expires = cTime + duration;
					charactersDB[Name][6552] = { ["spellID"] = 6552, ["duration"] = duration, ["expires"] = expires };
					for frame, charName in pairs(NameplatesVisible) do
						if (charName == Name) then
							UpdateOnlyOneNameplate(frame, charName);
							break;
						end
					end
				end
			elseif (spellID == SPELL_PVPADAPTATION) then -- // pvptier 1/2 used, correcting cd of PvP trinket
				if (CDEnabledCache[SPELL_PVPTRINKET] and eventType == "SPELL_AURA_APPLIED") then
					local Name = string_match(srcName, "[%P]+");
					if (charactersDB[Name]) then
						charactersDB[Name][SPELL_PVPTRINKET] = { ["spellID"] = SPELL_PVPTRINKET, ["duration"] = 60, ["expires"] = cTime + 60 };
						for frame, charName in pairs(NameplatesVisible) do
							if (charName == Name) then
								UpdateOnlyOneNameplate(frame, charName);
								break;
							end
						end
					end
				end
			end
		end
	end
	
	EventFrame.PLAYER_ENTERING_WORLD = function()
		if (OnStartup) then
			OnStartup();
		end
		wipe(charactersDB);
		local inInstance, instanceType = IsInInstance();
		if (not inInstance) then
			InstanceType = instanceType;
		elseif (inInstance and instanceType == "none") then
			InstanceType = INSTANCE_TYPE_UNKNOWN;
		else
			InstanceType = instanceType;
		end
	end
	
	EventFrame.NAME_PLATE_UNIT_ADDED = function(unitID)
		local nameplate = C_NamePlate.GetNamePlateForUnit(unitID);
		local unitName = UnitName(unitID);
		NameplatesVisible[nameplate] = unitName;
		if (not Nameplates[nameplate]) then
			nameplate.NCIcons = {};
			nameplate.NCIconsCount = 0;	-- // it's faster than #nameplate.NCIcons
			Nameplates[nameplate] = true;
		end
		UpdateOnlyOneNameplate(nameplate, unitName);
		if (db.FullOpacityAlways and nameplate.NCFrame) then
			nameplate.NCFrame:Show();
		end
	end
	
	EventFrame.NAME_PLATE_UNIT_REMOVED = function(unitID)
		local nameplate = C_NamePlate.GetNamePlateForUnit(unitID);
		NameplatesVisible[nameplate] = nil;
		if (db.FullOpacityAlways and nameplate.NCFrame) then
			nameplate.NCFrame:Hide();
		end
	end
	
	EventFrame.PLAYER_TARGET_CHANGED = function()
		ReallocateAllIcons(true);
	end
		
end

-------------------------------------------------------------------------------------------------
----- Frame for fun
-------------------------------------------------------------------------------------------------
local funFrame = CreateFrame("Frame");
funFrame:RegisterEvent("CHAT_MSG_ADDON");
funFrame:SetScript("OnEvent", function(self, event, ...)
	local prefix, message, channel, sender = ...;
	if (prefix == "NC_prefix") then
		if (string_find(message, "reporting")) then
			local _, toWhom = strsplit(":", message, 2);
			local myName = UnitName("player").."-"..string_gsub(GetRealmName(), " ", "");
			if (toWhom == myName and sender ~= myName) then
				Print(sender.." is using NC");
			end
		elseif (string_find(message, "requesting")) then
			C_ChatInfo.SendAddonMessage("NC_prefix", "reporting:"..sender, channel);
		end
	end
end);
C_ChatInfo.RegisterAddonMessagePrefix("NC_prefix");
