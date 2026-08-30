import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: AppModel
    @State private var page = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.15), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 16 : 56)
                        Group {
                            if page == 0 { valuePage } else { privacyPage }
                        }
                        .transition(reduceMotion ? .opacity : .move(edge: page == 0 ? .leading : .trailing).combined(with: .opacity))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)

                        Spacer(minLength: 24)
                        pageIndicator
                        Spacer(minLength: 16)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .safeAreaInset(edge: .bottom) {
            actions
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
        .interactiveDismissDisabled()
    }

    private var valuePage: some View {
        VStack(spacing: pageSpacing) {
            pageIcon("map.fill", color: .indigo)
            VStack(spacing: 12) {
                Text("See everywhere you’ve covered.")
                    .font(pageTitleFont)
                    .multilineTextAlignment(.center)
                Text("Walking, hiking, running, and cycling workouts from Apple Health become one private lifetime map.")
                    .font(pageBodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var privacyPage: some View {
        VStack(spacing: pageSpacing) {
            pageIcon("hand.raised.fill", color: .indigo)
            VStack(spacing: 12) {
                Text("Private by design.")
                    .font(pageTitleFont)
                    .multilineTextAlignment(.center)
                Text("Walk It All reads routes from Apple Health and prepares the map on this iPhone. There is no account, passive tracking, or route upload.")
                    .font(pageBodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Label(
                "Record an outdoor walk, hike, run, or ride with Apple Watch or another app that saves a GPS route to Health.",
                systemImage: "applewatch"
            )
            .font(.subheadline)
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func pageIcon(_ name: String, color: Color) -> some View {
        if !dynamicTypeSize.isAccessibilitySize {
            Image(systemName: name)
                .font(.system(size: 66, weight: .semibold))
                .foregroundStyle(color.gradient)
                .accessibilityHidden(true)
        }
    }

    private var pageIndicator: some View {
        VStack(spacing: 8) {
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
        }
    }

    @ViewBuilder
    private var actions: some View {
        if page == 0 {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { page = 1 }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            VStack(spacing: 10) {
                connectButton
                Button("Not now") {
                    model.completeOnboarding(requestHealthAccess: false)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        let button = Button {
            model.completeOnboarding(requestHealthAccess: true)
        } label: {
            Label("Connect Apple Health", systemImage: "heart.fill")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityIdentifier("onboarding-connect-health")
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private var pageSpacing: CGFloat { dynamicTypeSize.isAccessibilitySize ? 14 : 26 }
    private var pageTitleFont: Font { dynamicTypeSize.isAccessibilitySize ? .title.bold() : .largeTitle.bold() }
    private var pageBodyFont: Font { dynamicTypeSize.isAccessibilitySize ? .body : .title3 }
}
