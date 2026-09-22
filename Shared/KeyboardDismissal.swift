#if os(iOS)
import SwiftUI
import UIKit

extension View {
    /// Klavye açıkken yazı alanı dışında bir yere dokununca klavyeyi kapatır.
    ///
    /// Pencereye dokunuşları engellemeyen bir dokunma algılayıcı ekler; düğmeler ve listeler
    /// normal çalışmaya devam eder. Kök görünüme bir kez uygulanması yeterli.
    func dismissesKeyboardOnTap() -> some View {
        background(KeyboardDismissInstaller())
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private var installed: UITapGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, installed?.view !== window else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            installed = tap
        }

        @objc private func dismissKeyboard() {
            window?.endEditing(true)
        }

        // Yazı alanına dokunmak klavyeyi kapatmasın.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        // Diğer dokunuşlarla (kaydırma, düğmeler) aynı anda çalışsın.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
