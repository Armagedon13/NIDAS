-- Import section

local component = require("component")
local serialization = require("serialization")

local findMatchingPattern = require("modules.infusion.find-matching-pattern")
local checkForMissingEssentia = require("modules.infusion.check-for-missing-essentia")
local getRequiredEssentia = require("modules.infusion.get-required-essentia")
local getFreeCPU = require("modules.infusion.get-free-cpu")

--

local namespace = {
    recipes = {}
}
local infusion = {}

function namespace.save()
    local file = io.open("/home/NIDAS/settings/known-recipes", "w")
    file:write(serialization.serialize(namespace.recipes))
    file:close()
end

local function load()
    local file = io.open("/home/NIDAS/settings/known-recipes", "r")
    if file then
        namespace.recipes = serialization.unserialize(file:read("*a")) or {}
        file:close()
    end
end
load()

-- -- Sets up configuration menu for the infusion
-- local configure = require("modules.infusion.configure")(namespace)
-- function infusion.configure(x, y, _, _, _, page)
--     return configure(x, y, page)
-- end

function infusion.configure()
    return {}
end

-- --Sets up the event listeners for the infusion
-- require("modules.infusion.event-listen")(namespace)

-- Finds any pedestal
local transposer
pcall(
    function()
        transposer = component.transposer
        for i = 0, 5 do
            local inventoryName = transposer.getInventoryName(i)
            if inventoryName == "tile.blockStoneDevice" then
                infusion.centerPedestalNumber = i
            elseif inventoryName then
                infusion.outputSlotNumber = i
            end
        end
        return
    end
)

local request
local hasWarnedAboutMissingEssentia = false
function infusion.update()
    if (not request or request.isDone() or request.isCanceled()) and getFreeCPU(component.me_interface.address) then
        local itemsInChest = {}
        -- Adds all items in the chest connected through the storage bus to the list
        for item in component.me_interface.allItems() do
            if item.size > 0 then
                table.insert(itemsInChest, item)
            end
        end

        local pattern = findMatchingPattern(itemsInChest)
        if pattern then
            local label
            for _, output in ipairs(pattern.outputs) do
                if output.name then
                    label = output.name
                    break
                end
            end

            local missingEssentia = checkForMissingEssentia(namespace.recipes[label])
            if not namespace.recipes[label] or not missingEssentia then
                local craftable = component.me_interface.getCraftables({label = label})[1]
                print("Crafting " .. label)
                request = craftable.request()

                local isCancelled, reason = request.isCanceled()
                if isCancelled then
                    print("Request cancelled. Please clean up your altar if that is the case")
                    print(reason)
                    print()
                    return
                end

                -- TODO: event-based, non-blocking code

                -- Waits for an item to be in the center pedestal
                local itemLabel
                local item
                while not itemLabel do
                    item = transposer.getStackInSlot(infusion.centerPedestalNumber, 1)
                    itemLabel = item and item.label
                    os.sleep(0)
                end

                -- Starts the infusion
                component.redstone.setOutput({15, 15, 15, 15, 15, 15})
                component.redstone.setOutput({0, 0, 0, 0, 0, 0})

                -- Checks for the required essentia on the first time the recipe is crafted
                if not namespace.recipes[label] and not request.isCanceled() then
                    local inputs = {}
                    for _, input in ipairs(pattern and pattern.inputs or {}) do
                        -- Searches for input items in the pattern
                        if input.name then
                            table.insert(inputs, input.name)
                        end
                    end

                    namespace.recipes[label] = {
                        inputs = inputs,
                        essentia = getRequiredEssentia(component.blockstonedevice_2.address)
                    }
                    namespace.save()

                    missingEssentia = checkForMissingEssentia(namespace.recipes[label])
                    if missingEssentia then
                        print("WARNING, NOT ENOUGH ESSENTIA!")
                        print("Missing:")
                        for essentia, amount in pairs(namespace.recipes[label]) do
                            print("  " .. essentia .. ": " .. amount)
                        end
                        print()
                        while transposer.getStackInSlot(infusion.centerPedestalNumber, 1) do
                            transposer.transferItem(infusion.centerPedestalNumber, infusion.outputSlotNumber)
                            os.sleep(0)
                        end
                        print("Removed " .. itemLabel .. " from the center pedestal. Sorry for the flux.")
                        print("Please cancel the craft manually.")
                        print()
                        return
                    end
                end

                -- TODO: event-based non-blocking code
                -- Waits for the item in the center pedestal to change
                while itemLabel == item.label do
                    item = transposer.getStackInSlot(infusion.centerPedestalNumber, 1) or {}
                    os.sleep(0)
                end

                -- Removes all items from the center pedestal
                while transposer.getStackInSlot(infusion.centerPedestalNumber, 1) do
                    transposer.transferItem(infusion.centerPedestalNumber, infusion.outputSlotNumber)
                    os.sleep(0)
                end

                if request.isDone() then
                    print("Done")
                else
                    print("Oh, oh...")
                    print("Removed " .. itemLabel .. " from the pedestal.")
                    print("But the craft for " .. label .. " is still going in the ME system.")
                    print("Please cancel the craft manually.")
                    print("Are you using a dummy item?")
                end
                print()
                hasWarnedAboutMissingEssentia = false
            else
                if not hasWarnedAboutMissingEssentia then
                    print("Not enough essentia to craft " .. label)
                    print("Missing:")
                    for essentia, amount in pairs(missingEssentia) do
                        print("  " .. essentia .. ": " .. amount)
                    end
                    print()
                    hasWarnedAboutMissingEssentia = true
                end
            end
        else
            hasWarnedAboutMissingEssentia = false
        end
    end
end

return infusion
