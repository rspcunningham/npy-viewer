import Foundation
import Testing
@testable import NPYCore

@Test func parsesFloat32NPY() throws {
    let data = makeNPY(descr: "<f4", shape: [2, 3], payload: floats([0, 0.25, 0.5, 0.75, 1, 1.25]))
    let array = try NPYArray(data: data)

    #expect(array.shape == [2, 3])
    #expect(array.elementType == .float32)
    #expect(array.pixelValue(x: 2, y: 1) == .scalar(1.25))
}

@Test func parsesComplex64NPY() throws {
    let data = makeNPY(descr: "<c8", shape: [1, 2], payload: floats([1, -2, 3, 4]))
    let array = try NPYArray(data: data)

    #expect(array.shape == [1, 2])
    #expect(array.elementType == .complex64)
    #expect(array.pixelValue(x: 1, y: 0) == .complex(real: 3, imag: 4))
}

@Test func rejectsUnsupportedShape() throws {
    let data = makeNPY(descr: "<f4", shape: [2, 2, 3], payload: floats(Array(repeating: 0, count: 12)))

    #expect(throws: NPYError.self) {
        _ = try NPYArray(data: data)
    }
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
