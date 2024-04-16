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
local shortPeriod = 333
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
    print('Lua script started!')
    reactorLua.startTimer()
    reactorLua.startShortTimer()
end)

-- Called at the end of the round (CLEANUP)
Hook.Add('roundEnd', 'roundStartEndTime', function(instance, ptable)
    isEnded = true
    Hook.Remove('think', 'thinkTimeLoop')
    Hook.Remove('think', 'smallThinkTimeLoop')
end)

-- Main loop to fire functions related to active fuel rods
reactorLua.invisibleExplosion = function()
    for key,fuelRodItem in pairs(Item.ItemList) do
        if fuelRodItem.HasTag('activefuelrod') then
            local itemPosition = fuelRodItem.WorldPosition
            -- fuel rod in crate or outpost reactor change active tag
            if fuelRodItem.ContainerIdentifier == "fuelrodcrate" or 
               fuelRodItem.ContainerIdentifier == "outpostreactor"  then
                fuelRodItem.ReplaceTag('activefuelrod', 'containedactivefuelrod')
            end
            -- Active fuel rod not in container
            if fuelRodItem.ContainerIdentifier ~= "reactor1" 
                and fuelRodItem.ContainerIdentifier ~= "outpostreactor"
                and not fuelRodItem.HasTag('deepdiving') 
                and not fuelRodItem.HasTag('containradiation')  then
                -- spawn random fire 1 in 20
                if(randomfunction == true) and fuelRodItem.ContainerIdentifier ~= "fuelrodtongs" then
                    Entity.Spawner.AddItemToSpawnQueue(twisted, itemPosition, nil, nil, function(item) end)
                    randomfunction = false
                end
                for key, playerCharacter in pairs(Character.CharacterList) do
                    -- if player is holding fuel rod add burn damage
                    if playerCharacter.HasEquippedItem('activefuelrod', true) then 
                        reactorLua.applyBurnStrength(fuelRodItem.Name, playerCharacter)
                    end
                    -- check distance to fuel rod, if within range apply afflicitions
                    local distance = Vector2.Distance(itemPosition, playerCharacter.WorldPosition)
                    local maxDistance = 1000
                    if distance < maxDistance then
                        if Character.IsTargetVisible(fuelRodItem, playerCharacter, false, false) then
                            reactorLua.applyAfflictionStrengths(fuelRodItem.Name, playerCharacter, distance ,maxDistance, false, 100)
                        end
                    end
                end
            end
            -- fuel rod in reactor and its condition is less than 75%
            if fuelRodItem.ContainerIdentifier == "reactor1" and
                fuelRodItem.Container.Condition <= 75 then 
                for key, playerCharacter in pairs(Character.CharacterList) do
                    -- check distance to fuel rod, if within range apply afflicitions
                    local distance = Vector2.Distance(itemPosition, playerCharacter.WorldPosition)
                    local maxDistance = 1000
                    if distance < maxDistance then
                        if Character.IsTargetVisible(fuelRodItem.Container, playerCharacter, false, false) then
                            reactorLua.applyAfflictionStrengths(fuelRodItem.Name, playerCharacter, distance ,maxDistance, true, fuelRodItem.Container.Condition)
                        end
                    end
                end
            end 
        end
        -- fuel rod not in crate 
        if fuelRodItem.HasTag('containedactivefuelrod') and
            fuelRodItem.ContainerIdentifier ~= "fuelrodcrate" and
            fuelRodItem.ContainerIdentifier ~= "outpostreactor" then
                fuelRodItem.ReplaceTag('containedactivefuelrod', 'activefuelrod')
        end
    end
end

-- applied burn to the characters hand based on fuel rode type 
reactorLua.applyBurnStrength = function(fuelRodType, playerCharacter)
    local limb = playerCharacter.AnimController.GetLimb(LimbType.LeftHand)
    local baseBurnStrength = 1.5
    if fuelRodType == "Thoruium Fuel Rod" then
        baseBurnStrength = 2.5
    elseif fuelRodType == "Fulgarium Fuel Rod" then 
        baseBurnStrength = 3.5
    elseif fuelRodType == "Volatile Fulgarium Fuel Rod" then
        baseBurnStrength = 4
    end
    local calculatedBurnStrength = reactorLua.calculateAfflictionStrength(baseBurnStrength,0,1000)
    playerCharacter.CharacterHealth.ApplyAffliction(limb, burnPrefab.Instantiate(calculatedBurnStrength))
