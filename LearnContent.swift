//
//  LearnContent.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import Foundation

struct LearnReference: Identifiable, Hashable {
    let title: String
    let urlString: String

    var id: String { urlString }
}

struct LearnSection: Identifiable, Hashable {
    let id: UUID
    let title: String
    let body: String
    let references: [LearnReference]
    let note: String?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        references: [LearnReference] = [],
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.references = references
        self.note = note
    }
}

enum LearnContentStore {
    static let sourcesMethodology: [LearnSection] = [
        LearnSection(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777771")!,
            title: "Important disclaimer",
            body: """
InteroHB is designed for general wellness, self-awareness, and practice with in-app exercises. It is not a medical device, does not provide medical advice, and is not intended to diagnose, treat, cure, prevent, or monitor any disease or medical condition. Heart rate values are provided by the connected Bluetooth heart rate device.
"""
        ),
        LearnSection(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777772")!,
            title: "How InteroHB uses heart rate data",
            body: """
InteroHB uses heart rate values from a connected Bluetooth heart rate device during practice sessions. Heart rate can vary naturally based on movement, posture, breathing, stress, sleep, hydration, medication, fitness level, and other factors. InteroHB uses this information only to support reflection during in-app exercises.
"""
        ),
        LearnSection(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777773")!,
            title: "Sense methodology",
            body: """
Sense sessions compare the user's estimated heartbeat or heart rate with the measured value from the connected heart rate device. The resulting score is app-specific and reflects performance within the exercise only. It should not be interpreted as a clinical measurement or medical assessment.
"""
        ),
        LearnSection(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777774")!,
            title: "Flow methodology",
            body: """
Flow sessions help users observe how their heartbeat and heart rate change over a period of time. Flow-related scores are based on session patterns within the app, such as consistency, estimation accuracy, and changes observed during the exercise. These scores are app-specific and are intended only for wellness reflection and practice.
"""
        ),
        LearnSection(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777775")!,
            title: "Interoceptive Index methodology",
            body: """
The Interoceptive Index is an app-specific wellness score based on patterns across completed sessions, including heartbeat estimation accuracy, consistency over time, and session context. It is designed to summarize practice trends within InteroHB. It is not a medical score, diagnostic score, clinical assessment, or measure of disease risk.
"""
        ),
        LearnSection(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777776")!,
            title: "Sources",
            body: "These sources support general educational information about heart rate, Bluetooth heart rate data, and interoception research.",
            references: [
                LearnReference(
                    title: "American Heart Association — Target Heart Rates / Heart Rate Basics",
                    urlString: "https://www.heart.org/en/healthy-living/fitness/fitness-basics/target-heart-rates"
                ),
                LearnReference(
                    title: "CDC — Measuring Physical Activity Intensity",
                    urlString: "https://www.cdc.gov/physical-activity-basics/measuring/index.html"
                ),
                LearnReference(
                    title: "Bluetooth SIG — Heart Rate Service Specification",
                    urlString: "https://www.bluetooth.com/specifications/specs/heart-rate-service-1-0/"
                ),
                LearnReference(
                    title: "Garfinkel et al. — Interoceptive dimensions across cardiac and respiratory axes",
                    urlString: "https://royalsocietypublishing.org/doi/10.1098/rstb.2016.0014"
                ),
                LearnReference(
                    title: "Brener & Ring — Towards a psychophysics of interoceptive processes",
                    urlString: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5062103/"
                ),
                LearnReference(
                    title: "Kandasamy et al. — Interoceptive Ability Predicts Survival on a London Trading Floor",
                    urlString: "https://www.nature.com/articles/srep32986"
                )
            ],
            note: "InteroHB's in-app scores are proprietary, app-specific wellness scores and are not clinical or diagnostic measures."
        )
    ]

