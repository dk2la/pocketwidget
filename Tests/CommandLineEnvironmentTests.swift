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
        let missing = try environment(shell: sandbox.appendingPathComponent("no-such-shell"))
        let silent = try environment(shell: silentShell())

        XCTAssertTrue(missing.folders.contains("/usr/bin"))
        XCTAssertEqual(missing.folders, silent.folders)
    }

    // MARK: - Fallback folders

    /// A shell that exits at once without answering.
    private func silentShell() throws -> URL {
        try script("silent-\(UUID().uuidString)", in: folder("shells"), "#!/bin/sh\nexit 1\n")
    }

    /// A home folder with node installed by nvm, fnm and pnpm, the way each
    /// of them lays it out by default on macOS.
    private struct NodeManagerHome {
        var home: URL
        var nvmOld: URL
        var nvmNew: URL
        var fnmDefault: URL
        var fnmVersion: URL
        var pnpm: URL
    }

    private func nodeManagerHome() throws -> NodeManagerHome {
        let home = try folder("home-\(UUID().uuidString)")
        func make(_ path: String) throws -> URL {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let fnmVersion = try make(".local/share/fnm/node-versions/v21.7.3/installation/bin")
        let aliases = try make(".local/share/fnm/aliases")
        // fnm's default alias is a link to one installation.
        try FileManager.default.createSymbolicLink(
            at: aliases.appendingPathComponent("default"),
            withDestinationURL: fnmVersion.deletingLastPathComponent()
        )
        return NodeManagerHome(
            home: home,
            nvmOld: try make(".nvm/versions/node/v9.11.2/bin"),
            nvmNew: try make(".nvm/versions/node/v22.3.0/bin"),
            fnmDefault: aliases.appendingPathComponent("default/bin"),
            fnmVersion: fnmVersion,
            pnpm: try make("Library/pnpm")
        )
    }

    func testShellThatDoesNotAnswerGivesTheFallbackFolders() throws {
        let fake = try nodeManagerHome()
        let commandLine = try environment(shell: hungShell(), home: fake.home, timeLimit: 0.5)

        let folders = commandLine.folders

        XCTAssertEqual(Array(folders.prefix(2)), ["/usr/bin", "/bin"], "the app's own PATH leads the fallback")
        for expected in [fake.nvmOld, fake.nvmNew, fake.fnmDefault, fake.fnmVersion, fake.pnpm] {
            XCTAssertTrue(folders.contains(expected.path), "missing \(expected.path)")
        }
        for usual in ["\(fake.home.path)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"] {
            XCTAssertTrue(folders.contains(usual), "missing \(usual)")
        }
        let old = try XCTUnwrap(folders.firstIndex(of: fake.nvmOld.path))
        let new = try XCTUnwrap(folders.firstIndex(of: fake.nvmNew.path))
        XCTAssertLessThan(new, old, "the newest node wins, and v22 is newer than v9")
        XCTAssertEqual(
            commandLine.path(for: URL(fileURLWithPath: "/apps/tools/codex")),
            (["/apps/tools"] + folders).joined(separator: ":"),
            "the program's own folder still comes first"
        )
    }

    func testEmptyOrUnusableShellAnswerGivesTheFallbackFolders() throws {
        let fake = try nodeManagerHome()
        let fallback = try environment(shell: silentShell(), home: fake.home).folders
        XCTAssertTrue(fallback.contains(fake.nvmNew.path))

        // Nothing at all, only separators, and only relative folders.
        for answer in ["", ":::", "bin:.:relative/folder"] {
            let commandLine = try environment(shell: fakeShell(path: answer), home: fake.home)
            XCTAssertEqual(commandLine.folders, fallback, "answer \"\(answer)\" is not usable")
        }
    }

    func testNodeManagerFoldersFollowTheirEnvironmentVariables() throws {
        let home = try folder("home-plain")
        let nvm = try folder("custom-nvm/versions/node/v20.0.0/bin")
        let fnm = try folder("custom-fnm/node-versions/v20.0.0/installation/bin")
        let pnpm = try folder("custom-pnpm")
        let xdgFnm = try folder("xdg/fnm/node-versions/v18.0.0/installation/bin")
        let commandLine = try environment(shell: silentShell(), home: home, variables: [
            "PATH": "/usr/bin",
            "NVM_DIR": sandbox.appendingPathComponent("custom-nvm").path,
            "FNM_DIR": sandbox.appendingPathComponent("custom-fnm").path,
            "PNPM_HOME": pnpm.path,
            "XDG_DATA_HOME": sandbox.appendingPathComponent("xdg").path,
        ])

        for expected in [nvm, fnm, pnpm, xdgFnm] {
            XCTAssertTrue(commandLine.folders.contains(expected.path), "missing \(expected.path)")
        }
    }

    func testProgramInstalledOnlyInANodeManagerFolderIsFound() throws {
        let fake = try nodeManagerHome()
        let nvm = try script("pocket-nvm-cli", in: fake.nvmNew, "#!/bin/sh\n")
        let fnm = try script("pocket-fnm-cli", in: fake.fnmVersion, "#!/bin/sh\n")
        let pnpm = try script("pocket-pnpm-cli", in: fake.pnpm, "#!/bin/sh\n")
        let commandLine = try environment(shell: silentShell(), home: fake.home)

        XCTAssertEqual(commandLine.locate("pocket-nvm-cli")?.path, nvm.path)
        XCTAssertEqual(
            commandLine.locate("pocket-fnm-cli")?.resolvingSymlinksInPath().path,
            fnm.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(commandLine.locate("pocket-pnpm-cli")?.path, pnpm.path)
    }

    /// "Found" and "can run" agree: with no help from the shell, a `codex`
    /// that npm put next to an nvm-installed `node` is both found and able
    /// to start, because both steps read the same list of folders.
    func testProgramFoundInFallbackFolderRunsWithFallbackPath() async throws {
        let fake = try nodeManagerHome()
        let tools = try folder("fallback-tools")
        try script("node", in: fake.nvmNew, "#!/bin/sh\nprintf '%s' \"$PATH\"\n")
        try script("codex", in: tools, "#!/usr/bin/env node\n")
        // The app's own PATH knows the program but not node, which only the
        // fallback folders can supply.
        let commandLine = try environment(
            shell: silentShell(),
            home: fake.home,
            variables: ["PATH": "\(tools.path):/usr/bin:/bin"]
        )
        let client = CLIAssistantClient(provider: .codex, model: "", commandLine: commandLine)

        XCTAssertTrue(client.isInstalled)
        let answer = try await client.send(system: "system", prompt: "prompt")

        XCTAssertEqual(answer, ([tools.path] + commandLine.folders).joined(separator: ":"))
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
