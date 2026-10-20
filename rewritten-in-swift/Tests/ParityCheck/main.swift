import Foundation
import SpeedRace

// Speed Race (1974) — Swift + Metal port.
//
// Test runner. `swift run parity-check` executes:
//   1. the ported unit tests (a 1:1 translation of the Rust `#[cfg(test)]`
//      modules in src/*.rs), and
//   2. the golden parity replay: seeded input scripts recorded from the
//      canonical Rust `Game` are replayed through the Swift `Game` and every
//      frame must agree bit for bit (fixtures in Fixtures/parity/).
//
// Exit status is non-zero if anything fails, so this is also the CI gate.
// See docs/INVESTIGATION-parity.md for what each suite proves.

/// Minimal assertion harness. Throws a `Failure` carrying a readable message
/// so the runner can report *every* failing case rather than stopping at the
/// first one.
struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition {
        throw Failure(message())
    }
}

func expectEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ context: @autoclosure () -> String
) throws {
    if actual != expected {
        throw Failure("\(context()): expected \(expected), got \(actual)")
    }
}

struct TestCase: @unchecked Sendable {
    let name: String
    let body: () throws -> Void
    init(_ name: String, _ body: @escaping @Sendable () throws -> Void) {
        self.name = name
        self.body = body
    }
}

enum ParityCheckMain {
    static func run() -> Never {
        // DIAG-PARITY: a single diag case can be run in isolation with
        // `parity-check --only <name>`, the smallest experiment for the
        // frame-0 mismatch investigation.
        let cases: [TestCase] =
            rngTests + roadTests + gameTests + rosterTests + renderTests + goldenTraceTests
        let filter =
            CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--only"
            ? CommandLine.arguments[2] : nil
        var failures: [(String, String)] = []
        for testCase in cases where filter == nil || testCase.name.contains(filter!) {
            do {
                try testCase.body()
                print("  ok    \(testCase.name)")
            } catch {
                let message = (error as? Failure)?.description ?? String(describing: error)
                failures.append((testCase.name, message))
                print("  FAIL  \(testCase.name)\n        \(message)")
            }
        }
        print("")
        print("\(cases.count - failures.count)/\(cases.count) checks passed")
        if !failures.isEmpty {
            print("\(failures.count) failure(s)")
            exit(1)
        }
        exit(0)
    }
}

// Top-level entry point: an executable target with top-level code (rather than
// `@main`) because the suites are declared as file-scope constants.
ParityCheckMain.run()
