//
//  LearnView.swift.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import SwiftUI

struct LearnView: View {
    @State private var expanded: Set<LearnSection.ID> = []
    @State private var showOnboarding = false
    @Binding var deepLink: LearnDeepLink?

    private func expandTopic(_ topic: LearnTopic) {
        for sec in topic.sections {
            expanded.insert(sec.id)
        }
    }
    
    private func toggle(_ sec: LearnSection) {
        if expanded.contains(sec.id) { expanded.remove(sec.id) }
        else { expanded.insert(sec.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(LearnTopic.allCases, id: \.self) { topic in
                    Section(topic.rawValue) {
                        ForEach(topic.sections) { sec in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expanded.contains(sec.id) },
                                    set: { newValue in
                                        if newValue { expanded.insert(sec.id) }
                                        else { expanded.remove(sec.id) }
                                    }
                                )
                            ) {
                                Text(sec.body)
                                    .font(.body)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .padding(.top, 6)
                            } label: {
                                Text(sec.title)
                                    .font(.headline)
                                    .contentShape(Rectangle())
                                    .onTapGesture { toggle(sec) }
                            }
                        }
                    }
                }

                // Added website link section
                Section {
                    HStack {
                        Spacer()
                        Button("View Getting Started") {
                            showOnboarding = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.breathTeal)
                        Spacer()
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Link("For more information, visit InteroHB.com", destination: URL(string: "https://www.InteroHB.com")!)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.breathTeal)
                        Spacer()
                    }
                }
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                }
            }
            .onChange(of: deepLink) { _, link in
          
                guard let link else { return }
                switch link {
                case .interoception:
                    expandTopic(.interoception)
                case .estimatingHB:
                    expandTopic(.estimatingHB)
                case .awareness:
                    expandTopic(.awareness)
                }
                DispatchQueue.main.async { deepLink = nil }
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(marksAsSeen: false, showsDismissButton: true)
            }
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
    }
}
