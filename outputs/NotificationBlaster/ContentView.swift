import SwiftUI
import Combine
import UserNotifications

@MainActor
final class Blaster: ObservableObject {
    @Published var isRunning = false
    @Published var scheduledCount = 0
    @Published var status = "Ready"

    private let center = UNUserNotificationCenter.current()
    private let notificationCategory = "ORDER_SIMULATOR"
    private var identifiers: [String] = []
    private let queueSize = 60
    private var activeRunID: UUID?

    func start(minimum: Double, maximum: Double, orderNumber: String, amount: String, itemCount: Int, store: String) {
        guard !isRunning else { return }
        guard minimum > 0, maximum >= minimum else {
            status = "Enter valid delay values."
            return
        }

        let order = orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = store.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !order.isEmpty, !price.isEmpty, !domain.isEmpty, itemCount > 0 else {
            status = "Fill in the order, amount, items, and store."
            return
        }

        let runID = UUID()
        activeRunID = runID
        isRunning = true
        status = "Requesting notification permission…"

        center.setNotificationCategories([\n            UNNotificationCategory(identifier: notificationCategory, actions: [], intentIdentifiers: [], options: [])\n        ])\n\n        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.activeRunID == runID else { return }
                guard granted else {
                    self.isRunning = false
                    self.activeRunID = nil
                    self.status = error?.localizedDescription ?? "Allow notifications in Settings to start."
                    return
                }
                self.schedule(
                    runID: runID,
                    minimum: minimum,
                    maximum: maximum,
                    orderNumber: order,
                    amount: price,
                    itemCount: itemCount,
                    store: domain
                )
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

    private func schedule(
        runID: UUID,
        minimum: Double,
        maximum: Double,
        orderNumber: String,
        amount: String,
        itemCount: Int,
        store: String
    ) {
        let title = "Order #\(orderNumber)"
        let itemWord = itemCount == 1 ? "item" : "items"
        let body = "$\(amount), \(itemCount) \(itemWord) from \(store)"

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
    @State private var orderNumber = "1048"
    @State private var amount = "249.98"
    @State private var itemCount = "2"
    @State private var store = "larptom.com"

    private var minimum: Double { Double(minimumDelay) ?? 0 }
    private var maximum: Double { Double(maximumDelay) ?? 0 }
    private var items: Int { Int(itemCount) ?? 0 }
    private var validDelays: Bool { minimum > 0 && maximum >= minimum }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image("AppIconPreview")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text("Order Notification Simulator")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text("Personal local-notification simulator")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.top, 18)

                Button {
                    if blaster.isRunning {
                        blaster.stop()
                    } else {
                        blaster.start(
                            minimum: minimum,
                            maximum: maximum,
                            orderNumber: orderNumber,
                            amount: amount,
                            itemCount: items,
                            store: store
                        )
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: blaster.isRunning ? "stop.fill" : "play.fill")
                        Text(blaster.isRunning ? "Stop" : "Start")
                    }
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .foregroundStyle(.white)
                    .background(
                        blaster.isRunning ? Color.red : Color.green,
                        in: RoundedRectangle(cornerRadius: 20)
                    )
                }
                .disabled(!blaster.isRunning && (!validDelays || items <= 0))

                section("ORDER NOTIFICATION") {
                    formRow("Order number", text: $orderNumber)
                    Divider()
                    formRow("Amount", text: $amount, prefix: "$")
                    Divider()
                    formRow("Items", text: $itemCount)
                    Divider()
                    formRow("Store / domain", text: $store)
                }

                section("DELIVERY") {
                    formRow("Minimum delay", text: $minimumDelay, suffix: "sec")
                    Divider()
                    formRow("Maximum delay", text: $maximumDelay, suffix: "sec")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("PREVIEW")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Order #\(orderNumber.isEmpty ? "1048" : orderNumber)")
                            .font(.headline)
                        Text("$\(amount.isEmpty ? "249.98" : amount), \(items == 1 ? "1 item" : "\(items) items") from \(store.isEmpty ? "larptom.com" : store)")
                            .font(.subheadline)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
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

                Text("Simulator only — notifications are generated locally on this iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func formRow(_ title: String, text: Binding<String>, prefix: String? = nil, suffix: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()

            if let prefix {
                Text(prefix)
                    .foregroundStyle(.secondary)
            }

            TextField(title, text: text)
                .keyboardType(title == "Order number" || title == "Store / domain" ? .default : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 130)

            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 15)
    }
}
