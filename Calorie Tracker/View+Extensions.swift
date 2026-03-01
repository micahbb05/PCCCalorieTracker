import SwiftUI

extension View {
    func cardStyle(surface: Color, stroke: Color) -> some View {
        background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 8)
    }

    func inputStyle(surface: Color, text: Color, secondary: Color) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(text)
            .tint(text)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(secondary.opacity(0.35), lineWidth: 1)
            )
    }
}
