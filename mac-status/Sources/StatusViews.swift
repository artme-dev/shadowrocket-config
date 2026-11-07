import SwiftUI
import AppKit
import Combine

extension Health {
    var color: Color { switch self { case .good: return .green; case .bad: return .red; case .warning: return .orange; case .unknown: return .secondary } }
    var symbol: String { switch self { case .good: return "checkmark.circle.fill"; case .bad: return "exclamationmark.circle.fill"; case .warning: return "exclamationmark.triangle.fill"; case .unknown: return "questionmark.circle" } }
}

final class StatusStore: ObservableObject {
    @Published var snapshot = NetworkSnapshot()
    @Published var refreshing = false
    @Published var now = Date()
    let paths = Paths.current
    var onChange: (() -> Void)?
    private var timer: Timer?
    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        guard !refreshing else { return }
        refreshing = true; now = Date()
        let paths = self.paths
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let next = loadSnapshot(paths: paths)
            DispatchQueue.main.async {
                guard let self else { return }
                self.snapshot = next; self.now = Date(); self.refreshing = false; self.onChange?()
            }
        }
    }
    func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.diagnostic(at: Date()), forType: .string)
    }
    func showLog() { NSWorkspace.shared.activateFileViewerSelecting([paths.log]) }
    var age: String {
        guard let date = snapshot.checkDate else { return "Пока нет проверок" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < -30 { return "Время проверки некорректно" }
        if seconds < 10 { return "Проверено только что" }
        if seconds < 60 { return "Проверено \(seconds) с назад" }
        if seconds < 3600 { return "Проверено \(seconds / 60) мин назад" }
        return "Проверка: \(ruDate(date))"
    }
}

struct StatusHeader: View {
    @ObservedObject var store: StatusStore
    var body: some View {
        let health = store.snapshot.health(at: store.now)
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: health.symbol)
                .font(.system(size: 30, weight: .regular)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(health.color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.snapshot.headline(at: store.now)).font(.system(size: 16, weight: .semibold))
                Text(store.age).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ServiceRow: View {
    let service: ServiceState
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.45))
                Image(systemName: service.id == "OPENAI" ? "sparkle" : "asterisk")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(.primary)
            }.frame(width: 34, height: 34).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(service.name).font(.system(size: 13, weight: .semibold))
                Text(service.observed).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer(minLength: 4)
            Image(systemName: service.health.symbol).foregroundStyle(service.health.color)
                .font(.system(size: 14)).help(service.title)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(service.name). \(service.title). Выходной IP: \(service.observed)")
    }
}

struct GroupSurface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.045), lineWidth: 0.5))
    }
}

struct ProtectionRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let health: Health
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.secondary)
                .frame(width: 20, height: 19).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 4)
                    Text(value).font(.system(size: 12)).foregroundStyle(health == .good ? Color.secondary : health.color)
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(13).accessibilityElement(children: .combine)
    }
}

