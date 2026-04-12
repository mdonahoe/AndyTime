//
//  CrashReporter.swift
//  AndyTime2
//

import Foundation
import UIKit

// Pre-allocated C path buffer populated before any crash; used inside the signal
// handler where Swift allocation is unsafe.
private var _logPathBuf = [CChar](repeating: 0, count: 4096)

/// Catches uncaught exceptions and fatal signals and appends a report to
/// `Documents/crashes.txt`, which is accessible via iTunes / Files file sharing.
///
/// Call `CrashReporter.setup()` once in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
class CrashReporter {

    static let shared = CrashReporter()

    /// URL of the on-disk crash log.
    let crashLogURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        crashLogURL = docs.appendingPathComponent("crashes.txt")
    }

    // MARK: - Public API

    /// Install the uncaught-exception and signal handlers. Call once at app launch.
    static func setup() {
        // Copy the file path into a C buffer accessible from the signal handler.
        shared.crashLogURL.path.withCString { src in
            _ = strlcpy(&_logPathBuf, src, _logPathBuf.count)
        }

        // Objective-C / bridged Swift exceptions (e.g. NSInternalInconsistencyException).
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }

        // Fatal signals:
        //   SIGABRT → Swift fatalError / precondition / force-unwrap / array bounds
        //   SIGSEGV → null / bad pointer dereference
        //   SIGBUS  → misaligned memory access
        //   SIGILL  → illegal CPU instruction
        //   SIGTRAP → deliberate trap / breakpoint
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP] {
            signal(sig, crashSignalHandler)
        }

        print("[CrashReporter] Installed. Log: \(shared.crashLogURL.path)")
    }

    /// Returns the full text of the crash log, or nil if no crashes have been recorded.
    func readLog() -> String? {
        guard FileManager.default.fileExists(atPath: crashLogURL.path) else { return nil }
        return try? String(contentsOf: crashLogURL, encoding: .utf8)
    }

    /// Deletes the crash log file.
    func clearLog() {
        try? FileManager.default.removeItem(at: crashLogURL)
    }

    // MARK: - Internal

    func handleException(_ exception: NSException) {
        var lines: [String] = [
            "",
            "=== CRASH REPORT ===",
            "Date: \(Date())",
            "Type: Uncaught Exception",
            "Name: \(exception.name.rawValue)",
            "Reason: \(exception.reason ?? "(no reason)")",
            "Stack Trace:",
        ]
        lines += exception.callStackSymbols
        lines.append("")
        appendText(lines.joined(separator: "\n"))
    }

    func appendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: crashLogURL.path) {
            guard let fh = try? FileHandle(forWritingTo: crashLogURL) else { return }
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        } else {
            try? data.write(to: crashLogURL)
        }
    }
}

// MARK: - Signal Handler

// Must live at file scope (not inside a class) because signal() requires a C function pointer.
private func crashSignalHandler(_ signum: Int32) {
    // Phase 1: Write the signal name using only async-signal-safe POSIX I/O.
    //          No Swift runtime calls, no malloc.
    let fd = open(&_logPathBuf, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    if fd >= 0 {
        writeLiteral(fd, "\n=== CRASH REPORT ===\nType: Fatal Signal\n")
        switch signum {
        case SIGABRT: writeLiteral(fd, "Signal: SIGABRT (Abort — likely Swift fatalError / force-unwrap / bounds)\n")
        case SIGSEGV: writeLiteral(fd, "Signal: SIGSEGV (Segmentation Fault — bad pointer)\n")
        case SIGBUS:  writeLiteral(fd, "Signal: SIGBUS (Bus Error — misaligned access)\n")
        case SIGILL:  writeLiteral(fd, "Signal: SIGILL (Illegal Instruction)\n")
        case SIGTRAP: writeLiteral(fd, "Signal: SIGTRAP (Trap / Breakpoint)\n")
        default:      writeLiteral(fd, "Signal: unknown\n")
        }
        close(fd)
    }

    // Phase 2: Attempt a stack trace.
    //
    // For SIGABRT this is practical: Swift raises SIGABRT *after* the runtime
    // has already printed its message, so the heap and runtime are still intact.
    // For memory-corruption signals (SIGSEGV/SIGBUS) this may fail, but trying
    // doesn't make things worse — we've already written the signal name above.
    let stack = Thread.callStackSymbols
    let date = Date()
    let stackText = "Date: \(date)\nStack Trace:\n" + stack.joined(separator: "\n") + "\n"
    CrashReporter.shared.appendText(stackText)

    // Restore the default handler and re-raise so the OS crash reporter fires too.
    signal(signum, SIG_DFL)
    raise(signum)
}

/// Write a string literal to a file descriptor using only async-signal-safe syscalls.
private func writeLiteral(_ fd: Int32, _ s: StaticString) {
    s.withUTF8Buffer { buf in
        _ = Darwin.write(fd, buf.baseAddress, buf.count)
    }
}
