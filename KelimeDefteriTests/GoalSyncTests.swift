import Foundation
import Testing
@testable import KelimeDefteri

/// iCloud anahtar-değer deposunun yerine geçen sahte depo.
nonisolated private final class FakeCloud: GoalCloudStore {
    var values: [String: Any] = [:]
    var syncCount = 0

    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func synchronize() -> Bool { syncCount += 1; return true }
}

struct GoalSyncTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "goal-sync-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func cloudValueReplacesLocal() throws {
        try withDefaults { local in
            local.set(20, forKey: DailyGoal.key)
            let cloud = FakeCloud()
            cloud.values[DailyGoal.key] = 50
            #expect(GoalSync.reconcile(cloud: cloud, local: local))
            #expect(DailyGoal.target(in: local) == 50)
            #expect(!GoalSync.reconcile(cloud: cloud, local: local))
        }
    }

    @Test func emptyCloudReceivesLocalChoice() throws {
        try withDefaults { local in
            local.set(20, forKey: DailyGoal.key)
            let cloud = FakeCloud()
            #expect(!GoalSync.reconcile(cloud: cloud, local: local))
            #expect(cloud.values[DailyGoal.key] as? Int == 20)
            #expect(cloud.syncCount == 1)
        }
    }

    @Test func unchosenLocalIsNotUploaded() throws {
        // Yeni cihazda iCloud değeri henüz inmemişken varsayılan öbür cihazların hedefini ezmesin.
        try withDefaults { local in
            let cloud = FakeCloud()
            GoalSync.reconcile(cloud: cloud, local: local)
            #expect(cloud.values[DailyGoal.key] == nil)
            #expect(DailyGoal.target(in: local) == DailyGoal.defaultTarget)
        }
    }

    @Test func externalChangeUpdatesLocal() throws {
        try withDefaults { local in
            local.set(30, forKey: DailyGoal.key)
            let cloud = FakeCloud()
            cloud.values[DailyGoal.key] = 100
            #expect(!GoalSync.applyExternalChange(changedKeys: ["başka"], cloud: cloud, local: local))
            #expect(DailyGoal.target(in: local) == 30)
            #expect(GoalSync.applyExternalChange(changedKeys: [DailyGoal.key], cloud: cloud, local: local))
            #expect(DailyGoal.target(in: local) == 100)
            cloud.values[DailyGoal.key] = 10
            #expect(GoalSync.applyExternalChange(changedKeys: nil, cloud: cloud, local: local))
            #expect(DailyGoal.target(in: local) == 10)
        }
    }

    @Test func invalidValuesAreIgnored() throws {
        try withDefaults { local in
            local.set(20, forKey: DailyGoal.key)
            let cloud = FakeCloud()
            cloud.values[DailyGoal.key] = 7
            #expect(!GoalSync.applyExternalChange(changedKeys: [DailyGoal.key], cloud: cloud, local: local))
            #expect(DailyGoal.target(in: local) == 20)
            // Bozuk iCloud değeri boş sayılır: yereldeki geçerli seçim yüklenir.
            GoalSync.reconcile(cloud: cloud, local: local)
            #expect(cloud.values[DailyGoal.key] as? Int == 20)

            cloud.values[DailyGoal.key] = "elli"
            #expect(GoalSync.cloudTarget(cloud) == nil)

            GoalSync.setTarget(33, cloud: cloud, local: local)
            #expect(DailyGoal.target(in: local) == 20)
        }
    }

    @Test func userChoiceGoesToBothStores() throws {
        try withDefaults { local in
            let cloud = FakeCloud()
            GoalSync.setTarget(50, cloud: cloud, local: local)
            #expect(DailyGoal.target(in: local) == 50)
            #expect(cloud.values[DailyGoal.key] as? Int == 50)
            #expect(cloud.syncCount == 1)
            // Aynı değer tekrar yazılmaz (dış değişiklik → @AppStorage → onChange döngüsü).
            GoalSync.setTarget(50, cloud: cloud, local: local)
            #expect(cloud.syncCount == 1)
        }
    }

    /// Günlük yeni hakkı aynı desenle, ayrı anahtarda eşitlenir; hedefin anahtarına dokunmaz.
    @Test func dailyNewAllowanceSyncsSeparately() throws {
        try withDefaults { local in
            let cloud = FakeCloud()
            cloud.values[DailyNewAllowance.key] = 15
            #expect(GoalSync.reconcile(cloud: cloud, local: local, setting: .dailyNew))
            #expect(DailyNewAllowance.value(in: local) == 15)
            #expect(local.object(forKey: DailyGoal.key) == nil)
            // Hedef anahtarı değişti bildirimi yeni hakkını etkilemez.
            cloud.values[DailyNewAllowance.key] = 20
            #expect(!GoalSync.applyExternalChange(changedKeys: [DailyGoal.key], cloud: cloud, local: local, setting: .dailyNew))
            #expect(GoalSync.applyExternalChange(changedKeys: [DailyNewAllowance.key], cloud: cloud, local: local, setting: .dailyNew))
            #expect(DailyNewAllowance.value(in: local) == 20)
            // Geçersiz değer (seçenek dışı) yok sayılır.
            cloud.values[DailyNewAllowance.key] = 30
            #expect(!GoalSync.applyExternalChange(changedKeys: nil, cloud: cloud, local: local, setting: .dailyNew))
            GoalSync.setTarget(7, cloud: cloud, local: local, setting: .dailyNew)
            #expect(DailyNewAllowance.value(in: local) == 20)
            GoalSync.setTarget(5, cloud: cloud, local: local, setting: .dailyNew)
            #expect(DailyNewAllowance.value(in: local) == 5)
            #expect(cloud.values[DailyNewAllowance.key] as? Int == 5)
            #expect(cloud.values[DailyGoal.key] == nil)
        }
    }
}
