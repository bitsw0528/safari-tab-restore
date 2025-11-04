import AppKit

/// Errors that can occur while constructing or running the AppleScript that talks to Safari.
enum SafariOpenerError: LocalizedError {
    case scriptCreationFailed
    case scriptExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            return "Could not construct the AppleScript required to talk to Safari."
        case .scriptExecutionFailed(let message):
            return "Safari did not accept the request: \(message)"
        }
    }
}

/// Lightweight helper that asks Safari to reopen the selected URLs via AppleScript.
struct SafariOpener {
    /// Restores each requested window, making one AppleScript call per group of tabs.
    static func restore(groups: [WindowRestoreRequest]) throws {
        for group in groups {
            try openWindow(urls: group.urls)
        }
    }

    /// Builds and executes the AppleScript needed to recreate one Safari window.
    private static func openWindow(urls: [String]) throws {
        guard let first = urls.first else { return }

        var lines: [String] = []
        lines.append("tell application \"Safari\"")
        lines.append("    activate")
        lines.append("    make new document with properties {URL:\"\(escapeForAppleScript(first))\"}")

        let remaining = Array(urls.dropFirst())
        if !remaining.isEmpty {
            let listLiteral = remaining
                .map { "\"\(escapeForAppleScript($0))\"" }
                .joined(separator: ", ")
            lines.append("    tell front window")
            lines.append("        repeat with theURL in {\(listLiteral)}")
            lines.append("            make new tab at end of tabs with properties {URL:theURL}")
            lines.append("        end repeat")
            lines.append("    end tell")
        }

        lines.append("end tell")

        let scriptSource = lines.joined(separator: "\n")

        try execute(scriptSource)
    }

    /// Executes the generated AppleScript and surfaces any errors as Swift errors.
    private static func execute(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw SafariOpenerError.scriptCreationFailed
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if let errorInfo = errorInfo,
           let message = errorInfo[NSAppleScript.errorMessage] as? String {
            throw SafariOpenerError.scriptExecutionFailed(message)
        }
    }

    /// Escapes characters that would otherwise break an AppleScript string literal.
    private static func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
