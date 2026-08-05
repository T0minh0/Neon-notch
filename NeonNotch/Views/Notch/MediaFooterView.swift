import AppKit
import SwiftUI

struct MediaFooterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 18) {
            ArtworkView(url: model.media.artworkURL, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.media.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(model.media.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 172, alignment: .leading)

            Rectangle()
                .fill(NeonTheme.separator)
                .frame(width: 1, height: 38)
                .allowsHitTesting(false)

            MediaTransportControls(model: model, showsSkipControls: true)

            Rectangle()
                .fill(NeonTheme.separator)
                .frame(width: 1, height: 38)
                .allowsHitTesting(false)

            HStack(spacing: 7) {
                Label("Spotify", systemImage: "music.note")
                if let error = model.mediaControlError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NeonTheme.magenta)
                        .help(error)
                        .accessibilityLabel(error)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 96, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .opacity(model.media.state == .stopped ? 0.55 : 1)
    }
}

struct CompactMediaView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            ArtworkView(url: model.media.artworkURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.media.title).font(.caption.weight(.semibold)).lineLimit(1)
                Text(model.media.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)
            MediaTransportControls(model: model, showsSkipControls: false)
        }
    }
}

struct MediaTransportControls: View {
    @ObservedObject var model: AppModel
    let showsSkipControls: Bool

    var body: some View {
        HStack(spacing: showsSkipControls ? 18 : 8) {
            if showsSkipControls {
                transportButton(
                    command: .previousOrRestart,
                    symbol: "backward.fill",
                    label: "Voltar ou reiniciar faixa",
                    help: "Reinicia após 3 segundos; no início volta para a faixa anterior"
                )
            }

            transportButton(
                command: .togglePlayback,
                symbol: model.media.state == .playing ? "pause.fill" : "play.fill",
                label: model.media.state == .playing ? "Pausar Spotify" : "Reproduzir Spotify",
                help: model.media.state == .playing ? "Pausar" : "Reproduzir",
                emphasized: true
            )

            if showsSkipControls {
                transportButton(
                    command: .next,
                    symbol: "forward.fill",
                    label: "Próxima faixa",
                    help: "Pular para a próxima faixa"
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.mediaControlsEnabled)
        .opacity(model.mediaCommandInFlight == nil ? 1 : 0.58)
    }

    private func transportButton(
        command: MediaCommand,
        symbol: String,
        label: String,
        help: String,
        emphasized: Bool = false
    ) -> some View {
        Button {
            model.performMediaCommand(command)
        } label: {
            ZStack {
                if emphasized {
                    Circle()
                        .stroke(NeonTheme.cyan.opacity(0.65), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                if model.mediaCommandInFlight == command {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NeonTheme.cyan)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: emphasized ? 15 : 13, weight: .semibold))
                }
            }
            .frame(width: emphasized ? 36 : 28, height: emphasized ? 36 : 28)
            .contentShape(Rectangle())
        }
        .help(help)
        .accessibilityLabel(label)
    }
}

struct ArtworkView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        ZStack {
                            NeonTheme.raised
                            Image(systemName: "music.note").foregroundStyle(NeonTheme.cyan)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(Color.white.opacity(0.12)))
    }
}
