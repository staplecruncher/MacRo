import SwiftUI

struct InstallProgressView: View {
    let progress: InstallProgress

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            VStack(spacing: 12) {
                Text("\(InstallProgressFormatting.headline(for: progress)) \(progress.target.displayName)...")
                    .font(.headline)
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 360)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 360)
                }
                if let percentText = InstallProgressFormatting.percentText(for: progress) {
                    Text(percentText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(InstallProgressFormatting.detailText(for: progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let speedText = InstallProgressFormatting.speedText(for: progress) {
                    Text(speedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct InstallOverlay: View {
    @ObservedObject var coordinator: InstallCoordinator

    var body: some View {
        if let progress = coordinator.progress {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                InstallProgressView(progress: progress)
            }
        }
    }
}
