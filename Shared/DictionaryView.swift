import SwiftUI
import UIKit

/// iOS'un yerleşik sözlüğü (Ayarlar › Genel › Sözlük'ten indirilen sözlükler).
struct DictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
