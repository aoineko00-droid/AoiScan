//
//  TextStabilityAnalyzer.swift
//  AoiScan
//

import Foundation


struct TextStabilityAnalyzer {
    func similarity(
        baseline:String,
        candidate:String
    )->Float {
        let first = normalizedScalars(baseline)
        let second = normalizedScalars(candidate)
        let maximumCount = max(first.count, second.count)

        guard maximumCount > 0 else { return 1 }
        let distance = levenshteinDistance(first, second)
        return max(
            0,
            1 - Float(distance) / Float(maximumCount)
        )
    }

    private func normalizedScalars(_ text:String)->[UnicodeScalar] {
        let ignored = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)

        return text
            .lowercased()
            .unicodeScalars
            .filter { !ignored.contains($0) }
    }

    private func levenshteinDistance(
        _ first:[UnicodeScalar],
        _ second:[UnicodeScalar]
    )->Int {
        if first.isEmpty { return second.count }
        if second.isEmpty { return first.count }

        var previous = Array(0...second.count)
        var current = Array(repeating:0, count:second.count + 1)

        for firstIndex in first.indices {
            current[0] = firstIndex + 1

            for secondIndex in second.indices {
                let substitution = previous[secondIndex]
                    + (first[firstIndex] == second[secondIndex] ? 0 : 1)
                let insertion = current[secondIndex] + 1
                let deletion = previous[secondIndex + 1] + 1
                current[secondIndex + 1] = min(
                    substitution,
                    min(insertion, deletion)
                )
            }

            swap(&previous, &current)
        }

        return previous[second.count]
    }
}
