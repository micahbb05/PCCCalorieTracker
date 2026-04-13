// Calorie Tracker 2026

import SwiftUI
import UIKit

/// Renders a food log icon from `FoodSymbolMapper` (SF Symbol or template asset).
/// Uses a fixed square slot so template assets and SF Symbols read at a consistent visual size in lists.
struct FoodLogIconView: View {
    let token: FoodLogIconToken
    var accent: Color
    var size: CGFloat = 20

    private var drawableSide: CGFloat { max(4, size - 6) }

    var body: some View {
        ZStack {
            switch token {
            case .sf(let symbol):
                if FoodIconAvailability.hasSystemSymbol(named: symbol) {
                    Image(systemName: symbol)
                        .font(.system(size: drawableSide * 0.78, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(accent)
                        .imageScale(.medium)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: drawableSide * 0.78, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(accent)
                }
            case .asset(let assetName, let fallback):
                if FoodIconAvailability.hasAsset(named: assetName) {
                    Image(assetName)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .foregroundStyle(accent)
                        .frame(width: drawableSide, height: drawableSide)
                        .accessibilityHidden(true)
                } else if FoodIconAvailability.hasSystemSymbol(named: fallback) {
                    Image(systemName: fallback)
                        .font(.system(size: drawableSide * 0.78, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(accent)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: drawableSide * 0.78, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(accent)
                }
            }
        }
        .frame(width: size, height: size, alignment: .center)
        .contentShape(Rectangle())
    }
}

private enum FoodIconAvailability {
    private static let lock = NSLock()
    private static var sfSymbolCache: [String: Bool] = [:]
    private static var assetCache: [String: Bool] = [:]

    static func hasSystemSymbol(named name: String) -> Bool {
        lock.lock()
        if let cached = sfSymbolCache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let exists = UIImage(systemName: name) != nil

        lock.lock()
        sfSymbolCache[name] = exists
        lock.unlock()
        return exists
    }

    static func hasAsset(named name: String) -> Bool {
        lock.lock()
        if let cached = assetCache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let exists = UIImage(named: name) != nil

        lock.lock()
        assetCache[name] = exists
        lock.unlock()
        return exists
    }
}
