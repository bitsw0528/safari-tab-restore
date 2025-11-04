import Foundation

/// Parsed representation of a recently closed window entry from Safari's plist.
struct WindowRecord {
    let title: String
    let closedDate: Date?
    let tabs: [TabRecord]
}

/// Parsed representation of a single tab entry recovered from the plist.
struct TabRecord: Hashable {
    let url: String
    let title: String?
}

/// Keys that frequently contain useful URLs in Safari's plist.
private let prioritizedURLKeys: [String] = [
    "TabURL",
    "URL",
    "URLString",
    "TabURLString",
    "HistoryURL",
    "LastVisitedURL"
]

/// Absolute path to Safari's RecentlyClosedTabs.plist for the current user.
let safariRecentlyClosedTabsPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent("Library/Safari/RecentlyClosedTabs.plist").path
}()

/// Loads and deserializes the plist into memory.
func readPlistRoot(_ path: String) throws -> Any {
    let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
}

/// Traverses the plist to collect window-level records with their tabs and timestamps.
func extractWindowRecords(from root: Any) -> [WindowRecord] {
    guard let dict = root as? [String: Any] else { return [] }
    guard let items = dict["ClosedTabOrWindowPersistentStates"] as? [Any] else { return [] }

    var result: [WindowRecord] = []

    for (index, item) in items.enumerated() {
        guard let itemDict = item as? [String: Any] else { continue }
        let tabs = collectTabs(inItem: itemDict)
        guard !tabs.isEmpty else { continue }
        let title = guessWindowTitle(for: itemDict, fallbackIndex: index)
        let closedDate = extractClosedDate(for: itemDict)
        result.append(WindowRecord(title: title, closedDate: closedDate, tabs: tabs))
    }

    return result
}

/// Collects all of the tab records that belong to a plist entry for a single window.
func collectTabs(inItem itemDict: [String: Any]) -> [TabRecord] {
    if let persistent = itemDict["PersistentState"] as? [String: Any] {
        let fromTabStates = collectTabsFromTabStates(persistent)
        if !fromTabStates.isEmpty {
            return deduplicateTabs(fromTabStates)
        }

        let fallback = collectTabsGeneric(persistent)
        if !fallback.isEmpty {
            return deduplicateTabs(fallback)
        }
    }

    return deduplicateTabs(collectTabsGeneric(itemDict))
}

/// Specialized collector that understands Safari's `TabStates` structure.
func collectTabsFromTabStates(_ persistentState: [String: Any]) -> [TabRecord] {
    guard let tabStates = persistentState["TabStates"] as? [Any] else { return [] }
    var tabs: [TabRecord] = []

    for tabState in tabStates {
        if let record = tabRecord(from: tabState) {
            tabs.append(record)
        } else {
            tabs.append(contentsOf: collectTabsGeneric(tabState))
        }
    }

    return tabs
}

/// Attempts to convert a loosely typed dictionary into a `TabRecord`.
func tabRecord(from tabState: Any) -> TabRecord? {
    guard let dict = tabState as? [String: Any] else { return nil }
    guard let url = firstURL(in: dict) else { return nil }
    let title = extractTitle(from: dict)
    return TabRecord(url: url, title: title)
}

/// Finds the first plausible URL within a dictionary, searching key candidates first.
func firstURL(in dict: [String: Any]) -> String? {
    for key in prioritizedURLKeys {
        if let value = dict[key] as? String, isPlausibleURL(value) {
            return value
        }
    }

    for (_, value) in dict {
        if let nested = value as? [String: Any], let url = firstURL(in: nested) {
            return url
        } else if let array = value as? [Any] {
            for element in array {
                if let dict = element as? [String: Any], let url = firstURL(in: dict) {
                    return url
                }
            }
        } else if let stringValue = value as? String, isPlausibleURL(stringValue) {
            return stringValue
        }
    }

    return nil
}

