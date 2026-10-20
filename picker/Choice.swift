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
// rule as start.sh: the first line, without spaces or a Windows \r.
func savedChoice(at file: URL) -> String {
  let line = (try? String(contentsOf: file, encoding: .utf8))?
    .components(separatedBy: "\n").first ?? ""   // not split(): Swift treats \r\n as one character
  let word = line.filter { $0 != " " && $0 != "\t" && $0 != "\r" }
  return choices.contains { $0.id == word } ? word : "auto"
}

// Written whole, so start.sh never reads a half-written file.
func save(_ id: String, to file: URL) -> Bool {
  (try? (id + "\n").write(to: file, atomically: true, encoding: .utf8)) != nil
}
