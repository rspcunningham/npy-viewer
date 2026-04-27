import Foundation

enum ColorMap: UInt32, CaseIterable {
    case gray = 0
    case viridis = 1
    case magma = 2
    case hot = 3

    var label: String {
        switch self {
        case .gray:
            "Gray"
        case .viridis:
            "Viridis"
        case .magma:
            "Magma"
        case .hot:
            "Hot"
        }
    }
}
