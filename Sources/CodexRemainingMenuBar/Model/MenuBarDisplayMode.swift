import Foundation

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case iconAndPercentage
    case iconOnly
    case percentageOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iconAndPercentage: return "图标 + 百分比"
        case .iconOnly: return "仅图标"
        case .percentageOnly: return "仅百分比"
        }
    }
}
