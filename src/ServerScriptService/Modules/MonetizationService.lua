--[[
	MonetizationService.lua
	ServerScriptService.Modules.MonetizationService
	
	Handles Roblox Developer Products (Robux purchases)
	Products: 2x XP (15/30/60m) and 2x BrainCells (15/30/60m).
--]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function getDataManager()
	if _G.DataManager then return _G.DataManager end
	return require(ServerScriptService:WaitForChild("DataManager"))
end

local MonetizationService = {}

local PRODUCT_MAP = {
	[3709382572] = { Type = "BrainCells", Duration = 3600 }, -- 60 Min
	[3709382531] = { Type = "BrainCells", Duration = 1800 }, -- 30 Min
	[3709382478] = { Type = "BrainCells", Duration = 900 },  -- 15 Min
	[3709382324] = { Type = "EXP", Duration = 3600 }, -- 60 Min
	[3709382241] = { Type = "EXP", Duration = 1800 }, -- 30 Min
	[3709381787] = { Type = "EXP", Duration = 900 },  -- 15 Min
}

local function processReceipt(receiptInfo)
	local playerId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local player = Players:GetPlayerByUserId(playerId)
	
	if not player then
		-- Player left the game, do not grant yet
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	local DM = getDataManager()
	local data = DM.GetPlayerData(player)
	
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	local productInfo = PRODUCT_MAP[productId]
	if productInfo then
		local now = os.time()
		
		-- Initialize Boosts if missing
		data.Boosts = data.Boosts or { ExpBoostExpire = 0, BrainCellsBoostExpire = 0 }
		
		if productInfo.Type == "EXP" then
			if data.Boosts.ExpBoostExpire < now then
				data.Boosts.ExpBoostExpire = now + productInfo.Duration
			else
				data.Boosts.ExpBoostExpire = data.Boosts.ExpBoostExpire + productInfo.Duration
			end
			print("[Monetization] Granted 2x EXP Boost to " .. player.Name)
		elseif productInfo.Type == "BrainCells" then
			if data.Boosts.BrainCellsBoostExpire < now then
				data.Boosts.BrainCellsBoostExpire = now + productInfo.Duration
			else
				data.Boosts.BrainCellsBoostExpire = data.Boosts.BrainCellsBoostExpire + productInfo.Duration
			end
			print("[Monetization] Granted 2x BrainCells Boost to " .. player.Name)
		end
		
		-- Notify client
		local ev = ReplicatedStorage:FindFirstChild("Events")
		if ev and ev:FindFirstChild("BoostStateUpdate") then
			ev.BoostStateUpdate:FireClient(player, data.Boosts)
		end
		
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
end

-- Create events
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if eventsFolder and not eventsFolder:FindFirstChild("BoostStateUpdate") then
	local be = Instance.new("RemoteEvent")
	be.Name = "BoostStateUpdate"
	be.Parent = eventsFolder
end

_G.MonetizationService = MonetizationService
return MonetizationService
