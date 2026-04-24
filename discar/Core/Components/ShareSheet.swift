//
//  ShareSheet.swift
//  discar
//
//  UIActivityViewController wrapper for sharing files
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
