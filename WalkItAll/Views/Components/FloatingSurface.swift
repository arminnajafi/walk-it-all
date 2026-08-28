import SwiftUI

extension View {
    @ViewBuilder
    func walkItAllContentSurface(cornerRadius: CGFloat = 24) -> some View {
        self.background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    @ViewBuilder
    func walkItAllControlSurface(cornerRadius: CGFloat = 18) -> some View {
        self.background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
