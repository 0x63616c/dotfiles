-- Common modal placement and dismissal for canvas and webview popups.
-- Content, controls, and their rendering stay with each feature.
local theme = require("lib.theme")
local popup = {}

function popup.frame(screen, width, height)
  return {
    x = math.floor((screen.w - width) / 2),
    y = math.max(theme.popup.inset, math.floor((screen.h - height) * theme.popup.topFraction)),
    w = width, h = height,
  }
end

function popup.escape(close)
  return hs.hotkey.new({}, "escape", close)
end

function popup.backdrop(event, id, close, activeDrag)
  if event == "mouseDown" and id == "backdrop" and not activeDrag then
    close()
    return true
  end
  return false
end

function popup.webMessages(close)
  return hs.webview.usercontent.new("popup"):setCallback(function(message)
    if message.body == "close" then close() end
  end)
end

return popup
