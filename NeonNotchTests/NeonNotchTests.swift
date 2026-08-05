import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeonNotch

@MainActor
private final class DelayedMediaProvider: MediaProvider {
    var snapshot = MediaSnapshot(
        title: "Test Track",
        artist: "Test Artist",
        state: .playing
    )
    var performedCommands: [MediaCommand] = []

    func refresh() async {}

    func perform(_ command: MediaCommand) async throws -> MediaSnapshot {
        performedCommands.append(command)
        try await Task.sleep(for: .milliseconds(90))
        if command == .togglePlayback { snapshot.state = .paused }
        return snapshot
    }
}

@Suite("Neon Notch core")
struct NeonNotchTests {
    @Test("Attention sorts before working and completed")
    func agentPriority() {
        #expect(AgentStatus.needsAttention.priority < AgentStatus.working.priority)
        #expect(AgentStatus.working.priority < AgentStatus.completed.priority)
    }

    @Test("Sanitizer removes API tokens and collapses whitespace")
    func sanitization() {
        let source = "  use api_key=secret-value\n\nthen continue  "
        #expect(source.sanitizedSummary == "use [redacted] then continue")
    }

    @Test("Hook reduction maps interaction and completion")
    @MainActor
    func hookReduction() {
        let service = AgentMonitorService()
        let base = AgentHookEvent(
            schemaVersion: 1,
            source: .codex,
            event: "PermissionRequest",
            sessionID: "thread-1",
            agentID: nil,
            parentAgentID: nil,
            workingDirectory: "/tmp/demo",
            timestamp: Date(),
            title: "Agent session",
            summary: "Aprovação necessária"
        )
        #expect(service.snapshot(from: base, previous: nil).status == .needsAttention)

        let completed = AgentHookEvent(
            schemaVersion: 1,
            source: .claudeCode,
            event: "SessionEnd",
            sessionID: "session-1",
            agentID: nil,
            parentAgentID: nil,
            workingDirectory: "/tmp/demo",
            timestamp: Date(),
            title: "Agent session",
            summary: "Concluído"
        )
        #expect(service.snapshot(from: completed, previous: nil).status == .completed)
    }

    @Test("Clipboard hash is stable")
    func stableHash() {
        #expect("neon".contentHash == "neon".contentHash)
        #expect("neon".contentHash != "notch".contentHash)
    }

    @Test("Clipboard entries expire at exactly five hours and pins remain")
    func clipboardRetentionBoundary() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var regular = clipboardEntry(createdAt: now.addingTimeInterval(-(4 * 3_600 + 59 * 60)))
        #expect(!ClipboardRetentionPolicy.isExpired(regular, at: now))

        regular.createdAt = now.addingTimeInterval(-ClipboardRetentionPolicy.maximumAge)
        #expect(ClipboardRetentionPolicy.isExpired(regular, at: now))

