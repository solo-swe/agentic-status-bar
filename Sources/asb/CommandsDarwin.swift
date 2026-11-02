import ArgumentParser
import ASBCore
import Foundation

// The commands' entry points: they hand the process's own environment, standard input and output,
// and terminal to the testable `run` overloads. Tests call those with a temporary home instead, since
// these would act on the real one.

extension HookCommand {
    func run() {
        run(input: .standardInput, environment: ProcessInfo.processInfo.environment)
    }
}

extension SnapshotCommand {
    func run() throws {
        FileHandle.standardOutput.write(try output(environment: ProcessInfo.processInfo.environment))
    }
}

extension ActionCommand {
    func run() {
        run(environment: ProcessInfo.processInfo.environment)
    }
}

extension InstallCommand {
    func run() throws {
        try run(Setup.installer())
    }
}

extension UninstallCommand {
    func run() throws {
        let installer = Setup.installer()
        try run(installer, confirmPurge: {
            Self.askToPurge(installer, onTerminal: isatty(0) == 1,
                            prompt: { print($0, terminator: "") }, answer: { readLine() })
        })
    }
}
