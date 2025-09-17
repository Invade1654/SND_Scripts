--[=====[
[[SND Metadata]]
author: Invade1654
version: 1.0.1
description: |
  Phantom Trade NPC Helper - Automatically navigates to and interacts with PW Trade NPC
configs:
  Enable Debug Messages:
    description: Enable debug message output
    default: false
  Auto Repair Equipment:
    description: Automatically repair equipment after leaving duty
    default: true
  Duty IDs:
    description: List of duty IDs to run.
    default: 1266
  Exchange Item:
    description: |
      Select which item to purchase.
    default: "Waxing Arcanite"
    is_choice: true
    choices: ["Arcanit", "Waxing Arcanite"]
[[End Metadata]]
--]=====]

import("System.Numerics")

local DebugConfig = Config.Get("Enable Debug Messages")
local AutoRepairConfig = Config.Get("Auto Repair Equipment")
local DutyID = Config.Get("Duty IDs")
local ExchangeItem = Config.Get("Exchange Item")
local itemChoices = {"Arcanit", "Waxing Arcanite"}
local ExchangeIndex = 0
for i, item in ipairs(itemChoices) do
    if item == ExchangeItem then
        ExchangeIndex = i - 1
        break
    end
end

local Run_script = true
local loopDelay = 1.0
local interval_rate = 0.2
local dutyCount = 0
local consecutiveWipes = 0
local dutyStarted = false
local dutyCompleted = false
local dutyWiped = false

function OnDutyStarted()
    dutyStarted = true
    dutyCount = dutyCount + 1
end

function OnDutyCompleted()
    dutyCompleted = true
    consecutiveWipes = 0
end

function OnDutyWiped()
    dutyWiped = true
    consecutiveWipes = consecutiveWipes + 1
end

function LogMessage(message)
    if DebugConfig then
        Dalamud.Log("[Helper] " .. message)
        yield("/echo [Helper] " .. message)
    end
end

function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end

function StartDuty()
    sleep(1)
    yield("/rsr Auto")
    yield("/bmrai on")
    LogMessage("Duty started")
end

function StopDuty()
    sleep(1)
    yield("/ad stop")
    yield("/bmrai off")
    yield("/rsr Off")
    yield("/pdfleave")
    LogMessage("Duty stopped and left duty")
    
    repeat
        yield("/wait " .. interval_rate)
    until not Player.IsInDuty and not Player.IsBusy
    
    if AutoRepairConfig and dutyCount >= 5 then
        Repair()
        dutyCount = 0
    end
    
    sleep(1)
    
    local HeliometryCount = Inventory.GetItemCount(47)
    if HeliometryCount > 500 then
        Exchange()
    else
        RunAD()
    end
end

function WipeDuty()
    yield("/ad stop")
    yield("/bmrai off")
    yield("/rsr Off")
    yield("/pdfleave")
    LogMessage("Duty stopped due to wipe and left duty")
    
    repeat
        yield("/wait " .. interval_rate)
    until not Player.IsInDuty and not Player.IsBusy
    
    if AutoRepairConfig and dutyCount >= 5 then
        Repair()
        dutyCount = 0
    end
    
    sleep(1)
    
    if consecutiveWipes >= 5 then
        LogMessage("Reached maximum consecutive wipes (5), stopping automation")
        yield("/snd pause")
        return
    end
    
    local HeliometryCount = Inventory.GetItemCount(47)
    LogMessage("Current Heliometry Tomestones: " .. HeliometryCount)
    if HeliometryCount > 500 then
        Exchange()
    else
        RunAD()
    end
end

function GetENpcResidentName(dataId)
    local sheet = Excel.GetSheet("ENpcResident")
    if not sheet then return nil, "ENpcResident sheet not available" end

    local row = sheet:GetRow(dataId)
    if not row then return nil, "no row for id "..tostring(dataId) end

    local name = row.Singular or row.Name
    return name, "ENpcResident"
end

function DistanceBetweenPositions(pos1, pos2)
    return Vector3.Distance(pos1, pos2)
end

function RunAD()
    IPC.AutoDuty.Run(DutyID, 1, true)
