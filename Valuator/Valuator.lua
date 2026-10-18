-- Valuator
-- Shows vendor sell value (and, if aux-addon is installed, its auction
-- value) on tooltips, including a per-item breakdown for stacks. Needs
-- ShaguTweaks for the price database and link parsing; disables
-- ShaguTweaks' and Aux' own equivalent tooltip lines to avoid duplicates.
--
-- Uses a custom SmallMoneyFrameTemplate frame instead of a second
-- SetTooltipMoney call, since the latter overwrites the existing money
-- line on GameTooltip instead of adding a new one on this client.

local function hooksecurefunc(arg1, arg2, arg3)
	if type(arg1) == "string" then
		arg1, arg2, arg3 = _G, arg1, arg2;
	end
	local orig = arg1[arg2];
	arg1[arg2] = function(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,a16,a17,a18,a19,a20)
		local x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15,x16,x17,x18,x19,x20 = orig(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,a16,a17,a18,a19,a20);

		arg3(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,a16,a17,a18,a19,a20);

		return x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15,x16,x17,x18,x19,x20;
	end
end

local function CreateStaticMoneyFrame(name)
	local frame = CreateFrame("Frame", name, GameTooltip, "SmallMoneyFrameTemplate");
	frame.moneyType = "STATIC";
	-- Static: don't let the frame reset itself to character money via its own OnShow/OnEvent.
	frame:UnregisterAllEvents();
	frame:SetScript("OnShow", nil);
	frame:SetScript("OnEvent", nil);
	frame:Hide();
	return frame;
end

local perItemMoneyFrame = CreateStaticMoneyFrame("ValuatorMoneyFrame");
local totalMoneyFrame = CreateStaticMoneyFrame("ValuatorTotalMoneyFrame");
local auctionPerItemMoneyFrame = CreateStaticMoneyFrame("ValuatorAuctionMoneyFrame");
local auctionTotalMoneyFrame = CreateStaticMoneyFrame("ValuatorAuctionTotalMoneyFrame");

local function HideMoneyFrames()
	perItemMoneyFrame:Hide();
	totalMoneyFrame:Hide();
	auctionPerItemMoneyFrame:Hide();
	auctionTotalMoneyFrame:Hide();
end

-- Hide on tooltip hide too, or a frame left shown from an earlier item
-- would reappear misplaced on the next, unrelated tooltip (e.g. a world object).
GameTooltip:HookScript("OnHide", HideMoneyFrames);
ItemRefTooltip:HookScript("OnHide", HideMoneyFrames);

local auxHistory, auxInfo;
if require then
	local ok1, mod1 = pcall(require, "aux.core.history");
	if ok1 then auxHistory = mod1; end
	local ok2, mod2 = pcall(require, "aux.util.info");
	if ok2 then auxInfo = mod2; end
end

-- ShaguTweaks only enables its vendor-value module at VARIABLES_LOADED if
-- ShaguTweaks_config[title] == 1; since ShaguTweaks is our RequiredDep,
-- this runs first and forcing it to 0 keeps that module from ever hooking the tooltip.
if ShaguTweaks then
	ShaguTweaks_config = ShaguTweaks_config or {};
	local title = (ShaguTweaks.T and ShaguTweaks.T["Vendor Values"]) or "Vendor Values";
	ShaguTweaks_config[title] = 0;
end

-- Same idea for Aux' own tooltip lines. Aux only builds its settings table
-- at VARIABLES_LOADED too; our OptionalDep on aux-addon guarantees our
-- handler is registered, and so runs, after Aux's.
if require then
	local disableFrame = CreateFrame("Frame");
	disableFrame:RegisterEvent("VARIABLES_LOADED");
	disableFrame:SetScript("OnEvent", function()
		local ok, auxModule = pcall(require, "aux");
		if ok and auxModule and auxModule.character_data and auxModule.character_data.tooltip then
			auxModule.character_data.tooltip.value = false;
			auxModule.character_data.tooltip.merchant_sell = false;
		end
	end);
end

-- Label + right-aligned coin icons, like Blizzard's durability/repair lines.
-- Works for GameTooltip or ItemRefTooltip, reparenting the money frame as needed.
local function AddMoneyLine(tooltip, label, moneyFrame, copper)
	tooltip:AddDoubleLine(label, " ", 1, 1, 1, 1, 1, 1);
	local rightText = getglobal(tooltip:GetName().."TextRight"..tooltip:NumLines());

	moneyFrame:SetParent(tooltip);
	moneyFrame:ClearAllPoints();
	moneyFrame:SetPoint("RIGHT", rightText, "RIGHT", 0, 0);
	MoneyFrame_Update(moneyFrame:GetName(), copper);
	moneyFrame:Show();

	-- The frame reserves space for gold/silver/copper even when unused, so its
	-- right edge sits past the last visible icon -- shift by that gap to compensate.
	local copperButton = getglobal(moneyFrame:GetName().."CopperButton");
	if copperButton then
		local gap = moneyFrame:GetRight() - copperButton:GetRight();
		moneyFrame:ClearAllPoints();
		moneyFrame:SetPoint("RIGHT", rightText, "RIGHT", gap, 0);
	end
end

local function GetAuctionValuePerItem(link)
	if not auxHistory or not auxInfo or not link then return nil; end

	local ok, itemID, suffixID = pcall(auxInfo.parse_link, link);
	if not ok or not itemID or itemID == 0 then return nil; end

	local itemKey = itemID..":"..(suffixID or 0);
	local ok2, value = pcall(auxHistory.value, itemKey);
	if not ok2 or not value or value == 0 then return nil; end

	return value;
end

