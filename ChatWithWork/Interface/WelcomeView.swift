import SwiftUI
import UIKit

/// The first screen: the logotype, one line on what this is, and the two
/// ways in.
struct WelcomeView: View {
    let host: String?
    let onSignIn: () -> Void
    let onSignUp: () -> Void

    var body: some View {
        ZStack {
            Color(Palette.canvas).ignoresSafeArea()
            DotGrid().ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 32)

                VStack(spacing: 20) {
                    Image("Logotype")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .accessibilityLabel("Chat with Work")

                    Text("Private AI search for your work.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color(Palette.inkMuted))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 32)

                VStack(spacing: 12) {
                    Button(action: onSignIn) {
                        Text("Sign in")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .primaryActionStyle()
                    .accessibilityIdentifier("welcome.signIn")

                    Button(action: onSignUp) {
                        Text("Create an account")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .secondaryActionStyle()
                    .accessibilityIdentifier("welcome.signUp")

                    if let host {
                        Text(host)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color(Palette.inkFaint))
                            .padding(.top, 8)
                            .accessibilityLabel("Server: \(host)")
                    }
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
}

/// Live Wire's dot grid, fading toward the bottom, as behind the web app's
/// new chat page.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let dot = CGSize(width: 2, height: 2)
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(origin: CGPoint(x: x - 1, y: y - 1), size: dot)), with: .color(Color(Palette.dot)))
                    x += spacing
                }
                y += spacing
            }
        }
        .mask(
            LinearGradient(
                colors: [.black, .black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func primaryActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(Color(Palette.ink))
                .foregroundStyle(Color(Palette.inkInverted))
                .controlSize(.large)
        } else {
            buttonStyle(.borderedProminent)
                .tint(Color(Palette.ink))
                .foregroundStyle(Color(Palette.inkInverted))
                .controlSize(.large)
        }
    }

    @ViewBuilder
    func secondaryActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
                .tint(Color(Palette.ink))
                .controlSize(.large)
        } else {
            buttonStyle(.bordered)
                .tint(Color(Palette.ink))
                .controlSize(.large)
        }
    }
}
