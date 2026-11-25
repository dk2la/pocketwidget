import XCTest

/// Every test builds its own shell, home folder and programs in a temporary
/// folder, so the machine's real shell profile and installs never decide the
/// outcome.
final class CommandLineEnvironmentTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        // Resolved up front: the programs under test report paths as the
        // kernel sees them (/private/var/…), not as Foundation spells them.
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        sandbox = root.appendingPathComponent("pocket-cli-env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    // MARK: - Fixtures

    private func folder(_ name: String) throws -> URL {
        let url = sandbox.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func script(_ name: String, in directory: URL, _ body: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// A stand-in login shell: behaves like a profile that sets `PATH` (and
    /// optionally prints things), then runs the command it was handed, the
    /// way `shell -l -i -c <command>` does.
    private func fakeShell(path: String, before: String = "", after: String = "") throws -> URL {
        try script("shell-\(UUID().uuidString)", in: folder("shells"), """
        #!/bin/sh
        \(before)
        PATH='\(path)'
        export PATH
        for command; do :; done
        eval "$command"
        \(after)
        """)
    }

    /// A shell that never answers. It records its process id first, so a test
    /// can check that it was really stopped.
    private func hungShell(pidFile: URL? = nil) throws -> URL {
        try script("hung-\(UUID().uuidString)", in: folder("shells"), """
        #!/bin/sh
        \(pidFile.map { "echo $$ > '\($0.path)'" } ?? "")
        exec /bin/sleep 30
        """)
    }

    private func environment(
        shell: URL,
        home: URL? = nil,
        variables: [String: String] = ["PATH": "/usr/bin:/bin"],
        timeLimit: TimeInterval = 10
    ) throws -> CommandLineEnvironment {
        CommandLineEnvironment(
            shell: shell,
            home: try home ?? folder("home"),
            environment: variables,
            timeLimit: timeLimit
        )
    }

    // MARK: - PATH from the login shell

    func testResolvedPathIsProgramFolderThenShellPath() throws {
        let shell = try fakeShell(path: "/fake/node/bin:/usr/bin:/bin")
        let commandLine = try environment(shell: shell)

        XCTAssertEqual(
            commandLine.path(for: URL(fileURLWithPath: "/apps/tools/codex")),
            "/apps/tools:/fake/node/bin:/usr/bin:/bin"
        )
    }

    func testShellPathSurvivesWhatProfilesPrint() throws {
        // Interactive profiles greet, warn and echo; none of it may leak
        // into the value, even text that looks like a PATH.
        let shell = try fakeShell(
            path: "/fake/node/bin:/usr/bin",
            before: "echo 'Welcome back!'; echo 'PATH=/wrong/one:/wrong/two'; echo oops >&2",
            after: "echo 'Goodbye /also/wrong'"
        )
        let commandLine = try environment(shell: shell)

        XCTAssertEqual(commandLine.folders, ["/fake/node/bin", "/usr/bin"])
    }

    func testShellIsAskedAtMostOnce() throws {
        let counter = sandbox.appendingPathComponent("asked")
        let shell = try fakeShell(path: "/fake/bin", before: "echo asked >> '\(counter.path)'")
        let commandLine = try environment(shell: shell)

        // Several callers at once, as happens when the setup form and a chat
        // turn both need the answer right after launch.
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            _ = commandLine.path(for: URL(fileURLWithPath: "/apps/claude"))
        }
        XCTAssertEqual(commandLine.folders, ["/fake/bin"])
        _ = commandLine.locate("claude")

        let asked = try String(contentsOf: counter, encoding: .utf8)
        XCTAssertEqual(asked.split(separator: "\n").count, 1)
    }

    func testHungShellIsStoppedAtTheTimeLimit() throws {
        let pidFile = sandbox.appendingPathComponent("shell.pid")
        let commandLine = try environment(shell: hungShell(pidFile: pidFile), timeLimit: 1)

        let started = Date()
        let folders = commandLine.folders
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 5, "the read must give up at its time limit, not wait for the shell")
        XCTAssertTrue(folders.contains("/usr/bin"), "a silent shell falls back to the usual folders")
        let pid = try XCTUnwrap(
            pid_t(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        )
        XCTAssertEqual(kill(pid, 0), -1, "the hung shell must not be left running")
    }

    func testMissingShellFallsBackToTheUsualFolders() throws {
        let commandLine = try environment(shell: sandbox.appendingPathComponent("no-such-shell"))

        XCTAssertTrue(commandLine.folders.contains("/usr/bin"))
    }

    // MARK: - Finding programs

    func testLocatesProgramInTheShellPath() throws {
        let tools = try folder("tools")
        let program = try script("pocket-fake-cli", in: tools, "#!/bin/sh\nexit 0\n")
        let commandLine = try environment(shell: fakeShell(path: "/nonexistent-dir:\(tools.path)"))

        XCTAssertEqual(commandLine.locate("pocket-fake-cli")?.path, program.path)
        XCTAssertNil(commandLine.locate("pocket-definitely-not-a-program"))
    }

    // MARK: - Regression: `env: node: No such file or directory`

    /// The reported bug. `codex` installed through npm starts with
    /// `#!/usr/bin/env node`; with the short PATH of an app launched from
    /// Finder, `env` could not find `node`. Here the interpreter exists only
    /// in a folder the login shell knows about.
    func testProgramsWhoseInterpreterIsOnlyOnTheShellPathRun() async throws {
        for provider in [AssistantProvider.claudeCode, .codex] {
            let name = try XCTUnwrap(provider.executableName)
            let programs = try folder("programs-\(name)")
            let interpreters = try folder("interpreters-\(name)")
            try script("pocket-fake-node", in: interpreters, "#!/bin/sh\nprintf '%s' \"$PATH\"\n")
            try script(name, in: programs, "#!/usr/bin/env pocket-fake-node\n")
            let shellPath = "\(interpreters.path):\(programs.path):/usr/bin:/bin"
            let commandLine = try environment(shell: fakeShell(path: shellPath))
            let client = CLIAssistantClient(provider: provider, model: "", commandLine: commandLine)

            // The fake interpreter answers with the PATH it was started with.
            let answer = try await client.send(system: "system", prompt: "prompt")

            XCTAssertEqual(answer, "\(programs.path):\(shellPath)", "\(name) must start with the resolved PATH")
        }
    }
}
