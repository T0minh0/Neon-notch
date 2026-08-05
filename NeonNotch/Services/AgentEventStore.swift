import Darwin
import Foundation

@MainActor
final class AgentEventStore {
    static let reconstructionAge: TimeInterval = 86_400
    static let logMaximumAge: TimeInterval = 172_800
    static let logMaximumBytes: UInt64 = 5 * 1_024 * 1_024

    private let logURL: URL
    private let snapshotsURL: URL
    private let receiptsURL: URL
    private let now: () -> Date
    private var offset: UInt64 = 0
    private var remainder = Data()
    private var receipts: [String: Date] = [:]

    init(
        logURL: URL = AppPaths.eventLog,
        snapshotsURL: URL = AppPaths.agentSnapshots,
        receiptsURL: URL = AppPaths.agentEventReceipts,
        now: @escaping () -> Date = Date.init
    ) {
        self.logURL = logURL
        self.snapshotsURL = snapshotsURL
        self.receiptsURL = receiptsURL
        self.now = now
        loadReceipts()
    }

    func prepareLiveCursor() -> [AgentHookEvent] {
        let events = reconstructRecentEvents()
        offset = fileSize(at: logURL)
        remainder = Data()
        record(events)
        compactIfNeeded()
        return events
    }

    func readNewEvents() -> [AgentHookEvent] {
        guard FileManager.default.fileExists(atPath: logURL.path),
              let handle = try? FileHandle(forReadingFrom: logURL) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if offset > size {
            offset = 0
            remainder = Data()
        }
        try? handle.seek(toOffset: offset)
        let incoming = (try? handle.readToEnd()) ?? Data()
        offset = size
        guard !incoming.isEmpty else { return [] }

        var buffer = remainder
        buffer.append(incoming)
        var lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
        if buffer.last != 0x0A {
            remainder = Data(lines.removeLast())
        } else {
            remainder = Data()
            if lines.last?.isEmpty == true { lines.removeLast() }
        }

        var seen = Set(receipts.keys)
        let events = decode(lines.map { Data(Array($0)) }).filter { seen.insert($0.eventID).inserted }
        record(events)
        return events
    }

    func loadSnapshots() -> [AgentSnapshot] {
        guard let data = try? Data(contentsOf: snapshotsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshots = (try? decoder.decode([AgentSnapshot].self, from: data)) ?? []
        let cutoff = now().addingTimeInterval(-Self.reconstructionAge)
        return snapshots.filter { $0.updatedAt >= cutoff }
    }

    func persistSnapshots(_ snapshots: [AgentSnapshot]) {
        let cutoff = now().addingTimeInterval(-Self.reconstructionAge)
        let retained = snapshots.filter { $0.updatedAt >= cutoff }
        guard !retained.isEmpty else {
            try? FileManager.default.removeItem(at: snapshotsURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(retained) else { return }
        try? FileManager.default.createDirectory(at: snapshotsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: snapshotsURL, options: .atomic)
    }

    func compactIfNeeded(force: Bool = false) {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return }
        let descriptor = open(logURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return }
        defer { flock(descriptor, LOCK_UN) }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.readToEnd() else { return }
        let cutoff = now().addingTimeInterval(-Self.logMaximumAge)
        var events = decode(lines(in: data))
        let removedOldEvents = events.contains { $0.timestamp < cutoff }
        events.removeAll { $0.timestamp < cutoff }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var encodedLines = events.compactMap { event -> Data? in
            guard var line = try? encoder.encode(event) else { return nil }
            line.append(0x0A)
            return line
        }
        var total = encodedLines.reduce(UInt64(0)) { $0 + UInt64($1.count) }
        while total > Self.logMaximumBytes, !encodedLines.isEmpty {
            total -= UInt64(encodedLines.removeFirst().count)
        }

        guard force || removedOldEvents || UInt64(data.count) > Self.logMaximumBytes else { return }
        let compacted = encodedLines.reduce(into: Data()) { $0.append($1) }
        do {
            try handle.seek(toOffset: 0)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: compacted)
            try handle.synchronize()
            offset = UInt64(compacted.count)
            remainder = Data()
        } catch {
            return
        }
    }

    private func reconstructRecentEvents() -> [AgentHookEvent] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        let cutoff = now().addingTimeInterval(-Self.reconstructionAge)
        return decode(lines(in: data))
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func decode(_ lines: [Data]) -> [AgentHookEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lines.compactMap { try? decoder.decode(AgentHookEvent.self, from: $0) }
    }

    private func lines(in data: Data) -> [Data] {
        Array(data).split(separator: UInt8(0x0A)).map { Data(Array($0)) }
    }

    private func record(_ events: [AgentHookEvent]) {
        guard !events.isEmpty else { return }
        for event in events { receipts[event.eventID] = event.timestamp }
        pruneAndPersistReceipts()
    }

    private func loadReceipts() {
        guard let data = try? Data(contentsOf: receiptsURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        receipts = (try? decoder.decode([String: Date].self, from: data)) ?? [:]
        pruneAndPersistReceipts()
    }

    private func pruneAndPersistReceipts() {
        let cutoff = now().addingTimeInterval(-Self.logMaximumAge)
        receipts = receipts.filter { $0.value >= cutoff }
        guard !receipts.isEmpty else {
            try? FileManager.default.removeItem(at: receiptsURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(receipts) else { return }
        try? FileManager.default.createDirectory(at: receiptsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: receiptsURL, options: .atomic)
    }

    private func fileSize(at url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }
}
