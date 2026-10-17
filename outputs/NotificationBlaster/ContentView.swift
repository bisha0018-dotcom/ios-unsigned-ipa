import SwiftUI
import Combine
import UserNotifications
import WebKit

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
    @State private var showNotificationSimulator = false

    var body: some View {
        DashboardWebView {
            showNotificationSimulator = true
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showNotificationSimulator) {
            NavigationStack {
                NotificationSimulatorView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Back to dashboard") {
                                showNotificationSimulator = false
                            }
                        }
                    }
            }
            .preferredColorScheme(.light)
        }
    }
}

private struct DashboardWebView: UIViewRepresentable {
    let onOpenSimulator: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenSimulator: onOpenSimulator)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "openNotificationSimulator")
        let script = """
        document.addEventListener('click', function(event) {
          const button = event.target && event.target.closest
            ? event.target.closest('button[aria-label*="menu" i], [role="button"][aria-label*="menu" i]')
            : null;
          if (button) {
            event.preventDefault();
            event.stopImmediatePropagation();
            window.webkit.messageHandlers.openNotificationSimulator.postMessage('open');
          }
        }, true);
        """
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.setURLSchemeHandler(DashboardSchemeHandler(), forURLScheme: "larptom")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        if let url = URL(string: "larptom://bundle/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onOpenSimulator: () -> Void
        init(onOpenSimulator: @escaping () -> Void) { self.onOpenSimulator = onOpenSimulator }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "openNotificationSimulator" else { return }
            DispatchQueue.main.async { self.onOpenSimulator() }
        }
    }
}

private final class DashboardSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let pathParts = url.path.split(separator: "/").map(String.init)
        guard !pathParts.isEmpty,
              pathParts.allSatisfy({ $0 != "." && $0 != ".." }),
              let fileName = pathParts.last else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let subdirectory = pathParts.count > 1
            ? "Dashboard/" + pathParts.dropLast().joined(separator: "/")
            : "Dashboard"

        guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: subdirectory),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let ext = fileURL.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "html": mime = "text/html"
        case "js", "mjs": mime = "application/javascript"
        case "css": mime = "text/css"
        case "json", "geojson": mime = "application/json"
        case "svg": mime = "image/svg+xml"
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "webp": mime = "image/webp"
        case "mp3": mime = "audio/mpeg"
        case "woff": mime = "font/woff"
        case "woff2": mime = "font/woff2"
        case "ttf": mime = "font/ttf"
        case "otf": mime = "font/otf"
        default: mime = "application/octet-stream"
        }

        let response = URLResponse(
            url: url,
            mimeType: mime,
            expectedContentLength: data.count,
            textEncodingName: ext == "html" || ext == "js" || ext == "mjs" || ext == "css" || ext == "json" ? "utf-8" : nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

struct NotificationSimulatorView: View {
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
