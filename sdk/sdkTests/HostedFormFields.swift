//
//  HostedFormFields.swift
//  sdkTests
//
//  Finds the text fields of a card form hosted in a window, for the tests that check what the
//  form's UIKit fields end up with.
//

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
