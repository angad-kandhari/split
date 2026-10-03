import ApplicationServices

// Private API: maps an Accessibility window element to its window-server ID.
// Used by most Mac window managers; callers must cope with it failing.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError
