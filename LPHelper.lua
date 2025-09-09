--[=====[
[[SND Metadata]]
author: Invade1654
version: 1.0.0
description: |
  Auto Duty Helper - Automatically starts related functions when entering duties and stops them when leaving
  Features:
  - Auto start AutoDuty, RSR, BossModReborn when entering duties
  - Auto stop all functions when leaving duties
  - Auto leave duty if specified party member is not found for 10 seconds
  - Auto accept duty finder confirmation
configs:
  Enable Debug Messages:
    description: Enable debug message output
    default: false
  Auto Accept Quests:
    description: Automatically accept quest dialogues
    default: true
  Auto Repair Equipment:
    description: Automatically repair equipment after leaving duty
    default: true
  Party Member Name:
    description: Party member name to detect (leave duty if not found for 10s)
    default: ""
[[End Metadata]]
--]=====]

import("System.Numerics")

--[[
********************************************************************************
*                            User Settings                                     *
********************************************************************************
]]

local DebugConfig = Config.Get("Enable Debug Messages")
local AutoAcceptQuestsConfig = Config.Get("Auto Accept Quests")
local AutoRepairConfig = Config.Get("Auto Repair Equipment")
local PartyMemberConfig = Config.Get("Party Member Name")

local Run_script = true
local loopDelay = 1.0
local interval_rate = 0.2
local dutyStarted = false
local dutyCompleted = false
local dutyWiped = false

local partyMemberNotFoundTime = 0
local maxWaitTime = 10.0
local lastCheckTime = 0

--[[
********************************************************************************
*                            Trigger Event Functions                           *
********************************************************************************
]]

function OnDutyStarted()
    dutyStarted = true
    partyMemberNotFoundTime = 0
    lastCheckTime = os.clock()
    
    LogMessage("Event: Duty Started")
end

function OnDutyCompleted()
    dutyCompleted = true
    partyMemberNotFoundTime = 0
    
    LogMessage("Event: Duty Completed")
end

function OnDutyWiped()
    dutyWiped = true
    partyMemberNotFoundTime = 0
    
    LogMessage("Event: Duty Wiped")
end

--[[
********************************************************************************
*                            Helper Functions                                  *
********************************************************************************
]]

function LogMessage(message)
    if DebugConfig then
        Dalamud.Log("[Helper] " .. message)
        yield("/echo [Helper] " .. message)
    end
end

function sleep(seconds)
    yield('/wait ' .. tostring(seconds))
end

function GetPartyMember()
    if PartyMemberConfig == "" then
        return true
    end
    
    local partyMember = Entity.GetEntityByName(PartyMemberConfig)
    return partyMember ~= nil
end

function HasPlugin(name)
    for plugin in luanet.each(Svc.PluginInterface.InstalledPlugins) do
        if plugin.InternalName == name and plugin.IsLoaded then
            return true
        end
    end
    return false
end

--[[
********************************************************************************
*                            Main Functions                                    *
********************************************************************************
]]

function StartDuty()
    sleep(1)
    yield("/ad start")
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
    
    if AutoRepairConfig then
        Repair()
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
    
    if AutoRepairConfig then
        Repair()
    end
end

function CheckPartyMember()
    if PartyMemberConfig == "" then
        return
    end

    if not Player.IsInDuty then
        partyMemberNotFoundTime = 0
        return
    end
    
    local currentTime = os.clock()
    
    if GetPartyMember() then
        if partyMemberNotFoundTime > 0 then
            LogMessage("Party member found, resetting timer")
        end
        partyMemberNotFoundTime = 0
    else
        if partyMemberNotFoundTime == 0 then
            partyMemberNotFoundTime = currentTime
            LogMessage("Party member '" .. PartyMemberConfig .. "' not found, starting timer")
        else
            local elapsedTime = currentTime - partyMemberNotFoundTime
            if (currentTime - lastCheckTime) >= 5 then
                LogMessage("Party member not found for " .. math.floor(elapsedTime) .. " seconds")
                lastCheckTime = currentTime
            end
            
            if elapsedTime >= maxWaitTime then
                LogMessage("Party member not found for " .. maxWaitTime .. " seconds, leaving duty")
                WipeDuty()
                partyMemberNotFoundTime = 0
            end
        end
    end
end

function CheckDutyFinderConfirm()
    if AutoAcceptQuestsConfig && Addons.GetAddon("ContentsFinderConfirm").Ready then
        yield("/wait " .. interval_rate)
        yield("/callback ContentsFinderConfirm true 8")
    end
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
if not HasPlugin("TextAdvance") then
    yield("/echo [Helper] Requires TextAdvance plugin.")
end
if not HasPlugin("vnavmesh") then
    yield("/echo [Helper] Requires vnavmesh plugin.")
end

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
    
    CheckPartyMember()
    CheckDutyFinderConfirm()

    sleep(loopDelay)
end