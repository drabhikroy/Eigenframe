import Cocoa

// Keep a strong reference to the delegate so it is not immediately
// deallocated — NSApplication.delegate is a weak property.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.run()
