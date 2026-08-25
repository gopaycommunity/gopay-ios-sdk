//
//  ShareSheet.swift
//  example
//
//  SwiftUI wrapper for UIActivityViewController. `ShareLink` can't mix heterogeneous item types
//  (text + a UIImage) in one share sheet, so the bank-transfer sheet uses this instead.
//

import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {
        // No dynamic updates needed — activityItems never changes after the sheet is presented.
    }
}
