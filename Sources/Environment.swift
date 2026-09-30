import Foundation
import IOKit
import IOKit.hid

struct ControllerDevice {
    let id: UInt64
    let name: String
}

enum SteamState: Equatable {
    case closed, normal(Int32), fixed(Int32), unknown(Int32)

    var pid: Int32? {
        switch self {
        case .closed: return nil
        case .normal(let pid), .fixed(let pid), .unknown(let pid): return pid
        }
    }
    var needsFix: Bool {
        switch self { case .closed, .normal: return true; default: return false }
    }
    var label: String {
        switch self {
        case .closed: return "Steam closed"
        case .normal: return "Steam running · fix off"
        case .fixed: return "Steam running · fix on"
        case .unknown: return "Steam running · fix unknown"
        }
    }
}

enum HostEnvironment {
    static let steamExecutable = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx")

    /// Reads registry metadata only. Does not open a device or capture input.
    static func controllers() -> [ControllerDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [ControllerDevice] = []
        while true {
            let device = IOIteratorNext(iterator)
            guard device != 0 else { break }
            defer { IOObjectRelease(device) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(device, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard (property(kIOHIDVendorIDKey) as? NSNumber)?.intValue == 0x057e,
                  (property(kIOHIDProductIDKey) as? NSNumber)?.intValue == 0x2009 else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(device, &id) == KERN_SUCCESS else { continue }
            result.append(ControllerDevice(id: id, name: property(kIOHIDProductKey) as? String ?? "Switch Pro controller"))
        }
        return result.sorted { $0.id < $1.id }
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        // Drain before waiting: loaded-library listings can exceed pipe capacity.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func steamPID() -> Int32? {
        guard let result = try? run("/usr/bin/pgrep", ["-x", "steam_osx"]), result.status == 0 else { return nil }
        return result.output.split(separator: "\n").compactMap { Int32($0) }.first
    }

    static func steamState(pid: Int32) -> SteamState {
        guard let result = try? run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "txt", "-Fn"]), result.status == 0 else { return .unknown(pid) }
        let hasShim = result.output.split(separator: "\n").contains { $0.hasSuffix("/xbox-identity.dylib") }
        return hasShim ? .fixed(pid) : .normal(pid)
    }

    static func startSteam(shim: URL, swap: Bool) throws {
        let steam = Process()
        steam.executableURL = steamExecutable
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_INSERT_LIBRARIES"] = shim.path
        environment["X5_SWAP_FACE_BUTTONS"] = swap ? "1" : "0"
        environment.removeValue(forKey: "X5_IDENTITY_DEBUG")
        steam.environment = environment
        steam.standardOutput = FileHandle.nullDevice
        steam.standardError = FileHandle.nullDevice
        try steam.run()
    }

    static func restartAndStart(shim: URL, swap: Bool) throws {
        guard FileManager.default.isExecutableFile(atPath: steamExecutable.path) else {
            throw NSError(domain: "XboxHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Steam wasn't found. Open Steam normally once, quit it, then try again."])
        }
        guard FileManager.default.fileExists(atPath: shim.path) else {
            throw NSError(domain: "XboxHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "The helper's library is missing. Keep the complete app bundle together."])
        }
        if steamPID() != nil {
            let shutdown = Process()
            shutdown.executableURL = steamExecutable
            shutdown.arguments = ["-shutdown"]
            // Do not inherit injection into the short-lived shutdown client.
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
            shutdown.environment = environment
            shutdown.standardOutput = FileHandle.nullDevice
            shutdown.standardError = FileHandle.nullDevice
            try shutdown.run()
            // Do not block forever if Steam or the shutdown client hangs.
            let deadline = Date().addingTimeInterval(20)
            while steamPID() != nil && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            guard steamPID() == nil else {
                throw NSError(domain: "XboxHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "Steam hasn't finished closing. Quit Steam, then try again."])
            }
        }
        try startSteam(shim: shim, swap: swap)
    }
}
