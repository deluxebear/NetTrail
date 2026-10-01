import Darwin
import Foundation

/// Reads how a live process was launched. Every lookup degrades to nil/empty when the process
/// is gone or the call is not permitted.
public enum ProcessInspector {
    public static let maxAncestors = 8
    static let maxScriptLength = 300

    public static func origin(pid: pid_t) -> ProcessOrigin {
        var responsiblePath: String?
        if let responsible = responsiblePID(pid), responsible > 0, responsible != pid {
            responsiblePath = executablePath(responsible)
        }
        return ProcessOrigin(responsiblePath: responsiblePath, ancestors: ancestors(of: pid),
                             script: arguments(pid: pid).flatMap(script(arguments:)))
    }

    public static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Executable names of `pid`'s parents, nearest first, stopping before launchd.
    public static func ancestors(of pid: pid_t) -> [String] {
        var names: [String] = []
        var current = pid
        while names.count < maxAncestors, let parent = parentPID(current), parent > 1, parent != current {
            guard let name = name(of: parent) else { break }
            names.append(name)
            current = parent
        }
        return names
    }

    static func parentPID(_ pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(bitPattern: info.pbi_ppid)
    }

    static func name(of pid: pid_t) -> String? {
        if let path = executablePath(pid) {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    // MARK: Responsible process

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// `responsibility_get_pid_responsible_for_pid` is SPI, so it is looked up at runtime.
    private static let responsibleFunction: ResponsibleFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    static func responsiblePID(_ pid: pid_t) -> pid_t? {
        responsibleFunction.map { $0(pid) }
    }

    // MARK: Code signing

    private typealias CsopsFunction = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32

    /// `csops` has no public header, so it is looked up at runtime.
    private static let csops: CsopsFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops") else { return nil }
        return unsafeBitCast(symbol, to: CsopsFunction.self)
    }()

    private static let csOpsIdentity: UInt32 = 11
    private static let csOpsTeamID: UInt32 = 14

    /// Signing identifier and team ID as the kernel recorded them at exec. Unlike the Security
    /// framework this reads no file, which the sandboxed extension often may not open.
    public static func signingIdentity(pid: pid_t) -> (signingID: String?, teamID: String?) {
        (csopsString(pid, csOpsIdentity), csopsString(pid, csOpsTeamID))
    }

    private static func csopsString(_ pid: pid_t, _ operation: UInt32) -> String? {
        guard let csops else { return nil }
        var buffer = [UInt8](repeating: 0, count: 1024)
        guard csops(pid, operation, &buffer, buffer.count) == 0 else { return nil }
        return blobString(buffer)
    }

    /// Payload of a csops blob: an 8-byte header (magic, length) then a NUL-terminated string.
    static func blobString(_ bytes: [UInt8]) -> String? {
        guard bytes.count > 8 else { return nil }
        let payload = bytes[8...].prefix { $0 != 0 }
        return payload.isEmpty ? nil : String(decoding: payload, as: UTF8.self)
    }

    // MARK: Arguments

    public static func arguments(pid: pid_t) -> [String]? {
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var argMaxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argMaxMIB, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(argMax))
        size = buffer.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcArgs(Array(buffer.prefix(size)))
    }

    /// Parses a `KERN_PROCARGS2` buffer: argc, the exec path, NUL padding, then argv (env follows, ignored).
    static func parseProcArgs(_ bytes: [UInt8]) -> [String]? {
        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc >= 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        while index < bytes.count, bytes[index] != 0 { index += 1 }   // exec path
        while index < bytes.count, bytes[index] == 0 { index += 1 }   // padding
        var args: [String] = []
        while args.count < argc {
            guard index < bytes.count, let end = bytes[index...].firstIndex(of: 0) else { return nil }
            args.append(String(decoding: bytes[index..<end], as: UTF8.self))
            index = end + 1
        }
        return args
    }

    // MARK: Interpreter scripts

    private static let interpreters: Set<String> = ["node", "bun", "deno", "python", "ruby", "perl", "php", "bash", "sh", "zsh", "osascript"]
    /// Flags whose argument is inline code: the code may hold secrets, so nothing is reported.
    private static let inlineCodeFlags: Set<String> = ["-e", "--eval", "-p", "--print", "-c"]
    /// Flags that consume the next argument, which is therefore not the script.
    private static let valueFlags: Set<String> = ["-r", "--require", "--import", "--loader", "--experimental-loader",
                                                  "--title", "-W", "-X", "-I"]

    /// The script or module an interpreter runs, e.g. `server.js` for `node --inspect server.js`.
    public static func script(arguments argv: [String]) -> String? {
        guard let first = argv.first else { return nil }
        let interpreter = URL(fileURLWithPath: first).lastPathComponent.lowercased()
        let base = interpreter.hasPrefix("python") ? "python" : interpreter
        guard interpreters.contains(base) else { return nil }
        var rest = argv.dropFirst()
        if base == "deno" || base == "bun", rest.first == "run" { rest = rest.dropFirst() }
        var skipNext = false
        var iterator = rest.makeIterator()
        while let arg = iterator.next() {
            if skipNext { skipNext = false; continue }
            if inlineCodeFlags.contains(arg) { return nil }
            if arg == "-m", base == "python" { return iterator.next().map { truncate("-m \($0)") } }
            if valueFlags.contains(arg) { skipNext = true; continue }
            if arg.hasPrefix("-") { continue }
            return truncate(arg)
        }
        return nil
    }

    private static func truncate(_ text: String) -> String {
        text.count > maxScriptLength ? String(text.prefix(maxScriptLength)) + "…" : text
    }
}
