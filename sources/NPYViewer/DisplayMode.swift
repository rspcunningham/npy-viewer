import Foundation

enum DisplayMode: UInt32, CaseIterable {
    case scalar = 0
    case complexAbs = 1
    case complexPhase = 2
    case complexReal = 3
    case complexImag = 4

    var label: String {
        switch self {
        case .scalar:
            "scalar"
        case .complexAbs:
            "abs"
        case .complexPhase:
            "phase"
        case .complexReal:
            "real"
        case .complexImag:
            "imag"
        }
    }
}
