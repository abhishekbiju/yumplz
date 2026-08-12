import Foundation
import SwiftData

/// A single instruction in a Recipe. See `Step`, `Timer Duration`,
/// and `Section Header` in CONTEXT.md.
@Model
final class Step {
    var id: UUID = UUID()
    var text: String = ""
    var orderIndex: Int = 0

    /// Timer Duration, in seconds, auto-detected on import. Nil = no timer.
    var timerSeconds: Int?

    /// When true, this Step renders as a label rather than a cookable instruction
    /// (e.g. "For the dough"). Skipped in Cook Mode's step-by-step navigation.
    var isSectionHeader: Bool = false

    var recipe: Recipe?

    init(text: String, orderIndex: Int = 0, timerSeconds: Int? = nil, isSectionHeader: Bool = false) {
        self.text = text
        self.orderIndex = orderIndex
        self.timerSeconds = timerSeconds
        self.isSectionHeader = isSectionHeader
    }
}
