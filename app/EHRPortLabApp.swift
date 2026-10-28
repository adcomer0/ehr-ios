import SwiftUI

@main
struct EHRPortLabApp: App {
    var body: some Scene {
        WindowGroup { LabView() }
    }
}

@MainActor
final class NativeRuleModel: ObservableObject {
    @Published var isRunning = false
    @Published var didPass = false
    @Published var delaySeconds = 0
    @Published var forceMeeting = false
    @Published var timeline: [String] = []
    private let core: OpaquePointer? = ehr_core_create(42)
    private var runTask: Task<Void, Never>?
    private var roundID: UInt64 = 0

    private var now: UInt64 { UInt64(ProcessInfo.processInfo.systemUptime * 1000) }

    func run() {
        guard !isRunning else { return }
        guard let core else {
            timeline = ["The native core could not allocate its state."]
            return
        }
        isRunning = true
        didPass = false
        roundID += 1
        timeline = ["Local test round started. No game is connected."]
        var config = EHRBaitConfig()
        config.enabled = 1
        config.delay_min_seconds = Int32(delaySeconds)
        config.delay_max_seconds = Int32(delaySeconds)
        config.force_meeting = forceMeeting ? 1 : 0
        _ = ehr_core_configure(core, config)
        ehr_core_begin_round(core, roundID, 1)
        var event = EHRMurderEvent()
        event.event_id = roundID
        event.round_id = roundID
        event.monotonic_ms = now
        event.killer_id = 1
        event.victim_id = 2
        event.victim_is_bait = 1
        event.killer_is_exempt = 0
        let status = ehr_core_confirmed_murder(core, event)
        guard status == EHR_SCHEDULED else {
            timeline.append("Native rule did not schedule the expected action.")
            isRunning = false
            return
        }
        timeline.append("Simulated killer 1 killed Bait 2.")
        let expectedDelay = max(150, delaySeconds * 1000)
        timeline.append("Report scheduled after \(expectedDelay) ms.")
        runTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(expectedDelay + 30))
            guard !Task.isCancelled, let self else { return }
            self.finish(core)
        }
    }

    private func finish(_ core: OpaquePointer) {
        var action = EHRAction()
        let emitted = ehr_core_poll(core, now, &action)
        didPass = emitted == 1 && action.reporter_id == 1 && action.victim_id == 2
        if didPass {
            timeline.append(action.kind == EHR_FORCE_MEETING
                ? "Native core emitted a force-meeting action."
                : "Native core emitted a report-body action.")
            timeline.append("Check passed. No action was sent to Among Us.")
            print("EHR_PORT_LAB_NATIVE_CHECK_PASS adapter=unavailable")
        } else {
            timeline.append("Check failed: the expected native action was missing.")
        }
        isRunning = false
    }

    func cancel() {
        guard isRunning else { return }
        runTask?.cancel()
        ehr_core_set_phase(core, EHR_MEETING)
        isRunning = false
        timeline.append("Simulation stopped; pending action discarded.")
    }

    deinit {
        runTask?.cancel()
        ehr_core_destroy(core)
    }
}

struct LabView: View {
    @StateObject private var model = NativeRuleModel()
    @State private var showAbout = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("EHR, on-device")
                            .font(.largeTitle.bold())
                        Text("Native integration lab")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Game connection unavailable", systemImage: "exclamationmark.circle.fill")
                            .font(.headline).foregroundStyle(.orange)
                        Text("This build runs a native Bait rule simulation. It cannot host or join Among Us lobbies.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Reference: \(String(cString: ehr_core_reference_version()))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Try the native rule").font(.title2.bold())
                        Text("When Bait is killed, the killer reports the body after a short delay. This checks the rule locally, with simulated player events.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Stepper("Delay: \(model.delaySeconds) s", value: $model.delaySeconds, in: 0...5)
                            .disabled(model.isRunning)
                        Toggle("Force meeting action", isOn: $model.forceMeeting)
                            .disabled(model.isRunning)
                        Button(action: model.run) {
                            HStack {
                                if model.isRunning { ProgressView().tint(.white) }
                                Text(model.isRunning ? "Running native check…" : "Run native rule check")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent).disabled(model.isRunning)
                        .accessibilityIdentifier("run-native-check")
                        if model.didPass {
                            Label("Native check passed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.headline)
                                .accessibilityIdentifier("native-check-passed")
                        }
                        if !model.timeline.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(Array(model.timeline.enumerated()), id: \.offset) { _, text in
                                    Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What still needs to work").font(.headline)
                        Label("Inspect the exact iOS game build", systemImage: "circle")
                        Label("Connect native code to real game events", systemImage: "circle")
                        Label("Complete a round with vanilla players", systemImage: "circle")
                    }
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    Text("Independent research project. Not affiliated with or endorsed by Innersloth LLC or the EHR developers.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("EHR Port Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAbout = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings and About")
                }
            }
            .sheet(isPresented: $showAbout) { AboutView() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.cancel() }
            }
            .task {
                if ProcessInfo.processInfo.arguments.contains("--native-self-check") { model.run() }
                if ProcessInfo.processInfo.arguments.contains("--show-about") { showAbout = true }
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unavailable"
        let build = info["CFBundleVersion"] as? String ?? "unavailable"
        return "Version \(version) (\(build))"
    }
    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    Text("EHR Port Lab").font(.headline)
                    Text(version).textSelection(.enabled).accessibilityIdentifier("artifact-version")
                    Text("Native Bait rule experiment")
                    Text("Game adapter: unavailable")
                }
                Section("Scope") {
                    Text("This app contains no Among Us game, no copied game assets, and no playable EHR integration.")
                    Text("The native rule runs on the device. The simulation does not connect to a server.")
                }
                Section("References") {
                    Link("EHR v8.0.3 source", destination: URL(string: "https://github.com/Gurge44/EndlessHostRoles/tree/v8.0.3")!)
                    Link("Among Us mod information", destination: URL(string: "https://github.com/Innersloth-LLC/AmongUsModdingInformation")!)
                }
            }
            .navigationTitle("Settings & About")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
