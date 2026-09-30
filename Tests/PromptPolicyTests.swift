import Foundation

@main struct PromptPolicyTests {
    static func main() {
        var policy = PromptPolicy()
        func offer(_ enabled: Bool = true, _ ids: [UInt64] = [42], _ busy: Bool = false, _ needsFix: Bool = true) -> Bool {
            policy.offer(enabled: enabled, controllerIDs: ids, busy: busy, needsFix: needsFix)
        }
        precondition(!offer(false), "Disabled detection must never prompt")
        precondition(!offer(true, []), "No controller must never prompt")
        precondition(!offer(true, [42], true), "Steam transitions must not trigger prompts")
        precondition(offer(), "Initial connection should offer to open Steam")
        precondition(!offer(), "Declined offer must not loop")
        precondition(!offer(), "Steam status changes alone must not repeat an offer")
        precondition(offer(true, [42, 43]), "An additional controller must be eligible")
        precondition(!offer(true, [43]), "Removing one controller must not trigger an offer for the other")
        precondition(!offer(true, []))
        precondition(offer(true, [43]), "Disconnect clears declined offers")
        precondition(!offer(false, [43]))
        precondition(offer(true, [43]), "Re-enabling detection allows an offer")
        policy.reset()
        precondition(!offer(true, [42], false, false), "Already fixed Steam must not prompt")
        precondition(!offer(true, [43], false, false), "Reconnecting with the fix active must remain silent")
        precondition(!offer(true, [43]), "Closing Steam alone must not prompt for an old connection")
        precondition(offer(true, [44]), "A new connection without the fix must prompt")
        print("PASS: connections, reconnects, multiple controllers, suppression, deduplication and active-fix detection")
    }
}
