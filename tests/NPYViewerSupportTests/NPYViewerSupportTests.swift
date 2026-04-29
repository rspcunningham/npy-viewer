import Foundation
import NPYCore
import NPYViewerSupport
import Testing

@Test func displayModesExposeStableRawValuesAndLabels() {
    let cases: [(mode: DisplayMode, rawValue: UInt32, label: String, menuLabel: String)] = [
        (.scalar, 0, "scalar", "Scalar"),
        (.complexAbs, 1, "abs", "Abs"),
        (.complexPhase, 2, "phase", "Phase"),
        (.complexReal, 3, "real", "Real"),
        (.complexImag, 4, "imag", "Imag"),
        (.complexIntensity, 5, "intensity", "Intensity")
    ]

    #expect(DisplayMode.allCases == cases.map(\.mode))
    for testCase in cases {
        #expect(testCase.mode.rawValue == testCase.rawValue)
        #expect(DisplayMode(rawValue: testCase.rawValue) == testCase.mode)
        #expect(testCase.mode.label == testCase.label)
        #expect(testCase.mode.menuLabel == testCase.menuLabel)
    }
}

@Test func colorMapsExposeStableRawValuesAndLabels() {
    let cases: [(colorMap: ColorMap, rawValue: UInt32, label: String)] = [
        (.gray, 0, "Gray"),
        (.viridis, 1, "Viridis"),
        (.magma, 2, "Magma"),
        (.hot, 3, "Hot")
    ]

    #expect(ColorMap.allCases == cases.map(\.colorMap))
    for testCase in cases {
        #expect(testCase.colorMap.rawValue == testCase.rawValue)
        #expect(ColorMap(rawValue: testCase.rawValue) == testCase.colorMap)
        #expect(testCase.colorMap.label == testCase.label)
    }
}

@Test func colorMapsProvideSharedSampling() {
    #expect(ColorMap.gray.color(forNormalizedValue: 0.25) == ColorMapRGB(red: 0.25, green: 0.25, blue: 0.25))
    #expect(ColorMap.viridis.color(forNormalizedValue: 0) == ColorMapRGB(red: 0.267, green: 0.005, blue: 0.329))
    #expect(ColorMap.magma.color(forNormalizedValue: 1) == ColorMapRGB(red: 0.988, green: 0.992, blue: 0.749))
}

@Test func formatsViewerNumericFields() {
    #expect(ViewerFormatting.hoverFieldWidth == 9)
    #expect(ViewerFormatting.indexWidth(for: 0) == 1)
    #expect(ViewerFormatting.indexWidth(for: 200) == 3)
    #expect(ViewerFormatting.fixedWidth(7, width: 3) == "  7")
    #expect(ViewerFormatting.fixedWidth(100, width: 2) == "100")
    #expect(ViewerFormatting.paddedField("x") == "x        ")
    #expect(ViewerFormatting.controlValue(0.5) == "0.50")
}

@Test func formatsScalarAndComplexSidebarValues() {
    #expect(
        ViewerFormatting.sidebarDisplayString(for: .scalar(1.25)) ==
            "\(ViewerFormatting.paddedField("value"))  1.2500000"
    )

    let complexText = ViewerFormatting.sidebarDisplayString(for: .complex(real: 3, imag: 4))
    #expect(complexText.contains("\(ViewerFormatting.paddedField("real"))  3.0000000"))
    #expect(complexText.contains("\(ViewerFormatting.paddedField("imag"))  4.0000000"))
    #expect(complexText.contains("\(ViewerFormatting.paddedField("abs"))  5.0000000"))
    #expect(complexText.contains("\(ViewerFormatting.paddedField("intensity"))  25.0000000"))
    #expect(complexText.contains("\(ViewerFormatting.paddedField("phase"))  0.9272952"))
}

@Test func formatsHoverAndPlaceholderText() throws {
    let array = try NPYArray(data: makeNPY(descr: "<f4", shape: [10, 200], payload: floats(Array(repeating: 0, count: 2_000))))

    let hoverText = ViewerFormatting.hoverText(
        array: array,
        coordinate: (x: 3, y: 9),
        value: .scalar(1.25)
    )
    #expect(hoverText.contains("x           3"))
    #expect(hoverText.contains("y         9"))
    #expect(hoverText.contains("\(ViewerFormatting.paddedField("value"))  1.2500000"))

    let placeholderText = ViewerFormatting.placeholderHoverText(for: array)
    #expect(placeholderText.contains("x         ---"))
    #expect(placeholderText.contains("y         -"))
}

@Test func discoversNPYFilesInDisplayOrder() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NPYViewerSupportTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let aFile = directory.appendingPathComponent("a.NPY")
    let zFile = directory.appendingPathComponent("z.npy")
    let textFile = directory.appendingPathComponent("notes.txt")
    let hiddenFile = directory.appendingPathComponent(".hidden.npy")
    let npyDirectory = directory.appendingPathComponent("folder.npy", isDirectory: true)

    try Data().write(to: zFile)
    try Data().write(to: aFile)
    try Data().write(to: textFile)
    try Data().write(to: hiddenFile)
    try FileManager.default.createDirectory(at: npyDirectory, withIntermediateDirectories: true)

    #expect(NPYFileDiscovery.isNPYFile(aFile))
    #expect(NPYFileDiscovery.isNPYFile(URL(fileURLWithPath: "/tmp/SCAN.NPY")))
    #expect(!NPYFileDiscovery.isNPYFile(textFile))
    #expect(NPYFileDiscovery.isDirectory(npyDirectory))

    let files = try NPYFileDiscovery.npyFiles(in: directory).map(\.lastPathComponent)
    #expect(files == ["a.NPY", "z.npy"])
}

private func makeNPY(descr: String, shape: [Int], payload: Data) -> Data {
    var data = Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 0x01, 0x00])
    let shapeText = shape.map(String.init).joined(separator: ", ") + (shape.count == 1 ? "," : "")
    var header = "{'descr': '\(descr)', 'fortran_order': False, 'shape': (\(shapeText)), }"
    let baseLength = 10
    let paddedHeaderLength = ((baseLength + header.utf8.count + 1 + 15) / 16) * 16 - baseLength
    header += String(repeating: " ", count: paddedHeaderLength - header.utf8.count - 1)
    header += "\n"

    let length = UInt16(header.utf8.count)
    data.append(UInt8(length & 0xff))
    data.append(UInt8((length >> 8) & 0xff))
    data.append(header.data(using: .ascii)!)
    data.append(payload)
    return data
}

private func floats(_ values: [Float]) -> Data {
    var values = values
    return Data(bytes: &values, count: values.count * MemoryLayout<Float>.size)
}
