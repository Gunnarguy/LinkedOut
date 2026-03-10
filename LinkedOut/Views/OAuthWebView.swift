//
//  OAuthWebView.swift
//  LinkedOut
//
//  WKWebView-based OAuth flow that intercepts the redirect URL
//  before the browser tries to load it. This avoids the Safari
//  "can't establish secure connection" error when redirecting
//  from LinkedIn's HTTPS to our local HTTP backend.
//

import SwiftUI
import WebKit

struct OAuthWebView: View {
    let url: URL
    let onResult: (String, String) -> Void  // (code, state)
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            OAuthWebViewRepresentable(url: url, callbackPath: "/auth/callback", onResult: onResult)
                .ignoresSafeArea()
                .navigationTitle("Sign in with LinkedIn")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel() }
                    }
                }
        }
    }
}

private struct OAuthWebViewRepresentable: UIViewRepresentable {
    let url: URL
    let callbackPath: String
    let onResult: (String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(callbackPath: callbackPath, onResult: onResult)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let callbackPath: String
        let onResult: (String, String) -> Void

        init(callbackPath: String, onResult: @escaping (String, String) -> Void) {
            self.callbackPath = callbackPath
            self.onResult = onResult
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Intercept the OAuth callback redirect before the browser loads it
            if url.path.hasSuffix(callbackPath),
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
               let state = components.queryItems?.first(where: { $0.name == "state" })?.value {
                decisionHandler(.cancel)
                onResult(code, state)
                return
            }

            decisionHandler(.allow)
        }
    }
}
