import SwiftUI

struct ExpandedClipboardView: View {
    @ObservedObject var model: AppModel
    @State private var copiedEntryID: UUID?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        Group {
            if model.clipboardEntries.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 6) {
                        ForEach(model.clipboardEntries) { entry in
                            clipboardRow(entry)
                        }
                    }
                    .padding(.trailing, 5)
                }
                .scrollIndicators(.visible)
            }
        }
        .onDisappear { feedbackTask?.cancel() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 25))
                .foregroundStyle(NeonTheme.cyan)
            Text("Clipboard vazio").font(.headline)
            Text("Textos, links, imagens e arquivos recentes aparecem aqui por até 5 horas.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .neonCard()
    }

    private func clipboardRow(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 9) {
            Button {
                copy(entry)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.black.opacity(0.42))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(entry.isPinned ? NeonTheme.magenta.opacity(0.5) : NeonTheme.cyan.opacity(0.25))
                            }
                            .allowsHitTesting(false)
                        Image(systemName: copiedEntryID == entry.id ? "checkmark" : entry.kind.symbol)
                            .foregroundStyle(copiedEntryID == entry.id ? NeonTheme.green : (entry.isPinned ? NeonTheme.magenta : NeonTheme.cyan))
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.preview)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 5) {
                            Text(entry.kind.rawValue.uppercased())
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(entry.isPinned ? NeonTheme.magenta : NeonTheme.cyan)
                            Text("·")
                            Text(entry.sourceName)
                                .lineLimit(1)
                            Text("·")
                            Text(entry.createdAt, style: .relative)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copiar novamente")
            .accessibilityLabel("Copiar \(entry.preview)")

            actionButton(
                symbol: entry.isPinned ? "pin.fill" : "pin",
                label: entry.isPinned ? "Desafixar item" : "Fixar item",
                tint: entry.isPinned ? NeonTheme.magenta : NeonTheme.muted
            ) {
                model.toggleClipboardPin(entry)
            }

            actionButton(symbol: "doc.on.doc", label: "Copiar item", tint: NeonTheme.cyan) {
                copy(entry)
            }

            actionButton(symbol: "trash", label: "Excluir item", tint: NeonTheme.muted) {
                model.deleteClipboard(entry)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .frame(minHeight: 50)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NeonTheme.raised.opacity(0.68))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(entry.isPinned ? NeonTheme.magenta.opacity(0.4) : NeonTheme.separator, lineWidth: 0.75)
                }
                .allowsHitTesting(false)
        }
    }

    private func actionButton(
        symbol: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func copy(_ entry: ClipboardEntry) {
        model.copyClipboard(entry)
        feedbackTask?.cancel()
        copiedEntryID = entry.id
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            copiedEntryID = nil
        }
    }
}