end

-- applies the affliction for the diffrent fuel rods
reactorLua.applyAfflictionStrengths =  function(fuelRodType, playerCharacter, distance, maxDistance, isContained, reactorCondition)
    -- Regular and Thorium
    local radiationStrength = 1.5
    local radiationSoundsStrength = 2.5
    local overheatingStrength = 1.02
    local contaminatedStrength = 1.5
    local multiply = 1
    -- if the fuel rods are within a reactor
    if(isContained == false) then
        -- Fulgurium
        if rodType == "Fulgarium Fuel Rod" then 
            radiationStrength = 3.75
            radiationSoundsStrength = 3
            overheatingStrength = 1.2
            contaminatedStrength = 3.75
        -- Volitile fulgurium
        elseif rodType == "Volatile Fulgarium Fuel Rod" then
            radiationStrength = 5.4
            radiationSoundsStrength = 4
            overheatingStrength = 1.44
            contaminatedStrength = 5.4
        end
    else 
    -- if fuel rods are not in a reactor and reactor is broken
        if(reactorCondition <= 50)then -- medium
            multiply = 2
        elseif(reactorCondition <=25) then -- large
            multiply = 3
        end 
        -- Regular and Thorium
        radiationStrength = 0.15 
        radiationSoundsStrength = 0.9
        overheatingStrength = 0.06
        contaminatedStrength = 0.15
        -- Fulgurium
        if rodType == "Fulgarium Fuel Rod" then 
            radiationStrength = 0.225
            radiationSoundsStrength = 1.9
            overheatingStrength = 0.15
            contaminatedStrength = 0.225
        -- Volitile fulgurium
        elseif rodType == "Volatile Fulgarium Fuel Rod" then
            radiationStrength = 0.3
            radiationSoundsStrength = 1.9
            overheatingStrength = 0.21
            contaminatedStrength = 0.3
        end
    end
    -- add afflictions as damage so resistances apply 
    local limb = playerCharacter.AnimController.GetLimb(LimbType.Torso)
    -- Radiation affliction
    local radiationResult = limb.AddDamage(limb.SimPosition, 
    {radiationsickness.Instantiate(
        reactorLua.calculateAfflictionStrength(radiationStrength * multiply,distance,maxDistance)
    )}, false, 1, 0.2, nil)
    playerCharacter.CharacterHealth.ApplyDamage(limb, radiationResult, true)

    -- Overheating affliction
    local overheatingResult = limb.AddDamage(limb.SimPosition, 
    {overheating.Instantiate(
        reactorLua.calculateAfflictionStrength(overheatingStrength * multiply,distance,maxDistance)
    )}, false, 1, 0.2, nil)
    playerCharacter.CharacterHealth.ApplyDamage(limb, overheatingResult, true)

    -- Radiation Sound Affliction
    local radiationsoundResult = limb.AddDamage(limb.SimPosition, 
    {radiationsounds.Instantiate(
        reactorLua.calculateAfflictionStrength(radiationSoundsStrength * multiply,distance,maxDistance)
    )}, false, 1, 0.2, nil)
    playerCharacter.CharacterHealth.ApplyDamage(limb, radiationsoundResult, true)

    -- Contaminated Affliction
    local contaminatedResult = limb.AddDamage(limb.SimPosition, 
    {contaminated.Instantiate(
        reactorLua.calculateAfflictionStrength(contaminatedStrength * multiply,distance,maxDistance)
    )}, false, 1, 0.2, nil)
    playerCharacter.CharacterHealth.ApplyDamage(limb, contaminatedResult, true)
end

-- calculates the affliction strength based on distance from target
reactorLua.calculateAfflictionStrength = function(afflictionStrength, distance, range)
    local distanceStrength 
    if distance == 0 then
        distanceStrength = 1
    else 
        distanceStrength =  1 - (distance / range)
    end
    local afflictionStrength = afflictionStrength
    return reactorLua.mathsRound(distanceStrength * afflictionStrength, 1)
end

-- Random chance generator
reactorLua.randomFireChance = function()
    local randomAmount = math.random(1,20);
    if randomAmount == 18 then 
        return true 
        else return false 
    end
end

-- decimal point rounding, where x is the number and n is the ammount of decimal places
reactorLua.mathsRound = function(x, n)
    n = math.pow(10, n or 0)
    x = x * n
    if x >= 0 then x = math.floor(x + 0.5) else x = math.ceil(x - 0.5) end
    return x / n
end
