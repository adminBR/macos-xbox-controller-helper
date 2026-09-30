import Foundation

/// One offer per controller connection. Declining an offer never loops.
struct PromptPolicy {
    private var offered = Set<UInt64>()

    mutating func reset() { offered.removeAll() }

    mutating func offer(enabled: Bool, controllerIDs: [UInt64], busy: Bool, needsFix: Bool = true) -> Bool {
        guard enabled else { reset(); return false }
        let connected = Set(controllerIDs)
        offered.formIntersection(connected)
        guard !busy else { return false }
        let newlyConnected = connected.subtracting(offered)
        guard !newlyConnected.isEmpty else { return false }
        offered.formUnion(newlyConnected)
        // Count a connection even when the fix is already active, so closing
        // Steam later does not turn that old connection into a new prompt.
        return needsFix
    }
}
