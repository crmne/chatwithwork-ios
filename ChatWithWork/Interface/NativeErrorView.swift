import HotwireNative
import SwiftUI

/// What a screen shows when its page can't load: what went wrong in plain
/// words, and a way to try again.
struct NativeErrorView: ErrorPresentableView {
    let error: HotwireNativeError
    let handler: ErrorPresenter.Handler?

    var body: some View {
        let copy = ErrorCopy(error)

        ZStack {
            Color(Palette.canvas).ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: copy.symbol)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Color(Palette.inkMuted))
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)

                Text(copy.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(Palette.ink))
                    .multilineTextAlignment(.center)

                Text(copy.message)
                    .font(.body)
                    .foregroundStyle(Color(Palette.inkMuted))
                    .multilineTextAlignment(.center)

                if let handler {
                    Button(action: handler) {
                        Text("Try again")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 8)
                    }
                    .retryStyle()
                    .padding(.top, 10)
                    .accessibilityIdentifier("error.retry")
                }
            }
            .frame(maxWidth: 360)
            .padding(32)
        }
    }
}

/// The words for each kind of failure.
struct ErrorCopy: Equatable {
    let symbol: String
    let title: String
    let message: String

    init(_ error: HotwireNativeError) {
        switch error {
        case .web(let web) where web.isOffline:
            symbol = "wifi.slash"
            title = String(localized: "You're offline")
            message = String(localized: "Chat with Work needs a connection to reach your workspace. Check your connection and try again.")
        case .web(let web) where web.isTimeout:
            symbol = "hourglass"
            title = String(localized: "This is taking too long")
            message = String(localized: "The server didn't answer in time. Try again in a moment.")
        case .web(let web) where web.isConnectionError || web.isSSLError:
            symbol = "network.slash"
            title = String(localized: "Can't reach Chat with Work")
            message = String(localized: "The server couldn't be reached. Check your connection and try again.")
        case .http(.client(.notFound)):
            symbol = "questionmark.folder"
            title = String(localized: "This page isn't here")
            message = String(localized: "It may have been deleted, or it belongs to an organization you're not in.")
        case .http(.client(.forbidden)):
            symbol = "lock"
            title = String(localized: "You don't have access")
            message = String(localized: "Ask someone in the organization to share it with you.")
        case .http(.server):
            symbol = "exclamationmark.triangle"
            title = String(localized: "Something went wrong")
            message = String(localized: "The server ran into a problem. Try again in a moment.")
        default:
            symbol = "exclamationmark.triangle"
            title = String(localized: "This page didn't load")
            message = error.localizedDescription
        }
    }
}

private extension View {
    @ViewBuilder
    func retryStyle() -> some View {
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
}
