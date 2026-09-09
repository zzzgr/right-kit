import Darwin
import XCTest
@testable import RightKitShared

final class ScriptRunnerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RightKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func action(_ script: String) -> CustomAction {
        var action = CustomAction()
        action.title = "Test Script"
        action.language = .sh
        action.script = script
        action.timeoutSeconds = 5
        return action
    }

    private func run(_ action: CustomAction, inputs: [URL]? = nil, container: URL? = nil, secrets: [UUID: String] = [:],
                     cancelAfter: TimeInterval? = nil) throws -> ScriptRunSnapshot {
        let finished = expectation(description: "script finished")
        var result: ScriptRunSnapshot?
        let handle = ScriptRunner.start(action: action, in: ActionContext(targets: inputs ?? [directory], container: container ?? directory), secrets: secrets) {
            result = $0
            finished.fulfill()
        }
        if let cancelAfter { DispatchQueue.global().asyncAfter(deadline: .now() + cancelAfter) { handle.cancel() } }
        wait(for: [finished], timeout: 8)
        if result == nil { handle.cancel() }
        return try XCTUnwrap(result)
    }

    func testPathsWithUnicodeSpacesQuotesAndShellSyntaxStayLiteral() throws {
        let names = ["中文 ' space &.txt", "$(touch PWNED); `touch PWNED`.txt", "line\nbreak.txt"]
        let files = try names.map { name -> URL in
            let file = directory.appendingPathComponent(name)
            try Data().write(to: file)
            return file
        }
        let result = try run(action(#"printf '%s\0' "$@""#), inputs: files)
        XCTAssertEqual(result.state, .succeeded)
        XCTAssertEqual(result.stdout, files.map(\.path).joined(separator: "\0") + "\0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("PWNED").path))
    }

    func testWorkingDirectoryEnvironmentAndContextFile() throws {
        var action = action(#"printf '%s\n%s\n%s\n' "$PWD" "$TEST_VALUE" "$RIGHTKIT_INPUT_COUNT"; /bin/cat "$RIGHTKIT_CONTEXT_FILE""#)
        action.environment = [ScriptEnvironmentVariable(name: "TEST_VALUE", value: "value with ' & $()")]
        action.workingDirectory = .custom
        action.customWorkingDirectory = directory.path
        let result = try run(action)
        XCTAssertEqual(result.state, .succeeded)
        let lines = result.stdout.components(separatedBy: "\n")
        XCTAssertEqual(URL(fileURLWithPath: lines[0]).resolvingSymlinksInPath(), directory.resolvingSymlinksInPath())
        XCTAssertEqual(lines[1], "value with ' & $()")
        XCTAssertEqual(lines[2], "1")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines.dropFirst(3).joined(separator: "\n").utf8)) as? [String: Any])
        XCTAssertEqual(json["paths"] as? [String], [directory.path])
        XCTAssertEqual(json["invocationIndex"] as? Int, 1)
    }

    func testNonzeroExitAndStandardErrorAreReported() throws {
        let result = try run(action("printf 'out'; printf 'problem' >&2; exit 7"))
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.stdout, "out")
        XCTAssertEqual(result.stderr, "problem")
    }

    func testFinderWorkingDirectoryResolvesAFileTargetToItsParent() throws {
        let file = directory.appendingPathComponent("selected.txt")
        try Data().write(to: file)
        var action = action("/bin/pwd")
        action.workingDirectory = .finder
        let result = try run(action, inputs: [file], container: file)
        XCTAssertEqual(result.state, .succeeded)
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(URL(fileURLWithPath: path).resolvingSymlinksInPath(), directory.resolvingSymlinksInPath())
    }

    func testBothOutputPipesDrainAfterTheirRetentionLimit() throws {
        let script = #"""
        /usr/bin/awk 'BEGIN {for (i=0;i<400000;i++) printf "x"}' &
        /usr/bin/awk 'BEGIN {for (i=0;i<400000;i++) printf "e"}' >&2 &
        wait
        """#
        let result = try run(action(script))
        XCTAssertEqual(result.state, .succeeded)
        XCTAssertEqual(result.stdout.utf8.count, ScriptOutputBuffer.limit)
        XCTAssertEqual(result.stderr.utf8.count, ScriptOutputBuffer.limit)
        XCTAssertTrue(result.stdoutTruncated)
        XCTAssertTrue(result.stderrTruncated)
    }

    func testIndividualInvocationsStopAtFirstFailure() throws {
        let files = try ["one", "two", "three"].map { name -> URL in
            let file = directory.appendingPathComponent(name)
            try Data().write(to: file)
            return file
        }
        var action = action(#"printf '%s\n' "$1"; case "$1" in */two) exit 9;; esac"#)
        action.batchMode = .individually
        let result = try run(action, inputs: files)
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.exitCode, 9)
        XCTAssertEqual(result.totalInvocations, 3)
        XCTAssertEqual(result.completedInvocations, 2)
        XCTAssertEqual(result.stdout, files.prefix(2).map(\.path).joined(separator: "\n") + "\n")
    }

    func testCancellationKillsShellAndItsChildEvenWhenTermIsIgnored() throws {
        let result = try run(action("trap '' TERM\nsleep 30 &\nprintf '%s\\n' \"$!\"\nwait"), cancelAfter: 0.25)
        XCTAssertEqual(result.state, .cancelled)
        XCTAssertLessThan(result.duration, 3)
        try assertProcessExited(result.stdout)
    }

    func testTimeoutAppliesToTaskAndKillsChildren() throws {
        var action = action("sleep 30 &\nprintf '%s\\n' \"$!\"\nwait")
        action.timeoutSeconds = 1
        let result = try run(action)
        XCTAssertEqual(result.state, .timedOut)
        XCTAssertGreaterThanOrEqual(result.duration, 1)
        XCTAssertLessThan(result.duration, 3)
        try assertProcessExited(result.stdout)
    }

    func testTimeoutBudgetIsSharedAcrossIndividualInvocations() throws {
        let files = try ["one", "two", "three"].map { name -> URL in
            let file = directory.appendingPathComponent(name)
            try Data().write(to: file)
            return file
        }
        var action = action("sleep 0.6\nprintf 'done\\n'")
        action.timeoutSeconds = 1
        action.batchMode = .individually
        let result = try run(action, inputs: files)
        XCTAssertEqual(result.state, .timedOut)
        XCTAssertLessThan(result.completedInvocations, 3)
        XCTAssertLessThan(result.duration, 2.5)
    }

    func testBackgroundChildDoesNotOutliveCompletedShell() throws {
        let result = try run(action("sleep 30 &\nprintf '%s\\n' \"$!\""))
        XCTAssertEqual(result.state, .succeeded)
        XCTAssertLessThan(result.duration, 3)
        try assertProcessExited(result.stdout)
    }

    func testMissingInterpreterFailsWithoutTryingAShellFallback() throws {
        var action = action("print('should not run')")
        action.language = .python
        action.interpreterPath = directory.appendingPathComponent("missing-python").path
        let result = try run(action)
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.error, Strings.Custom.missingInterpreter)
        XCTAssertNil(result.exitCode)
    }

    func testExternalScriptReadsItsLatestContentsAndIsNotModified() throws {
        let file = directory.appendingPathComponent("external script.sh")
        try Data("printf first".utf8).write(to: file)
        var action = action("")
        action.source = .file
        action.scriptPath = file.path
        XCTAssertEqual(try run(action).stdout, "first")
        try Data("printf second".utf8).write(to: file)
        XCTAssertEqual(try run(action).stdout, "second")
        XCTAssertEqual(try String(contentsOf: file), "printf second")
    }

    func testSecretsAreRedactedFromBothStreams() throws {
        var action = action(#"printf 'token=%s' "$TOKEN"; printf '%s' "$TOKEN" >&2"#)
        let variable = ScriptEnvironmentVariable(name: "TOKEN", isSecret: true)
        action.environment = [variable]
        let result = try run(action, secrets: [variable.id: "private-value-中文"])
        XCTAssertEqual(result.state, .succeeded)
        XCTAssertEqual(result.stdout, "token=[REDACTED]")
        XCTAssertEqual(result.stderr, "[REDACTED]")
    }

    func testSecretSplitAcrossChunksIsNeverPublishedInPart() {
        let secret = "long-private-中文-value"
        var buffer = ScriptOutputBuffer()
        let bytes = Data(secret.utf8)
        buffer.append(Data("before ".utf8))
        for byte in bytes.dropLast() {
            buffer.append(Data([byte]))
            XCTAssertEqual(buffer.text(secrets: [secret], final: false), "before ")
        }
        buffer.append(Data(bytes.suffix(1)))
        XCTAssertEqual(buffer.text(secrets: [secret], final: true), "before [REDACTED]")
    }

    func testChangedRulesOrMissingInputsFailBeforeLaunchingScript() throws {
        let marker = directory.appendingPathComponent("should-not-exist")
        var action = action(#"touch "$1/should-not-exist""#)
        action.rules.target = .files
        XCTAssertEqual(try run(action).error, Strings.Custom.invalidSelection)
        action.rules.target = .both
        XCTAssertEqual(try run(action, inputs: [marker]).error, Strings.Custom.missingInput)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testOverlappingSecretsStayMaskedWhileOutputIsIncomplete() {
        var buffer = ScriptOutputBuffer()
        buffer.append(Data("abcde".utf8))
        XCTAssertEqual(buffer.text(secrets: ["abc", "abcdef"], final: false), "")
        buffer.append(Data("f".utf8))
        XCTAssertEqual(buffer.text(secrets: ["abc", "abcdef"], final: true), "[REDACTED]")
        var repeated = ScriptOutputBuffer()
        repeated.append(Data("ababab".utf8))
        XCTAssertEqual(repeated.text(secrets: ["abab"], final: true), "[REDACTED]")
    }

    private func assertProcessExited(_ output: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let pid = try XCTUnwrap(Int32(output.trimmingCharacters(in: .whitespacesAndNewlines)), file: file, line: line)
        for _ in 0..<50 {
            if kill(pid, 0) == -1 && errno == ESRCH { return }
            usleep(20_000)
        }
        XCTFail("Child process \(pid) survived task completion", file: file, line: line)
        kill(pid, SIGKILL)
    }
}
