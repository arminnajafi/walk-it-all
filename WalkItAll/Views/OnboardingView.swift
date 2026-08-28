import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: AppModel
    @State private var page = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.16), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button("Explore first") {
                                model.completeOnboarding(requestHealthAccess: false)
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .padding()

                        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 8 : 16)

                        Group {
                            if page == 0 {
                                valuePage
                                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                            } else {
                                healthPage
                                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 20)

                        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 12 : 20)

                        HStack(spacing: 8) {
                            Capsule()
                                .fill(page == 0 ? Color.indigo : Color.secondary.opacity(0.3))
                                .frame(width: page == 0 ? 24 : 8, height: 8)
                            Capsule()
                                .fill(page == 1 ? Color.indigo : Color.secondary.opacity(0.3))
                                .frame(width: page == 1 ? 24 : 8, height: 8)
                        }
                        .animation(reduceMotion ? nil : .snappy, value: page)
                        .accessibilityHidden(true)

                        Text("Step \(page + 1) of 2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)

                        action
                            .padding(24)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .interactiveDismissDisabled()
    }

    private var valuePage: some View {
        VStack(spacing: pageSpacing) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "map.fill")
                    .font(.system(size: 68, weight: .semibold))
                    .foregroundStyle(.indigo.gradient)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 12) {
                Text("See what you’ve covered.")
                    .font(pageTitleFont)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Turn the walks already in Apple Health into a lifetime map of Manhattan—then walk what remains.")
                    .font(pageBodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var healthPage: some View {
        VStack(spacing: pageSpacing) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 68, weight: .semibold))
                    .foregroundStyle(.red.gradient)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 12) {
                Text("Your history stays yours.")
                    .font(pageTitleFont)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Walk It All reads walking and hiking routes from Apple Health. Matching happens on this iPhone, with no account, ads, or tracking.")
                    .font(pageBodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("For future walks, record an outdoor walk with Apple Watch or another Health-compatible app that saves a route.", systemImage: "applewatch")
                .font(.subheadline)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var pageSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 12 : 24
    }

    private var pageTitleFont: Font {
        dynamicTypeSize.isAccessibilitySize ? .title.bold() : .largeTitle.bold()
    }

    private var pageBodyFont: Font {
        dynamicTypeSize.isAccessibilitySize ? .body : .title3
    }

    @ViewBuilder
    private var action: some View {
        if page == 0 {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { page = 1 }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        } else if #available(iOS 26.0, *) {
            Button {
                model.completeOnboarding(requestHealthAccess: true)
            } label: {
                Label("Connect Apple Health", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Button {
                model.completeOnboarding(requestHealthAccess: true)
            } label: {
                Label("Connect Apple Health", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
