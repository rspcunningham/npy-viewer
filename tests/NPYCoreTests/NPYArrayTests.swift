import Foundation
import Testing
@testable import NPYCore

@Test func parsesFloat32NPY() throws {
    let data = makeNPY(descr: "<f4", shape: [2, 3], payload: floats([0, 0.25, 0.5, 0.75, 1, 1.25]))
    let array = try NPYArray(data: data)

    #expect(array.shape == [2, 3])
    #expect(array.elementType == .float32)
    #expect(array.height == 2)
    #expect(array.width == 3)
    #expect(array.pixelCount == 6)
    #expect(array.payloadByteCount == 24)
    #expect(array.pixelValue(x: 2, y: 1) == .scalar(1.25))
}

@Test func parsesComplex64NPY() throws {
    let data = makeNPY(descr: "<c8", shape: [1, 2], payload: floats([1, -2, 3, 4]))
    let array = try NPYArray(data: data)

    #expect(array.shape == [1, 2])
    #expect(array.elementType == .complex64)
    #expect(array.pixelValue(x: 1, y: 0) == .complex(real: 3, imag: 4))
}

@Test func parsesNativeEndianDTypesAndHeaderVersions() throws {
    let floatData = makeNPY(descr: "=f4", shape: [1, 1], payload: floats([7]), major: 2)
    let floatArray = try NPYArray(data: floatData)
    #expect(floatArray.elementType == .float32)
    #expect(floatArray.pixelValue(x: 0, y: 0) == .scalar(7))

    let complexData = makeNPY(descr: "=c8", shape: [1, 1], payload: floats([3, -4]), major: 3)
    let complexArray = try NPYArray(data: complexData)
    #expect(complexArray.elementType == .complex64)
    #expect(complexArray.pixelValue(x: 0, y: 0) == .complex(real: 3, imag: -4))
}

@Test func loadsNPYFromFileURL() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NPYArrayTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("array.npy")
    try makeNPY(descr: "<f4", shape: [1, 2], payload: floats([4, 8])).write(to: url)

    let array = try NPYArray(contentsOf: url)
    #expect(array.url == url)
    #expect(array.shape == [1, 2])
    #expect(array.pixelValue(x: 1, y: 0) == .scalar(8))
}

@Test func providesRawPayloadPointer() throws {
    let array = try NPYArray(data: makeNPY(descr: "<f4", shape: [2, 2], payload: floats([1, 2, 3, 4])))

    let values = try array.withRawPayloadPointer { pointer in
        let floats = pointer.bindMemory(to: Float.self, capacity: array.pixelCount)
        return Array(UnsafeBufferPointer(start: floats, count: array.pixelCount))
    }

    #expect(values == [1, 2, 3, 4])
}

@Test func returnsNilForOutOfBoundsPixels() throws {
    let array = try NPYArray(data: makeNPY(descr: "<f4", shape: [2, 2], payload: floats([1, 2, 3, 4])))

    #expect(array.pixelValue(x: -1, y: 0) == nil)
    #expect(array.pixelValue(x: 0, y: -1) == nil)
    #expect(array.pixelValue(x: 2, y: 0) == nil)
    #expect(array.pixelValue(x: 0, y: 2) == nil)
}

@Test func rejectsUnsupportedShape() throws {
    let data = makeNPY(descr: "<f4", shape: [2, 2, 3], payload: floats(Array(repeating: 0, count: 12)))

    #expect(throws: NPYError.self) {
        _ = try NPYArray(data: data)
    }
}

@Test func rejectsBadMagicAndUnsupportedVersions() {
    expectNPYError("bad magic", {
        _ = try NPYArray(data: Data([0, 1, 2]))
    }, matches: { error in
        guard case .badMagic = error else { return false }
        return true
    })

    var unsupportedVersion = Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 9, 0, 0, 0])
    unsupportedVersion.append(Data(repeating: 0, count: 8))
    expectNPYError("unsupported version", {
        _ = try NPYArray(data: unsupportedVersion)
    }, matches: { error in
        guard case .unsupportedVersion(9, 0) = error else { return false }
        return true
    })
}

@Test func rejectsMalformedHeaders() {
    expectNPYError("declared header exceeds file length", {
        _ = try NPYArray(data: makeNPYWithDeclaredHeaderLength(128))
    }, matches: { error in
        guard case .malformedHeader("declared header exceeds file length") = error else { return false }
        return true
    })

    expectNPYError("missing v2 header length", {
        _ = try NPYArray(data: Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 2, 0, 1, 0]))
    }, matches: { error in
        guard case .malformedHeader("missing version 2/3 header length") = error else { return false }
        return true
    })

    expectNPYError("header is not text", {
        _ = try NPYArray(data: makeNPYWithRawHeaderBytes(Data([0xff]), major: 3))
    }, matches: { error in
        guard case .malformedHeader("header is not text") = error else { return false }
        return true
    })

    let missingFieldCases = [
        ("descr", "{'fortran_order': False, 'shape': (1, 1), }"),
        ("fortran_order", "{'descr': '<f4', 'shape': (1, 1), }"),
        ("shape", "{'descr': '<f4', 'fortran_order': False, }")
    ]

    for (field, header) in missingFieldCases {
        expectNPYError("missing \(field)", {
            _ = try NPYArray(data: makeNPY(header: header, payload: floats([1])))
        }, matches: { error in
            guard case .malformedHeader("missing \(field) field") = error else { return false }
            return true
        })
    }
}

