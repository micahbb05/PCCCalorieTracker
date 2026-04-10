// Calorie Tracker 2026

import Foundation
import CloudKit

struct CloudSyncPayload: Codable, Equatable, Sendable {
    let hasCompletedOnboarding: Bool
    let deficitCalories: Int
    let useWeekendDeficit: Bool
    let weekendDeficitCalories: Int
    let goalTypeRaw: String
    let surplusCalories: Int
    let fixedGoalCalories: Int?
    let dailyGoalTypeArchiveData: String
    let proteinGoal: Int
    let mealEntriesData: String
    let trackedNutrientsData: String
    let nutrientGoalsData: String
    let lastCentralDayIdentifier: String
    let selectedAppIconChoiceRaw: String
    let dailyEntryArchiveData: String
    let dailyCalorieGoalArchiveData: String
    let dailyBurnedCalorieArchiveData: String
    let dailyExerciseArchiveData: String
    let venueMenusData: String
    let venueMenuSignaturesData: String
    let quickAddFoodsData: String
    let useAIBaseServings: Bool
    let calibrationStateData: String?
    let healthWeighInsData: String?
    let syncedHealthProfileData: String?
    let syncedTodayWorkoutsData: String?
    let syncedHealthSourceDeviceTypeRaw: String?
}

enum CloudSyncOriginDeviceType: String, Codable, Sendable {
    case iphone
    case ipad
    case mac
    case unknown
}

struct CloudSyncEnvelope: Codable, Sendable {
    let updatedAt: Double
    let payload: CloudSyncPayload
    let storageVersion: Int
    let originDeviceType: CloudSyncOriginDeviceType

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case payload
        case storageVersion
        case originDeviceType
    }

    init(
        updatedAt: Double,
        payload: CloudSyncPayload,
        storageVersion: Int = 2,
        originDeviceType: CloudSyncOriginDeviceType = .unknown
    ) {
        self.updatedAt = updatedAt
        self.payload = payload
        self.storageVersion = storageVersion
        self.originDeviceType = originDeviceType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Double.self, forKey: .updatedAt)
        payload = try container.decode(CloudSyncPayload.self, forKey: .payload)
        storageVersion = try container.decodeIfPresent(Int.self, forKey: .storageVersion) ?? 1
        originDeviceType = try container.decodeIfPresent(CloudSyncOriginDeviceType.self, forKey: .originDeviceType) ?? .unknown
    }
}

enum CloudSyncStatusLevel: Equatable {
    case checking
    case uploading
    case synced
    case warning
    case error
}

enum CloudSyncTrigger {
    case launch
    case foreground
    case timer
    case push
    case manual
}

enum AppCloudSyncError: LocalizedError {
    case accountUnavailable(CKAccountStatus)
    case cloudKitUnavailable
    case missingPayloadAsset
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case let .accountUnavailable(status):
            switch status {
            case .available:
                return nil
            case .noAccount:
                return "Sign into iCloud on both devices to sync your data."
            case .restricted:
                return "iCloud sync is restricted on this device."
            case .couldNotDetermine:
                return "This device could not determine your iCloud availability."
            case .temporarilyUnavailable:
                return "iCloud is temporarily unavailable. Try again in a moment."
            @unknown default:
                return "iCloud sync is unavailable on this device."
            }
        case .cloudKitUnavailable:
            return "iCloud sync is unavailable in this simulator session."
        case .missingPayloadAsset:
            return "The synced record is missing its payload."
        case .invalidPayload:
            return "The synced payload could not be decoded."
        }
    }
}

actor AppCloudSyncService {
    static let shared = AppCloudSyncService()

    private let recordID = CKRecord.ID(recordName: "user-state")
    private let recordType = "AppState"
    private let assetFieldName = "payloadAsset"
    private let updatedAtFieldName = "updatedAt"
    private let subscriptionID = "app-state-private-changes"

    private nonisolated static var isCloudKitRuntimeAvailable: Bool {
#if targetEnvironment(simulator)
        false
#else
        true
#endif
    }

    func fetchEnvelope() async throws -> CloudSyncEnvelope? {
        _ = try await requireCloudAccountAvailable()

        do {
            let record = try await fetchRecord()
            guard
                let asset = record[assetFieldName] as? CKAsset,
                let fileURL = asset.fileURL
            else {
                throw AppCloudSyncError.missingPayloadAsset
            }

            let data = try Data(contentsOf: fileURL)
            do {
                return try JSONDecoder().decode(CloudSyncEnvelope.self, from: data)
            } catch {
                throw AppCloudSyncError.invalidPayload
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveEnvelope(_ envelope: CloudSyncEnvelope) async throws {
        _ = try await requireCloudAccountAvailable()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-sync-\(UUID().uuidString).json")
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: tempURL, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let record: CKRecord
        do {
            record = try await fetchRecord()
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        var attemptsRemaining = 2
        var workingRecord = record
        while true {
            workingRecord[assetFieldName] = CKAsset(fileURL: tempURL)
            workingRecord[updatedAtFieldName] = envelope.updatedAt as NSNumber

            do {
                _ = try await saveRecord(workingRecord)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attemptsRemaining > 0 {
                attemptsRemaining -= 1
                workingRecord = try await fetchRecord()
            }
        }
    }

    func ensureSubscription() async throws {
        _ = try await requireCloudAccountAvailable()

        do {
            _ = try await fetchSubscription()
        } catch let error as CKError where error.code == .unknownItem {
            let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo
            _ = try await saveSubscription(subscription)
        }
    }

    nonisolated static func isAppStateChangeNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return false
        }

        return notification.subscriptionID == "app-state-private-changes"
    }

    private func requireCloudKitRuntimeAvailable() throws {
        guard Self.isCloudKitRuntimeAvailable else {
            throw AppCloudSyncError.cloudKitUnavailable
        }
    }

    private func privateCloudDatabase() throws -> CKDatabase {
        try requireCloudKitRuntimeAvailable()
        return CKContainer.default().privateCloudDatabase
    }

    private func cloudAccountStatus() async throws -> CKAccountStatus {
        try requireCloudKitRuntimeAvailable()
        let status: CKAccountStatus = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            CKContainer.default().accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }

        return status
    }

    private func requireCloudAccountAvailable() async throws -> CKAccountStatus {
        let status = try await cloudAccountStatus()
        guard status == .available else {
            throw AppCloudSyncError.accountUnavailable(status)
        }
        return status
    }

    private func fetchRecord() async throws -> CKRecord {
        let database = try privateCloudDatabase()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        let database = try privateCloudDatabase()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: CKError(.internalError))
                }
            }
        }
    }

    private func fetchSubscription() async throws -> CKSubscription {
        let database = try privateCloudDatabase()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKSubscription, Error>) in
            database.fetch(withSubscriptionID: subscriptionID) { subscription, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let subscription {
                    continuation.resume(returning: subscription)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription {
        let database = try privateCloudDatabase()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKSubscription, Error>) in
            database.save(subscription) { savedSubscription, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedSubscription {
                    continuation.resume(returning: savedSubscription)
                } else {
                    continuation.resume(throwing: CKError(.internalError))
                }
            }
        }
    }
}
