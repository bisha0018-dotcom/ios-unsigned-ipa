import SwiftUI
import Combine
import UserNotifications

struct DeliveryMode: Identifiable, Hashable {
    let id: String
    let title: String
    let minimum: Double
    let maximum: Double

    static let modes: [DeliveryMode] = [
        .init(id: "normal", title: "Normal", minimum: 0.5, maximum: 2.5),
        .init(id: "fast", title: "Fast", minimum: 0.3, maximum: 1.2),
        .init(id: "faster", title: "Faster", minimum: 0.15, maximum: 0.7),
        .init(id: "rapid", title: "Rapid", minimum: 0.1, maximum: 0.4)
    ]
}

@MainActor
final class Blaster: ObservableObject {
    @Published var isRunning = false
    @Published var scheduledCount = 0
    @Published var status = "Ready"

    private let center = UNUserNotificationCenter.current()
    private let notificationCategory = "ORDER_SIMULATOR"
    private let customSoundName = UNNotificationSoundName("shopify_sale_sound.caf")
    private var identifiers: [String] = []
    private let queueSize = 63
    private var activeRunID: UUID?

    func start(mode: DeliveryMode, orderNumber: String, amount: String, itemCount: Int, store: String) {
        guard !isRunning else { return }

        let order = orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let storeName = store.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !order.isEmpty, !price.isEmpty, !storeName.isEmpty, itemCount > 0 else {
            status = "Fill in the order, amount, items, and store."
            return
        }

        let runID = UUID()
        activeRunID = runID
        isRunning = true
        status = "Requesting notification permission…"

        center.setNotificationCategories([
            UNNotificationCategory(identifier: notificationCategory, actions: [], intentIdentifiers: [], options: [])
        ])

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

                self.schedule(
                    runID: runID,
                    minimum: mode.minimum,
                    maximum: mode.maximum,
                    orderNumber: order,
                    amount: price,
                    itemCount: itemCount,
                    store: storeName
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
        let startingOrder = Int(orderNumber) ?? 1001
        let itemWord = itemCount == 1 ? "item" : "items"
        let body = "$\(amount), \(itemCount) \(itemWord) from Online Store • \(store)"

        let runIDs = (0..<queueSize).map { _ in UUID().uuidString }
        identifiers = runIDs
        scheduledCount = 0
        status = "Queued 0 of \(queueSize)"

        var elapsed = 0.0

        for (index, identifier) in runIDs.enumerated() {
            elapsed += Double.random(in: minimum...maximum)

            let content = UNMutableNotificationContent()
            content.title = "Order #\(startingOrder + index)"
            content.body = body
            content.sound = UNNotificationSound(named: customSoundName)
            content.categoryIdentifier = notificationCategory

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(elapsed, 0.1),
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

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

    @AppStorage("orderNumber") private var orderNumber = "1001"
    @AppStorage("amount") private var amount = "249.98"
    @AppStorage("itemCount") private var itemCount = "2"
    @AppStorage("store") private var store = "Ecom Paya"
    @AppStorage("deliveryMode") private var deliveryModeID = "normal"

    private var items: Int { Int(itemCount) ?? 0 }
    private var deliveryMode: DeliveryMode {
        DeliveryMode.modes.first(where: { $0.id == deliveryModeID }) ?? DeliveryMode.modes[0]
    }

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
                            mode: deliveryMode,
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
                .disabled(!blaster.isRunning && items <= 0)

                section("ORDER NOTIFICATION") {
                    formRow("Order number", text: $orderNumber)
                    Divider()
                    formRow("Amount", text: $amount, prefix: "$")
                    Divider()
                    formRow("Items", text: $itemCount)
                    Divider()
                    formRow("Store name", text: $store)
                }

                section("DELIVERY MODE") {
                    Picker("Speed", selection: $deliveryModeID) {
                        ForEach(DeliveryMode.modes) { mode in
                            Text(mode.title).tag(mode.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 14)

                    HStack {
                        Text(deliveryMode.title)
                            .font(.subheadline.bold())
                        Spacer()
                        Text(String(format: "%.2f–%.2f sec", deliveryMode.minimum, deliveryMode.maximum))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 14)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("PREVIEW")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Order #\(orderNumber.isEmpty ? "1001" : orderNumber)")
                            .font(.headline)

                        Text("$\(amount.isEmpty ? "249.98" : amount), \(items == 1 ? "1 item" : "\(items) items") from Online Store • \(store.isEmpty ? "Ecom Paya" : store)")
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

                    Text("63 per run")
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
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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

    private func formRow(
        _ title: String,
        text: Binding<String>,
        prefix: String? = nil
    ) -> some View {
        HStack {
            Text(title)
            Spacer()

            if let prefix {
                Text(prefix)
                    .foregroundStyle(.secondary)
            }

            TextField(title, text: text)
                .keyboardType(title == "Store name" ? .default : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 130)
        }
        .padding(.vertical, 15)
    }
}
