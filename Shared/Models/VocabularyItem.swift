import Foundation
import SwiftData

@Model
final class VocabularyItem {
    var term: String
    var context: String?
    var createdAt: Date

    init(term: String, context: String? = nil) {
        self.term = term
        self.context = context
        self.createdAt = Date()
    }
}
