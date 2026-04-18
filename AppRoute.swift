//
//  AppRoute.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import Foundation
import Combine

enum LearnDeepLink: Hashable {
    case interoception
    case estimatingHB
    case awareness
}

final class AppRoute: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var learnLink: LearnDeepLink? = nil
}
