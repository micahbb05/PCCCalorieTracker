// Calorie Tracker 2026

import Foundation

actor AppMenuPreloadService {
    static let shared = AppMenuPreloadService()

    private let defaults = UserDefaults.standard
    private let menuService = NutrisliceMenuService()
    private let venueMenusKey = "venueMenusData"
    private let venueMenuSignaturesKey = "venueMenuSignaturesData"

    func preloadTodayMenus() async -> Bool {
        var venueMenus = loadVenueMenus()
        var venueMenuSignatures = loadVenueMenuSignatures()
        var didUpdate = false

        for venue in DiningVenue.allCases {
            for menuType in menuService.allMenuTypes where venue.supportedMenuTypes.contains(menuType) {
                let currentSignature = menuService.currentMenuSignature(for: venue, menuType: menuType)
                let existingMenu = venueMenus[venue]?[menuType] ?? .empty
                let lastSignature = venueMenuSignatures[venue]?[menuType]
                guard existingMenu.lines.isEmpty || lastSignature != currentSignature else {
                    continue
                }

                do {
                    let menu = try await menuService.fetchTodayMenu(for: venue, menuType: menuType)
                    var venueCache = venueMenus[venue] ?? [:]
                    venueCache[menuType] = menu
                    venueMenus[venue] = venueCache

                    var signatureCache = venueMenuSignatures[venue] ?? [:]
                    signatureCache[menuType] = currentSignature
                    venueMenuSignatures[venue] = signatureCache
                    didUpdate = true
                } catch {
                    continue
                }
            }
        }

        if didUpdate {
            saveVenueMenus(venueMenus)
            saveVenueMenuSignatures(venueMenuSignatures)
        }

        return didUpdate
    }

    private func loadVenueMenus() -> StoredVenueMenuCache {
        guard
            let stored = defaults.string(forKey: venueMenusKey),
            !stored.isEmpty,
            let data = stored.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(StoredVenueMenuCache.self, from: data)
        else {
            return [:]
        }

        return decoded
    }

    private func loadVenueMenuSignatures() -> StoredVenueMenuSignatureCache {
        guard
            let stored = defaults.string(forKey: venueMenuSignaturesKey),
            !stored.isEmpty,
            let data = stored.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(StoredVenueMenuSignatureCache.self, from: data)
        else {
            return [:]
        }

        return decoded
    }

    private func saveVenueMenus(_ venueMenus: StoredVenueMenuCache) {
        guard let data = try? JSONEncoder().encode(venueMenus) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: venueMenusKey)
    }

    private func saveVenueMenuSignatures(_ signatures: StoredVenueMenuSignatureCache) {
        guard let data = try? JSONEncoder().encode(signatures) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: venueMenuSignaturesKey)
    }
}
