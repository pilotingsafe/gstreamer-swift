import CGStreamer
import CGStreamerBaseShim
import Synchronization

/// A case for a string-backed native element enum property.
///
/// String-backed enum properties are installed as string GObject properties.
/// The case `name` is the canonical stored value. The optional `nick` is an
/// additional accepted input spelling, and the optional `blurb` documents the
/// case for Swift authors and future introspection work.
public struct NativeElementEnumCase: Sendable {
    public var name: String
    public var nick: String?
    public var blurb: String?

    public init(name: String, nick: String? = nil, blurb: String? = nil) {
        self.name = name
        self.nick = nick
        self.blurb = blurb
    }
}

/// Native element property declaration for a Swift-backed native element.
///
/// Declarations are validated before C registration. Invalid declarations throw
/// during `GStreamer.register(_:)`, before any process-local factory is
/// registered. Runtime values outside a descriptor's Swift-side range or enum
/// cases are ignored so the previous valid value remains readable through
/// `Element` getters and callback readers.
public enum NativeElementProperty: Sendable {
    case bool(name: String, default: Bool, blurb: String)
    case int(name: String, default: Int, min: Int, max: Int, blurb: String)
    case double(name: String, default: Double, min: Double, max: Double, blurb: String)
    case string(name: String, default: String?, blurb: String)
    case stringEnum(name: String, default: String, cases: [NativeElementEnumCase], blurb: String)
}

/// Reads current native element property values from Swift callbacks.
///
/// A property reader is a thread-safe snapshot interface for callback code.
///
/// A reader is injected into property-aware native element factories before
/// lifecycle callbacks begin. Reads are thread-safe and return only values for
/// matching declared property kinds. String-backed enum properties are exposed
/// through ``enumCase(_:)`` and return canonical case names, never nicks.
public struct NativeElementPropertyReader: Sendable {
    private let store: NativeElementPropertyStore?

    internal init(store: NativeElementPropertyStore?) {
        self.store = store
    }

    internal static let empty = NativeElementPropertyReader(store: nil)

    /// Returns a Bool property value, or nil if the property is unknown or has a different kind.
    public func bool(_ name: String) -> Bool? {
        store?.bool(name)
    }

    /// Returns an Int property value, or nil if the property is unknown or has a different kind.
    ///
    /// Returned Int values are backed by GObject `gint` storage and are known to
    /// fit in the Int32 range.
    public func int(_ name: String) -> Int? {
        store?.int(name)
    }

    /// Returns a Double property value, or nil if the property is unknown or has a different kind.
    public func double(_ name: String) -> Double? {
        store?.double(name)
    }

    /// Returns a nullable String property value.
    ///
    /// This returns nil for unknown properties, enum properties, and declared
    /// String properties whose current value is nil.
    public func string(_ name: String) -> String? {
        store?.string(name)
    }

    /// Returns a string-backed enum property's canonical case name.
    public func enumCase(_ name: String) -> String? {
        store?.enumCase(name)
    }
}
internal enum NativePropertyKind: Sendable {
    case bool
    case int
    case double
    case string
    case stringEnum
}

internal struct ValidatedNativeElementEnumCase: Sendable {
    var name: String
    var nick: String?
    var blurb: String?
}

internal struct ValidatedNativeElementProperty: Sendable {
    var name: String
    var blurb: String
    var kind: NativePropertyKind
    var boolDefault: Bool
    var intDefault: Int32
    var intMin: Int32
    var intMax: Int32
    var doubleDefault: Double
    var doubleMin: Double
    var doubleMax: Double
    var stringDefault: String?
    var enumCases: [ValidatedNativeElementEnumCase]
    var enumDefault: String?
    var enumInputToCanonical: [String: String]

    var defaultValue: NativePropertyValue {
        switch kind {
        case .bool:
            return .bool(boolDefault)
        case .int:
            return .int(intDefault)
        case .double:
            return .double(doubleDefault)
        case .string:
            return .string(stringDefault)
        case .stringEnum:
            return .stringEnum(enumDefault ?? "")
        }
    }
}

