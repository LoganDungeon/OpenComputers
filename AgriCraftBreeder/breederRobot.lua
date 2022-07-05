local component = require("component")
local event = require("event")
local robot = require("robot")
local sides = require("sides")
local term = require("term")

local modem = component.proxy(component.list("modem")())
local inv_contr = component.proxy(component.list("inventory_controller")())

local robot_port = 5336
local computer_port = 5337

local lastCmd = ""

modem.open(robot_port)


-- attempt to drop items into the inventory at side
local function dropItem(side, fromSlot, stackSize)
  robot.select(fromSlot)
  local inventorySize = inv_contr.getInventorySize(side)
  local index = 1
  while stackSize ~= 0 and index <= inventorySize do
    local success = inv_contr.dropIntoSlot(side, index, 1)
    if success == true then
      stackSize = stackSize - 1
    else
      index = index + 1
    end
  end
end

-- attempt to dump stacks of items into the inventory at side
local function dumpItem(side, fromSlot)
  robot.select(fromSlot)
  local inventorySize = inv_contr.getInventorySize(side)
  local index = 1
  while inv_contr.getStackInInternalSlot(fromSlot) ~= nil and index <= inventorySize do
    inv_contr.dropIntoSlot(side, index, 64)
    index = index + 1
  end
end

-- harvests all 4 spots
local function harvest()
  -- move forward and harvest down
  for i=0, 1, 1 do
    robot.forward()
    robot.swingDown()
  end
  for i=0, 2, 1 do
    robot.turnLeft()
    robot.forward()
    robot.swingDown()
  end
  robot.turnRight()
  robot.forward()
  robot.turnRight()
  robot.turnRight()
end

-- drops all cropsticks remaining in inventory into the cropstick drawer
local function dropCropSticksOff()
  robot.forward()
  robot.forward()
  robot.turnRight()
  -- select the itemstack with the crop sticks
  for i=1, 16, 1 do
    local item = inv_contr.getStackInInternalSlot(i)
    -- check if we have an item
    if item == nil then
      goto continue
    end

    if item.name == "agricraft:crop_sticks" then
      -- drop them off
      robot.select(i)
      inv_contr.dropIntoSlot(sides.front, 2, 64)
    end
    ::continue::
  end
  -- go back to start
  robot.select(1)
  robot.turnRight()
  robot.forward()
  robot.forward()
  robot.turnRight()
  robot.turnRight()
end

-- gets 6 new cropsticks from the drawer and places them
local function placeNewCropSticks()
  robot.forward()
  robot.forward()
  robot.turnRight()
  -- get the items
  inv_contr.suckFromSlot(sides.front, 2, 6)
  -- equip them
  local inv_slot
  for i=1, 16, 1 do
    local item = inv_contr.getStackInInternalSlot(i)
    -- check if we have an item
    if item == nil then
      goto continue
    end

    if item.name == "agricraft:crop_sticks" then
      inv_slot = i
    end
    ::continue::
  end
  robot.select(inv_slot)
  inv_contr.equip()
  -- begin placing them
  robot.turnLeft()
  robot.turnLeft()
  robot.useDown()

  robot.forward()
  robot.turnLeft()
  robot.useDown()
  robot.useDown()

  robot.forward()
  robot.turnLeft()
  robot.useDown()

  robot.forward()
  robot.turnRight()
  robot.useDown()
  robot.useDown()
  -- return to start
  robot.forward()
  robot.turnRight()
  robot.turnRight()
  -- reequip the pickaxe
  robot.select(inv_slot)
  inv_contr.equip()
end

-- drops off all items (that are not seeds) into the outputchest
local function dropOffProduce()
  robot.turnLeft()
  robot.forward()
  for i=1, 16, 1 do
    local item = inv_contr.getStackInInternalSlot(i)
    -- check if we have an item
    if item == nil then
      goto continue
    end

    -- check if the item is not a seed
    local itemMatch = string.match(item.name, "seed")
    if itemMatch == nil then
      -- drop them off
      dumpItem(sides.down, i)
    end
    ::continue::
  end
  robot.back()
  robot.turnRight()
  robot.select(1)
end

local function gotSeeds()
  local seed1 = inv_contr.getStackInInternalSlot(15)
  local seed2 = inv_contr.getStackInInternalSlot(16)
  -- check if we have an item
  if seed1 == nil or seed2 == nil then
    -- return false
    os.sleep(0.5)
    modem.broadcast(computer_port, robot.name(), "false")
    return
  end

  -- check if the item is indeed a seed
  local seed1Match = string.match(seed1.name, "seed")
  local seed2Match = string.match(seed2.name, "seed")
  if seed1Match == nil or seed2Match == nil then
    -- return false
    os.sleep(0.5)
    modem.broadcast(computer_port, robot.name(), "false")
    return
  end
  -- check if both items have stacksize 1
  if seed1.size ~= 1 or seed2.size ~= 1 then
    -- return false
    os.sleep(0.5)
    modem.broadcast(computer_port, robot.name(), "false")
    return
  end
  -- check if they are the same seeds
  if seed1.name ~= seed2.name then
    os.sleep(0.5)
    modem.broadcast(computer_port, robot.name(), "false")
    return
  end
  -- return true
  os.sleep(0.5)
  modem.broadcast(computer_port, robot.name(), "true", seed1.label)
