import Foundation

var failures = 0
func check<T: Equatable>(_ name: String, _ got: T, _ want: T) {
  if got == want { print("  ok   \(name)") } else { failures += 1; print("  FAIL \(name): got \(got), want \(want)") }
}

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("picker-\(getpid())")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let file = dir.appendingPathComponent("choice")

check("no file means auto", savedChoice(at: file), "auto")
check("saving works", save("codemon", to: file), true)
check("a saved choice reads back", savedChoice(at: file), "codemon")
check("it's one word on a line, as start.sh reads it", try? String(contentsOf: file, encoding: .utf8), "codemon\n")
try? "junk\n".write(to: file, atomically: true, encoding: .utf8)
check("an unknown word means auto", savedChoice(at: file), "auto")
check("every choice is one start.sh knows", choices.map(\.id), ["auto", "dungeon", "codemon", "off"])
check("a missing folder fails to save rather than crashing",
      save("off", to: dir.appendingPathComponent("gone/choice")), false)
try? FileManager.default.removeItem(at: dir)

if failures > 0 { print("\(failures) failed"); exit(1) }
print("all passed")
