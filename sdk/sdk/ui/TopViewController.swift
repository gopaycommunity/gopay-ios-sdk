import UIKit

/// Walks the key window's view-controller hierarchy to find the controller best suited to present
/// from. Used to present the 3DS WebView when the caller doesn't supply an explicit presenter.
@MainActor
func gopayTopViewController(base: UIViewController? = nil) -> UIViewController? {
    let root: UIViewController?
    if let base = base {
        root = base
    } else if #available(iOS 13.0, *) {
        root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    } else {
        root = UIApplication.shared.keyWindow?.rootViewController
    }

    if let nav = root as? UINavigationController {
        return gopayTopViewController(base: nav.visibleViewController)
    }
    if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
        return gopayTopViewController(base: selected)
    }
    if let presented = root?.presentedViewController {
        return gopayTopViewController(base: presented)
    }
    return root
}
