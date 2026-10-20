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

// The saved choice, or "auto" when there's none or it isn't one we know.
func savedChoice(at file: URL) -> String {
  let word = (try? String(contentsOf: file, encoding: .utf8))?
    .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
  return choices.contains { $0.id == word } ? word : "auto"
}

// Written whole, so start.sh never reads a half-written file.
func save(_ id: String, to file: URL) -> Bool {
  (try? (id + "\n").write(to: file, atomically: true, encoding: .utf8)) != nil
}
