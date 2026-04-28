import Foundation

struct DownloadProgressSnapshot {
    let fraction: Double?
    let bytesReceived: Int64
    let totalBytesExpected: Int64?
    let bytesPerSecond: Double?
}

struct DownloadProgressTracker {
    private var samples: [(date: Date, bytesReceived: Int64)] = []

    mutating func record(
        bytesReceived: Int64,
        totalBytesExpected: Int64,
        at date: Date = .now
    ) -> DownloadProgressSnapshot {
        samples.append((date, bytesReceived))
        samples.removeAll { date.timeIntervalSince($0.date) > 3.0 }

        let fraction: Double?
        if totalBytesExpected > 0 {
            fraction = min(Double(bytesReceived) / Double(totalBytesExpected), 1.0)
        } else {
            fraction = nil
        }

        let bytesPerSecond: Double? = {
            guard let first = samples.first, let last = samples.last, samples.count >= 2 else {
                return nil
            }
            let elapsed = last.date.timeIntervalSince(first.date)
            guard elapsed > 0 else { return nil }
            return Double(last.bytesReceived - first.bytesReceived) / elapsed
        }()

        return DownloadProgressSnapshot(
            fraction: fraction,
            bytesReceived: bytesReceived,
            totalBytesExpected: totalBytesExpected > 0 ? totalBytesExpected : nil,
            bytesPerSecond: bytesPerSecond
        )
    }
}
