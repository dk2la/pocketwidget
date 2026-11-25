import Foundation
import OSLog

/// The command-line environment: the one place that decides which `PATH` the
/// `claude` and `codex` programs are found on and started with.
///
/// An app launched from Finder or at login gets a short system `PATH`, not
/// the one the person sees in a terminal. A program installed through npm
/// starts with `#!/usr/bin/env node`, so with the short `PATH` it dies with
/// `env: node: No such file or directory`. The person's login shell knows the
/// real `PATH`, so it is asked once per launch.
///
/// The shell, the home folder and the starting environment are injectable,
/// so tests never depend on the machine they run on.
final class CommandLineEnvironment: @unchecked Sendable {
    /// The environment of the running app: the account's shell and home.
    static let shared = CommandLineEnvironment()

    private static let log = Logger(subsystem: "com.dk2la.pocket", category: "assistant")

    private let shell: URL
    private let home: URL
    private let environment: [String: String]
    private let timeLimit: TimeInterval

    private let lock = NSLock()
    private var resolved: [String]?

    /// - Parameters:
    ///   - shell: the login shell to ask; `nil` means the one named in the
    ///     person's account.
    ///   - home: the person's home folder.
    ///   - environment: the variables the app itself was started with.
    ///   - timeLimit: seconds the shell gets to answer before it is stopped.
    init(
        shell: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeLimit: TimeInterval = 5
    ) {
        self.shell = shell ?? Self.accountShell(environment: environment)
        self.home = home
        self.environment = environment
        self.timeLimit = timeLimit
    }

    // MARK: - Interface

    /// The folders programs are looked up in, in order: the login shell's
    /// `PATH`, or the usual install folders when the shell gave no answer.
    ///
    /// The first call asks the shell and may take up to the time limit;
    /// every later call returns the remembered answer.
    var folders: [String] {
        lock.lock()
        defer { lock.unlock() }
        if let resolved { return resolved }
        let answer: [String]
        if let fromShell = readShellPath() {
            answer = fromShell
        } else {
            Self.log.info("login shell gave no PATH, using the usual folders")
            answer = usualFolders()
        }
        resolved = answer
        return answer
    }

    /// The `PATH` to start `executable` with: its own folder first, so the
    /// interpreter installed next to a program wins, then `folders`.
    func path(for executable: URL) -> String {
        ([executable.deletingLastPathComponent().path] + folders).joined(separator: ":")
    }

    /// Finds a program by name in `folders`.
    func locate(_ name: String) -> URL? {
        let manager = FileManager.default
        for folder in folders {
            let candidate = URL(fileURLWithPath: folder).appendingPathComponent(name)
            if manager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Usual folders

    /// Where command-line programs usually live, for when the shell is no
    /// help: the app's own `PATH`, then the common install folders.
    private func usualFolders() -> [String] {
        let home = home.path
        var folders = Self.entries(of: environment["PATH"] ?? "")
        folders += [
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nvm/versions/node/current/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ]
        return Self.withoutRepeats(folders)
    }

    // MARK: - Asking the shell

    /// The shell named in the person's account. `SHELL` is only a fallback:
    /// it is inherited, so it can name whatever shell started the app.
    private static func accountShell(environment: [String: String]) -> URL {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return URL(fileURLWithPath: path) }
        }
        if let path = environment["SHELL"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/bin/zsh")
    }

    /// Runs the shell as a login and interactive one, so the lines nvm, fnm
    /// and others add to shell profiles take effect, and returns the `PATH`
    /// it ends up with. `nil` when it does not answer in time or answers
    /// with nothing usable.
    private func readShellPath() -> [String]? {
        // Profiles print greetings and warnings, so the value is wrapped in
        // a marker no profile can know in advance.
        let marker = "__POCKET_PATH_\(UUID().uuidString)__"
        // The answer goes to a file, not a pipe. A pipe stays open for as
        // long as anything the profile started still holds it, and reading
        // it to the end would outlive the time limit.
        let answerFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("pocket-shell-path-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: answerFile.path, contents: nil),
              let answer = try? FileHandle(forWritingTo: answerFile)
        else { return nil }
        defer {
            try? answer.close()
            try? FileManager.default.removeItem(at: answerFile)
        }

        let process = Process()
        process.executableURL = shell
        process.arguments = ["-l", "-i", "-c", "/usr/bin/printf '%s%s%s' '\(marker)' \"$PATH\" '\(marker)'"]
        var variables = environment
        variables["HOME"] = home.path
        process.environment = variables
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = answer
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }
        if exited.wait(timeout: .now() + timeLimit) == .timedOut {
            // SIGKILL cannot be ignored or trapped by a profile. The short
            // second wait only lets the system finish collecting the shell.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = exited.wait(timeout: .now() + 2)
            return nil
        }

        guard let data = try? Data(contentsOf: answerFile) else { return nil }
        return Self.shellPath(in: String(decoding: data, as: UTF8.self), marker: marker)
    }

    /// The folders between the last pair of markers; `nil` when the markers
    /// are missing or hold no absolute folder.
    private static func shellPath(in output: String, marker: String) -> [String]? {
        guard let closing = output.range(of: marker, options: .backwards),
              let opening = output.range(
                  of: marker,
                  options: .backwards,
                  range: output.startIndex..<closing.lowerBound
              )
        else { return nil }
        let folders = entries(of: String(output[opening.upperBound..<closing.lowerBound]))
        return folders.isEmpty ? nil : folders
    }

    /// Splits a `PATH` value, keeping only absolute folders: an empty or
    /// relative entry means "the current folder", which is never wanted for
    /// a program started from a neutral one.
    private static func entries(of path: String) -> [String] {
        path.split(separator: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("/") }
    }

    private static func withoutRepeats(_ folders: [String]) -> [String] {
        var seen = Set<String>()
        return folders.filter { seen.insert($0).inserted }
    }
}
