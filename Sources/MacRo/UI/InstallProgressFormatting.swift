import Foundation

enum InstallProgressFormatting {
    static func headline(for progress: InstallProgress) -> String {
        switch progress.phase {
        case .downloading:
            "Downloading"
        case .installing:
            "Installing"
        }
    }

    static func percentText(for progress: InstallProgress) -> String? {
        guard let fraction = progress.fraction else { return nil }
        return "\(Int(fraction * 100))%"
    }

    static func detailText(for progress: InstallProgress) -> String {
        let received = formatBytes(progress.bytesReceived)
        guard let total = progress.totalBytesExpected, total > 0 else {
            return "\(received) downloaded"
        }
        return "\(received) / \(formatBytes(total))"
    }

    static func speedText(for progress: InstallProgress) -> String? {
        guard let bytesPerSecond = progress.bytesPerSecond else { return nil }
        return "\(formatBytes(Int64(bytesPerSecond)))/s"
    }

    nonisolated(unsafe) private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter
    }()

    private static func formatBytes(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }
}
