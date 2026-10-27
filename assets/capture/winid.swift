// Prints the CGWindowID of the on-screen window with the given title (for screencapture -l).
import CoreGraphics

let title = CommandLine.arguments[1]
let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in wins where (w[kCGWindowName as String] as? String) == title {
  print(w[kCGWindowNumber as String]!)
  break
}
