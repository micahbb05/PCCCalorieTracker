import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.20, green: 0.50, blue: 0.98)

    /// Dark gradient used for sheet backgrounds (barcode, USDA search, edit entry, etc.)
    static let sheetBackgroundGradient: [Color] = [
        Color(red: 0.04, green: 0.06, blue: 0.15),
        Color(red: 0.07, green: 0.09, blue: 0.19),
        Color(red: 0.04, green: 0.05, blue: 0.12)
    ]
}
