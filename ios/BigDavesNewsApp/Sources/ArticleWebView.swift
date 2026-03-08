import UIKit
import SwiftUI
import WebKit

struct ArticleWebView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showCopiedAlert = false

    var body: some View {
        NavigationStack {
            ArticleContentWebView(url: url)
                .navigationTitle("Article")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                            showCopiedAlert = true
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                    }
                }
                .alert("Link copied", isPresented: $showCopiedAlert) {
                    Button("OK", role: .cancel) {}
                }
        }
    }
}

private struct ArticleContentWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == url { return }
        webView.load(URLRequest(url: url))
    }
}
