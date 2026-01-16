import Foundation

class HistoryManager {
    private var history: [String] = []
    private var currentIndex: Int = -1
    private let maxItems = 3

    func add(_ text: String) {
        // Add to front, remove oldest if over limit
        history.insert(text, at: 0)
        if history.count > maxItems {
            history.removeLast()
        }
        // Reset index for cycling
        currentIndex = -1
    }

    func getNext() -> String? {
        guard !history.isEmpty else { return nil }

        currentIndex = (currentIndex + 1) % history.count
        return history[currentIndex]
    }

    func getAll() -> [String] {
        return history
    }

    func clear() {
        history.removeAll()
        currentIndex = -1
    }
}