end

local function plantSeeds()
  robot.forward()
  robot.forward()
  robot.select(15)
  inv_contr.equip()
  robot.useDown()
  robot.turnLeft()
  robot.forward()
  robot.turnLeft()
  robot.forward()
  robot.select(16)
  inv_contr.equip()
  robot.useDown()
  robot.turnLeft()
  robot.forward()
  robot.turnLeft()
  robot.back()
  robot.select(15)
  inv_contr.equip()
  robot.select(1)
end

local function goToAnalyzer()
  robot.forward()
  robot.turnRight()
  robot.forward()
end

local function goBackFromAnalyzer()
  robot.back()
  robot.turnLeft()
  robot.back()
end

local function dropSeed(i)
  local item = inv_contr.getStackInInternalSlot(i)
  -- check if we have an item
  if item == nil then
    return
  end

  local itemMatch = string.match(item.name, "seed")
  if itemMatch ~= nil then
    -- we found a seed
    -- place the seed
    dumpItem(sides.down, i)
  end
end

local function takeSeedFromAnalyzer(i)
  robot.select(i)
  inv_contr.suckFromSlot(sides.down, 1, 64)
end

local function getStackSize(slot)
  local item = inv_contr.getStackInInternalSlot(slot)
  os.sleep(0.5)
  -- check if we have an item
  if item == nil then
    modem.broadcast(computer_port, robot.name(), "stacksize", -1)
    return
  end
  modem.broadcast(computer_port, robot.name(), "stacksize", item.size)
end

local function trashInventory()
  -- move to the trash
  robot.turnLeft()
  robot.forward()
  robot.forward()
  for i=1, 14, 1 do
    dumpItem(sides.down, i)
    os.sleep(1)
  end
  robot.back()
  robot.back()
  robot.turnRight()
end

local function trashSeeds()
  -- move to the trash
  robot.turnLeft()
  robot.forward()
  robot.forward()
  -- trash all seeds in slots 1-14
  for i=1, 14, 1 do
    local item = inv_contr.getStackInInternalSlot(i)
    -- check if we have an item
    if item == nil then
      goto continue
    end

    local itemMatch = string.match(item.name, "seed")
    if itemMatch ~= nil then
      -- we found a seed
      -- place the seed
      dumpItem(sides.down, i)
    end
    ::continue::
  end
  robot.back()
  robot.back()
  robot.turnRight()
end

local function manageSeeds(a, b)
  -- move one seed from a to slot 15
  robot.select(a)
  robot.transferTo(15, 1)
  -- if a still contains an item, transfer it to 16, otherwise transfer b to 16
  if inv_contr.getStackInInternalSlot(a) == nil then
    robot.select(b)
  end
  robot.transferTo(16, 1)
  trashSeeds()
  robot.select(1)
end

local function goToOutput()
  robot.turnRight()
  robot.forward()
end

local function goBackFromOutput()
  robot.back()
  robot.turnLeft()
end

while true do
  local evt, _, from, eventPort, _, name, cmd, a, b, c = event.pull("modem_message")
  if name == robot.name() and cmd ~= lastCmd then
    --print("received " .. cmd)
    -- harvests all 4 spots
    if cmd == "harvest" then
      harvest()
    end
    -- drop of all crop sticks
    if cmd == "cropstickdrop" then
      dropCropSticksOff()
    end
    -- place new crop sticks
    if cmd == "placecropstick" then
      placeNewCropSticks()
    end
    -- drop off harvest results
    if cmd == "dropoffproduce" then
      dropOffProduce()
    end
    -- go to the analyzer
    if cmd == "gotoanalyzer" then
      goToAnalyzer()
    end
    -- go back home
    if cmd == "gobackfromanalyzer" then
      goBackFromAnalyzer()
    end
    -- drop a seed into the analyzer
    if cmd == "dropseed" then
      dropSeed(a)
    end
    -- trash the entire inventory
    if cmd == "trashinventory" then
      trashInventory()
    end    
    -- take the seed back from the analyzer
    if cmd == "takeseedfromanalyzer" then
      takeSeedFromAnalyzer(a)
    end
    -- send the stacksize of item in slot a
    if cmd == "getstacksize" then
      getStackSize(a)
    end    
    -- go to the output chest
    if cmd == "gotooutput" then
      goToOutput()
    end
    -- go back home from the output chest
    if cmd == "gobackfromoutput" then
      goBackFromOutput()
    end
    -- save the two best seeds and throw away all the other seeds
    if cmd == "manageseeds" then
      manageSeeds(a, b)
    end
    -- drop the item at slot
    if cmd == "dropitem" then
      dropItem(a, b, c)
    end
    -- check if we got 2 seed in slot 15 and 16
    if cmd == "gotseeds" then
      gotSeeds()
    end
    -- Plant the two seeds
    if cmd == "plantseeds" then
      plantSeeds()
    end
    -- exit the program
    if cmd == "exit" then
      term.clear()
      os.exit()
    end
  end
  lastCmd = cmd
end