local function Valuator_Update(tooltip, itemID, stackCount, link, suppressTotal)
	HideMoneyFrames();

	stackCount = stackCount or 1;

	local price;
	if itemID and ShaguTweaks and ShaguTweaks.SellValueDB then
		price = ShaguTweaks.SellValueDB[itemID];
		if price == 0 then price = nil; end
	end

	local auctionValue = GetAuctionValuePerItem(link);
	local addedLine = false;

	if stackCount > 1 then
		if price then
			AddMoneyLine(tooltip, "Value / item:", perItemMoneyFrame, price);
			addedLine = true;
		end
		if auctionValue then
			AddMoneyLine(tooltip, "Auction value / item:", auctionPerItemMoneyFrame, auctionValue);
			addedLine = true;
		end
	end

	-- suppressTotal: the native merchant tooltip already shows the stack's
	-- total, so skip ours there; the per-item and auction lines above/below still add new info.
	if price and not suppressTotal then
		AddMoneyLine(tooltip, "Total value:", totalMoneyFrame, price * stackCount);
		addedLine = true;
	end
	if auctionValue then
		AddMoneyLine(tooltip, "Auction value:", auctionTotalMoneyFrame, auctionValue * stackCount);
		addedLine = true;
	end

	if addedLine then
		tooltip:Show();
	end
end

hooksecurefunc(GameTooltip, "SetLootItem", function(tip, slot)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link = GetLootSlotLink(slot);
	local _, _, stackCount = GetLootSlotInfo(slot);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetLootRollItem", function(tip, rollID)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link = GetLootRollItemLink(rollID);
	local _, _, stackCount = GetLootRollItemInfo(rollID);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetBagItem", function(tip, bag, slot)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link = GetContainerItemLink(bag, slot);
	local _, stackCount = GetContainerItemInfo(bag, slot);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	local atMerchant = MerchantFrame and MerchantFrame:IsVisible();
	Valuator_Update(GameTooltip, itemID, stackCount, link, atMerchant);
end);

hooksecurefunc(GameTooltip, "SetInventoryItem", function(tip, unit, slot)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end
	if not (slot and slot > 19) then return; end -- slot > 19: bank slots, not equipped gear

	local link = GetInventoryItemLink(unit, slot);
	local stackCount = GetInventoryItemCount(unit, slot);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetQuestItem", function(tip, qtype, slot)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end
	if not (qtype == "reward" or qtype == "choice") then return; end

	local link = GetQuestItemLink(qtype, slot);
	local _, _, stackCount = GetQuestItemInfo(qtype, slot);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetQuestLogItem", function(tip, qtype, slot)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local stackCount;
	if qtype == "reward" then
		_, _, stackCount = GetQuestLogRewardInfo(slot);
	elseif qtype == "choice" then
		_, _, stackCount = GetQuestLogChoiceInfo(slot);
	else
		return;
	end

	local link = GetQuestLogItemLink(qtype, slot);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetInboxItem", function(tip, mailID, attachmentIndex)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink or not ShaguTweaks.GetItemLinkByName then return; end

	local itemName, _, stackCount = GetInboxItem(mailID);
	if not itemName then return; end
	local link = ShaguTweaks.GetItemLinkByName(itemName);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetTradePlayerItem", function(tip, index)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link = GetTradePlayerItemLink(index);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, nil, link);
end);

hooksecurefunc(GameTooltip, "SetTradeTargetItem", function(tip, index)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link = GetTradeTargetItemLink(index);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, nil, link);
end);

-- No suppressTotal here: that's about not duplicating the native sell
-- price for YOUR items while trading, which doesn't apply to the merchant's own stock.
hooksecurefunc(GameTooltip, "SetMerchantItem", function(tip, merchantIndex)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link = GetMerchantItemLink(merchantIndex);
	local _, _, _, stackCount = GetMerchantItemInfo(merchantIndex);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetCraftItem", function(tip, skill, slot)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link, stackCount;
	if slot then
		link = GetCraftReagentItemLink(skill, slot);
		local _, _, reagentCount = GetCraftReagentInfo(skill, slot);
		stackCount = reagentCount;
	else
		link = GetCraftItemLink(skill);
	end
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetCraftSpell", function(tip, slot)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link = GetCraftItemLink(slot);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, nil, link);
end);

hooksecurefunc(GameTooltip, "SetTradeSkillItem", function(tip, skillIndex, reagentIndex)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link, stackCount;
	if reagentIndex then
		link = GetTradeSkillReagentItemLink(skillIndex, reagentIndex);
		local _, _, reagentCount = GetTradeSkillReagentInfo(skillIndex, reagentIndex);
		stackCount = reagentCount;
	else
		link = GetTradeSkillItemLink(skillIndex);
	end
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetAuctionItem", function(tip, atype, index)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end

	local link = GetAuctionItemLink(atype, index);
	local _, _, stackCount = GetAuctionItemInfo(atype, index);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

hooksecurefunc(GameTooltip, "SetAuctionSellItem", function(tip)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink or not ShaguTweaks.GetItemLinkByName then return; end

	local itemName, _, stackCount = GetAuctionSellItemInfo();
	if not itemName then return; end
	local link = ShaguTweaks.GetItemLinkByName(itemName);
	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(GameTooltip, itemID, stackCount, link);
end);

-- Not a GameTooltip method: SetItemRef is the global chat-link handler,
-- targeting ItemRefTooltip. Reads itemID from the clicked link directly,
-- not from GameTooltip.itemLink (which could be stale/unrelated).
hooksecurefunc("SetItemRef", function(link, text, button)
	if not ShaguTweaks or not ShaguTweaks.GetItemIDFromLink then return; end
	if IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return; end

	local itemID = ShaguTweaks.GetItemIDFromLink(link);
	Valuator_Update(ItemRefTooltip, itemID, nil, link);
end);
