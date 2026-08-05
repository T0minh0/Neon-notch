import AppKit
import Foundation

@MainActor
final class SpotifyService: MediaProvider {
    private(set) var snapshot: MediaSnapshot = .empty

    func refresh() async {
        guard Self.isSpotifyRunning else {
            snapshot = .empty
            return
        }

        let script = """
        tell application "Spotify"
            if player state is stopped then return "STOPPED"
            set t to current track
            return (name of t) & "|||" & (artist of t) & "|||" & (album of t) & "|||" & (artwork url of t) & "|||" & ((duration of t) as text) & "|||" & ((player position) as text) & "|||" & ((player state) as text)
        end tell
        """
        let result = await ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", script])
        guard result.status == 0 else {
            // Preserve the last known track when Automation is temporarily denied or Spotify is busy.
            return
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output != "STOPPED" else {
            snapshot = .empty
            return
        }

        let fields = output.components(separatedBy: "|||")
        guard fields.count >= 7 else { return }
        let rawDuration = Double(fields[4]) ?? 0
        let remoteArtwork = URL(string: fields[3])
        let artwork = await cachedArtworkURL(for: remoteArtwork) ?? remoteArtwork
        snapshot = MediaSnapshot(
            title: fields[0],
            artist: fields[1],
            album: fields[2],
            artworkURL: artwork,
            duration: rawDuration > 100_000 ? rawDuration / 1_000 : rawDuration,
            position: Double(fields[5]) ?? 0,
            state: fields[6].lowercased().contains("playing") ? .playing : .paused
        )
    }

    func perform(_ command: MediaCommand) async throws -> MediaSnapshot {
        guard Self.isSpotifyRunning else { throw MediaProviderError.spotifyNotRunning }

        let result = await ProcessRunner.run(
            "/usr/bin/osascript",
            arguments: ["-e", Self.script(for: command)]
        )
        guard result.status == 0 else {
            throw Self.error(for: result)
        }

        try? await Task.sleep(for: .milliseconds(180))
        await refresh()
        return snapshot
    }

    static func script(for command: MediaCommand) -> String {
        switch command {
        case .togglePlayback:
            "tell application \"Spotify\" to playpause"
        case .previousOrRestart:
            """
            tell application "Spotify"
                if player position > 3 then
                    set player position to 0
                else
                    previous track
                end if
            end tell
            """
        case .next:
            "tell application \"Spotify\" to next track"
        }
    }

    private static var isSpotifyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }

    private static func error(for result: ProcessResult) -> MediaProviderError {
        let message = "\(result.stderr) \(result.stdout)".lowercased()
        if message.contains("-1743")
            || message.contains("not authorized")
            || message.contains("not permitted")
            || message.contains("automation") {
            return .automationDenied
        }
        return .commandFailed
    }

    private func cachedArtworkURL(for remoteURL: URL?) async -> URL? {
        guard let remoteURL else { return nil }
        do {
            try AppPaths.prepare()
            let fileExtension = remoteURL.pathExtension.isEmpty ? "jpg" : remoteURL.pathExtension
            let destination = AppPaths.artworkCache
                .appendingPathComponent(remoteURL.absoluteString.contentHash)
                .appendingPathExtension(fileExtension)
            if FileManager.default.fileExists(atPath: destination.path) { return destination }
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            guard data.count <= 10_000_000,
                  statusCode.map({ 200..<300 ~= $0 }) ?? true else { return nil }
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }
}
