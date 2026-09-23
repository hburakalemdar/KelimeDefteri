import SwiftData
import SwiftUI

// Tur sürerken kelime silinebilir (başka cihazdan iCloud ile ya da başka bir yoldan). Oyunlar kelimeleri
// tur başında alır; silinmiş bir kelimenin alanlarını okumak SwiftData'da çökebilir. Bu yüzden oyunlar
// çizmeden önce kelimenin yerinde olup olmadığına bakar ve defterin kimlik kümesi değişince silineni atlar.

extension Word {
    /// Kelime silinmiş mi: bağlamdan çıkmış ya da defterde (`alive`) artık yok.
    func isGone(from alive: Set<PersistentIdentifier>) -> Bool {
        isDeleted || modelContext == nil || !alive.contains(persistentModelID)
    }
}

extension Array where Element == Word {
    /// Defterdeki kelimelerin kimlik kümesi; yalnızca kelime eklenince ya da silinince değişir.
    var aliveIDs: Set<PersistentIdentifier> { Set(map(\.persistentModelID)) }
}
