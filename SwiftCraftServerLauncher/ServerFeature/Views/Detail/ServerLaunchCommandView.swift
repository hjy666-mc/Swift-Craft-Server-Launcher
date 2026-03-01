import SwiftUI

struct ServerLaunchCommandView: View {
    let server: ServerInstance
    @EnvironmentObject var serverRepository: ServerRepository
    @State private var customLaunchCommand: String = ""
    @State private var isDirty = false
    @State private var showServerConfig = false
    @State private var showPlayerManager = false
    @State private var showModsManager = false
    @State private var showPluginsManager = false
    @State private var showWorldsManager = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "terminal")
                Text("server.launch.title".localized())
                    .font(.title2)
                Spacer()
            }

            TextField("server.launch.placeholder".localized(), text: $customLaunchCommand, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .onChange(of: customLaunchCommand) { _, newValue in
                    isDirty = newValue != server.launchCommand
                }

            HStack {
                Button("common.save".localized()) {
                    var updated = server
                    updated.launchCommand = customLaunchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = serverRepository.updateServerSilently(updated)
                    isDirty = false
                }
                .disabled(!isDirty)
                Text("server.launch.nogui_hint".localized())
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button("server.launch.server_config".localized()) { showServerConfig = true }
                Button("server.launch.players".localized()) { showPlayerManager = true }
                Button("server.launch.worlds".localized()) { showWorldsManager = true }
                if server.serverType == .fabric || server.serverType == .forge {
                    Button("server.launch.mods".localized()) { showModsManager = true }
                }
                if server.serverType == .paper {
                    Button("server.launch.plugins".localized()) { showPluginsManager = true }
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            customLaunchCommand = server.launchCommand
            isDirty = false
        }
        .sheet(isPresented: $showServerConfig) {
            ServerPropertiesEditorView(server: server)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showPlayerManager) {
            ServerPlayersView(server: server)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showWorldsManager) {
            ServerWorldsManagerView(server: server)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showModsManager) {
            ServerModsManagerView(server: server)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showPluginsManager) {
            ServerPluginsManagerView(server: server)
                .presentationDetents([.large])
        }
    }
}
