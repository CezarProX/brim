// ClipboardLinkCleaner.swift
// Brim
//
// Strips well-known tracking parameters from web links. The list is deliberately
// conservative: a parameter is removed only when it is pure tracking. Generic names
// that sites also use for real navigation (`ref`, `s`, `t`, `si`, `feature`) are
// removed on the specific hosts where they are known to be tracking only.

import Foundation

enum ClipboardLinkCleaner {
    /// Tracking parameters removed on every host (compared lowercased).
    static let globalParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "twclid", "ttclid",
        "yclid", "igshid", "igsh", "mc_eid", "mc_cid", "_hsenc", "_hsmi", "__hssc", "__hstc",
        "mkt_tok", "vero_id", "oly_enc_id", "oly_anon_id", "li_fat_id", "ref_src", "ref_url",
        "s_cid", "spm", "_ga", "_gl", "wickedid", "rb_clickid", "ck_subscriber_id",
    ]

    /// Parameters removed only on these hosts (and their subdomains).
    static let hostParameters: [(hosts: [String], names: Set<String>)] = [
        (["open.spotify.com", "spotify.link"], ["si", "context", "nd", "dlsi"]),
        (["youtube.com", "youtu.be", "music.youtube.com"], ["si", "pp"]),
        (["twitter.com", "x.com", "mobile.twitter.com"], ["s", "t"]),
        (["amazon.com", "amazon.co.uk", "amazon.de", "amazon.fr", "amazon.es", "amazon.it",
          "amazon.ca", "amazon.co.jp", "amazon.com.au"],
         ["ref", "ref_", "pf_rd_r", "pf_rd_p", "pf_rd_m", "pf_rd_s", "pf_rd_t", "pf_rd_i",
          "pd_rd_r", "pd_rd_w", "pd_rd_wg", "psc", "qid", "sr", "crid", "sprefix", "linkcode", "linkid"]),
        (["producthunt.com"], ["ref"]),
        (["medium.com"], ["source"]),
        (["linkedin.com"], ["trk", "trkinfo", "originalsubdomain", "midtoken", "midsig", "trackingid"]),
    ]

    /// Returns the link without tracking parameters. Text that is not a single web link is returned unchanged.
    static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ClipboardEntry.webURL(trimmed), let queryStart = trimmed.firstIndex(of: "?") else {
            return text
        }
        let host = (url.host ?? "").lowercased()
        let base = String(trimmed[..<queryStart])
        let afterQuery = trimmed[trimmed.index(after: queryStart)...]
        let fragmentStart = afterQuery.firstIndex(of: "#")
        let query = fragmentStart.map { afterQuery[..<$0] } ?? afterQuery[...]
        let fragment = fragmentStart.map { String(afterQuery[$0...]) } ?? ""
        let hostNames = hostParameters.filter { entry in
            entry.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }.reduce(into: Set<String>()) { $0.formUnion($1.names) }
        let kept = query.split(separator: "&", omittingEmptySubsequences: true).filter { pair in
            let name = String(pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
                .removingPercentEncoding?.lowercased() ?? ""
            if name.hasPrefix("utm_") || globalParameters.contains(name) || hostNames.contains(name) { return false }
            if name == "feature", pair.lowercased().hasSuffix("=share"), host.contains("youtu") { return false }
            return true
        }
        let rebuilt = kept.isEmpty ? base : base + "?" + kept.joined(separator: "&")
        return rebuilt + fragment
    }
}
