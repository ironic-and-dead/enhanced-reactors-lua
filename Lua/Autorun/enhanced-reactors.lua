local reactorLua = {} -- reactor lua

math.randomseed(os.time())

local isEnded = false -- end of round

if CLIENT and Game.IsMultiplayer then return end 

-- Prefab Instantiate
local twisted = ItemPrefab.GetItemPrefab("effect_firestarter")
local burnPrefab = AfflictionPrefab.Prefabs["burn"]
local radiationsickness = AfflictionPrefab.Prefabs["radiationsickness"]
local contaminated = AfflictionPrefab.Prefabs["contaminated"]
local radiationsounds = AfflictionPrefab.Prefabs["radiationsounds"]
local overheating = AfflictionPrefab.Prefabs["overheating"]

-- Time loop called every 1 second for recording game time only during a round
local period = 1000
local randomfunction = false
reactorLua.startTimer = function()
    Hook.Add('think', 'thinkTimeLoop', function(instance, ptable)
        if not isEnded then
            Timer.Wait(reactorLua.startTimer, period)
        end
        randomfunction = reactorLua.randomFireChance()
        Hook.Remove('think', 'thinkTimeLoop')
    end)
end

-- Short time loop called every 1/3 of a second 
local shortPeriod = 3000
reactorLua.startShortTimer = function()
    Hook.Add('think', 'smallThinkTimeLoop', function(instance, ptable)
        if not isEnded then
            Timer.Wait(reactorLua.startShortTimer, shortPeriod)
        end
        reactorLua.invisibleExplosion()
        Hook.Remove('think', 'smallThinkTimeLoop')
    end)
end

-- Called at the start of the round 
Hook.Add('roundStart', 'roundStartTime', function(instance, ptable)
    isEnded = false
    reactorLua.startTimer()
    reactorLua.startShortTimer()
end)

-- Called at the end of the round (CLEANUP)
Hook.Add('roundEnd', 'roundStartEndTime', function(instance, ptable)
    isEnded = true
    Hook.Remove('think', 'thinkTimeLoop')
    Hook.Remove('think', 'smallThinkTimeLoop')
end)

local supportedReactors = {
    "reactor1",
    "outpostreactor",
    "ekdockyard_reactor_mini",
    "ekdockyard_reactor_small",
    "ekdockyard_reactorslow_small"
}

-- Define valid exemptions for container identifiers
local shieldedContainer = {
    "fuelrodcrate", 
    "clownexosuit", 
    "exosuit"
}

-- Define max distance for afflictions 1000 = 1m
local maxDistance = 1000

-- Main loop to fire functions related to active fuel rods
reactorLua.invisibleExplosion = function()
    for _,fuelRodItem in pairs(Item.ItemList) do
        if fuelRodItem.HasTag('reactorfuel') 
        and fuelRodItem.HasTag('activefuelrod') then
            local itemPosition = fuelRodItem.WorldPosition
            -- Check if the fuel rod is in a shielded container
            if not reactorLua.isInValidContainer(fuelRodItem.ContainerIdentifier, shieldedContainer) then
                -- Active fuel rod is not in not in a supported reactor
                if not reactorLua.isInValidContainer(fuelRodItem.ContainerIdentifier, supportedReactors)
                    and not fuelRodItem.HasTag('deepdiving') 
                    and not fuelRodItem.HasTag('containradiation')  then
                    -- Spawn random fire 1 in 20
                    if randomfunction and fuelRodItem.ContainerIdentifier ~= "fuelrodtongs" then
                        Entity.Spawner.AddItemToSpawnQueue(twisted, itemPosition, nil, nil, function(item) end)
                        randomfunction = false
                    end
                    for _, playerCharacter in pairs(Character.CharacterList) do
                        -- If player is holding fuel rod add burn damage
                        if playerCharacter.HasEquippedItem('activefuelrod', true) then 
                            reactorLua.applyBurnStrength(fuelRodItem.Name, playerCharacter)
                        end
                        -- Check distance to fuel rod, if within range apply afflicitions
                        local distance = Vector2.Distance(itemPosition, playerCharacter.WorldPosition)
                        if distance < maxDistance then
                            if Character.IsTargetVisible(fuelRodItem, playerCharacter, false, false) then
                                reactorLua.applyAfflictionStrengths(fuelRodItem.Name, playerCharacter, distance ,maxDistance, false, 100)
                            end
                        end
                    end
                end
                -- Fuel rod in reactor and its condition is less than 75%
                if reactorLua.isInValidContainer(fuelRodItem.ContainerIdentifier, supportedReactors) and
                    fuelRodItem.Container.Condition <= 75 then 
                    for _, playerCharacter in pairs(Character.CharacterList) do
                        -- Check distance to fuel rod, if within range apply afflicitions
                        local distance = Vector2.Distance(itemPosition, playerCharacter.WorldPosition)
                        if distance < maxDistance then
                            if Character.IsTargetVisible(fuelRodItem.Container, playerCharacter, false, false) then
                                reactorLua.applyAfflictionStrengths(fuelRodItem.Name, playerCharacter, distance ,maxDistance, true, fuelRodItem.Container.Condition)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Check if the target is in a in a valid container