@Test func rejectsUnsupportedDTypeFortranOrderAndShortPayload() {
    expectNPYError("unsupported dtype", {
        _ = try NPYArray(data: makeNPY(descr: "<i4", shape: [1, 1], payload: floats([1])))
    }, matches: { error in
        guard case .unsupportedDType("<i4") = error else { return false }
        return true
    })

    expectNPYError("fortran order", {
        _ = try NPYArray(data: makeNPY(descr: "<f4", shape: [1, 1], payload: floats([1]), fortranOrder: true))
    }, matches: { error in
        guard case .fortranOrderUnsupported = error else { return false }
        return true
    })

    expectNPYError("short payload", {
        _ = try NPYArray(data: makeNPY(descr: "<f4", shape: [2, 2], payload: floats([1])))
    }, matches: { error in
        guard case .dataTooShort(expected: 16, actual: 4) = error else { return false }
        return true
    })
}

@Test func rejectsNonTwoDimensionalOrEmptyShapes() {
    let cases = [
        [4],
        [0, 2],
        [2, 0],
        [2, 2, 1]
    ]

    for shape in cases {
        expectNPYError("unsupported shape \(shape)", {
            _ = try NPYArray(
                data: makeNPY(
                    descr: "<f4",
                    shape: shape,
                    payload: floats(Array(repeating: 0, count: max(shape.reduce(1, *), 1)))
                )
            )
        }, matches: { error in
            guard case .unsupportedShape(shape) = error else { return false }
            return true
        })
    }
}

@Test func exposesElementAndPixelDisplayStrings() {
    #expect(NPYElementType.float32.bytesPerElement == 4)
    #expect(NPYElementType.float32.dtypeName == "float32")
    #expect(NPYElementType.complex64.bytesPerElement == 8)
    #expect(NPYElementType.complex64.dtypeName == "complex64")

    #expect(NPYPixelValue.scalar(1.25).displayString == "1.25")
    #expect(NPYPixelValue.complex(real: 3, imag: 4).displayString == "real 3  imag 4  abs 5  phase 0.9272952")
}

@Test func exposesLocalizedErrorDescriptions() {
    let descriptions: [(NPYError, String)] = [
        (.unreadable, "could not be read"),
        (.badMagic, "not a NumPy"),
        (.unsupportedVersion(2, 5), "2.5"),
        (.malformedHeader("missing descr"), "missing descr"),
        (.unsupportedDType("<i4"), "<i4"),
        (.unsupportedShape([1, 2, 3]), "[1, 2, 3]"),
        (.fortranOrderUnsupported, "Fortran-order"),
        (.dataTooShort(expected: 8, actual: 4), "Expected 8 bytes, found 4"),
        (.emptyData, "no data payload")
    ]

    for (error, expectedText) in descriptions {
        #expect(error.errorDescription?.contains(expectedText) == true)
    }
}

private func makeNPY(
    descr: String,
    shape: [Int],
    payload: Data,
    major: UInt8 = 1,
    minor: UInt8 = 0,
    fortranOrder: Bool = false
) -> Data {
    let shapeText = shape.map(String.init).joined(separator: ", ") + (shape.count == 1 ? "," : "")
    let orderText = fortranOrder ? "True" : "False"
    let header = "{'descr': '\(descr)', 'fortran_order': \(orderText), 'shape': (\(shapeText)), }"
    return makeNPY(header: header, payload: payload, major: major, minor: minor)
}

private func makeNPY(header: String, payload: Data, major: UInt8 = 1, minor: UInt8 = 0) -> Data {
    var data = Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, major, minor])
    var header = header
    let lengthByteCount = major == 1 ? 2 : 4
    let baseLength = 6 + 2 + lengthByteCount
    let paddedHeaderLength = ((baseLength + header.utf8.count + 1 + 15) / 16) * 16 - baseLength
    header += String(repeating: " ", count: paddedHeaderLength - header.utf8.count - 1)
    header += "\n"

    let length = UInt32(header.utf8.count)
    data.append(UInt8(length & 0xff))
    data.append(UInt8((length >> 8) & 0xff))
    if lengthByteCount == 4 {
        data.append(UInt8((length >> 16) & 0xff))
        data.append(UInt8((length >> 24) & 0xff))
    }
    data.append(header.data(using: major == 3 ? .utf8 : .isoLatin1)!)
    data.append(payload)
    return data
}

private func makeNPYWithDeclaredHeaderLength(_ length: UInt16) -> Data {
    Data([
        0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59,
        1, 0,
        UInt8(length & 0xff),
        UInt8((length >> 8) & 0xff)
    ])
}

private func makeNPYWithRawHeaderBytes(_ headerBytes: Data, major: UInt8) -> Data {
    var data = Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, major, 0])
    let length = UInt32(headerBytes.count)
    data.append(UInt8(length & 0xff))
    data.append(UInt8((length >> 8) & 0xff))
    data.append(UInt8((length >> 16) & 0xff))
    data.append(UInt8((length >> 24) & 0xff))
    data.append(headerBytes)
    return data
}

private func floats(_ values: [Float]) -> Data {
    var values = values
    return Data(bytes: &values, count: values.count * MemoryLayout<Float>.size)
}

private func expectNPYError(
    _ description: String,
    _ body: () throws -> Void,
    matches: (NPYError) -> Bool
) {
    do {
        try body()
        Issue.record("Expected NPYError for \(description)")
    } catch let error as NPYError {
        #expect(matches(error))
    } catch {
        Issue.record("Expected NPYError for \(description), got \(error)")
    }
}
