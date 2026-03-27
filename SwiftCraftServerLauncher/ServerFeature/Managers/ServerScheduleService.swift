import Foundation

struct ServerSchedule: Identifiable, Codable, Hashable {
    enum Action: String, Codable, CaseIterable {
        case start
        case stop
        case restart
        case command

        var i18nKey: String {
            switch self {
            case .start:
                return "server.schedules.action.start"
            case .stop:
                return "server.schedules.action.stop"
            case .restart:
                return "server.schedules.action.restart"
            case .command:
                return "server.schedules.action.command"
            }
        }
    }

    struct Time: Codable, Hashable {
        var hour: Int
        var minute: Int
    }

    var id: UUID
    var name: String
    var isEnabled: Bool
    var action: Action
    var time: Time
    var weekdays: [Int]
    var command: String

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        action: Action,
        time: Time,
        weekdays: [Int] = [],
        command: String = ""
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.action = action
        self.time = time
        self.weekdays = weekdays
        self.command = command
    }
}

@MainActor
final class ServerScheduleService: ObservableObject {
    static let shared = ServerScheduleService()

    private var schedulesByServerId: [String: [ServerSchedule]] = [:]
    private var serversById: [String: ServerInstance] = [:]
    private var lastFireToken: [UUID: String] = [:]
    private var lastRunAt: [UUID: Date] = [:]
    private var timer: Timer?
    private var nodeRepository: ServerNodeRepository?

    private init() {}

    func attach(nodeRepository: ServerNodeRepository) {
        self.nodeRepository = nodeRepository
    }

    func refreshServers(_ servers: [ServerInstance]) {
        serversById = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
        for server in servers where schedulesByServerId[server.id] == nil {
            schedulesByServerId[server.id] = loadSchedules(server: server)
        }
        startTimerIfNeeded()
    }

    func schedules(for server: ServerInstance) -> [ServerSchedule] {
        if let existing = schedulesByServerId[server.id] {
            return existing
        }
        let loaded = loadSchedules(server: server)
        schedulesByServerId[server.id] = loaded
        return loaded
    }

    func updateSchedules(for server: ServerInstance, schedules: [ServerSchedule]) {
        schedulesByServerId[server.id] = schedules
        serversById[server.id] = server
        saveSchedules(server: server, schedules: schedules)
        startTimerIfNeeded()
        tick()
    }

    func loadSchedules(server: ServerInstance) -> [ServerSchedule] {
        let url = scheduleFileURL(for: server)
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([ServerSchedule].self, from: data)) ?? []
    }

    private func saveSchedules(server: ServerInstance, schedules: [ServerSchedule]) {
        let url = scheduleFileURL(for: server)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func scheduleFileURL(for server: ServerInstance) -> URL {
        let base: URL
        if server.nodeId == ServerNode.local.id {
            base = AppPaths.serverDirectory(serverName: server.name)
        } else {
            base = AppPaths.remoteNodeServersDirectory(nodeId: server.nodeId)
                .appendingPathComponent(server.name, isDirectory: true)
        }
        return base.appendingPathComponent(".scsl", isDirectory: true)
            .appendingPathComponent("schedules.json")
    }

    private func startTimerIfNeeded() {
        if timer != nil { return }
        timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func tick() {
        let now = Date()
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: now)
        for (serverId, schedules) in schedulesByServerId {
            guard let server = serversById[serverId] else { continue }
            for schedule in schedules where schedule.isEnabled {
                if shouldFire(schedule, components: comps, now: now, calendar: calendar),
                   !hasFired(schedule, components: comps) {
                    markFired(schedule, components: comps)
                    Task { @MainActor in
                        await execute(schedule: schedule, server: server, reason: "timer")
                    }
                }
            }
        }
    }

    private func shouldFire(
        _ schedule: ServerSchedule,
        components: DateComponents,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let hour = components.hour, let minute = components.minute else { return false }
        if schedule.weekdays.isEmpty == false {
            guard let weekday = components.weekday, schedule.weekdays.contains(weekday) else { return false }
        }
        guard hour == schedule.time.hour, minute == schedule.time.minute else {
            // allow late firing if app was suspended: within 2 minutes after target time
            let today = calendar.dateComponents([.year, .month, .day], from: now)
            var target = DateComponents()
            target.year = today.year
            target.month = today.month
            target.day = today.day
            target.hour = schedule.time.hour
            target.minute = schedule.time.minute
            guard let fireDate = calendar.date(from: target) else { return false }
            if now >= fireDate && now.timeIntervalSince(fireDate) <= 120 {
                return true
            }
            return false
        }
        return true
    }

    private func token(for components: DateComponents, scheduleId: UUID) -> String {
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "\(scheduleId.uuidString)-\(year)-\(month)-\(day)-\(hour)-\(minute)"
    }

    private func hasFired(_ schedule: ServerSchedule, components: DateComponents) -> Bool {
        lastFireToken[schedule.id] == token(for: components, scheduleId: schedule.id)
    }

    private func markFired(_ schedule: ServerSchedule, components: DateComponents) {
        lastFireToken[schedule.id] = token(for: components, scheduleId: schedule.id)
    }

    func runNow(schedule: ServerSchedule, server: ServerInstance) async {
        await execute(schedule: schedule, server: server, reason: "manual")
    }

    private func execute(schedule: ServerSchedule, server: ServerInstance, reason: String) async {
        Logger.shared.info("定时任务触发(\(reason)): \(server.name) / \(schedule.name) / \(schedule.action.rawValue)")
        let useCase = ServerLaunchUseCase()
        switch schedule.action {
        case .start:
            await useCase.launchServer(server: server)
        case .stop:
            await useCase.stopServer(server: server)
        case .restart:
            await useCase.stopServer(server: server)
            await useCase.launchServer(server: server)
        case .command:
            let command = schedule.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { return }
            do {
                if server.nodeId == ServerNode.local.id {
                    try LocalServerDirectService.sendCommand(server: server, command: command)
                } else if let node = nodeRepository?.getNode(by: server.nodeId) {
                    try await SSHNodeService.sendRemoteDirectCommand(
                        node: node,
                        serverName: server.name,
                        command: command
                    )
                }
            } catch {
                Logger.shared.error("定时任务命令执行失败: \(error.localizedDescription)")
                GlobalErrorHandler.shared.handle(error)
            }
        }
        lastRunAt[schedule.id] = Date()
        NotificationCenter.default.post(name: .serverScheduleDidRun, object: schedule.id)
    }

    func lastRunDate(for schedule: ServerSchedule) -> Date? {
        lastRunAt[schedule.id]
    }
}

extension Notification.Name {
    static let serverScheduleDidRun = Notification.Name("scsl.server.schedule.didRun")
}
