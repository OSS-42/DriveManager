import DriveCore
import Foundation

let usage = """
Usage: drive-scan [path] [--depth N] [--top N] [--json]

Scans a folder (your home folder by default) and lists what takes the most space.

  --depth N   how many folder levels to show (default 2)
  --top N     how many items to show per folder (default 10)
  --json      print the tree as JSON instead of a table
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n\n" + usage + "\n").utf8))
    exit(2)
}

var path = NSHomeDirectory()
var depth = 2
var top = 10
var json = false

var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--depth":
        guard let value = arguments.popFirst(), let number = Int(value), number >= 0 else { fail("--depth needs a number") }
        depth = number
    case "--top":
        guard let value = arguments.popFirst(), let number = Int(value), number > 0 else { fail("--top needs a number above 0") }
        top = number
    case "--json":
        json = true
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        if argument.hasPrefix("-") { fail("Unknown option \(argument)") }
        path = (argument as NSString).expandingTildeInPath
    }
}

let result = await Scanner().scan(URL(fileURLWithPath: path))

if json {
    print(Report.json(result, depth: depth, top: top))
} else {
    print(Report.text(result, depth: depth, top: top))
}
