-- Headless interaction check for the webview shell. Never loads live Hammerspoon.
local toggle, complete, view, escape
package.loaded.hyper = { bind = function(_, _, fn) toggle = fn end }

local function fluent(name)
  return function(self, value)
    self[name] = value
    return self
  end
end

hs = {
  configdir = "hammerspoon",
  logger = { new = function() return { e = function() end } end },
  alert = { show = function() error("unexpected alert") end },
  screen = { mainScreen = function() return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end } end },
  canvas = { windowLevels = { screenSaver = 100 } },
  task = { new = function(_, callback)
    return { start = function() complete = callback; return true end }
  end },
  hotkey = { new = function(_, _, fn)
    escape = { trigger = fn, enable = function(self) self.enabled = true end,
               disable = function(self) self.enabled = false end }
    return escape
  end },
  webview = { new = function(frame)
    view = { frame = frame, allowTextEntry = fluent("textEntry"),
      windowStyle = fluent("style"), transparent = fluent("transparentValue"),
      shadow = fluent("shadowValue"), level = fluent("levelValue"),
      behaviorAsLabels = fluent("behavior"), policyCallback = fluent("policy"),
      windowCallback = fluent("window"), url = fluent("loadedURL"),
      show = fluent("fade"), delete = function(self, _, fade) self.deleted = fade end }
    return view
  end },
}

dofile("hammerspoon/diagnostics.lua")

toggle()  -- start render
assert(complete and not view)
toggle()  -- dismiss while render is pending
complete(0, "file:///snapshot.html", "")
assert(not view)

toggle()
complete(0, "file:///snapshot.html", "")
assert(view.style == 0 and view.transparentValue and view.shadowValue == false)
assert(view.fade == 0.14 and escape.enabled and view.loadedURL == "file:///snapshot.html")
local first = view
toggle()  -- Hyper+D closes
assert(first.deleted == 0.14 and not escape.enabled)

toggle()
complete(0, "file:///snapshot.html", "")
local second = view
assert(second.policy("navigationAction", second, { request = { URL = "diagnostics://close/" } }) == false)
assert(second.deleted == 0.14 and not escape.enabled)

toggle()
complete(0, "file:///snapshot.html", "")
local third = view
escape.trigger()  -- Escape closes
assert(third.deleted == 0.14 and not escape.enabled)
print("diagnostics overlay interactions passed")
