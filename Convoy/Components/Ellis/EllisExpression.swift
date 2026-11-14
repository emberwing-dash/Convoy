import SwiftUI

// MARK: - Ellis Emotional Expressions & States
// Represents all 19 expressions and behavioural states for the mascot.
public enum EllisExpression: String, CaseIterable, Equatable {
    case idle           // Natural, relaxed expression (original artwork)
    case blink          // Single eyelid blink
    case doubleBlink    // Two rapid blinks
    case lookLeft       // Eyes glance to the left
    case lookRight      // Eyes glance to the right
    case lookUp         // Eyes glance upwards
    case headTilt       // Inquisitive look
    case listening      // Attentive wide eyes, ready for user input
    case thinking       // Thoughtful look up and sideways, pondering
    case speaking       // Subtle talking animation/sparkle
    case happy          // Joyful smiling eyes (^ ^)
    case excited        // Energetic star/sparkle eyes
    case surprised      // Wide round eyes (O O)
    case confused       // One raised brow, questioning look
    case angry          // Playful annoyed slanted eyes (\ /)
    case sleepy         // Drooping eyelids, relaxed
    case celebrating    // Radiant joyful celebration
    case pained         // Reaction to hard screen-edge collision (> <)
    case recovering     // Dazed soft blink settling back to normal

    /// Priority level for resolving competing animation triggers
    var priority: Int {
        switch self {
        case .pained:
            return 100 // Highest: impact reaction
        case .surprised, .recovering:
            return 90
        case .angry, .celebrating, .excited:
            return 80
        case .listening, .thinking, .speaking:
            return 70 // Conversation reactions
        case .happy, .confused, .sleepy:
            return 60
        case .lookLeft, .lookRight, .lookUp, .headTilt:
            return 40
        case .doubleBlink, .blink:
            return 20
        case .idle:
            return 0
        }
    }
}