    static let interoception: [LearnSection] = [
        LearnSection(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                     title: "What is interoception?",
                     body: """
Interoception is the awareness of internal body signals, such as heartbeat, breathing, temperature, and emotions.

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
1) Practice Sense
2) View the measured heart-rate reference
3) See the difference between the two
4) Track sessions over time
5) Practice Flow sessions

These features are designed for general wellness, self-observation, and educational use.
"""),
        LearnSection(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                     title: "Two areas of practice",
                     body: """
Sense: noticing and counting your heartbeat then comparing it with a measured heart-rate reference
Flow: noticing your heartbeat change over time and comparing it with the measured heart-rate reference
"""),
        LearnSection(id: UUID(uuidString: "22222222-2222-2222-2222-222222222223")!,
                     title: "Why there is a short cooldown",
                     body: """
After you submit a Sense session or begin a new Flow session, InteroHB uses a short cooldown before another entry can start.

The goal is to keep your practice history cleaner by separating distinct attempts instead of stacking repeated back-to-back entries that do not add much useful information.

Think of it as a brief reset period between practice sessions rather than a penalty.
""")
    ]

    static let estimatingHB: [LearnSection] = [
        LearnSection(id: UUID(uuidString: "33333333-3333-3333-3333-333333333331")!,
                     title: "How to notice your heartbeat",
                     body: """
• sit still for a moment before you begin
• notice where the heartbeat feels easiest to sense, such as the chest, throat, or torso
• relax your jaw, shoulders, and hands so body tension does not mask the sensation
• let your breathing settle instead of forcing a deeper breath
• wait briefly for a clearer internal pulse sensation before you start counting
"""),
        LearnSection(id: UUID(uuidString: "33333333-3333-3333-3333-333333333332")!,
                     title: "Counting tips",
                     body: """
• count each heartbeat once in a steady rhythm
• avoid rushing to a number before the sensation feels clear
• if you lose track, pause and restart instead of guessing
• try not to hold your breath while counting
• keep your attention on the internal sensation rather than repeating a familiar number
"""),
        LearnSection(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                     title: "A simple Sense routine",
                     body: """
Take one slow inhale and a longer exhale.
Wait for the heartbeat sensation to feel clearer.
Then count carefully and enter your best estimate.

This can create a steadier moment for Sense.
""")
    ]

    static let awareness: [LearnSection] = [
        LearnSection(id: UUID(uuidString: "44444444-4444-4444-4444-444444444441")!,
                     title: "How to observe change over time",
                     body: """
• breathe comfortably
• stay still if possible
• relax your jaw and shoulders so changes in heartbeat feel easier to notice
• pay attention to whether the heartbeat feels faster, slower, stronger, or softer as time passes
• reduce distractions so you can notice gradual shifts
• stay gentle and avoid trying to force the heartbeat to change
"""),
        LearnSection(id: UUID(uuidString: "44444444-4444-4444-4444-444444444442")!,
                     title: "If Flow feels unclear",
                     body: """
Try one change at a time:
1) adjust your posture
2) reduce distractions
3) shorten the session and focus only on whether the heartbeat is changing
4) choose a quieter environment
5) compare the beginning of the session with the end instead of judging every second

You can note what helped you track heartbeat changes more clearly in different situations.
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
    case sourcesMethodology = "Sources & Methodology"
    case interoception = "Interoception"
    case howItWorks = "How It Works"
    case estimatingHB = "Sense"
    case awareness = "Flow"
    case calibration = "Calibration"
    case safety = "Important"

    var id: String { rawValue }

    var sections: [LearnSection] {
        switch self {
        case .sourcesMethodology: return LearnContentStore.sourcesMethodology
        case .interoception: return LearnContentStore.interoception
        case .howItWorks:    return LearnContentStore.howItWorks
        case .estimatingHB:  return LearnContentStore.estimatingHB
        case .awareness:      return LearnContentStore.awareness
        case .calibration:   return LearnContentStore.calibration
        case .safety:        return LearnContentStore.safety
        }
    }
}
