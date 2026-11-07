import Foundation
import Darwin

enum Health: Int, Comparable {
    case good = 0, unknown = 1, warning = 2, bad = 3
    static func < (lhs: Health, rhs: Health) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct TraceCheck: Decodable {
    let endpoint: String
    let status: String
    let observed: [String?]
}
struct ServiceSample: Decodable {
    let service: String
    let status: String
    let expected: String
    let checks: [TraceCheck]
    let terminated: [String]?
    var observedIPs: [String] { Array(Set(checks.flatMap { $0.observed.compactMap { $0 } })).sorted() }
}
struct WatchSample: Decodable {
    let at: String
    let mode: String
    let interface: String?
    let services: [ServiceSample]
    let status: String
    var date: Date? { parseDate(at) }
}
struct GuardPolicy: Decodable {
    struct Service: Decodable { let expected_ip: String }
    let services: [String: Service]
}
struct Acceptance: Decodable {
    struct PF: Decodable { let pass: Bool }
    let at: String
    let status: String
    let pf_physical_tcp_tests: PF?
}

struct JobState {
    var loaded = false
    var running = false
    var lastExit: Int?
    var enforcing = false
    var error: String?
    var healthy: Bool { loaded && (running || lastExit == 0) }
    static func parse(_ text: String, exit: Int32) -> JobState {
        guard exit == 0, text.contains(" = {") else { return JobState(error: "Служба не загружена или недоступна") }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let last = lines.first(where: { $0.hasPrefix("last exit code = ") })?
            .replacingOccurrences(of: "last exit code = ", with: "")
        let code = last.flatMap { Int($0.components(separatedBy: CharacterSet(charactersIn: ": ")).first ?? "") }
        return JobState(loaded: true, running: lines.contains("state = running"), lastExit: code,
                        enforcing: lines.contains("--enforce"), error: nil)
    }
    var description: String {
        if !loaded { return "Не загружена" }
        if running { return "Выполняет проверку" }
        if lastExit == 75 { return "Проверка уже выполнялась" }
        if lastExit == 0 { return "Работает по расписанию" }
        if let exit = lastExit { return "Ошибка · код \(exit)" }
        return "Ожидает первого запуска"
    }
}

struct ServiceState: Identifiable {
    let id: String
    let sample: ServiceSample?
    let expected: String?
    let fresh: Bool
    var name: String { id == "OPENAI" ? "OpenAI" : "Claude" }
    var policyChanged: Bool { sample != nil && expected != nil && sample!.expected != expected }
    var health: Health {
        guard fresh, let sample, let expected, validIP(expected), !policyChanged else { return .unknown }
        if sample.status == "wrong_exit" { return .bad }
        if sample.status == "healthy", !sample.checks.isEmpty,
           sample.checks.allSatisfy({ $0.status == "healthy" && !$0.observed.isEmpty && $0.observed.allSatisfy({ $0 == expected }) }) { return .good }
        return .warning
    }
    var title: String {
        if policyChanged { return "Ожидается новая проверка" }
        if !fresh { return "Нет свежих данных" }
        switch health {
        case .good: return "Ожидаемый выход"
        case .bad: return "Обнаружен другой IP"
        case .warning: return "Не удалось подтвердить выход"
        case .unknown: return "Нет данных"
        }
    }
    var observed: String {
        guard let sample else { return "—" }
        let ips = sample.observedIPs.filter(validIP)
        return ips.isEmpty ? "—" : ips.joined(separator: ", ")
    }
}

struct NetworkSnapshot {
    var sample: WatchSample?
    var policy: GuardPolicy?
    var watcher = JobState()
    var firewall = JobState()
    var route: String?
    var acceptance: Acceptance?
    var readAt = Date()
    var readError: String?
    var policyError = false
    func fresh(at now: Date) -> Bool {
        guard let date = sample?.date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= -30 && age <= 150
    }
    func services(at now: Date) -> [ServiceState] {
        ["OPENAI", "CLAUDE"].map { id in
            let match = sample?.services.filter { $0.service == id } ?? []
            return ServiceState(id: id, sample: match.count == 1 ? match.first : nil,
                                expected: policy?.services[id]?.expected_ip, fresh: fresh(at: now))
        }
    }
    func health(at now: Date) -> Health {
        let states = services(at: now)
        if states.contains(where: { $0.health == .bad }) { return .bad }
        guard readError == nil, !policyError, fresh(at: now), route?.hasPrefix("utun") == true,
              sample?.interface == route, sample?.status == "healthy",
              watcher.healthy, watcher.enforcing, firewall.healthy,
              states.allSatisfy({ $0.health == .good }) else { return .warning }
        return .good
    }
    func headline(at now: Date) -> String {
        if health(at: now) == .bad { return "Проверьте выходной IP" }
        if sample == nil { return "Ожидание данных" }
        if !fresh(at: now) { return "Проверка устарела" }
        if route?.hasPrefix("utun") != true { return "Туннель не обнаружен" }
        if sample?.interface != route { return "Маршрут изменился" }
        if !watcher.healthy || !watcher.enforcing { return "Watcher требует внимания" }
        if !firewall.healthy { return firewall.loaded ? "Защита требует внимания" : "Служба защиты не загружена" }
        if health(at: now) == .good { return "Маршруты в порядке" }
        return "Есть что проверить"
    }
    var checkDate: Date? { sample?.date }
    var firewallVerificationDate: Date? {
        guard acceptance?.status == "installed_and_verified", acceptance?.pf_physical_tcp_tests?.pass == true,
              let at = acceptance?.at else { return nil }
        return parseDate(at)
    }
    func diagnostic(at now: Date) -> String {
        var lines = ["AI Network · сводка состояния", "Считано: \(readAt.formatted())", headline(at: now),
                     "Маршрут: \(route ?? "не определён")", "Watcher: \(watcher.description)",
                     "Реакция watcher: \(watcher.enforcing ? "проверка с защитой" : "не подтверждена")",
                     "Служба kill switch: \(firewall.description)",
                     "Правила PF сейчас не проверялись: приложение работает без прав администратора."]
        if let date = checkDate { lines.append("IP-проверка: \(date.formatted())") }
        for s in services(at: now) { lines.append("\(s.name): \(s.title); наблюдался \(s.observed); ожидается \(s.expected ?? "не задан")") }
        if let date = firewallVerificationDate { lines.append("Последняя сохранённая проверка блокировки: \(date.formatted())") }
        return lines.joined(separator: "\n")
    }
}

func parseDate(_ value: String) -> Date? {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = format.date(from: value) { return date }
    format.formatOptions = [.withInternetDateTime]
    return format.date(from: value)
}
func validIP(_ value: String) -> Bool {
    var v4 = in_addr(); var v6 = in6_addr()
    return value.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
}

struct Paths {
    let root: URL
    let home: URL
    static var current: Paths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Paths(root: home.appendingPathComponent("custom-network/shadowrocket-config"), home: home)
    }
    var status: URL { home.appendingPathComponent("Library/Caches/ai-watch/status.json") }
    var policy: URL { root.appendingPathComponent("out/mac-guards/policy.json") }
    var acceptance: URL { root.appendingPathComponent("out/mac-guards/acceptance.json") }
    var log: URL { home.appendingPathComponent("Library/Logs/ai-watch.jsonl") }
}

