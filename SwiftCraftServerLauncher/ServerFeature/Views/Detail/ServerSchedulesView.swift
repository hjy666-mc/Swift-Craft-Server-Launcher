import SwiftUI

struct ServerSchedulesView: View {
    let server: ServerInstance
    @StateObject private var store: ServerScheduleStore
    @State private var editingSchedule: ServerSchedule?
    @State private var isCreatingNew = false

    init(server: ServerInstance) {
        self.server = server
        _store = StateObject(wrappedValue: ServerScheduleStore(server: server))
    }

    var body: some View {
        ServerDetailPage(title: "server.schedules.title".localized()) {
            VStack(alignment: .leading, spacing: 16) {
                headerBar
                if store.schedules.isEmpty {
                    ServerDetailEmptyState(text: "server.schedules.empty".localized())
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.schedules) { schedule in
                                scheduleRow(schedule)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear { store.reload(server: server) }
        .onChange(of: server.id) { _, _ in
            store.reload(server: server)
        }
        .sheet(item: $editingSchedule) { schedule in
            ServerScheduleEditor(
                schedule: schedule,
                isNew: isCreatingNew
            ) { updated in
                if isCreatingNew {
                    store.addNew(updated)
                } else {
                    store.upsert(updated)
                }
                editingSchedule = nil
                isCreatingNew = false
            } onCancel: {
                editingSchedule = nil
                isCreatingNew = false
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text("server.schedules.subtitle".localized())
                .font(.headline)
            Spacer()
            Button("server.schedules.add".localized()) {
                let draft = ServerSchedule(
                    name: "server.schedules.default_name".localized(),
                    action: .start,
                    time: .init(hour: 2, minute: 0)
                )
                isCreatingNew = true
                editingSchedule = draft
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func scheduleRow(_ schedule: ServerSchedule) -> some View {
        _ = store.lastRunToken
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.name)
                    .font(.headline)
                Text(scheduleSummary(schedule))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let nextRun = store.nextRunText(for: schedule) {
                    Text("\("server.schedules.next_run".localized()) \(nextRun)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastRun = store.lastRunText(for: schedule) {
                    Text("\("server.schedules.last_run".localized()) \(lastRun)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button("server.schedules.run_now".localized()) {
                    Task { @MainActor in
                        await store.runNow(schedule)
                    }
                }
                .buttonStyle(.bordered)
                Toggle("", isOn: bindingForSchedule(schedule))
                    .labelsHidden()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.windowBackgroundColor).opacity(0.3))
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("server.schedules.edit".localized()) {
                isCreatingNew = false
                editingSchedule = schedule
            }
            Button("server.schedules.delete".localized(), role: .destructive) {
                store.delete(schedule)
            }
        }
        .onTapGesture {
            isCreatingNew = false
            editingSchedule = schedule
        }
    }

    private func scheduleSummary(_ schedule: ServerSchedule) -> String {
        let timeText = String(format: "%02d:%02d", schedule.time.hour, schedule.time.minute)
        let actionText = schedule.action.i18nKey.localized()
        let daysText = scheduleDaysText(schedule.weekdays)
        if schedule.action == .command {
            return "\(actionText) · \(timeText) · \(daysText)"
        }
        return "\(actionText) · \(timeText) · \(daysText)"
    }

    private func scheduleDaysText(_ weekdays: [Int]) -> String {
        if weekdays.isEmpty {
            return "server.schedules.days.everyday".localized()
        }
        let ordered = weekdays.sorted()
        let labels = ordered.map { weekdayLabel($0) }
        return labels.joined(separator: " ")
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "server.schedules.weekday.sun".localized()
        case 2: return "server.schedules.weekday.mon".localized()
        case 3: return "server.schedules.weekday.tue".localized()
        case 4: return "server.schedules.weekday.wed".localized()
        case 5: return "server.schedules.weekday.thu".localized()
        case 6: return "server.schedules.weekday.fri".localized()
        case 7: return "server.schedules.weekday.sat".localized()
        default: return ""
        }
    }

    private func bindingForSchedule(_ schedule: ServerSchedule) -> Binding<Bool> {
        Binding(
            get: { schedule.isEnabled },
            set: { newValue in
                var updated = schedule
                updated.isEnabled = newValue
                store.upsert(updated)
            }
        )
    }
}

@MainActor
final class ServerScheduleStore: ObservableObject {
    @Published var schedules: [ServerSchedule] = []
    @Published var lastRunToken = UUID()
    private var server: ServerInstance
    private var runObserver: NSObjectProtocol?

    init(server: ServerInstance) {
        self.server = server
        reload(server: server)
        runObserver = NotificationCenter.default.addObserver(
            forName: .serverScheduleDidRun,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastRunToken = UUID()
            }
        }
    }

    deinit {
        if let runObserver {
            NotificationCenter.default.removeObserver(runObserver)
        }
    }

    func reload(server: ServerInstance) {
        self.server = server
        schedules = ServerScheduleService.shared.schedules(for: server)
    }

    func upsert(_ schedule: ServerSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.insert(schedule, at: 0)
        }
        persist()
    }

    func addNew(_ schedule: ServerSchedule) {
        var draft = schedule
        if schedules.contains(where: { $0.id == draft.id }) {
            draft.id = UUID()
        }
        schedules.insert(draft, at: 0)
        persist()
    }

    func delete(_ schedule: ServerSchedule) {
        schedules.removeAll { $0.id == schedule.id }
        persist()
    }

    private func persist() {
        ServerScheduleService.shared.updateSchedules(for: server, schedules: schedules)
    }

    func lastRunText(for schedule: ServerSchedule) -> String? {
        guard let date = ServerScheduleService.shared.lastRunDate(for: schedule) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func nextRunText(for schedule: ServerSchedule) -> String? {
        guard let date = nextRunDate(for: schedule) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func runNow(_ schedule: ServerSchedule) async {
        await ServerScheduleService.shared.runNow(schedule: schedule, server: server)
        lastRunToken = UUID()
    }

    private func nextRunDate(for schedule: ServerSchedule) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let baseComponents = calendar.dateComponents([.year, .month, .day], from: now)
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.date(from: baseComponents) ?? now) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: day)
            if schedule.weekdays.isEmpty == false, !schedule.weekdays.contains(weekday) {
                continue
            }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = schedule.time.hour
            comps.minute = schedule.time.minute
            if let candidate = calendar.date(from: comps), candidate >= now {
                return candidate
            }
        }
        return nil
    }
}

