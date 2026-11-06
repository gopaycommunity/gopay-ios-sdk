//
//  HostedFormFields.swift
//  sdkTests
//
//  Hosts a card form in a window and finds its text fields, for the tests that check what the
//  form's UIKit fields end up with.
//

import SwiftUI
import Testing
import UIKit

/// The text fields under `view`, depth first, which is the order the card form lays them out in:
/// the card number, the expiration, the CVV.
func textFields(in view: UIView) -> [UITextField] {
    var found: [UITextField] = []
    func walk(_ view: UIView) {
        if let field = view as? UITextField { found.append(field) }
        view.subviews.forEach(walk)
    }
    walk(view)
    return found
}

/// Types `text` at the end of `field` the way the keyboard does, through the field's delegate.
@MainActor
func type(_ text: String, into field: UITextField) {
    let end = NSRange(location: (field.text ?? "").utf16.count, length: 0)
    _ = field.delegate?.textField?(field, shouldChangeCharactersIn: end, replacementString: text)
}

/// Hosts a card form in a window of `size`, shown but not key, and returns once it is on screen:
/// its three fields are there and its height has stopped changing. A loaded runner takes many
/// times longer than a quiet Mac to get there, so this waits for it rather than for a time, and
/// fails the test if the fields never come rather than letting it index past them.
///
/// Not key: the suites run side by side in one process, and the 3DS tests present their screen
/// over the key window's top view controller, which would take the focus.
@MainActor
func hostedWindow<V: View>(_ view: V, size: CGSize = CGSize(width: 390, height: 844)) async throws -> UIWindow {
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = UIHostingController(rootView: view)
    window.isHidden = false
    window.layoutIfNeeded()
    try #require(await settle(until: textFields(in: window).count == 3), "the form never showed its three fields")
    _ = await settledValue { formHeight(in: window) }
    return window
}

/// How tall the form in `window` lays out: a field showing its error is a line taller.
@MainActor
func formHeight(in window: UIWindow) -> CGFloat {
    let width = window.bounds.width
    return window.rootViewController?.view.sizeThatFits(
        CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    ).height ?? 0
}

/// Whether `field` is visible on screen: its area as drawn holds more than one color, the
/// placeholder's glyphs over the background. Under the privacy cover the area is a single flat
/// color. Measured on what is drawn, since what a cover is for is what a snapshot or a recording
/// sees.
@MainActor
func isVisible(_ field: UITextField, in window: UIWindow) -> Bool {
    window.layoutIfNeeded()
    let area = field.convert(field.bounds, to: window)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    // `layer.render` rather than `drawHierarchy`, which draws nothing in a test process.
    let image = UIGraphicsImageRenderer(bounds: area, format: format).image { context in
        window.layer.render(in: context.cgContext)
    }
    guard let cgImage = image.cgImage,
          let data = cgImage.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data) else { return false }
    let bytesPerPixel = cgImage.bitsPerPixel / 8
    var colors = Set<UInt32>()
    for y in 0..<cgImage.height {
        for x in 0..<cgImage.width {
            let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
            colors.insert(UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]))
            if colors.count > 1 { return true }
        }
    }
    return false
}
