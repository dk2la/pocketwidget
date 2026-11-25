import AppKit
import OSLog

/// The real Mac behind assistant setup: what is installed, and Terminal.
/// Only presence is looked at — no other program's Keychain items or
/// sign-in files are read.
enum AssistantSetupSystem {
    private static let log = Logger(subsystem: "com.dk2la.pocket", category: "assistant")

    /// Looks for the two programs, the two desktop apps and the tools an
    /// install can use.
    @MainActor
    static func detect() async -> AssistantSetupFacts {
        let commandLine = CommandLineEnvironment.shared
        let hasClaudeApp = hasApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude")
        let hasChatGPTApp = hasApp(bundleID: "com.openai.chat", name: "ChatGPT")
        // Off the main actor: the first lookup after launch asks the login
        // shell for its PATH, which can take seconds.
        return await Task.detached {
            AssistantSetupFacts(
                claudePath: commandLine.locate("claude")?.path,
                codexPath: commandLine.locate("codex")?.path,
                hasClaudeApp: hasClaudeApp,
                hasChatGPTApp: hasChatGPTApp,
                hasCurl: commandLine.locate("curl") != nil,
                hasNode: commandLine.locate("npm") != nil,
                hasHomebrew: commandLine.locate("brew") != nil
            )
        }.value
    }

    @MainActor
    private static func hasApp(bundleID: String, name: String) -> Bool {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications/\(name).app", "\(home)/Applications/\(name).app"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Runs `script` in Terminal by opening it as a temporary `.command`
    /// file. Opening a file needs no Automation permission, unlike telling
    /// Terminal what to do through AppleScript. The script removes the file
    /// as its first step.
    @MainActor
    static func openTerminal(script: String) -> Bool {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pocket-\(UUID().uuidString.prefix(8)).command")
        do {
            try Data(script.utf8).write(to: file, options: .atomic)
            // Terminal refuses a `.command` file that is not executable.
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        } catch {
            log.error("could not write the setup script: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let opened = NSWorkspace.shared.open(file)
        if !opened {
            try? FileManager.default.removeItem(at: file)
            log.error("Terminal did not open the setup script")
        }
        return opened
    }
}
