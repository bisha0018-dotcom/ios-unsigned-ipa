import SwiftUI
import Combine
import UserNotifications

@MainActor
final class Blaster: ObservableObject {
    @Published var isRunning = false
    @Published var scheduledCount = 0
    @Published var status = "Ready"

    private let center = UNUserNotificationCenter.current()
    private var identifiers: [String] = []
    private let queueSize = 60
    private var activeRunID: UUID?

    func start(minimum: Double, maximum: Double, message: String) {
        guard !isRunning else { return }
        guard minimum > 0, maximum >= minimum else {
            status = "Enter valid delay values."
            return
        }

        let runID = UUID()
        activeRunID = runID
        isRunning = true
        status = "Requesting notification permission…"

        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.activeRunID == runID else { return }
                guard granted else {
                    self.isRunning = false
                    self.activeRunID = nil
                    self.status = error?.localizedDescription ?? "Allow notifications in Settings to start."
                    return
                }
                self.schedule(runID: runID, minimum: minimum, maximum: maximum, message: message)
            }
        }
    }

    func stop() {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        identifiers.removeAll()
        activeRunID = nil
        isRunning = false
        status = "Stopped. Pending notifications cancelled."
    }

    private func schedule(runID: UUID, minimum: Double, maximum: Double, message: String) {
        let title = "Notification Blaster"
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Your notification is here."
            : message
        let runIDs = (0..<queueSize).map { _ in UUID().uuidString }
        identifiers = runIDs
        scheduledCount = 0
        status = "Queued 0 of \(queueSize)"

        var elapsed = 0.0
        for identifier in runIDs {
            elapsed += Double.random(in: minimum...maximum)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: elapsed, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request) { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.activeRunID == runID else { return }
                    if error == nil {
                        self.scheduledCount += 1
                        self.status = "Queued \(self.scheduledCount) of \(self.queueSize)"
                    } else {
                        self.status = error?.localizedDescription ?? "Could not schedule a notification."
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var blaster = Blaster()
    @State private var minimumDelay = "0.5"
    @State private var maximumDelay = "2.5"
    @State private var message = "Hello from Notification Blaster!"

    private var minimum: Double { Double(minimumDelay) ?? 0 }
    private var maximum: Double { Double(maximumDelay) ?? 0 }
    private var validDelays: Bool { minimum > 0 && maximum >= minimum }

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.orange)
                Text("Notification Blaster")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("A burst of local notifications")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)

            Button {
                if blaster.isRunning { blaster.stop() }
                else { blaster.start(minimum: minimum, maximum: maximum, message: message) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: blaster.isRunning ? "stop.fill" : "play.fill")
                    Text(blaster.isRunning ? "Stop" : "Start")
                }
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .foregroundStyle(.white)
                .background(blaster.isRunning ? Color.red : Color.orange, in: RoundedRectangle(cornerRadius: 22))
            }
            .disabled(!blaster.isRunning && !validDelays)

            VStack(spacing: 0) {
                delayRow(title: "Minimum delay", value: $minimumDelay)
                Divider()
                delayRow(title: "Maximum delay", value: $maximumDelay)
            }
            .padding(.horizontal, 16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 8) {
                Text("NOTIFICATION MESSAGE")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("Message", text: $message, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                Label("\(blaster.scheduledCount)", systemImage: "bell")
                    .font(.title3.bold())
                Text("scheduled")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("60 per run")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Text(blaster.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 22)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private func delayRow(title: String, value: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Seconds", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("sec")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }
}