end

function Exchange()
    if Svc.ClientState.TerritoryType == Phantom then
        while Svc.Condition[CharacterCondition.betweenAreas] or Svc.Condition[CharacterCondition.casting] do
            sleep(.5)
        end
        IPC.vnavmesh.PathfindAndMoveTo(PWTradeNPC.position, false)
        LogMessage("Moving to PW Trade NPC.")
        sleep(1)
        while IPC.vnavmesh.PathfindInProgress() or IPC.vnavmesh.IsRunning() do
            sleep(.02)
            curPos = Svc.ClientState.LocalPlayer.Position
            if DistanceBetweenPositions(curPos, PWTradeNPC.position) < 5 then
                LogMessage("Reached target NPC. Stopping vnavmesh.")
                IPC.vnavmesh.Stop()
            end
        end
    end

    local e = Entity.GetEntityByName(PWTradeNPC.name)
    if e then
        e:SetAsTarget()
    end

    if Entity.Target and Entity.Target.Name == PWTradeNPC.name then
        Entity.Target:Interact()
    end

    LogMessage("Attempting to purchase " .. ExchangeItem)
    repeat
        yield("/wait " .. interval_rate)
    until Addons.GetAddon("ShopExchangeCurrency").Exists

    yield("/callback ShopExchangeCurrency true 0 ".. ExchangeIndex .. " 1")
    repeat
        yield("/wait " .. interval_rate)
    until Addons.GetAddon("SelectYesno").Ready
    yield("/callback SelectYesno true 1")
    yield("/wait 0.5")
    yield("/callback ShopExchangeCurrency true -1") 
    LogMessage("Purchase of " .. ExchangeItem .. " completed")
    
    sleep(1)
    RunAD()
end

function Repair()
    LogMessage("Attempting to repair equipment")
    Actions.ExecuteGeneralAction(6)
    repeat
        yield("/wait " .. interval_rate)
    until Addons.GetAddon("Repair").Ready

    yield("/pcall Repair true 0")
    repeat
        yield("/wait " .. interval_rate)
    until Addons.GetAddon("SelectYesno").Ready

    yield("/callback SelectYesno true 0")
    repeat
        yield("/wait " .. interval_rate)
    until not Svc.Condition[39]

    Actions.ExecuteGeneralAction(6)
    LogMessage("Equipment repair completed")
end

CharacterCondition = {
    normalConditions                   = 1,
    mounted                            = 4,
    crafting                           = 5,
    gathering                          = 6,
    casting                            = 27,
    occupiedInQuestEvent               = 32,
    occupied33                         = 33,
    occupiedMateriaExtractionAndRepair = 39,
    executingCraftingAction            = 40,
    preparingToCraft                   = 41,
    executingGatheringAction           = 42,
    betweenAreas                       = 45,
    jumping48                          = 48,
    occupiedSummoningBell              = 50,
    mounting57                         = 57,
    unknown85                          = 85,
}

Phantom = 1278
PWTradeNPC = {name = GetENpcResidentName(1053904), position = Vector3(40.818, 0, 20.828)}

--[[
********************************************************************************
*                          Start of script loop                                *
********************************************************************************
]]

if not HasPlugin("AutoDuty") then
    yield("/echo [Helper] Requires AutoDuty plugin.")
end
if not HasPlugin("BossModReborn") then
    yield("/echo [Helper] Requires BossMod Reborn plugin.")
end
if not HasPlugin("RotationSolver") then
    yield("/echo [Helper] Requires Rotation Solver Reborn plugin.")
end
if not HasPlugin("PandorasBox") then
    yield("/echo [Helper] Requires Pandora's Box plugin.")
end
if not HasPlugin("vnavmesh") then
    yield("/echo [Helper] Requires vnavmesh plugin.")
end

Repair()
RunAD()

while Run_script do
    if dutyStarted then
        dutyStarted = false
        StartDuty()
    end
    
    if dutyCompleted then
        dutyCompleted = false
        StopDuty()
    end
    
    if dutyWiped then
        dutyWiped = false
        WipeDuty()
    end
    
    sleep(loopDelay)
end