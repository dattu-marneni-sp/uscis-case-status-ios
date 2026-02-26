import SwiftUI
import WebKit

/// Hidden WebView used as fallback when URLSession is blocked by Cloudflare.
/// Loads USCIS page, submits form via JS, extracts status. Stays invisible in view hierarchy.
struct USCISWebView: View {
    let receiptNumber: String
    let onComplete: (Result<CaseStatus, Error>) -> Void

    var body: some View {
        WebViewRepresentable(receiptNumber: receiptNumber, onComplete: onComplete)
            .frame(width: 100, height: 100)
            .opacity(0)
            .allowsHitTesting(false)
    }
}

#if os(iOS)
private struct WebViewRepresentable: UIViewRepresentable {
    let receiptNumber: String
    let onComplete: (Result<CaseStatus, Error>) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = makeWebViewConfig()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let shouldLoad = !coordinator.hasStartedLoad || coordinator.receiptNumber != receiptNumber
        guard shouldLoad else { return }
        coordinator.receiptNumber = receiptNumber
        coordinator.onComplete = onComplete
        coordinator.hasStartedLoad = true
        coordinator.hasSubmittedForm = false
        coordinator.startTimeout()
        guard let url = URL(string: "https://egov.uscis.gov/casestatus/landing.do") else {
            onComplete(.failure(USCISError.parsingError))
            return
        }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(receiptNumber: receiptNumber, onComplete: onComplete)
    }
}
#else
private struct WebViewRepresentable: NSViewRepresentable {
    let receiptNumber: String
    let onComplete: (Result<CaseStatus, Error>) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = makeWebViewConfig()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let shouldLoad = !coordinator.hasStartedLoad || coordinator.receiptNumber != receiptNumber
        guard shouldLoad else { return }
        coordinator.receiptNumber = receiptNumber
        coordinator.onComplete = onComplete
        coordinator.hasStartedLoad = true
        coordinator.hasSubmittedForm = false
        coordinator.startTimeout()
        guard let url = URL(string: "https://egov.uscis.gov/casestatus/landing.do") else {
            onComplete(.failure(USCISError.parsingError))
            return
        }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(receiptNumber: receiptNumber, onComplete: onComplete)
    }
}
#endif

private func makeWebViewConfig() -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    config.processPool = WKProcessPool()
    // Use Safari-like user agent so Cloudflare/PAT may auto-pass on Apple devices
    config.applicationNameForUserAgent = "Safari/605.1.15"
    return config
}

private final class Coordinator: NSObject, WKNavigationDelegate {
    var receiptNumber: String
    var onComplete: (Result<CaseStatus, Error>) -> Void
    var hasStartedLoad = false
    var hasSubmittedForm = false
    var hasCompleted = false
    var timeoutWorkItem: DispatchWorkItem?

    init(receiptNumber: String, onComplete: @escaping (Result<CaseStatus, Error>) -> Void) {
        self.receiptNumber = receiptNumber
        self.onComplete = onComplete
    }

    func startTimeout() {
        timeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.hasCompleted else { return }
            self.hasCompleted = true
            DispatchQueue.main.async {
                self.onComplete(.failure(USCISError.timeout))
            }
        }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    func finishWith(_ result: Result<CaseStatus, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        timeoutWorkItem?.cancel()
        DispatchQueue.main.async { self.onComplete(result) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString else { return }
        let isLanding = url.contains("landing.do")
        let isResult = url.contains("mycasestatus")
        if isLanding && !hasSubmittedForm {
            hasSubmittedForm = true
            submitForm(webView: webView)
        } else if isResult {
            extractStatus(webView: webView)
        }
    }

    private func submitForm(webView: WKWebView) {
        let escaped = receiptNumber
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let js = """
        (function() {
            var input = document.querySelector('input[name="appReceiptNum"]') || document.querySelector('#receipt_number') || document.querySelector('#appReceiptNum');
            if (input) input.value = "\(escaped)";
            var form = document.querySelector('form');
            if (form) { form.submit(); return true; }
            return false;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                self.finishWith(.failure(error))
                return
            }
            if (result as? Bool) != true {
                self.finishWith(.failure(USCISError.parsingError))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWith(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWith(.failure(error))
    }

    private func extractStatus(webView: WKWebView) {
        webView.evaluateJavaScript(USCISService.cloudflareCheckJS) { [weak self] result, _ in
            guard let self = self else { return }
            if let check = result as? String, check == "challenge" {
                self.finishWith(.failure(USCISError.cloudflareBlocked))
                return
            }
            webView.evaluateJavaScript(USCISService.extractionJS) { [weak self] result, error in
                guard let self = self else { return }
                if let error = error {
                    self.finishWith(.failure(error))
                    return
                }
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let parsed = try? JSONDecoder().decode(ExtractionResult.self, from: data),
                      !parsed.title.isEmpty || !parsed.details.isEmpty else {
                    self.finishWith(.failure(USCISError.parsingError))
                    return
                }
                self.finishWith(.success(CaseStatus(title: parsed.title, details: parsed.details)))
            }
        }
    }
}

private struct ExtractionResult: Decodable {
    let title: String
    let details: String
}
