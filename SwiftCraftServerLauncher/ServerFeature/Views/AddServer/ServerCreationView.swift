import SwiftUI
import UniformTypeIdentifiers

struct ServerCreationView: View {
    @StateObject private var viewModel: ServerCreationViewModel
    @EnvironmentObject var serverRepository: ServerRepository
    @Environment(\.dismiss)
    private var dismiss

    private let triggerConfirm: Binding<Bool>
    private let triggerCancel: Binding<Bool>

    @State private var showJarPicker = false

    init(
        isDownloading: Binding<Bool>,
        isFormValid: Binding<Bool>,
        triggerConfirm: Binding<Bool>,
        triggerCancel: Binding<Bool>,
        selectedNode: ServerNode = .local,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.triggerConfirm = triggerConfirm
        self.triggerCancel = triggerCancel
        let configuration = GameFormConfiguration(
            isDownloading: isDownloading,
            isFormValid: isFormValid,
            triggerConfirm: triggerConfirm,
            triggerCancel: triggerCancel,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
        self._viewModel = StateObject(
            wrappedValue: ServerCreationViewModel(
                configuration: configuration,
                selectedNode: selectedNode
            )
        )
    }

    var body: some View {
        formContentView
            .onAppear {
                viewModel.setup(serverRepository: serverRepository)
            }
            .onChange(of: viewModel.selectedServerType) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.handleServerTypeChange(newValue)
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.selectedGameVersion) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.handleGameVersionChange(newValue)
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.selectedLoaderVersion) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.serverNameValidator.serverName) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.serverNameValidator.isServerNameDuplicate) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.serverSetupService.downloadState.isDownloading) { oldValue, newValue in
                if oldValue != newValue {
                    viewModel.updateParentState()
                }
            }
            .onChange(of: viewModel.customJarURL) { _, _ in
                viewModel.updateParentState()
            }
            .onChange(of: viewModel.hasAcceptedEula) { _, _ in
                viewModel.updateParentState()
            }
            .onChange(of: triggerConfirm.wrappedValue) { _, newValue in
                if newValue {
                    viewModel.handleConfirm()
                    triggerConfirm.wrappedValue = false
                }
            }
            .onChange(of: triggerCancel.wrappedValue) { _, newValue in
                if newValue {
                    viewModel.handleCancel()
                    triggerCancel.wrappedValue = false
                }
            }
            .fileImporter(
                isPresented: $showJarPicker,
                allowedContentTypes: [UTType(filenameExtension: "jar") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    viewModel.customJarURL = urls.first
                case .failure:
                    viewModel.customJarURL = nil
                }
            }
    }

    private var formContentView: some View {
        VStack {
            FormSection {
                serverTypePicker
                if viewModel.selectedServerType != .custom {
                    versionPicker
                }
                if viewModel.selectedServerType == .fabric || viewModel.selectedServerType == .forge {
                    loaderVersionPicker
                }
                if viewModel.selectedServerType == .custom {
                    customJarPicker
                }
            }

            FormSection {
                ServerNameInputView(
                    serverName: Binding(
                        get: { viewModel.serverNameValidator.serverName },
                        set: { viewModel.serverNameValidator.serverName = $0 }
                    ),
                    isServerNameDuplicate: Binding(
                        get: { viewModel.serverNameValidator.isServerNameDuplicate },
                        set: { viewModel.serverNameValidator.isServerNameDuplicate = $0 }
                    ),
                    isDisabled: viewModel.serverSetupService.downloadState.isDownloading,
                    serverSetupService: viewModel.serverSetupService
                )
            }

            FormSection {
                Toggle("server.form.eula.agree".localized(), isOn: $viewModel.hasAcceptedEula)
                Text("server.form.eula.description".localized())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var serverTypePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.form.type".localized())
                .font(.subheadline)
                .foregroundColor(.primary)
            Picker("", selection: $viewModel.selectedServerType) {
                ForEach(ServerType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())
        }
    }

    private var versionPicker: some View {
        CustomVersionPicker(
            selected: $viewModel.selectedGameVersion,
            availableVersions: viewModel.availableVersions,
            time: $viewModel.versionTime
        ) { version in
            await ModrinthService.queryVersionTime(from: version)
        }
    }

    private var loaderVersionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.form.loader.version".localized())
                .font(.subheadline)
                .foregroundColor(.primary)
            Picker("", selection: $viewModel.selectedLoaderVersion) {
                ForEach(viewModel.availableLoaderVersions, id: \.self) { version in
                    Text(version).tag(version)
                }
            }
            .labelsHidden()
            .pickerStyle(MenuPickerStyle())
            .disabled(viewModel.availableLoaderVersions.isEmpty)
        }
    }

    private var customJarPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.form.custom.jar".localized())
                .font(.subheadline)
                .foregroundColor(.primary)
            HStack(spacing: 8) {
                Button {
                    showJarPicker = true
                } label: {
                    Text("server.form.custom.jar.select".localized())
                }
                if let url = viewModel.customJarURL {
                    Text(url.lastPathComponent)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("server.form.custom.jar.empty".localized())
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
