import AppKit

// A menu bar icon for picking what the herdr side pane plays while Claude works.

let choiceFile = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/runner/choice")

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
  var statusItem: NSStatusItem!
  let menu = NSMenu()

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    menu.delegate = self
    menu.addItem(withTitle: "While Claude works, play:", action: nil, keyEquivalent: "")
    for choice in choices {
      let item = NSMenuItem(title: choice.title, action: #selector(pick(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = choice.id
      menu.addItem(item)
    }
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit Game Picker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusItem.menu = menu
    refresh()
  }

  // The file can be edited by hand too, so the tick is read fresh each time the menu opens.
  func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

  func refresh() {
    let current = savedChoice(at: choiceFile)
    for item in menu.items where item.representedObject != nil {
      item.state = item.representedObject as? String == current ? .on : .off
    }
    let image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: "Game Picker")
    image?.isTemplate = true
    statusItem.button?.image = image
    statusItem.button?.appearsDisabled = current == "off"
  }

  @objc func pick(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    if !save(id, to: choiceFile) { NSSound.beep() }
    refresh()
  }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