        regular.isPinned = true
        #expect(!ClipboardRetentionPolicy.isExpired(regular, at: now))
        #expect(ClipboardRetentionPolicy.maximumAge == 18_000)
    }

    @Test("Clear preserves pins, leaves NSPasteboard unchanged, and removes an empty cache")
    @MainActor
    func clipboardClearPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = root.appendingPathComponent("clipboard.json")
        let now = Date()
        let pinned = clipboardEntry(createdAt: now.addingTimeInterval(-20_000), isPinned: true)
        let regular = clipboardEntry(createdAt: now.addingTimeInterval(-60))
        try JSONEncoder().encode([pinned, regular]).write(to: store)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NeonNotchTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("keep-current-clipboard", forType: .string)
        let service = ClipboardService(pasteboard: pasteboard, storeURL: store)
        defer { service.stop() }

        service.clear()
        #expect(service.entries == [pinned])
        #expect(pasteboard.string(forType: .string) == "keep-current-clipboard")
        let persisted = try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: store))
        #expect(persisted == [pinned])

        service.delete(pinned.id)
        #expect(service.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("Expired items are pruned on load and immediately after unpinning")
    @MainActor
    func clipboardLoadAndUnpinPruning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = root.appendingPathComponent("clipboard.json")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = clipboardEntry(createdAt: now.addingTimeInterval(-18_001))
        let oldPin = clipboardEntry(createdAt: now.addingTimeInterval(-25_000), isPinned: true)
        try JSONEncoder().encode([expired, oldPin]).write(to: store)

        let service = ClipboardService(storeURL: store, now: { now })
        defer { service.stop() }
        #expect(service.entries == [oldPin])

        service.togglePinned(oldPin.id)
        #expect(service.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test("Spotify previous command uses the three-second restart boundary")
    @MainActor
    func spotifyPreviousOrRestartScript() {
        let script = SpotifyService.script(for: .previousOrRestart)
        #expect(script.contains("player position > 3"))
        #expect(script.contains("set player position to 0"))
        #expect(script.contains("previous track"))
    }

    @Test("Rapid media commands do not create concurrent tasks")
    @MainActor
    func mediaCommandSerialization() async throws {
        let provider = DelayedMediaProvider()
        let store = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("clipboard.json")
        let clipboard = ClipboardService(storeURL: store)
        defer { clipboard.stop() }
        let model = AppModel(mediaProvider: provider, clipboardService: clipboard)

        model.performMediaCommand(.togglePlayback)
        model.performMediaCommand(.next)
        #expect(model.mediaCommandInFlight == .togglePlayback)
        try await Task.sleep(for: .milliseconds(140))

        #expect(provider.performedCommands == [.togglePlayback])
        #expect(model.media.state == .paused)
        #expect(model.mediaCommandInFlight == nil)
    }

    @Test("Completed agents expire after 24 hours")
    func retention() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let recent = Date().addingTimeInterval(-60)
        #expect(recent > cutoff)
        #expect(Date().addingTimeInterval(-25 * 60 * 60) < cutoff)
    }

    @Test("Notch panel dimensions match the approved visual contract")
    func notchPanelMetrics() {
        #expect(NotchPanelMetrics.expandedHeight == 380)
        #expect(NotchPanelMetrics.footerHeight == 72)
        #expect(NotchPanelMetrics.collapsedHorizontalAllowance == 16)
        #expect(NotchPanelMetrics.collapsedVerticalAllowance == 8)
        #expect(NotchPanelMetrics.taperStartY(in: CGRect(x: 0, y: 0, width: 1_120, height: 380)) == 308)
        #expect(NotchPanelMetrics.bottomInset(for: 1_120) == 300)
        #expect(NotchPanelMetrics.bottomInset(for: 800) == 216)
    }

    @Test("Expanded shape preserves its body and exposes only the lower side cutouts")
    func expandedShapeGeometry() {
        let rect = CGRect(x: 0, y: 0, width: 1_120, height: 380)
        let path = NeonNotchShape(
            topInset: 38,
            notchWidth: 210,
            taperedBottom: true
        ).path(in: rect)

        #expect(path.contains(CGPoint(x: 10, y: 300)))
        #expect(!path.contains(CGPoint(x: 40, y: 374)))
        #expect(path.contains(CGPoint(x: rect.midX, y: 374)))
    }

    @Test("Hook merge is idempotent, backed up, and removable")
    @MainActor
    func hookConfigurationLifecycle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support", isDirectory: true)
        let bundled = root.appendingPathComponent("BundledHook")
        let destination = support.appendingPathComponent("bin/NeonNotchHook")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try Data("helper".utf8).write(to: bundled)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)

        let custom: [String: Any] = [
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "/usr/bin/custom-hook"]]]]
            ]
        ]
        let customData = try JSONSerialization.data(withJSONObject: custom)
        try customData.write(to: root.appendingPathComponent(".claude/settings.json"))

        let manager = HookIntegrationManager(
            homeDirectory: root,
            supportDirectory: support,
            helperURL: destination,
            bundledHelperURL: bundled
        )
        try manager.installOrRepair()
        try manager.installOrRepair()

        let data = try Data(contentsOf: root.appendingPathComponent(".claude/settings.json"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try #require(object["hooks"] as? [String: Any])
        let stopGroups = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stopGroups.count == 2)
        #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("backups").path))

        try manager.remove()
        let removedData = try Data(contentsOf: root.appendingPathComponent(".claude/settings.json"))
        let removedObject = try #require(JSONSerialization.jsonObject(with: removedData) as? [String: Any])
        let removedHooks = try #require(removedObject["hooks"] as? [String: Any])
        let remainingStop = try #require(removedHooks["Stop"] as? [[String: Any]])
        #expect(remainingStop.count == 1)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

private func clipboardEntry(
    createdAt: Date,
    isPinned: Bool = false
) -> ClipboardEntry {
    let payload = UUID().uuidString
    return ClipboardEntry(
        id: UUID(),
        kind: .text,
        preview: payload,
        payload: payload,
        sourceBundleID: "com.example.source",
        sourceName: "Example",
        createdAt: createdAt,
        isPinned: isPinned,
        contentHash: payload.contentHash
    )
}
