import SwiftUI
import WebKit

struct USCISWebView: View {
    let receiptNumber: String
    let onStatusFetched: (CaseStatus) -> Void
    let onError: (String) -> Void
    let onDismiss: () -> Void

    @State private var showWebView = true
    @State private var statusText = "Loading USCIS..."
    @State private var didExtract = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { onDismiss() }
                    .font(.subheadline)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if showWebView {
                WebViewRepresentable(
                    receiptNumber: receiptNumber,
                    onPageReady: { isChallenge in
                        statusText = isChallenge
                            ? "Please complete the verification below"
                            : "Reading case status..."
                    },
                    onStatusExtracted: { status in
                        guard !didExtract else { return }
                        didExtract = true
                        showWebView = false
                        if !status.title.isEmpty || !status.details.isEmpty {
                            onStatusFetched(status)
                        } else {
                            onError("Could not read status. Please try again.")
                        }
                    },
                    onError: { error in
                        guard !didExtract else { return }
                        didExtract = true
                        onError(error)
                    }
                )
                .frame(minHeight: 400)
            }
        }
    }
}

#if os(iOS)
struct WebViewRepresentable: UIViewRepresentable {
    let receiptNumber: String
    let onPageReady: (Bool) -> Void
    let onStatusExtracted: (CaseStatus) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.loadStatus(in: wv, receipt: receiptNumber)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(onPageReady: onPageReady, onStatusExtracted: onStatusExtracted, onError: onError)
    }
}
#else
struct WebViewRepresentable: NSViewRepresentable {
    let receiptNumber: String
    let onPageReady: (Bool) -> Void
    let onStatusExtracted: (CaseStatus) -> Void
    let onError: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        context.coordinator.loadStatus(in: wv, receipt: receiptNumber)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(onPageReady: onPageReady, onStatusExtracted: onStatusExtracted, onError: onError)
    }
}
#endif

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    let onPageReady: (Bool) -> Void
    let onStatusExtracted: (CaseStatus) -> Void
    let onError: (String) -> Void
    private var hasExtracted = false
    private var pollCount = 0
    private let maxPolls = 30

    init(onPageReady: @escaping (Bool) -> Void,
         onStatusExtracted: @escaping (CaseStatus) -> Void,
         onError: @escaping (String) -> Void) {
        self.onPageReady = onPageReady
        self.onStatusExtracted = onStatusExtracted
        self.onError = onError
    }

    func loadStatus(in webView: WKWebView, receipt: String) {
        guard let url = USCISService.buildStatusURL(for: receipt) else { return }
        let body = USCISService.buildPOSTBody(for: receipt)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 60
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollForStatus(in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onError(error.localizedDescription)
    }

    private func pollForStatus(in webView: WKWebView) {
        guard !hasExtracted, pollCount < maxPolls else { return }
        pollCount += 1

        webView.evaluateJavaScript(USCISService.cloudflareCheckJS) { [weak self] result, _ in
            guard let self = self else { return }
            let state = result as? String ?? "ready"

            if state == "challenge" {
                self.onPageReady(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.pollForStatus(in: webView)
                }
            } else {
                self.onPageReady(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.extractStatus(from: webView)
                }
            }
        }
    }

    private func extractStatus(from webView: WKWebView) {
        guard !hasExtracted else { return }

        webView.evaluateJavaScript(USCISService.extractionJS) { [weak self] result, _ in
            guard let self = self, !self.hasExtracted else { return }
            self.hasExtracted = true

            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(CaseStatus.self, from: data) {
                self.onStatusExtracted(parsed)
            } else {
                self.onStatusExtracted(CaseStatus(title: "", details: ""))
            }
        }
    }
}
