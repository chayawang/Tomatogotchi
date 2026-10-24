import Foundation
import Darwin
import DesktopCore

@main
struct SessionChecks {
    static func require(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }
    static func child(_ mode: String, directory: URL) throws -> (Process, Pipe, Pipe) {
        let process = Process(), output = Pipe(), input = Pipe()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = [mode, directory.path]
        process.standardOutput = output
        process.standardInput = input
        try process.run()
        return (process, output, input)
    }
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            let lease = try SessionLease.acquire(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            guard let lease else { exit(23) }
            withExtendedLifetime(lease) {
                print("READY")
                fflush(stdout)
                if CommandLine.arguments[1] == "--hold" { _ = readLine() }
            }
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tomatogotchi-session-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pet = directory.appendingPathComponent("pet.json")
        let sentinel = Data("existing pet must remain untouched".utf8)
        try sentinel.write(to: pet)

        // A real child holds the lease while both this process and another child contend.
        let (owner, output, input) = try child("--hold", directory: directory)
        defer { if owner.isRunning { owner.terminate(); owner.waitUntilExit() } }
        require(String(data: output.fileHandleForReading.availableData, encoding: .utf8) == "READY\n", "Owner must acquire before contenders start")
        require(SessionLease.ownerProcessID(directory: directory) == owner.processIdentifier, "Metadata identifies owner")
        require(try SessionLease.acquire(directory: directory) == nil, "Parent must not take occupied lease")
        let (duplicate, duplicateOutput, _) = try child("--probe", directory: directory)
        duplicate.waitUntilExit()
        require(duplicate.terminationStatus == 23, "Second process must be rejected without blocking")
        require(duplicateOutput.fileHandleForReading.readDataToEndOfFile().isEmpty, "Secondary must not run primary work")
        require(owner.isRunning, "A secondary launch cannot terminate the owner")

        // Graceful release leaves the same lock file in place and permits a new owner.
        try input.fileHandleForWriting.write(contentsOf: Data("quit\n".utf8))
        owner.waitUntilExit()
        require(owner.terminationStatus == 0, "First owner exits normally")
        var next = try SessionLease.acquire(directory: directory)
        require(next != nil, "Lease must release when owner exits")
        require(try SessionLease.acquire(directory: directory) == nil, "Same-process duplicate also excluded")
        next = nil
        require(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".session.lock").path), "Never unlink lease file")

        // No cleanup handler is available after SIGKILL; the OS must release the lock.
        let (crashed, crashOutput, crashInput) = try child("--hold", directory: directory)
        require(String(data: crashOutput.fileHandleForReading.availableData, encoding: .utf8) == "READY\n", "Crash fixture acquired")
        require(kill(crashed.processIdentifier, SIGKILL) == 0, "Kill isolated helper")
        crashed.waitUntilExit()
        withExtendedLifetime(crashInput) {}
        var recovered = try SessionLease.acquire(directory: directory)
        require(recovered != nil, "Crash must not strand a lock or depend on stale PID")
        recovered = nil
        require(try Data(contentsOf: pet) == sentinel, "Session handling cannot mutate pet data")

        // Simultaneous launches must elect exactly one owner, rather than each
        // observing the others and all exiting as duplicates.
        let competitors = try (0..<3).map { _ in try child("--hold", directory: directory) }
        var winners = 0
        for (process, pipe, _) in competitors {
            let ready = pipe.fileHandleForReading.availableData
            if ready.isEmpty {
                process.waitUntilExit()
                require(process.terminationStatus == 23, "Contender must exit as secondary")
            } else {
                require(String(data: ready, encoding: .utf8) == "READY\n", "Unexpected contender output")
                winners += 1
            }
        }
        require(winners == 1, "Exactly one of simultaneous launches must survive")
        for (process, _, _) in competitors where process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        withExtendedLifetime(competitors) {}

        // An unwritable/non-directory location must fail closed, never pretend ownership.
        do {
            _ = try SessionLease.acquire(directory: pet)
            fatalError("Invalid data directory must throw")
        } catch { }
        print("PASS SessionChecks: cross-process exclusion, simultaneous election, owner metadata, secondary isolation, normal release, SIGKILL recovery, unchanged pet and storage failure")
    }
}
