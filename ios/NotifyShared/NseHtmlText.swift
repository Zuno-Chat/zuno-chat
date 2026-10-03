import Foundation

final class NseHtmlNode {
  let tag: String?
  var attributes: [String: String]
  var text: String
  var children: [NseHtmlNode] = []

  init(tag: String?, attributes: [String: String] = [:], text: String = "") {
    self.tag = tag
    self.attributes = attributes
    self.text = text
  }

  var textContent: String {
    tag == nil ? text : children.map(\.textContent).joined()
  }
}

enum NseHtmlText {
  private static let blockTags: Set<String> = [
    "blockquote", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "pre",
  ]
  private static let voidTags: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
    "source", "track", "wbr",
  ]
  private static let closesParagraph: Set<String> = [
    "p", "div", "ul", "ol", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6", "hr",
    "table",
  ]
  private static let maxEventScalars = 65_536
  private static let maxInputScalars = 16_384
  private static let maxStackDepth = 40
  private static let bullets = ["•", "◦", "▪", "‣"]
  private static let entities: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“",
    "rdquo": "”", "copy": "©", "reg": "®", "trade": "™", "euro": "€", "eacute": "é",
  ]
  private static let trailingSpace: Set<UInt32> = [
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004,
    0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    0xFEFF,
  ]

  static func plainText(_ html: String) -> String {
    var depth = 0
    let stripped = removingReplies(bounded(html, to: maxEventScalars))
    var reply = walkChildren(parse(bounded(stripped, to: maxInputScalars)), &depth)
    while let last = reply.unicodeScalars.last, trailingSpace.contains(last.value) {
      reply.unicodeScalars.removeLast()
    }
    return reply
  }

  private static func bounded(_ text: String, to limit: Int) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.prefix(limit)))
  }

  static func removingReplies(_ html: String) -> String {
    let options: String.CompareOptions = [.caseInsensitive, .literal]
    guard let open = html.range(of: "<mx-reply>", options: options) else { return html }
    var close: Range<String.Index>?
    var from = open.upperBound
    while let found = html.range(of: "</mx-reply>", options: options, range: from..<html.endIndex) {
      close = found
      from = found.upperBound
    }
    guard let close else { return html }
    var stripped = html
    stripped.removeSubrange(open.lowerBound..<close.upperBound)
    return stripped
  }

  static func parse(_ html: String) -> NseHtmlNode {
    let root = NseHtmlNode(tag: nil)
    var stack = [root]
    let scalars = Array(
      html.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        .unicodeScalars)
    var position = 0
    var pending = ""

    func flushText() {
      guard !pending.isEmpty else { return }
      let current = stack[stack.count - 1]
      if let last = current.children.last, last.tag == nil {
        last.text += decode(pending)
      } else {
        current.children.append(NseHtmlNode(tag: nil, text: decode(pending)))
      }
      pending = ""
    }

    func keepAsText() {
      pending.unicodeScalars.append(scalars[position])
      position += 1
    }

    while position < scalars.count {
      guard scalars[position] == "<", position + 1 < scalars.count else {
        keepAsText()
        continue
      }
      let next = scalars[position + 1]
      if next == "!" {
        flushText()
        position = skipComment(scalars, from: position)
        continue
      }
      if next == "/" {
        guard let (name, end) = readName(scalars, from: position + 2) else {
          keepAsText()
          continue
        }
        flushText()
        position = skip(to: ">", scalars, from: end) + 1
        if let index = stack.lastIndex(where: { $0.tag == name }), index > 0 {
          stack.removeSubrange(index...)
        }
        continue
      }
      guard let (name, end) = readName(scalars, from: position + 1) else {
        keepAsText()
        continue
      }
      flushText()
      let (attributes, selfClosing, after) = readAttributes(scalars, from: end)
      position = after
      if closesParagraph.contains(name) || name == "li" {
        let closing = name == "li" ? "li" : "p"
        if stack.count > 1, stack[stack.count - 1].tag == closing { stack.removeLast() }
      }
      let element = NseHtmlNode(tag: name, attributes: attributes)
      stack[stack.count - 1].children.append(element)
      if !selfClosing && !voidTags.contains(name) && stack.count < maxStackDepth {
        stack.append(element)
      }
    }
    flushText()
    return root
  }

  private static func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
    (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
  }

  private static func isNameScalar(_ scalar: Unicode.Scalar) -> Bool {
    isNameStart(scalar) || (scalar >= "0" && scalar <= "9") || scalar == "-" || scalar == ":"
  }

  private static func readName(_ scalars: [Unicode.Scalar], from start: Int) -> (String, Int)? {
    guard start < scalars.count, isNameStart(scalars[start]) else { return nil }
    var end = start
    var name = ""
    while end < scalars.count, isNameScalar(scalars[end]) {
      name.unicodeScalars.append(scalars[end])
      end += 1
    }
    return (name.lowercased(), end)
  }

  private static func skip(to target: Unicode.Scalar, _ scalars: [Unicode.Scalar], from start: Int)
    -> Int
  {
    var position = start
    while position < scalars.count, scalars[position] != target { position += 1 }
    return position
  }

  private static func skipComment(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
    let isComment =
      start + 3 < scalars.count && scalars[start + 2] == "-" && scalars[start + 3] == "-"
    guard isComment else { return skip(to: ">", scalars, from: start) + 1 }
    var position = start + 4
    while position + 2 < scalars.count {
      if scalars[position] == "-" && scalars[position + 1] == "-" && scalars[position + 2] == ">" {
        return position + 3
      }
      position += 1
    }
    return scalars.count
  }

  private static func readAttributes(_ scalars: [Unicode.Scalar], from start: Int) -> (
    [String: String], Bool, Int
  ) {
    var attributes: [String: String] = [:]
    var position = start
    var selfClosing = false
    while position < scalars.count {
      let scalar = scalars[position]
      if scalar == ">" { return (attributes, selfClosing, position + 1) }
      if scalar == "/" {
        selfClosing = true
        position += 1
        continue
      }
      if scalar.properties.isWhitespace {
        position += 1
        continue
      }
      selfClosing = false
      var name = ""
      while position < scalars.count, !scalars[position].properties.isWhitespace,
        scalars[position] != "=", scalars[position] != ">", scalars[position] != "/"
      {
        name.unicodeScalars.append(scalars[position])
        position += 1
      }
      while position < scalars.count, scalars[position].properties.isWhitespace { position += 1 }
      var value = ""
      if position < scalars.count, scalars[position] == "=" {
        position += 1
        while position < scalars.count, scalars[position].properties.isWhitespace { position += 1 }
        if position < scalars.count, scalars[position] == "\"" || scalars[position] == "'" {
          let quote = scalars[position]
          position += 1
          while position < scalars.count, scalars[position] != quote {
            value.unicodeScalars.append(scalars[position])
            position += 1
          }
          position += 1
        } else {
          while position < scalars.count, !scalars[position].properties.isWhitespace,
            scalars[position] != ">"
          {
            value.unicodeScalars.append(scalars[position])
            position += 1
          }
        }
      }
      let key = name.lowercased()
      if !name.isEmpty, attributes[key] == nil {
        attributes[key] = decode(value)
      }
    }
    return (attributes, selfClosing, scalars.count)
  }

  static func decode(_ text: String) -> String {
    guard text.contains("&") else { return text }
    var result = ""
    var rest = Substring(text)
    while let ampersand = rest.firstIndex(of: "&") {
      result += rest[..<ampersand]
      let tail = rest[rest.index(after: ampersand)...]
      if let semicolon = tail.prefix(12).firstIndex(of: ";"),
        let decoded = entity(String(tail[..<semicolon]))
      {
        result += decoded
        rest = tail[tail.index(after: semicolon)...]
      } else {
        result += "&"
        rest = tail
      }
    }
    return result + rest
  }

  private static func entity(_ name: String) -> String? {
    if let named = entities[name] { return named }
    guard name.hasPrefix("#") else { return nil }
    let digits = name.dropFirst()
    let value =
      digits.first == "x" || digits.first == "X"
      ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
    guard let value, value != 0, let scalar = Unicode.Scalar(value) else { return nil }
    return String(Character(scalar))
  }

  private static func walkChildren(_ node: NseHtmlNode, _ depth: inout Int) -> String {
    var reply = ""
    var lastTag = ""
    for child in node.children {
      let thisTag = child.tag ?? ""
      if thisTag == "p" && lastTag == "p" {
        reply += "\n\n"
      } else if blockTags.contains(thisTag), !reply.isEmpty, reply.unicodeScalars.last != "\n" {
        reply += "\n"
      }
      reply += walk(child, &depth)
      if !thisTag.isEmpty { lastTag = thisTag }
    }
    return reply
  }

  private static func walk(_ node: NseHtmlNode, _ depth: inout Int) -> String {
    guard let tag = node.tag else { return node.text == "\n" ? "" : node.text }
    switch tag {
    case "em", "i":
      return "*\(walkChildren(node, &depth))*"
    case "strong", "b":
      return "**\(walkChildren(node, &depth))**"
    case "u", "ins":
      return "__\(walkChildren(node, &depth))__"
    case "del", "strike", "s":
      return "~~\(walkChildren(node, &depth))~~"
    case "code":
      return "`\(node.textContent)`"
    case "pre":
      return "```\(preformatted(node))```\n"
    case "a":
      let href = (node.attributes["href"] ?? "").lowercased()
      let content = walkChildren(node, &depth)
      if href.hasPrefix("https://matrix.to/#/") || href.hasPrefix("matrix:") { return content }
      return "🔗\(content)"
    case "img":
      return node.attributes["alt"] ?? node.attributes["title"] ?? node.attributes["src"] ?? ""
    case "br":
      return "\n"
    case "blockquote":
      let message = walkChildren(node, &depth)
      return
        message.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n") + "\n"
    case "ul", "ol":
      return list(node, ordered: tag == "ol", &depth)
    case "mx-reply":
      return ""
    case "hr":
      return "\n----------\n"
    case "h1", "h2", "h3", "h4", "h5", "h6":
      let level = Int(String(tag.dropFirst())) ?? 1
      return String(repeating: "#", count: level) + " " + walkChildren(node, &depth) + "\n"
    case "span":
      let content = walkChildren(node, &depth)
      guard let reason = node.attributes["data-mx-spoiler"] else { return content }
      let blocks = String(repeating: "█", count: content.utf16.count)
      return reason.isEmpty ? blocks : "(\(reason)) \(blocks)"
    default:
      return walkChildren(node, &depth)
    }
  }

  private static func list(_ node: NseHtmlNode, ordered: Bool, _ depth: inout Int) -> String {
    depth += 1
    var entries: [String] = []
    for child in node.children where child.tag == "li" {
      entries.append(walk(child, &depth))
    }
    depth -= 1
    let indent = String(repeating: "    ", count: depth)
    let nested = "\n\(indent)  "
    if ordered {
      let start = node.attributes["start"].flatMap { value -> Int? in
        value.isEmpty || !value.allSatisfy({ $0.isASCII && $0.isNumber }) ? nil : Int(value)
      }
      return entries.enumerated().map { offset, entry in
        "\(indent)\((start ?? 1) &+ offset). \(entry.replacingOccurrences(of: "\n", with: nested))"
      }.joined(separator: "\n")
    }
    let bullet = bullets[depth % bullets.count]
    return entries.map { entry in
      "\(indent)\(bullet) \(entry.replacingOccurrences(of: "\n", with: nested))"
    }.joined(separator: "\n")
  }

  private static func preformatted(_ node: NseHtmlNode) -> String {
    var text = node.textContent
    var language = ""
    if let code = node.children.first, code.tag == "code" {
      text = code.textContent
      if let classes = code.attributes["class"],
        let regex = try? NSRegularExpression(
          pattern: "language-([A-Za-z0-9_]+)", options: [.caseInsensitive]),
        let match = regex.firstMatch(
          in: classes, range: NSRange(classes.startIndex..., in: classes)),
        let range = Range(match.range(at: 1), in: classes)
      {
        language = String(classes[range])
      }
    }
    if !text.isEmpty {
      if text.unicodeScalars.first != "\n" { text = "\n" + text }
      if text.unicodeScalars.last != "\n" { text += "\n" }
    }
    return language + text
  }
}
