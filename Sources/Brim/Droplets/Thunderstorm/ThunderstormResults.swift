import Foundation

/// Everything the launcher can search, gathered so result building is a pure function.
struct ThunderSources {
  var apps: [InstalledApp] = []
  var files: [URL] = []
  var clipboard: [ClipboardEntry] = []
  var quicklinks: [ThunderQuicklink] = []
  var snippets: [ThunderSnippet] = []
  var systemCommands: [ThunderSystemCommand] = []
  var frecency: [String: ThunderFrecency] = [:]
  var webTemplate = "https://duckduckgo.com/?q={query}"
  var clipboardText = ""
}

/// Turns a query into ordered rows: answers first, then quicklinks, then the ranked mix, then
/// the web-search fallback.
enum ThunderResults {
  static func build(query rawQuery: String, sources: ThunderSources, now: Date = .now, limit: Int = 9) -> [ThunderResult] {
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    var lookup: [String: ThunderResult] = [:]
    var candidates: [ThunderCandidate] = []
    func add(_ result: ThunderResult, keywords: String = "", boost: Double) {
      lookup[result.id] = result
      candidates.append(ThunderCandidate(id: result.id, title: result.title, keywords: keywords, kindBoost: boost))
    }

    for app in sources.apps {
      add(
        ThunderResult(id: "app:\(app.url.path)", kind: .app, title: app.name, subtitle: "Application",
          symbol: "app.fill", iconPath: app.url.path, action: .openApp(app.url)),
        keywords: app.bundleID ?? "", boost: 30)
    }
    for command in sources.systemCommands {
      add(
        ThunderResult(id: "sys:\(command.rawValue)", kind: .system, title: command.title, subtitle: "System",
          symbol: command.symbol, action: .system(command)),
        keywords: command.keywords, boost: 10)
    }
    for snippet in sources.snippets {
      add(
        ThunderResult(id: "snip:\(snippet.id)", kind: .snippet, title: snippet.title,
          subtitle: String(snippet.text.replacingOccurrences(of: "\n", with: " ").prefix(70)),
          symbol: "text.append", action: .paste(snippet.expanded(now: now, clipboard: sources.clipboardText))),
        keywords: snippet.keyword, boost: 20)
    }
    for url in sources.files.prefix(5) {
      add(
        ThunderResult(id: "file:\(url.path)", kind: .file, title: url.lastPathComponent,
          subtitle: abbreviated(url.deletingLastPathComponent().path), symbol: "doc.fill", iconPath: url.path,
          action: .open(url)),
        boost: 0)
    }
    if query.count >= 2 {
      for entry in sources.clipboard where entry.kind != .image {
        guard let text = entry.text, !text.isEmpty else { continue }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        add(
          ThunderResult(id: "clip:\(entry.id)", kind: .clipboard, title: String(line.prefix(90)),
            subtitle: "Clipboard history", symbol: "doc.on.clipboard.fill", action: .clipboardEntry(entry.id)),
          keywords: String(text.prefix(300)), boost: -25)
      }
    }

    var rows: [ThunderResult] = []
    rows += answers(for: query)
    rows += quicklinkRows(for: query, sources.quicklinks)
    let ranked = ThunderRanking.rank(candidates, query: query, frecency: sources.frecency, now: now, limit: limit)
    rows += ranked.compactMap { lookup[$0.id] }
    if !query.isEmpty, let web = webRow(query, sources.webTemplate) { rows.append(web) }
    var seen = Set<String>()
    return rows.filter { seen.insert($0.id).inserted }.prefix(limit + 3).map { $0 }
  }

  private static func answers(for query: String) -> [ThunderResult] {
    if let conversion = ThunderUnits.convert(query) {
      let text = conversion.display
      return [
        ThunderResult(id: "conv:\(query)", kind: .conversion, title: text,
          subtitle: "\(ThunderCalculator.format(conversion.value)) \(conversion.from)", symbol: "arrow.left.arrow.right",
          action: .copy(ThunderCalculator.format(conversion.result)))
      ]
    }
    if let value = ThunderCalculator.evaluate(query) {
      let text = ThunderCalculator.format(value)
      return [
        ThunderResult(id: "calc:\(query)", kind: .calculator, title: text, subtitle: query, symbol: "equal.circle.fill",
          action: .copy(text))
      ]
    }
    return []
  }

  private static func quicklinkRows(for query: String, _ links: [ThunderQuicklink]) -> [ThunderResult] {
    links.compactMap { link in
      guard let argument = link.query(from: query), let url = ThunderQuicklink.expand(link.template, query: argument)
      else { return nil }
      return ThunderResult(
        id: "ql:\(link.id)", kind: .quicklink, title: argument.isEmpty ? link.name : "\(link.name): \(argument)",
        subtitle: url.host ?? url.absoluteString, symbol: "link", action: .open(url))
    }
  }

  private static func webRow(_ query: String, _ template: String) -> ThunderResult? {
    guard let url = ThunderQuicklink.expand(template, query: query) else { return nil }
    return ThunderResult(
      id: "web:\(query)", kind: .web, title: "Search the web for “\(query)”", subtitle: url.host ?? "",
      symbol: "globe", action: .open(url))
  }

  private static func abbreviated(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
  }
}
