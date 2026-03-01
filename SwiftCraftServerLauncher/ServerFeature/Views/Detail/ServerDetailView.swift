import SwiftUI

struct ServerDetailView: View {
    let server: ServerInstance
    @EnvironmentObject var serverRepository: ServerRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "server.rack")
                Text(server.name)
                    .font(.title2)
                Spacer()
                Text(server.serverType.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                infoChip(title: "Version", value: server.gameVersion)
                if !server.loaderVersion.isEmpty {
                    infoChip(title: "Loader", value: server.loaderVersion)
                }
            }

            Divider()

            ServerConsoleView(server: server)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.12))
        )
    }
}
