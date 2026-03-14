import SwiftUI

struct DownloadProgressIndicatorView: View {
    let progress: Double?

    var body: some View {
        let resolvedProgress = min(max(progress ?? 0, 0), 1)
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: resolvedProgress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            Text("\(Int(resolvedProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
