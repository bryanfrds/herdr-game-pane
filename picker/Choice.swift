import Foundation

// What the side pane plays, saved as one word in ~/.claude/runner/choice for start.sh.

struct Choice: Equatable {
  let id: String
  let title: String
}

let choices = [
  Choice(id: "auto", title: "Both games, in turn"),
  Choice(id: "dungeon", title: "Dungeon"),
  Choice(id: "codemon", title: "CodeMon"),
  Choice(id: "off", title: "Off"),
]

// The saved choice, or "auto" when there's none or it isn't one we know. Read by the same
// rule as start.sh: the first line, without spaces, tabs or a Windows \r. Done on bytes, as
// head and tr do; as text, Swift treats \r\n as one character and won't split it.
func savedChoice(at file: URL) -> String {
  let bytes = (try? Data(contentsOf: file)) ?? Data()
  let line = bytes.prefix { $0 != 0x0A }.filter { $0 != 0x20 && $0 != 0x09 && $0 != 0x0D }
  let word = String(decoding: line, as: UTF8.self)
  return choices.contains { $0.id == word } ? word : "auto"
}

// Written whole, so start.sh never reads a half-written file.
func save(_ id: String, to file: URL) -> Bool {
  (try? (id + "\n").write(to: file, atomically: true, encoding: .utf8)) != nil
}
