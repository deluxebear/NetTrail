import Darwin
import Foundation
import Testing
@testable import TraceCore

@Suite struct ProcessInspectorTests {
    private func procArgs(_ exec: String, _ argv: [String], env: [String] = ["HOME=/x"]) -> [UInt8] {
        var argc = Int32(argv.count)
        var bytes = withUnsafeBytes(of: &argc) { Array($0) }
        bytes += Array(exec.utf8) + [0, 0, 0, 0]
        for item in argv + env { bytes += Array(item.utf8) + [0] }
        return bytes
    }

    @Test func parsesProcArgsBuffer() {
        let args = ProcessInspector.parseProcArgs(procArgs("/usr/bin/curl", ["curl", "-s", "https://x.com"]))
        #expect(args == ["curl", "-s", "https://x.com"])
    }

    @Test func rejectsTruncatedProcArgs() {
        #expect(ProcessInspector.parseProcArgs([1, 0]) == nil)
        #expect(ProcessInspector.parseProcArgs(Array(procArgs("/bin/x", ["x", "y"]).prefix(12))) == nil)
    }

    @Test(arguments: [
        (["node", "/opt/app/server.js", "--port", "3000"], "/opt/app/server.js"),
        (["/usr/local/bin/node", "--require", "ts-node/register", "--inspect=9229", "src/main.ts"], "src/main.ts"),
        (["python3.12", "-u", "-m", "http.server"], "-m http.server"),
        (["Python", "/Users/a/tool.py"], "/Users/a/tool.py"),
        (["deno", "run", "--allow-net", "main.ts"], "main.ts"),
        (["bash", "/opt/deploy.sh", "prod"], "/opt/deploy.sh"),
    ])
    func extractsInterpreterScript(argv: [String], expected: String) {
        #expect(ProcessInspector.script(arguments: argv) == expected)
    }

    @Test(arguments: [
        ["node", "-e", "fetch('https://x.com?token=secret')"],
        ["python3", "-c", "import os"],
        ["zsh", "-c", "curl -H 'Authorization: x' https://x.com"],
        ["zsh", "-l"],
        ["curl", "https://x.com"],
        [],
    ])
    func ignoresInlineCodeAndNonInterpreters(argv: [String]) {
        #expect(ProcessInspector.script(arguments: argv) == nil)
    }

    @Test func inspectsOwnProcess() {
        let pid = getpid()
        #expect(ProcessInspector.executablePath(pid) != nil)
        #expect(ProcessInspector.arguments(pid: pid)?.isEmpty == false)
        #expect(!ProcessInspector.ancestors(of: pid).isEmpty)
        #expect(ProcessInspector.ancestors(of: pid).count <= ProcessInspector.maxAncestors)
        _ = ProcessInspector.origin(pid: pid)
    }

    @Test func missingProcessYieldsEmptyOrigin() {
        let origin = ProcessInspector.origin(pid: 99_999_999)
        #expect(origin == ProcessOrigin(responsiblePath: nil, ancestors: [], script: nil))
    }
}
