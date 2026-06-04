import Foundation

// MARK: - FuzzySearch

/// Lightweight fuzzy substring matcher used by inspector search fields.
///
/// Filtering semantics:
/// - An empty query returns the input unchanged.
/// - The query is matched character-by-character (in order, case-insensitive)
///   against the candidate string. Characters do not need to be contiguous.
/// - Candidates that don't contain every query character (in order) are dropped.
/// - Matches are scored so that contiguous, earlier matches rank higher; the
///   results are returned sorted by descending score, ties broken by the
///   candidate string for stable ordering.
enum FuzzySearch {

    /// Returns `items` filtered and ranked by a fuzzy match against `query`,
    /// using `key` to extract the searchable string for each item.
    static func filter<T>(
        _ items: [T],
        query: String,
        key: (T) -> String
    ) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let needle = Array(trimmed.lowercased())
        var scored: [(item: T, score: Int, text: String)] = []
        scored.reserveCapacity(items.count)

        for item in items {
            let text = key(item)
            if let score = match(needle: needle, haystack: text) {
                scored.append((item, score, text))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
        }

        return scored.map(\.item)
    }

    /// Returns a non-negative score if every needle character appears, in
    /// order, somewhere in `haystack` (case-insensitive). Higher is better.
    /// Returns `nil` if there is no match.
    private static func match(needle: [Character], haystack: String) -> Int? {
        let hay = Array(haystack.lowercased())
        var score = 0
        var haystackIndex = 0
        var lastMatch = -2
        var consecutive = 0

        // Strong bonus when the haystack contains the needle as a single
        // contiguous substring — typical "starts-with" / "contains" matches
        // should always rank above sparser fuzzy matches.
        if let range = haystack.range(of: String(needle), options: .caseInsensitive) {
            let distanceFromStart = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            score += 200 - min(distanceFromStart, 100)
        }

        for needleChar in needle {
            var found = false
            while haystackIndex < hay.count {
                let hayChar = hay[haystackIndex]
                haystackIndex += 1
                if hayChar == needleChar {
                    score += 10
                    if haystackIndex - 1 == lastMatch + 1 {
                        consecutive += 1
                        score += consecutive * 5
                    } else {
                        consecutive = 0
                    }
                    // Earlier matches are slightly better than later ones.
                    score -= min(haystackIndex - 1, 50) / 5
                    lastMatch = haystackIndex - 1
                    found = true
                    break
                }
            }
            if !found { return nil }
        }
        return score
    }
}
