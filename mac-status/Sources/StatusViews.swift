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

struct GlassDivider: View {
    var body: some View { Divider() }
}

enum ServiceArtwork {
    static let images: [String: NSImage] = {
        var images: [String: NSImage] = [:]
        let candidates = ["OPENAI": ["com.openai.chat", "com.openai.codex"],
                          "CLAUDE": ["com.anthropic.claudefordesktop"]]
        for (service, identifiers) in candidates {
            if let url = identifiers.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
                images[service] = NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return images
    }()
}

struct ServiceRow: View {
    let service: ServiceState
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let image = ServiceArtwork.images[service.id] {
                    Image(nsImage: image).resizable().interpolation(.high).frame(width: 34, height: 34)
                } else {
                    Image(systemName: service.id == "OPENAI" ? "sparkle" : "asterisk")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(service.health == .good ? Color.green : service.health.color)
                        .frame(width: 34, height: 34).background(.white, in: Circle())
                }
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name).font(.system(size: 13.5, weight: .semibold))
                Text(service.observed).font(.system(size: 13)).monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.82)).lineLimit(1).truncationMode(.middle)

            }
            Spacer(minLength: 4)
            Image(systemName: service.health == .good ? "checkmark" : service.health.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(service.health == .good ? Color.primary.opacity(0.8) : service.health.color)
                .help(service.title)
        }
        .frame(height: 47)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(service.name). \(service.title). Выходной IP: \(service.observed)")
    }
}

struct GlassAction: View {
    let title: String
    var symbol: String? = nil
    var help: String = ""
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if let symbol { Image(systemName: symbol).font(.system(size: 12)) }
            }
            .padding(.horizontal, 7).padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(.white.opacity(hovering ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.help(help)
        .padding(.horizontal, -7)
    }
}

struct ProtectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.icon.frame(width: 20); configuration.title }
    }
}

struct StatusPanel: View {
    @ObservedObject var store: StatusStore
    var showDetails: () -> Void
    var quit: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI Network").font(.system(size: 15, weight: .bold))
                Spacer()
                Image(systemName: store.snapshot.health(at: store.now).symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(store.snapshot.health(at: store.now).color).accessibilityHidden(true)
            }
            Text(store.snapshot.headline(at: store.now))
                .font(.system(size: 13, weight: .medium)).padding(.top, 10).lineLimit(1)
            Text(store.age).font(.system(size: 12.5)).foregroundStyle(.primary.opacity(0.82)).padding(.top, 3)
            GlassDivider().padding(.vertical, 12)
            Text("Выходные адреса").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader).padding(.bottom, 6)
            ForEach(store.snapshot.services(at: store.now)) { ServiceRow(service: $0) }
            GlassDivider().padding(.vertical, 12)
            Text("Защита").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader).padding(.bottom, 10)
            HStack {
                Label("Watcher", systemImage: "eye").labelStyle(ProtectionLabelStyle())
                Spacer()
                Text(watcherValue).foregroundStyle(.primary.opacity(0.82))
            }.font(.system(size: 13)).lineLimit(1)
            HStack {
                Label("Kill switch", systemImage: "shield.lefthalf.filled").labelStyle(ProtectionLabelStyle())
                Spacer()
                Text(store.snapshot.firewall.healthy ? "Служба работает" : "Требует внимания")
                    .foregroundStyle(.primary.opacity(0.82))
            }.font(.system(size: 13)).padding(.top, 10).lineLimit(1)
            Text(firewallDetail).font(.system(size: 11.5)).foregroundStyle(.primary.opacity(0.82))
                .padding(.top, 6).padding(.leading, 28)
            GlassDivider().padding(.top, 12).padding(.bottom, 5)
            GlassAction(title: "Обновить данные", symbol: "arrow.clockwise",
                        help: "Перечитать локальные статусы. Сетевые пробы выполняет watcher.", action: store.refresh)
                .keyboardShortcut("r", modifiers: .command).disabled(store.refreshing)
            GlassAction(title: "Подробнее…", action: showDetails)
        }
        .padding(15).frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }
    var watcherValue: String {
        if store.snapshot.watcher.healthy && store.snapshot.watcher.enforcing { return "Включён" }
        return store.snapshot.watcher.loaded ? "Требует внимания" : "Выключен"
    }
    var firewallDetail: String {
        if let date = store.snapshot.firewallVerificationDate {
            return "Блокировка проверена \(date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))))"
        }
        return "Нет сохранённой проверки блокировки"
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .bold)).accessibilityAddTraits(.isHeader)
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct DetailLine: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 18)
            Text(value).foregroundStyle(.primary.opacity(0.82)).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size: 13))
    }
}

struct DetailView: View {
    @ObservedObject var store: StatusStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("AI Network").font(.system(size: 20, weight: .bold))
                        Text(store.snapshot.headline(at: store.now)).font(.system(size: 13.5))
                    }
                    Spacer()
                    Image(systemName: store.snapshot.health(at: store.now).symbol)
                        .font(.system(size: 23)).foregroundStyle(store.snapshot.health(at: store.now).color)
                }
                Text(store.age).font(.system(size: 12.5)).foregroundStyle(.primary.opacity(0.82))
                GlassDivider()
                ForEach(store.snapshot.services(at: store.now)) { service in
                    DetailSection(title: service.name) {
                        DetailLine(title: "Результат", value: service.title)
                        DetailLine(title: "Ожидаемый IP", value: service.expected ?? "Нет данных")
                        DetailLine(title: "Наблюдаемый IP", value: service.observed)
                        if let sample = service.sample {
                            ForEach(Array(sample.checks.enumerated()), id: \.offset) { _, check in
                                DetailLine(title: URL(string: check.endpoint)?.host ?? "Проверка",
                                           value: check.status == "healthy" && service.fresh ? "Подтверждён" : "Не подтверждён")
                            }
                        }
                    }
                    GlassDivider()
                }
                DetailSection(title: "Защита Mac") {
                    DetailLine(title: "Watcher", value: store.snapshot.watcher.description)
                    DetailLine(title: "OpenAI", value: store.snapshot.watcher.enforcing ? "Закрытие при неверном IP" : "Режим не подтверждён")
                    DetailLine(title: "Claude", value: "Предупреждение")
                    DetailLine(title: "Служба kill switch", value: store.snapshot.firewall.description)
                    DetailLine(title: "Проверка блокировки", value: store.snapshot.firewallVerificationDate.map { ruDate($0) } ?? "Нет отчёта")
                    Text("Здесь показаны состояние службы и дата сохранённой проверки. Текущие правила firewall требуют прав администратора и приложением не проверяются.")
                        .font(.system(size: 12)).foregroundStyle(.primary.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
                }
                GlassDivider()
                DetailSection(title: "Последняя проверка") {
                    DetailLine(title: "IP-проверка", value: store.snapshot.checkDate.map { ruDate($0, seconds: true) } ?? "Нет данных")
                    DetailLine(title: "Туннель", value: store.snapshot.route ?? "Не обнаружен")
                    Text("Watcher проверяет IP раз в минуту. Приложение обновляет локальные данные каждые 15 секунд. Выход из приложения не останавливает защиту.")
                        .font(.system(size: 12)).foregroundStyle(.primary.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(22)
        }
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .frame(minWidth: 480, minHeight: 500)
    }
}

func ruDate(_ value: Date, date: Bool = true, seconds: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = date ? (seconds ? "d MMM, HH:mm:ss" : "d MMM, HH:mm") : "HH:mm:ss"
    return formatter.string(from: value)
}
