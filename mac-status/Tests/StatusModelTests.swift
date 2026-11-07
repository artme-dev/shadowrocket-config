import Foundation
func runModelTests() -> Int32 {
    var failures = [String]()
    func check(_ condition: @autoclosure () -> Bool, _ name: String) { if !condition() { failures.append(name) } }
    let now = Date()
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let ip = "203.0.113.20"
    func sample(_ at: Date, status: String = "healthy", ip observed: String = "203.0.113.20", checks: Bool = true) -> WatchSample {
        WatchSample(at: formatter.string(from: at), mode: "enforce", interface: "utun8", services: ["OPENAI", "CLAUDE"].map {
            ServiceSample(service: $0, status: status, expected: ip,
                          checks: checks ? [TraceCheck(endpoint: "https://example.test/trace", status: status, observed: [observed])] : [], terminated: [])
        }, status: status == "healthy" ? "healthy" : "attention")
    }
    let healthyJob = JobState(loaded: true, running: false, lastExit: 0, enforcing: true)
    let policy = GuardPolicy(services: ["OPENAI": .init(expected_ip: ip), "CLAUDE": .init(expected_ip: ip)])
    var state = NetworkSnapshot(sample: sample(now), policy: policy, watcher: healthyJob, firewall: healthyJob, route: "utun8")
    check(state.health(at: now) == .good, "fresh successful checks and loaded guards are healthy")
    state.sample = sample(now.addingTimeInterval(-151))
    check(state.health(at: now) != .good, "stale success must not be green")
    state.sample = sample(now.addingTimeInterval(61))
    check(state.health(at: now) != .good, "future timestamp must not be green")
    state.sample = sample(now, status: "wrong_exit", ip: "203.0.113.99")
    check(state.health(at: now) == .bad, "fresh confirmed mismatch is red")
    state.sample = sample(now, checks: false)
    check(state.health(at: now) != .good, "empty successful report must not be green")
    state.sample = WatchSample(at: formatter.string(from: now), mode: "enforce", interface: "utun8", services: [], status: "healthy")
    check(state.health(at: now) != .good, "missing services must not be green")
    state.sample = sample(now)
    state.policy = GuardPolicy(services: ["OPENAI": .init(expected_ip: "203.0.113.99"), "CLAUDE": .init(expected_ip: ip)])
    check(state.health(at: now) != .good, "new expected policy invalidates old successful checks")
    state.policy = policy; state.watcher = JobState()
    check(state.health(at: now) != .good, "unloaded watcher must not be green")
    state.watcher = healthyJob; state.firewall = JobState()
    check(state.health(at: now) != .good, "unloaded firewall job must not be green")
    state.firewall = healthyJob; state.route = "en0"
    check(state.health(at: now) != .good, "direct default route must not be green")
    state.route = "utun9"
    check(state.health(at: now) != .good, "interface changed since check must not be green")
    state.route = "utun8"; state.sample = sample(now, ip: "203.0.113.99")
    check(state.health(at: now) != .good, "observed mismatch cannot be hidden by a healthy label")
    let text = "system/job = {\n\tstate = not running\n\tlast exit code = 0\n\tstate = active\n\t--enforce\n}"
    let job = JobState.parse(text, exit: 0)
    check(job.healthy && !job.running && job.enforcing, "scheduled idle job is not disabled")
    check(!JobState.parse(text, exit: 113).loaded, "launchctl failure is not loaded")
    check(JobState.parse("job = {\nlast exit code = 75: EX_TEMPFAIL\n}", exit: 0).lastExit == 75, "parse busy exit code")
    check(parseDate("2026-11-07T14:20:00.123456+07:00") != nil, "fractional timezone timestamp")
    check(parseDate("2026-11-07T14:20:00+07:00") != nil, "whole-second timezone timestamp")
    check(validIP("2001:db8::1") && !validIP("<html>") && !validIP("203.0.113.999"), "validate displayed IP values")
    if failures.isEmpty { print("18 status-model checks passed"); return 0 }
    failures.forEach { print("FAIL: \($0)") }; return 1
}
