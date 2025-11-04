import Foundation
import Combine

/// Observable object that loads and manages the recently closed Safari tabs state.
@MainActor
final class RestoreTabsViewModel: ObservableObject {
    /// Snapshot of the windows we found in Safari's RecentlyClosedTabs.plist.
    @Published private(set) var windows: [WindowSelection] = []
    /// Tracks which window disclosure groups should currently be expanded.
    @Published private var expandedWindowIDs: Set<UUID> = []
    /// Tracks which tab entries the user has selected for restoration.
    @Published private var selectedTabIDs: Set<UUID> = []

    /// Flags whether we are currently reading Safari's data from disk.
    @Published var isLoading: Bool = false
    /// Error to display when we cannot read or parse the Safari data.
    @Published var errorMessage: String?
    /// Success message describing the result of the last restore attempt.
    @Published var statusMessage: String?
    /// Error message describing why the most recent restore attempt failed.
    @Published var operationError: String?

    /// Callback to show warning dialog when too many tabs are selected.
    var showWarningCallback: (() -> Void)?

    private let plistPath = safariRecentlyClosedTabsPath
    /// Formats the closed timestamp into the short string shown next to each window.
    private lazy var closedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Convenience flag used to enable or disable actions that need a selection.
    var hasSelection: Bool {
        !selectedTabIDs.isEmpty
    }

    /// Indicates whether every tab in the current list is selected.
    var isFullySelected: Bool {
        let totalTabs = windows.reduce(0) { $0 + $1.tabs.count }
        return totalTabs > 0 && selectedTabIDs.count == totalTabs
    }

