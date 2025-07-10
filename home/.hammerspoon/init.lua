hs.loadSpoon("ReloadConfiguration")
spoon.ReloadConfiguration:start()

-- HANDLE SCROLLING WITH MOUSE BUTTON PRESSED
-- This handles fn + s + trackpad drag for smooth scrolling
-- Works by intercepting middle mouse button (button 2) events from Karabiner-Elements

local scrollMouseButton = 2
local deferred = false

-- MOMENTUM SCROLLING ATTEMPTS (FAILED - COMMENTED OUT FOR FUTURE REFERENCE)
-- 
-- We tried several approaches to add trackpad-like momentum scrolling:
-- 1. Adding momentum on mouse button release - didn't work because we want momentum when finger lifts from trackpad, not when fn+s is released
-- 2. Using velocity tracking during drag - made scrolling choppy and unresponsive
-- 3. Timer-based gesture end detection (50ms timeout) - momentum never triggered properly
-- 4. Various momentum decay algorithms - none felt natural
-- 
-- The core issue seems to be that detecting "finger lifted from trackpad" while maintaining 
-- the fn+s button press is difficult with the current event handling approach.
-- 
-- Current working solution: Responsive immediate scrolling without momentum
-- Future consideration: May need different event handling approach or Karabiner-Elements integration

overrideOtherMouseDown = hs.eventtap.new({ hs.eventtap.event.types.otherMouseDown }, function(e)
  local pressedMouseButton = e:getProperty(hs.eventtap.event.properties['mouseEventButtonNumber'])
  if scrollMouseButton == pressedMouseButton
  then
    deferred = true
    return true
  end
end)

overrideOtherMouseUp = hs.eventtap.new({ hs.eventtap.event.types.otherMouseUp }, function(e)
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
  if scrollMouseButton == pressedMouseButton
  then
    deferred = false
    oldmousepos = hs.mouse.absolutePosition()
    local dx = e:getProperty(hs.eventtap.event.properties['mouseEventDeltaX'])
    local dy = e:getProperty(hs.eventtap.event.properties['mouseEventDeltaY'])
    
    -- Check for modifier keys (cmd, ctrl, option, shift) for zoom/special functionality
    local eventFlags = e:getFlags()
    local sysModifiers = hs.eventtap.checkKeyboardModifiers()
    
    local modifiers = {}
    if eventFlags['cmd'] or sysModifiers['cmd'] then
        table.insert(modifiers, "cmd")
    end
    if eventFlags['ctrl'] or sysModifiers['ctrl'] then
        table.insert(modifiers, "ctrl")
    end
    if eventFlags['alt'] or sysModifiers['alt'] then
        table.insert(modifiers, "alt")
    end
    if eventFlags['shift'] or sysModifiers['shift'] then
        table.insert(modifiers, "shift")
    end
    
    -- Create scroll event with detected modifiers
    local scroll = hs.eventtap.event.newScrollEvent({dx * scrollmult, dy * scrollmult}, modifiers, "pixel")
    scroll:post()
    
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
