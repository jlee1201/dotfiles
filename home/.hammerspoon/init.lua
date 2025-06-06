hs.loadSpoon("ReloadConfiguration")
spoon.ReloadConfiguration:start()

-- HANDLE SCROLLING WITH MOUSE BUTTON PRESSED
local scrollMouseButton = 2
local deferred = false

overrideOtherMouseDown = hs.eventtap.new({ hs.eventtap.event.types.otherMouseDown }, function(e)
  local pressedMouseButton = e:getProperty(hs.eventtap.event.properties['mouseEventButtonNumber'])
  -- print("down")
  if scrollMouseButton == pressedMouseButton
  then
    deferred = true
    return true
  end
end)

overrideOtherMouseUp = hs.eventtap.new({ hs.eventtap.event.types.otherMouseUp }, function(e)
  -- print("up")
  local pressedMouseButton = e:getProperty(hs.eventtap.event.properties['mouseEventButtonNumber'])
  if scrollMouseButton == pressedMouseButton
  then
    if (deferred) then
      overrideOtherMouseDown:stop()
      overrideOtherMouseUp:stop()
      hs.eventtap.otherClick(e:location(), pressedMouseButton)
      overrideOtherMouseDown:start()
      overrideOtherMouseUp:start()
      return true
    end
    return false
  end
  return false
end)

local oldmousepos = {}
local scrollmult = -4   -- negative multiplier makes mouse work like traditional scrollwheel

dragOtherToScroll = hs.eventtap.new({ hs.eventtap.event.types.otherMouseDragged }, function(e)
  local pressedMouseButton = e:getProperty(hs.eventtap.event.properties['mouseEventButtonNumber'])
  -- print ("pressed mouse " .. pressedMouseButton)
  if scrollMouseButton == pressedMouseButton
  then
    -- print("scroll");
    deferred = false
    oldmousepos = hs.mouse.absolutePosition()
    local dx = e:getProperty(hs.eventtap.event.properties['mouseEventDeltaX'])
    local dy = e:getProperty(hs.eventtap.event.properties['mouseEventDeltaY'])
    
    -- Check both event flags and system modifiers
    local eventFlags = e:getFlags()
    local sysModifiers = hs.eventtap.checkKeyboardModifiers()
    
    print("Event flags:", hs.inspect(eventFlags))
    print("System modifiers:", hs.inspect(sysModifiers))
    
    if eventFlags['ctrl'] or sysModifiers['ctrl'] then
      print("Using ctrl modifier for scroll")
      -- Try the standard {"ctrl"} format
      local scroll = hs.eventtap.event.newScrollEvent({dx * scrollmult, dy * scrollmult}, {"ctrl"}, "pixel")
      scroll:post()
      print("Posted scroll event with ctrl modifier")
    else
      print("No ctrl modifier detected")
      -- Regular scroll without modifiers
      local scroll = hs.eventtap.event.newScrollEvent({dx * scrollmult, dy * scrollmult}, {}, "pixel")
      scroll:post()
      print("Posted regular scroll event")
    end
    -- put the mouse back
    hs.mouse.absolutePosition(oldmousepos)
    return true
  else
    return false, {}
  end
end)

overrideOtherMouseDown:start()
overrideOtherMouseUp:start()
dragOtherToScroll:start()