struct ServerScheduleEditor: View {
    @State private var draft: ServerSchedule
    @State private var time: Date
    let isNew: Bool
    let onSave: (ServerSchedule) -> Void
    let onCancel: () -> Void

    init(
        schedule: ServerSchedule,
        isNew: Bool,
        onSave: @escaping (ServerSchedule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: schedule)
        let base = Calendar.current.date(from: DateComponents(hour: schedule.time.hour, minute: schedule.time.minute))
        _time = State(initialValue: base ?? Date())
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "server.schedules.create".localized() : "server.schedules.edit".localized())
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("server.schedules.name".localized()) {
                    TextField("", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("server.schedules.action".localized()) {
                    Picker("", selection: $draft.action) {
                        ForEach(ServerSchedule.Action.allCases, id: \.self) { action in
                            Text(action.i18nKey.localized()).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                if draft.action == .command {
                    LabeledContent("server.schedules.command".localized()) {
                        TextField("server.schedules.command.placeholder".localized(), text: $draft.command)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                LabeledContent("server.schedules.time".localized()) {
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                LabeledContent("server.schedules.days".localized()) {
                    WeekdaySelector(selected: $draft.weekdays)
                }
                Toggle("server.schedules.enabled".localized(), isOn: $draft.isEnabled)
            }
            HStack {
                Spacer()
                Button("common.cancel".localized()) { onCancel() }
                Button("common.confirm".localized()) { commit() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func commit() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        draft.time = .init(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.name = "server.schedules.default_name".localized()
        }
        onSave(draft)
    }
}

struct WeekdaySelector: View {
    @Binding var selected: [Int]

    var body: some View {
        HStack(spacing: 6) {
            weekdayButton(2, "server.schedules.weekday.mon".localized())
            weekdayButton(3, "server.schedules.weekday.tue".localized())
            weekdayButton(4, "server.schedules.weekday.wed".localized())
            weekdayButton(5, "server.schedules.weekday.thu".localized())
            weekdayButton(6, "server.schedules.weekday.fri".localized())
            weekdayButton(7, "server.schedules.weekday.sat".localized())
            weekdayButton(1, "server.schedules.weekday.sun".localized())
        }
    }

    private func weekdayButton(_ value: Int, _ label: String) -> some View {
        let isSelected = selected.contains(value)
        return Button {
            if isSelected {
                selected.removeAll { $0 == value }
            } else {
                selected.append(value)
            }
        } label: {
            Text(label)
                .font(.subheadline)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(.plain)
    }
}