    /// Fetches Safari's recently closed tabs from disk and prepares the view state.
    func load() {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        operationError = nil

        // Reading the plist can be relatively expensive, so do it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let root = try readPlistRoot(self.plistPath)
                let records = extractWindowRecords(from: root)
                // Sort windows so that the newest closed window appears at the top of the list.
                let sortedRecords = records.enumerated().sorted { lhs, rhs in
                    switch (lhs.element.closedDate, rhs.element.closedDate) {
                    case let (lhsDate?, rhsDate?):
                        if lhsDate != rhsDate {
                            return lhsDate > rhsDate
                        }
                        // Fall back to the original order when the timestamps match.
                        return lhs.offset < rhs.offset
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    default:
                        return lhs.offset < rhs.offset
                    }
                }.map(\.element)

                let selections = sortedRecords.map { record in
                    WindowSelection(record: record)
                }
                DispatchQueue.main.async {
                    self.isLoading = false
                    if selections.isEmpty {
                        self.errorMessage = "No windows or tabs detected in the recently closed list."
                    } else {
                        self.windows = selections
                        self.expandedWindowIDs = Set(selections.map { $0.id })
                        self.selectedTabIDs.removeAll()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Failed to read RecentlyClosedTabs.plist: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Sends the selected tabs to Safari and reports success or failure.
    func restoreSelectedTabs() {
        operationError = nil
        statusMessage = nil

        let requests: [WindowRestoreRequest] = windows.compactMap { window in
            let selectedTabs = window.tabs.filter { selectedTabIDs.contains($0.id) }
            guard !selectedTabs.isEmpty else { return nil }
            return WindowRestoreRequest(title: window.header, urls: selectedTabs.map { $0.url })
        }

        guard !requests.isEmpty else {
            operationError = "Select at least one tab to restore."
            return
        }

        let windowCount = requests.count

        // Check if user is trying to open more than 10 windows.
        if windowCount > 10 {
            showWarningCallback?()
            return
        }

        performRestore(requests: requests)
    }

    /// Force restore tabs without warning (called from warning dialog).
    func forceRestoreSelectedTabs() {
        operationError = nil
        statusMessage = nil

        let requests: [WindowRestoreRequest] = windows.compactMap { window in
            let selectedTabs = window.tabs.filter { selectedTabIDs.contains($0.id) }
            guard !selectedTabs.isEmpty else { return nil }
            return WindowRestoreRequest(title: window.header, urls: selectedTabs.map { $0.url })
        }

        guard !requests.isEmpty else {
            operationError = "Select at least one tab to restore."
            return
        }

        performRestore(requests: requests)
    }

    /// Performs the actual tab restoration.
    private func performRestore(requests: [WindowRestoreRequest]) {
        do {
            try SafariOpener.restore(groups: requests)

            let tabCount = requests.reduce(0) { $0 + $1.urls.count }
            let windowCount = requests.count
            statusMessage = "Opened \(tabCount) tab\(tabCount == 1 ? "" : "s") across \(windowCount) window\(windowCount == 1 ? "" : "s")."
        } catch {
            operationError = "Unable to open selected tabs: \(error.localizedDescription)"
        }
    }

    /// Returns whether the given window should currently show its tab list.
    func isWindowExpanded(_ id: UUID) -> Bool {
        expandedWindowIDs.contains(id)
    }

    /// Updates the expanded/collapsed state for a specific window in the UI.
    func setWindowExpanded(_ id: UUID, expanded: Bool) {
        if expanded {
            expandedWindowIDs.insert(id)
        } else {
            expandedWindowIDs.remove(id)
        }
    }

    /// Determines whether a tab is currently selected.
    func isTabSelected(windowID: UUID, tabID: UUID) -> Bool {
        selectedTabIDs.contains(tabID)
    }

    /// Syncs the selection state between the checkbox UI and the model.
    func setTabSelected(windowID: UUID, tabID: UUID, isSelected: Bool) {
        if isSelected {
            selectedTabIDs.insert(tabID)
        } else {
            selectedTabIDs.remove(tabID)
        }
    }

    /// Checks whether all tabs belonging to a window are currently selected.
    func areAllTabsSelected(in windowID: UUID) -> Bool {
        guard let window = windows.first(where: { $0.id == windowID }) else { return false }
        guard !window.tabs.isEmpty else { return false }
        return window.tabs.allSatisfy { selectedTabIDs.contains($0.id) }
    }

    /// Selects or deselects every tab inside a specific window.
    func setAllTabs(in windowID: UUID, isSelected: Bool) {
        guard let window = windows.first(where: { $0.id == windowID }) else { return }
        if isSelected {
            for tab in window.tabs {
                selectedTabIDs.insert(tab.id)
            }
        } else {
            for tab in window.tabs {
                selectedTabIDs.remove(tab.id)
            }
        }
    }

    /// Returns a short summary (e.g., "2/5 selected") for the selection badge.
    func selectionSummary(for windowID: UUID) -> String {
        guard let window = windows.first(where: { $0.id == windowID }) else { return "" }
        let selectedCount = window.tabs.filter { selectedTabIDs.contains($0.id) }.count
        return "\(selectedCount)/\(window.tabs.count) selected"
    }

    /// Produces the label used for each window header in the list.
    func windowLabel(for windowID: UUID) -> String {
        guard let window = windows.first(where: { $0.id == windowID }) else { return "" }
        if let date = window.closedDate {
            return "Closed \(closedDateFormatter.string(from: date))"
        }
        return window.header
    }

    /// Selects every tab across every recovered window.
    func selectAll() {
        selectedTabIDs = Set(windows.flatMap { $0.tabs.map(\.id) })
    }

    /// Toggles between selecting everything and deselecting everything.
    func toggleSelectAll() {
        if isFullySelected {
            clearSelection()
        } else {
            selectAll()
        }
    }

    /// Clears the entire selection.
    func clearSelection() {
        selectedTabIDs.removeAll()
    }
}

/// UI-facing representation of a window's worth of recovered tabs.
struct WindowSelection: Identifiable {
    let id = UUID()
    let header: String
    let closedDate: Date?
    var tabs: [TabSelection]

    /// Convenience initializer to convert from the parsed data model.
    init(record: WindowRecord) {
        self.header = record.title
        self.closedDate = record.closedDate
        self.tabs = record.tabs.map { TabSelection(record: $0) }
    }
}

/// UI-facing representation of a single tab entry.
struct TabSelection: Identifiable, Hashable {
    let id = UUID()
    let title: String?
    let url: String

    /// Convenience initializer to convert from the parsed data model.
    init(record: TabRecord) {
        self.title = record.title
        self.url = record.url
    }

    /// Picks a readable label for the tab, preferring the title but falling back to host or URL.
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        if let host = URL(string: url)?.host {
            return host
        }
        return url
    }
}

/// Minimal payload describing what should be re-opened in Safari.
struct WindowRestoreRequest {
    let title: String
    let urls: [String]
}