/// Generic fallback that walks any plist structure to locate potential tab URLs.
func collectTabsGeneric(_ value: Any) -> [TabRecord] {
    var tabs: [TabRecord] = []

    if let dict = value as? [String: Any] {
        for (key, innerValue) in dict {
            if let stringValue = innerValue as? String {
                let lowerKey = key.lowercased()
                if lowerKey.contains("url"), isPlausibleURL(stringValue) {
                    let title = lowerKey.contains("title") ? sanitizeTitle(stringValue) : nil
                    tabs.append(TabRecord(url: stringValue, title: title))
                    continue
                }
            }
            tabs.append(contentsOf: collectTabsGeneric(innerValue))
        }
    } else if let array = value as? [Any] {
        for element in array {
            tabs.append(contentsOf: collectTabsGeneric(element))
        }
    }

    return tabs
}

/// Removes duplicate URLs while preserving the order in which they were found.
func deduplicateTabs(_ tabs: [TabRecord]) -> [TabRecord] {
    var seen = Set<String>()
    var result: [TabRecord] = []

    for tab in tabs {
        if !seen.contains(tab.url) {
            seen.insert(tab.url)
            result.append(tab)
        }
    }
    return result
}

/// Key names we have observed Safari using for closed timestamps.
private let closedDateKeyCandidates: [String] = [
    "LastClosedDate",
    "ClosedDate",
    "CloseDate",
    "DateClosed",
    "ClosedTimestamp",
    "TabCloseDate"
]

/// Attempts to locate a close date for a window by looking through common plist keys.
func extractClosedDate(for item: [String: Any]) -> Date? {
    for key in closedDateKeyCandidates {
        if let date = item[key] as? Date {
            return date
        }
    }

    if let persistent = item["PersistentState"] as? [String: Any] {
        for key in closedDateKeyCandidates {
            if let date = persistent[key] as? Date {
                return date
            }
        }
        if let date = findFirstDate(in: persistent) {
            return date
        }
    }

    return findFirstDate(in: item)
}

/// Recursively searches any plist value for the first `Date` it contains.
func findFirstDate(in value: Any) -> Date? {
    if let date = value as? Date {
        return date
    }
    if let dict = value as? [String: Any] {
        for (_, inner) in dict {
            if let date = findFirstDate(in: inner) {
                return date
            }
        }
    } else if let array = value as? [Any] {
        for element in array {
            if let date = findFirstDate(in: element) {
                return date
            }
        }
    }
    return nil
}

/// Picks a human-friendly title for a window entry, falling back to a numbered label.
func guessWindowTitle(for item: [String: Any], fallbackIndex: Int) -> String {
    var candidates: [String] = []

    if let persistent = item["PersistentState"] as? [String: Any] {
        if let overview = persistent["TabOverviewTitle"] as? String, !overview.isEmpty {
            candidates.append(overview)
        }
        if let windowTitle = persistent["WindowTitle"] as? String, !windowTitle.isEmpty {
            candidates.append(windowTitle)
        }
        if let tabStates = persistent["TabStates"] as? [Any] {
            for case let tabDict as [String: Any] in tabStates {
                if let title = extractTitle(from: tabDict) {
                    candidates.append(title)
                    break
                }
            }
        }
    }

    for key in ["TabTitle", "Title", "Name"] {
        if let value = item[key] as? String, !value.isEmpty {
            candidates.append(value)
        }
    }

    if let first = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        return sanitizeTitle(first)
    }

    return "Window \(fallbackIndex + 1)"
}

/// Extracts a plausible title string from a dictionary if one exists.
func extractTitle(from dict: [String: Any]) -> String? {
    let keys = ["TabTitle", "Title", "Name"]
    for key in keys {
        if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sanitizeTitle(value)
        }
    }
    return nil
}

/// Normalizes whitespace to keep window and tab titles compact.
private func sanitizeTitle(_ title: String) -> String {
    title
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

/// Uses simple heuristics to decide whether a string looks like a URL.
private func isPlausibleURL(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
        return true
    }
    if trimmed.hasPrefix("www.") {
        return true
    }
    return false
}
