//
//  DocumentExporter.swift
//  discar
//

import SwiftUI
import UIKit

struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: (() -> Void)?
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Create document picker for exporting
        let picker = UIDocumentPickerViewController(forExporting: [url])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No update needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDismiss: (() -> Void)?
        
        init(onDismiss: (() -> Void)?) {
            self.onDismiss = onDismiss
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            print("✅ File exported to: \(urls)")
            onDismiss?()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("❌ Export cancelled")
            onDismiss?()
        }
    }
}