internal enum NativePropertyValue: Sendable {
    case bool(Bool)
    case int(Int32)
    case double(Double)
    case string(String?)
    case stringEnum(String)
}

// Safety invariant: descriptors and name indexes are immutable after init, and
// all mutable property values are accessed only while holding this Mutex.
internal final class NativeElementPropertyStore: @unchecked Sendable {
    private let descriptors: [ValidatedNativeElementProperty]
    private let indexesByName: [String: Int]
    private let values: Mutex<[NativePropertyValue]>

    init(descriptors: [ValidatedNativeElementProperty]) {
        self.descriptors = descriptors
        self.indexesByName = Dictionary(uniqueKeysWithValues: descriptors.enumerated().map { index, descriptor in
            (descriptor.name, index)
        })
        self.values = Mutex(descriptors.map(\.defaultValue))
    }

    func bool(_ name: String) -> Bool? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .bool, case .bool(let boolValue) = value else {
                return nil
            }
            return boolValue
        }
    }

    func int(_ name: String) -> Int? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .int, case .int(let intValue) = value else {
                return nil
            }
            return Int(intValue)
        }
    }

    func double(_ name: String) -> Double? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .double, case .double(let doubleValue) = value else {
                return nil
            }
            return doubleValue
        }
    }

    func string(_ name: String) -> String? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .string, case .string(let stringValue) = value else {
                return nil
            }
            return stringValue
        }
    }

    func enumCase(_ name: String) -> String? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .stringEnum, case .stringEnum(let enumValue) = value else {
                return nil
            }
            return enumValue
        }
    }

    func setBool(index: Int, value: Bool) {
        update(index: index) { descriptor in
            guard descriptor.kind == .bool else { return nil }
            return .bool(value)
        }
    }

    func setInt(index: Int, value: Int32) {
        update(index: index) { descriptor in
            guard descriptor.kind == .int, descriptor.intMin...descriptor.intMax ~= value else {
                return nil
            }
            return .int(value)
        }
    }

    func setDouble(index: Int, value: Double) {
        update(index: index) { descriptor in
            guard descriptor.kind == .double,
                  value.isFinite,
                  descriptor.doubleMin...descriptor.doubleMax ~= value
            else {
                return nil
            }
            return .double(value)
        }
    }

    func setString(index: Int, value: String?) {
        update(index: index) { descriptor in
            switch descriptor.kind {
            case .string:
                return .string(value)
            case .stringEnum:
                guard let value, let canonical = descriptor.enumInputToCanonical[value] else {
                    return nil
                }
                return .stringEnum(canonical)
            case .bool, .int, .double:
                return nil
            }
        }
    }

    func bool(index: Int) -> Bool {
        read(index: index) { descriptor, value in
            guard descriptor.kind == .bool, case .bool(let boolValue) = value else {
                return false
            }
            return boolValue
        } ?? false
    }

    func int(index: Int) -> Int32 {
        read(index: index) { descriptor, value in
            guard descriptor.kind == .int, case .int(let intValue) = value else {
                return 0
            }
            return intValue
        } ?? 0
    }

    func double(index: Int) -> Double {
        read(index: index) { descriptor, value in
            guard descriptor.kind == .double, case .double(let doubleValue) = value else {
                return 0
            }
            return doubleValue
        } ?? 0
    }

    func stringForC(index: Int) -> UnsafeMutablePointer<CChar>? {
        let value: String? = read(index: index) { descriptor, value in
            switch (descriptor.kind, value) {
            case (.string, .string(let stringValue)):
                return stringValue
            case (.stringEnum, .stringEnum(let enumValue)):
                return enumValue
            default:
                return nil
            }
        } ?? nil

        guard let value else {
            return nil
        }
        return g_strdup(value)
    }

    private func read<T>(
        name: String,
        _ body: (ValidatedNativeElementProperty, NativePropertyValue) -> T?
    ) -> T? {
        guard let index = indexesByName[name] else {
            return nil
        }
        return read(index: index, body)
    }

    private func read<T>(
        index: Int,
        _ body: (ValidatedNativeElementProperty, NativePropertyValue) -> T?
    ) -> T? {
        guard descriptors.indices.contains(index) else {
            return nil
        }
        let descriptor = descriptors[index]
        return values.withLock { values in
            guard values.indices.contains(index) else {
                return nil
            }
            return body(descriptor, values[index])
        }
    }

    private func update(
        index: Int,
        _ value: (ValidatedNativeElementProperty) -> NativePropertyValue?
    ) {
        guard descriptors.indices.contains(index) else {
            return
        }
        let descriptor = descriptors[index]
        guard let newValue = value(descriptor) else {
            return
        }
        values.withLock { values in
            guard values.indices.contains(index) else {
                return
            }
            values[index] = newValue
        }
    }
}
extension NativeElementProperty {
    var propertyName: String {
        switch self {
        case .bool(let name, _, _),
             .int(let name, _, _, _, _),
             .double(let name, _, _, _, _),
             .string(let name, _, _),
             .stringEnum(let name, _, _, _):
            return name
        }
    }
}
internal final class NativePropertyCDescriptorStorage {
    let descriptors: UnsafeMutablePointer<SwiftGstNativePropertyDescriptor>?
    let count: guint

