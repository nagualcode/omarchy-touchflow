import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// TouchFlow — every four-finger gesture, one plugin.
//
// The compositor owns the touchpad, so the *gesture itself* has to stay in
// Hyprland's input.lua (hl.gesture). What used to live there as days of Lua
// plus two bash scripts is now this service: the gestures only call back in
// through omarchy-shell and TouchFlow decides what happens, reading the live
// Hyprland object model instead of round-tripping hyprctl + jq.
//
//   input.lua                    touchflow (this file)
//   swipes 4-fingers  --IPC----> up/down/next/prev
//                                focus/move windows, skip empties, menus
Item {
  id: root

  // ── helpers ──────────────────────────────────────────────────────────
  function workspaces() {
    return (typeof Hyprland !== "undefined" && Hyprland.workspaces)
      ? Hyprland.workspaces.values
      : []
  }

  function toplevelsOf(ws) {
    return ws && ws.toplevels && ws.toplevels.values ? ws.toplevels.values : []
  }

  function windowCount(ws) {
    return ws ? root.toplevelsOf(ws).length : 0
  }

  function activeWorkspace() {
    var list = root.workspaces()
    for (var i = 0; i < list.length; i++)
      if (list[i].active === true) return list[i]
    for (var i = 0; i < list.length; i++) {
      var top = root.toplevelsOf(list[i])
      for (var j = 0; j < top.length; j++)
        if (top[j].activated === true) return list[i]
    }
    if (typeof Hyprland !== "undefined" && Hyprland.focusedWorkspace)
      return Hyprland.focusedWorkspace
    return null
  }

  function activeWorkspaceId() {
    var ws = root.activeWorkspace()
    return ws ? Number(ws.id) : 0
  }

  function workspaceById(id) {
    var list = root.workspaces()
    for (var i = 0; i < list.length; i++)
      if (Number(list[i].id) === Number(id)) return list[i]
    return null
  }

  function hasWindows(id) {
    return root.windowCount(root.workspaceById(id)) > 0
  }

  function firstEmptyWorkspace() {
    var list = root.workspaces().slice(0)
    list.sort(function (a, b) { return Number(a.id) - Number(b.id) })
    for (var i = 0; i < list.length; i++) {
      var id = Number(list[i].id)
      if (id > 0 && root.windowCount(list[i]) === 0) return id
    }
    return null
  }

  // ── dispatch ─────────────────────────────────────────────────────────
  // Omarchy runs Hyprland in Lua mode, so moves and focus go through the
  // custom Lua dispatcher expressions, exactly like the other Omarchy plugins.
  function dispatch(expr) {
    Quickshell.execDetached(["hyprctl", "dispatch", expr])
  }

  function focusWorkspace(id) {
    root.dispatch('hl.dsp.focus({ workspace = "' + root.luaStringLiteral(String(id)) + '" })')
  }

  function moveWindowTo(workspaceLiteral) {
    root.dispatch("hl.dsp.window.move({ workspace = " + workspaceLiteral + ", follow = true })")
  }

  // Mirrors the Lua string escaper used by the rest of the Omarchy shell so a
  // fresh workspace (or any future name) survives the Lua parse.
  function luaStringLiteral(value) {
    return String(value || "").replace(/[\\"\x00-\x1f\x7f]/g, function(ch) {
      if (ch === "\\") return "\\\\"
      if (ch === '"') return '\\"'
      var decimal = ch.charCodeAt(0).toString()
      return "\\" + ("000" + decimal).slice(-3)
    })
  }

  // ── fallbacks ────────────────────────────────────────────────────────
  function openBrowser() {
    Quickshell.execDetached(["uwsm", "app", "--", "chromium"])
  }

  function openTerminal() {
    Quickshell.execDetached(["foot"])
  }

  // ── gestures ─────────────────────────────────────────────────────────
  // Swipe up: relocate the active window.
  //   no window / empty workspace  -> browser
  //   many windows                 -> first empty workspace (or a fresh one)
  //   lone window                  -> next workspace, only if it is occupied
  function up() {
    var ws = root.activeWorkspace()
    var count = root.windowCount(ws)
    if (!ws || count === 0) { root.openBrowser(); return "browser" }
    if (count > 1) {
      var empty = root.firstEmptyWorkspace()
      if (empty !== null) { root.moveWindowTo(String(empty)); return "move:" + empty }
      root.moveWindowTo("'emptyn'")
      return "move:emptyn"
    }
    var next = Number(ws.id) + 1
    if (root.hasWindows(next)) { root.moveWindowTo(String(next)); return "move:" + next }
    return "idle"
  }

  // Swipe down: move the active window one workspace towards the left edge,
  // or open a terminal when there is nothing to move.
  function down() {
    var ws = root.activeWorkspace()
    if (!ws || root.windowCount(ws) === 0) { root.openTerminal(); return "terminal" }
    var target = Number(ws.id) - 1
    if (target <= 0) return "at-edge"
    root.moveWindowTo(String(target))
    return "move:" + target
  }

  // Swipe left/right: jump to the next/previous occupied workspace, skipping
  // empty holes, and always leave a fresh workspace available right after the
  // last used one.
  function navigate(delta) {
    var cur = root.activeWorkspaceId()
    if (!(cur > 0)) return "none"
    var chosen = null
    var all = root.workspaces()
    for (var i = 0; i < all.length; i++) {
      var id = Number(all[i].id)
      if (!(id > 0) || root.windowCount(all[i]) < 1) continue
      if (delta > 0 && id > cur && (chosen === null || id < chosen)) chosen = id
      else if (delta < 0 && id < cur && (chosen === null || id > chosen)) chosen = id
    }
    if (chosen !== null) { root.focusWorkspace(chosen); return "focus:" + chosen }
    if (delta > 0) { var fresh = cur + 1; root.focusWorkspace(fresh); return "fresh:" + fresh }
    return "none"
  }

  function stateString() {
    var ws = root.activeWorkspace()
    return "active=" + (ws ? Number(ws.id) : 0)
      + " workspaces=" + root.workspaces().length
  }

  // The contract Hyprland's input.lua talks to:
  //   omarchy-shell touchflow up | down | next | prev | state
  IpcHandler {
    target: "touchflow"
    function up(): string { return root.up() }
    function down(): string { return root.down() }
    function next(): string { return root.navigate(1) }
    function prev(): string { return root.navigate(-1) }
    function state(): string { return root.stateString() }
  }
}