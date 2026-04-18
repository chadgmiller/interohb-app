//
//  LearnContent.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import Foundation

struct LearnSection: Identifiable, Hashable {
    let id: UUID
    let title: String
    let body: String

    init(id: UUID = UUID(), title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

enum LearnContentStore {
    static let interoception: [LearnSection] = [
        LearnSection(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                     title: "What is interoception?",
                     body: """
Interoception is the awareness of internal body signals, such as heartbeat, breathing, temperature, and muscle tension.

It can be part of how people notice bodily sensations in everyday life.

This app uses heartbeat perception as one area of wellness and educational practice.
"""),
        LearnSection(id: UUID(uuidString: "11111111-1111-1111-1111-111111111112")!,
                     title: "Why it can be useful",
                     body: """
Practicing body awareness may help users become more familiar with how their body feels in different situations.

The goal of this app is to support observation, reflection, and general wellness practice over time.
""")
    ]

    static let howItWorks: [LearnSection] = [
        LearnSection(id: UUID(uuidString: "22222222-2222-2222-2222-222222222221")!,
                     title: "The process",
                     body: """
1) Estimate your heartbeat
2) View the measured heart-rate reference
3) See the difference between the two
4) Track sessions over time
5) Practice heartbeat awareness sessions

These features are designed for general wellness, self-observation, and educational use.
"""),
        LearnSection(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                     title: "Two areas of practice",
                     body: """
Heartbeat Estimate: estimating your heartbeat and comparing it with a measured heart-rate reference
Awareness Session: noticing your heartbeat during a session and comparing it with the measured heart-rate reference
""")
    ]

    static let estimatingHB: [LearnSection] = [
        LearnSection(id: UUID(uuidString: "33333333-3333-3333-3333-333333333331")!,
                     title: "Body cues to notice before estimating",
                     body: """
• breathing depth and rhythm
• warmth in the chest or face
• jaw or shoulder tension
• heartbeat sensations you may notice
• where the heartbeat feels easiest to notice
"""),
        LearnSection(id: UUID(uuidString: "33333333-3333-3333-3333-333333333332")!,
                     title: "Common habits to watch for",
                     body: """
• guessing too quickly
• estimating right after movement
• estimating while holding your breath
• choosing the same numbers out of habit
"""),
        LearnSection(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                     title: "A simple technique",
                     body: """
Take one slow inhale and a longer exhale.
Then estimate your heartbeat.

This can help create a steadier moment for the exercise.
""")
    ]

    static let awareness: [LearnSection] = [
        LearnSection(id: UUID(uuidString: "44444444-4444-4444-4444-444444444441")!,
                     title: "Awareness basics",
                     body: """
• breathe comfortably
• stay still if possible
• relax your jaw and shoulders
• reduce distractions if possible
• stay gentle and avoid forcing the exercise
"""),
        LearnSection(id: UUID(uuidString: "44444444-4444-4444-4444-444444444442")!,
                     title: "If the session feels difficult",
                     body: """
Try one change at a time:
1) adjust your posture
2) reduce distractions
3) lower mental effort
4) choose a quieter environment

You can note what felt most helpful in different situations.
""")
    ]

    static let calibration: [LearnSection] = [
        LearnSection(id: UUID(uuidString: "55555555-5555-5555-5555-555555555551")!,
                     title: "A simple practice plan",
                     body: """
Try a few short sessions in a stable setting, such as sitting calmly.

As you become familiar with the exercises, you can also try them in different situations, such as after activity or during a busy day.
"""),
        LearnSection(id: UUID(uuidString: "55555555-5555-5555-5555-555555555552")!,
                     title: "Practice over time",
                     body: """
Short, regular practice may be more helpful than doing long sessions only once in a while.

The app is designed to support gradual familiarity over time.
""")
    ]

    static let safety: [LearnSection] = [
        LearnSection(id: UUID(uuidString: "66666666-6666-6666-6666-666666666661")!,
                     title: "Important",
                     body: """
This app is for general wellness and educational purposes only.
It is not a medical device and does not diagnose, detect, monitor, treat, or prevent any condition.
If you have health concerns or symptoms, consult a qualified healthcare professional.
""")
    ]
}

enum LearnTopic: String, CaseIterable, Identifiable {
    case interoception = "Interoception"
    case howItWorks = "How It Works"
    case estimatingHB = "Estimating HB"
    case awareness = "Awareness"
    case calibration = "Calibration"
    case safety = "Important"

    var id: String { rawValue }

    var sections: [LearnSection] {
        switch self {
        case .interoception: return LearnContentStore.interoception
        case .howItWorks:    return LearnContentStore.howItWorks
        case .estimatingHB:  return LearnContentStore.estimatingHB
        case .awareness:      return LearnContentStore.awareness
        case .calibration:   return LearnContentStore.calibration
        case .safety:        return LearnContentStore.safety
        }
    }
}