struct CommandResult { var output: String; var exit: Int32 }
func readCommand(_ path: String, _ args: [String]) -> CommandResult {
    // Fixed executable/arguments only. No shell, sudo, probe, signal or launchctl mutation.
    let task = Process(); task.executableURL = URL(fileURLWithPath: path); task.arguments = args
    let stdout = Pipe(); let stderr = Pipe(); task.standardOutput = stdout; task.standardError = stderr
    let done = DispatchSemaphore(value: 0)
    task.terminationHandler = { _ in done.signal() }
    do { try task.run() } catch { return CommandResult(output: "", exit: -1) }
    if done.wait(timeout: .now() + 3) == .timedOut {
        // Only terminate the read-only child process launched by this app.
        task.terminate()
        return CommandResult(output: "", exit: -2)
    }
    return CommandResult(output: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "", exit: task.terminationStatus)
}
func decodeFile<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 131072 else { throw CocoaError(.fileReadTooLarge) }
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
}
func loadSnapshot(paths: Paths) -> NetworkSnapshot {
    var state = NetworkSnapshot()
    do { state.sample = try decodeFile(WatchSample.self, at: paths.status) }
    catch { state.readError = "Нет доступного отчёта watcher" }
    do { state.policy = try decodeFile(GuardPolicy.self, at: paths.policy) }
    catch { state.policyError = true }
    state.acceptance = try? decodeFile(Acceptance.self, at: paths.acceptance)
    let user = readCommand("/bin/launchctl", ["print", "gui/\(getuid())/com.local.ai-watch"])
    let system = readCommand("/bin/launchctl", ["print", "system/com.local.artme-ai-guard"])
    state.watcher = JobState.parse(user.output, exit: user.exit)
    state.firewall = JobState.parse(system.output, exit: system.exit)
    let route = readCommand("/sbin/route", ["-n", "get", "default"])
    if route.exit == 0 {
        state.route = route.output.components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("interface:") })?
            .components(separatedBy: "interface:").last?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    state.readAt = Date()
    return state
}
