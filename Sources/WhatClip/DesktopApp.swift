import AppKit
import WhatClipCore

/// The standard macOS menu bar for WhatClip, so Hide, Minimise, Close, Edit and the rest behave as people expect.
/// Only WhatClip's own menus; nothing system-wide is changed.
@MainActor
enum DesktopMenu {
    static func build(target: AnyObject, settingsAction: Selector, aboutAction: Selector, helpAction: Selector,
                      pickerAction: Selector, historyAction: Selector, pauseAction: Selector,
                      exportAction: Selector, importAction: Selector) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "WhatClip")
        app.addItem(item("About WhatClip", aboutAction, target: target))
        app.addItem(.separator())
        app.addItem(item("Settings…", settingsAction, key: ",", target: target))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Hide WhatClip", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]; app.addItem(hideOthers)
        app.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Quit WhatClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        main.addItem(sub("WhatClip", app))

        let file = NSMenu(title: "File")
        file.addItem(item("Export History…", exportAction, target: target))
        file.addItem(item("Import History…", importAction, target: target))
        main.addItem(sub("File", file))

        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        main.addItem(sub("Edit", edit))

        let view = NSMenu(title: "View")
        view.addItem(item("Clipboard Picker", pickerAction, key: "v", mods: [.command, .shift], target: target))
        view.addItem(item("History Window", historyAction, key: "0", target: target))
        view.addItem(.separator())
        let full = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]; view.addItem(full)
        main.addItem(sub("View", view))

        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        window.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        window.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        window.addItem(.separator())
        window.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        window.addItem(item("Pause Capturing", pauseAction, target: target))
        main.addItem(sub("Window", window))
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(item("WhatClip Help", helpAction, target: target))
        main.addItem(sub("Help", help))
        NSApp.helpMenu = help

        return main
    }

    private static func item(_ title: String, _ action: Selector, key: String = "", mods: NSEvent.ModifierFlags = .command, target: AnyObject) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: action, keyEquivalent: key)
        m.keyEquivalentModifierMask = mods; m.target = target
        return m
    }
    private static func sub(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: nil, keyEquivalent: ""); m.submenu = menu; return m
    }
}