reactorLua.isInValidContainer = function(containerId, containerArray)
    for _, validId in ipairs(containerArray) do
        if containerId == validId then
            return true
        end
    end
    return false
end

-- applied burn to the characters hand based on fuel rode type 
reactorLua.applyBurnStrength = function(fuelRodType, playerCharacter)
    local limb = playerCharacter.AnimController.GetLimb(LimbType.LeftHand)
    local burnStrengthByFuelRod = {
        ["Thoruium Fuel Rod"] = 2.5,
        ["Fulgarium Fuel Rod"] = 3.5,
        ["Volatile Fulgarium Fuel Rod"] = 4
    }
    local baseBurnStrength = burnStrengthByFuelRod[fuelRodType] or 1.5
    local calculatedBurnStrength = reactorLua.calculateAfflictionStrength(baseBurnStrength, 0, 1000)
    playerCharacter.CharacterHealth.ApplyAffliction(limb, burnPrefab.Instantiate(calculatedBurnStrength))
end
-- applies the affliction for the diffrent fuel rods
reactorLua.applyAfflictionStrengths = function(fuelRodType, playerCharacter, distance, maxDistance, isContained, reactorCondition)
    local radiationStrength, radiationSoundsStrength, overheatingStrength, contaminatedStrength
    local multiply = 1
    local limb = playerCharacter.AnimController.GetLimb(LimbType.Torso)

    -- Default Affliction values for Regular and Thorium fuel rods
    local defaultAfflictions = {
        radiationStrength = 1.5,
        radiationSoundsStrength = 2.5,
        overheatingStrength = 1.02,
        contaminatedStrength = 1.5
    }

    -- Default Affliction values for broken reactor
    local reactorBrokenAfflictions = {
        radiationStrength = 0.15,
        radiationSoundsStrength = 0.9,
        overheatingStrength = 0.06,
        contaminatedStrength = 0.15
    }

    -- Afflictions for Fulgarium and Volatile Fulgarium fuel rods
    local fulguriumAfflictions = {
        ["Fulgarium Fuel Rod"] = {3.75, 3, 1.2, 3.75},
        ["Volatile Fulgarium Fuel Rod"] = {5.4, 4, 1.44, 5.4}
    }

    -- Afflictions for broken reactor with Fulgarium and Volatile Fulgarium fuel rods
    local reactorBrokenFulguriumAfflictions = {
        ["Fulgarium Fuel Rod"] = {0.225, 1.9, 0.15, 0.225},
        ["Volatile Fulgarium Fuel Rod"] = {0.3, 1.9, 0.21, 0.3}
    }

    -- Set affliction strengths based on containment status
    if not isContained then
        -- Use fulgurium or default values
        radiationStrength, radiationSoundsStrength, overheatingStrength, contaminatedStrength = 
            table.unpack(fulguriumAfflictions[fuelRodType] or {
                defaultAfflictions.radiationStrength, 
                defaultAfflictions.radiationSoundsStrength, 
                defaultAfflictions.overheatingStrength, 
                defaultAfflictions.contaminatedStrength
            })
    else
        -- Apply reactor condition multiplier
        if reactorCondition <= 50 then
            multiply = reactorCondition <= 25 and 3 or 2
        end
        -- Use broken reactor fulgurium or default values
        radiationStrength, radiationSoundsStrength, overheatingStrength, contaminatedStrength = 
            table.unpack(reactorBrokenFulguriumAfflictions[fuelRodType] or {
                reactorBrokenAfflictions.radiationStrength, 
                reactorBrokenAfflictions.radiationSoundsStrength, 
                reactorBrokenAfflictions.overheatingStrength, 
                reactorBrokenAfflictions.contaminatedStrength
            })
    end

    -- Helper function to apply afflictions
    local function applyAffliction(afflictionPrefab, strength)
        local result = limb.AddDamage(
            limb.SimPosition, 
            {afflictionPrefab.Instantiate(reactorLua.calculateAfflictionStrength(strength * multiply, distance, maxDistance))}, 
            false, 1, 0.2, nil
        )
        playerCharacter.CharacterHealth.ApplyDamage(limb, result, true)
    end

    -- Apply the four afflictions
    applyAffliction(radiationsickness, radiationStrength)
    applyAffliction(overheating, overheatingStrength)
    applyAffliction(radiationsounds, radiationSoundsStrength)
    applyAffliction(contaminated, contaminatedStrength)
end

-- calculates the affliction strength based on distance from target
reactorLua.calculateAfflictionStrength = function(baseStrength, distance, range)
    local distanceStrength = (distance == 0) and 
    1 or 
    (1 - (distance / range))
    return reactorLua.mathsRound(distanceStrength * baseStrength, 1)
end

-- Random chance generator (1 in 20 chance)
reactorLua.randomFireChance = function()
    return math.random(1, 20) == 18
end

-- decimal point rounding, where x is the number and n is the ammount of decimal places
reactorLua.mathsRound = function(x, n)
    n = math.pow(10, n or 0)
    x = x * n
    if x >= 0 then x = math.floor(x + 0.5) else x = math.ceil(x - 0.5) end
    return x / n
end
