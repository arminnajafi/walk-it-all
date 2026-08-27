import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
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

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Explore first") {
                        model.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding()

                Spacer()

                Group {
                    if page == 0 {
                        valuePage
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        healthPage
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                HStack(spacing: 8) {
                    Capsule()
                        .fill(page == 0 ? Color.indigo : Color.secondary.opacity(0.3))
                        .frame(width: page == 0 ? 24 : 8, height: 8)
                    Capsule()
                        .fill(page == 1 ? Color.indigo : Color.secondary.opacity(0.3))
                        .frame(width: page == 1 ? 24 : 8, height: 8)
                }
                .animation(.snappy, value: page)

                action
                    .padding(24)
            }
        }
        .interactiveDismissDisabled()
    }

    private var valuePage: some View {
        VStack(spacing: 24) {
            Image(systemName: "map.fill")
                .font(.system(size: 68, weight: .semibold))
                .foregroundStyle(.indigo.gradient)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("See what you’ve covered.")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Turn the walks already in Apple Health into a lifetime map of Manhattan—then walk what remains.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var healthPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 68, weight: .semibold))
                .foregroundStyle(.red.gradient)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("Your history stays yours.")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Walk It All reads walking and hiking routes from Apple Health. Matching happens on this iPhone, with no account, ads, or tracking.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Label("For future walks, start an Outdoor Walk workout on Apple Watch or iPhone.", systemImage: "applewatch")
                .font(.subheadline)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var action: some View {
        if page == 0 {
            Button("Continue") {
                withAnimation(.snappy) { page = 1 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        } else if #available(iOS 26.0, *) {
            Button {
                model.connectHealthAndImport()
                dismiss()
            } label: {
                Label("Connect Apple Health", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Button {
                model.connectHealthAndImport()
                dismiss()
            } label: {
                Label("Connect Apple Health", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

