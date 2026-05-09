import Foundation

internal enum GstLaunch {
  static func property(_ name: String, value: String) -> String {
    "\(name)=\(quotedString(value))"
  }

  static func fileURI(forPath path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.absoluteString
  }

  private static func quotedString(_ value: String) -> String {
    var result = "\""
    for character in value {
      switch character {
      case "\\":
        result += "\\\\"
      case "\"":
        result += "\\\""
      case "\n":
        result += "\\n"
      case "\r":
        result += "\\r"
      case "\t":
        result += "\\t"
      default:
        result.append(character)
      }
    }
    result += "\""
    return result
  }
}
