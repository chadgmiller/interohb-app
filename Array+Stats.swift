//
//  Array+Stats.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/17.
//

import Foundation

extension Array where Element == Double {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }

    func variance() -> Double {
        guard let avg = average(), count > 1 else { return 0 }
        let v = map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(count)
        return v
    }
}
