//
//  Card.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/01.
//

import SwiftUI

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .padding()
            .background(AppColors.cardSurface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .padding(.bottom, 20)
    }
}