    private var strings: [UnsafeMutablePointer<CChar>] = []
    private var enumCaseArrays: [UnsafeMutablePointer<SwiftGstNativeEnumCaseDescriptor>] = []

    init(properties: [ValidatedNativeElementProperty]) {
        self.count = guint(properties.count)
        guard !properties.isEmpty else {
            self.descriptors = nil
            return
        }

        let descriptors = UnsafeMutablePointer<SwiftGstNativePropertyDescriptor>.allocate(capacity: properties.count)
        self.descriptors = descriptors

        for (index, property) in properties.enumerated() {
            let enumCases = makeEnumCaseArray(property.enumCases)
            descriptors[index] = SwiftGstNativePropertyDescriptor(
                name: makeCString(property.name),
                blurb: makeCString(property.blurb),
                kind: property.cKind,
                bool_default: property.boolDefault ? 1 : 0,
                int_default: property.intDefault,
                int_min: property.intMin,
                int_max: property.intMax,
                double_default: property.doubleDefault,
                double_min: property.doubleMin,
                double_max: property.doubleMax,
                string_default: makeCString(property.stringDefault),
                enum_cases: enumCases,
                enum_case_count: guint(property.enumCases.count)
            )
        }
    }

    deinit {
        for pointer in strings {
            g_free(pointer)
        }
        for pointer in enumCaseArrays {
            pointer.deallocate()
        }
        descriptors?.deallocate()
    }

    private func makeCString(_ value: String?) -> UnsafePointer<CChar>? {
        guard let value else {
            return nil
        }
        guard let pointer = value.withCString({ g_strdup($0) }) else {
            return nil
        }
        strings.append(pointer)
        return UnsafePointer(pointer)
    }

    private func makeEnumCaseArray(
        _ enumCases: [ValidatedNativeElementEnumCase]
    ) -> UnsafePointer<SwiftGstNativeEnumCaseDescriptor>? {
        guard !enumCases.isEmpty else {
            return nil
        }
        let pointer = UnsafeMutablePointer<SwiftGstNativeEnumCaseDescriptor>.allocate(capacity: enumCases.count)
        enumCaseArrays.append(pointer)
        for (index, enumCase) in enumCases.enumerated() {
            pointer[index] = SwiftGstNativeEnumCaseDescriptor(
                name: makeCString(enumCase.name),
                nick: makeCString(enumCase.nick),
                blurb: makeCString(enumCase.blurb)
            )
        }
        return UnsafePointer(pointer)
    }
}

extension ValidatedNativeElementProperty {
    var cKind: SwiftGstNativePropertyKind {
        switch kind {
        case .bool:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_BOOL
        case .int:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_INT
        case .double:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_DOUBLE
        case .string:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_STRING
        case .stringEnum:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_STRING_ENUM
        }
    }
}