struct StatusPanel: View {
    @ObservedObject var store: StatusStore
    var showDetails: () -> Void
    var quit: () -> Void
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("AI Network").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Только просмотр").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
            StatusHeader(store: store)
            VStack(alignment: .leading, spacing: 7) {
                Text("ВЫХОДНЫЕ АДРЕСА").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 3)
                GroupSurface {
                    ForEach(Array(store.snapshot.services(at: store.now).enumerated()), id: \.element.id) { index, service in
                        if index > 0 { Divider().padding(.leading, 58) }
                        ServiceRow(service: service)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("ЗАЩИТА MAC").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 3)
                GroupSurface {
                    ProtectionRow(icon: "eye", title: "Watcher",
                                  value: watcherValue,
                                  detail: store.snapshot.watcher.enforcing ? "Проверяет IP раз в минуту" : "Режим с закрытием приложений не подтверждён",
                                  health: store.snapshot.watcher.healthy && store.snapshot.watcher.enforcing ? .good : .warning)
                    Divider().padding(.leading, 43)
                    ProtectionRow(icon: "shield.lefthalf.filled", title: "Kill switch",
                                  value: store.snapshot.firewall.healthy ? "Служба работает" : store.snapshot.firewall.description,
                                  detail: firewallDetail,
                                  health: store.snapshot.firewall.healthy ? .good : .warning)
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "network").accessibilityHidden(true)
                Text(store.snapshot.route?.hasPrefix("utun") == true ? "Туннель · \(store.snapshot.route!)" : "Маршрут: \(store.snapshot.route ?? "не определён")")
                Spacer()
                Button("Подробнее…", action: showDetails).buttonStyle(.link)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 2)
            Divider()
            HStack(spacing: 8) {
                Button(action: { store.refresh() }) {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }.keyboardShortcut("r", modifiers: .command).disabled(store.refreshing)
                    .help("Перечитать локальные статусы. Новые сетевые проверки выполняет watcher.")
                Spacer()
                Button(action: {
                    store.copySummary(); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }) { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .accessibilityLabel(copied ? "Сводка скопирована" : "Скопировать сводку")
                    .help("Скопировать сводку без ключей и паролей")
                Button(action: quit) { Image(systemName: "power") }
                    .accessibilityLabel("Выйти из AI Network").help("Выйти. Watcher и firewall продолжат работать.")
            }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(18).frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }
    var watcherValue: String {
        let w = store.snapshot.watcher
        if w.healthy && w.enforcing { return "Включён" }
        return w.description
    }
    var firewallDetail: String {
        if let date = store.snapshot.firewallVerificationDate {
            return "Блокировка проверена \(date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))))"
        }
        return "Нет сохранённой проверки блокировки"
    }
}

struct DetailView: View {
    @ObservedObject var store: StatusStore
    var body: some View {
        Form {
            Section {
                StatusHeader(store: store).padding(.vertical, 6)
                LabeledContent("Последняя IP-проверка", value: store.snapshot.checkDate.map { ruDate($0, seconds: true) } ?? "Нет данных")
                LabeledContent("Туннель", value: store.snapshot.route ?? "Не обнаружен")
                LabeledContent("Статус считан", value: ruDate(store.snapshot.readAt, date: false, seconds: true))
            }
            ForEach(store.snapshot.services(at: store.now)) { service in
                Section(service.name) {
                    LabeledContent("Результат") { Label(service.title, systemImage: service.health.symbol).foregroundStyle(service.health.color) }
                    LabeledContent("Ожидаемый IP", value: service.expected ?? "Нет данных").textSelection(.enabled)
                    LabeledContent("Наблюдаемый IP", value: service.observed).textSelection(.enabled)
                    if let sample = service.sample {
                        ForEach(Array(sample.checks.enumerated()), id: \.offset) { _, check in
                            LabeledContent(URL(string: check.endpoint)?.host ?? "Проверка") {
                                Text(check.status == "healthy" && service.fresh ? "Подтверждён" : service.fresh ? "Не подтверждён" : "Устарело")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Защита") {
                LabeledContent("Watcher", value: store.snapshot.watcher.description)
                LabeledContent("Реакция OpenAI", value: store.snapshot.watcher.enforcing ? "Закрытие при неверном IP" : "Не подтверждена")
                LabeledContent("Реакция Claude", value: "Предупреждение")
                LabeledContent("Служба kill switch", value: store.snapshot.firewall.description)
                LabeledContent("Проверка блокировки", value: store.snapshot.firewallVerificationDate.map { ruDate($0) } ?? "Нет сохранённого отчёта")
                Text("Состояние службы и последняя проверка правил показаны отдельно. Чтение текущих правил PF требует прав администратора и здесь не выполняется.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Text("Приложение перечитывает локальные данные каждые 15 секунд. Сетевые проверки выполняет watcher раз в минуту. Проверка старше 2½ минут помечается как устаревшая.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Выход из приложения не останавливает watcher, firewall или VPN.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .frame(minWidth: 540, idealWidth: 580, minHeight: 600, idealHeight: 700)

    }
}

func ruDate(_ value: Date, date: Bool = true, seconds: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = date ? (seconds ? "d MMM, HH:mm:ss" : "d MMM, HH:mm") : "HH:mm:ss"
    return formatter.string(from: value)
}
