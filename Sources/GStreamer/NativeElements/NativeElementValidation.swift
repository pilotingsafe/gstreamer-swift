import CGStreamer
import CGStreamerBaseShim

internal enum NativeElementTypeName {
    static func sanitizedFactoryNameComponent(_ factoryName: String) -> String {
        var result = ""
        result.reserveCapacity(factoryName.count)
        for scalar in factoryName.unicodeScalars {
            result.unicodeScalars.append(scalar.isASCIIAlphaNumeric ? scalar : "_")
        }
        return result
    }

    static func fnv1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(formatLowercaseHex: hash)
    }

    static func generatedBaseSinkTypeName(factoryName: String) -> String {
        "SwiftGstNativeBaseSink_\(sanitizedFactoryNameComponent(factoryName))_\(fnv1a64Hex(factoryName))"
    }

    static func generatedBaseTransformTypeName(factoryName: String) -> String {
        "SwiftGstNativeBaseTransform_\(sanitizedFactoryNameComponent(factoryName))_\(fnv1a64Hex(factoryName))"
    }

    static func generatedBaseTransformOutOfPlaceTypeName(factoryName: String) -> String {
        "SwiftGstNativeBaseTransformOutOfPlace_\(sanitizedFactoryNameComponent(factoryName))_\(fnv1a64Hex(factoryName))"
    }

    static func isValidDynamicGTypeName(_ typeName: String) -> Bool {
        guard let first = typeName.unicodeScalars.first, first.isASCIILetter else {
            return false
        }
        return typeName.unicodeScalars.allSatisfy { scalar in
            scalar.isASCIIAlphaNumeric || scalar == "_"
        }
    }
}
internal struct ValidatedBaseSinkRegistration {
    var factoryName: String
    var typeName: String
    var metadata: NativeElementMetadata
    var sinkCaps: String
    var properties: [ValidatedNativeElementProperty]
}

internal struct ValidatedBaseTransformRegistration {
    var factoryName: String
    var typeName: String
    var metadata: NativeElementMetadata
    var sinkCaps: String
    var srcCaps: String
    var passthroughOptions: SwiftBaseTransformPassthroughOptions
    var properties: [ValidatedNativeElementProperty]
}

internal struct ValidatedBaseTransformOutOfPlaceRegistration {
    var factoryName: String
    var typeName: String
    var metadata: NativeElementMetadata
    var sinkCaps: String
    var srcCaps: String
    var options: SwiftBaseTransformOutOfPlaceOptions
    var properties: [ValidatedNativeElementProperty]
}
private enum NativeElementBaseClass {
    case baseSink
    case baseTransform

    var diagnosticName: String {
        switch self {
        case .baseSink:
            return "BaseSink"
        case .baseTransform:
            return "BaseTransform"
        }
    }

    var gtype: GType {
        switch self {
        case .baseSink:
            return gst_base_sink_get_type()
        case .baseTransform:
            return gst_base_transform_get_type()
        }
    }
}
internal enum NativeElementRegistration {
    static func validateBaseSink(_ element: SwiftBaseSinkElement) throws -> ValidatedBaseSinkRegistration {
        try validateFactoryName(element.factoryName)

        let typeName: String
        if let explicitTypeName = element.typeName {
            guard !explicitTypeName.isEmpty else {
                throw GStreamerError.invalidArgument(
                    parameter: "typeName",
                    reason: "typeName must not be empty"
                )
            }
            try validateTypeName(explicitTypeName)
            typeName = explicitTypeName
        } else {
            let generated = NativeElementTypeName.generatedBaseSinkTypeName(factoryName: element.factoryName)
            try validateTypeName(generated)
            typeName = generated
        }

        try validateMetadata(element.metadata)
        try validateCaps(element.sinkCaps, parameter: "sinkCaps")
        let properties = try validateProperties(element.properties, baseClass: .baseSink)

        return ValidatedBaseSinkRegistration(
            factoryName: element.factoryName,
            typeName: typeName,
            metadata: element.metadata,
            sinkCaps: element.sinkCaps,
            properties: properties
        )
    }

    static func validateBaseTransform(
        _ element: SwiftBaseTransformElement
    ) throws -> ValidatedBaseTransformRegistration {
        try validateFactoryName(element.factoryName)

        let typeName: String
        if let explicitTypeName = element.typeName {
            guard !explicitTypeName.isEmpty else {
                throw GStreamerError.invalidArgument(
                    parameter: "typeName",
                    reason: "typeName must not be empty"
                )
            }
            try validateTypeName(explicitTypeName)
            typeName = explicitTypeName
        } else {
            let generated = NativeElementTypeName.generatedBaseTransformTypeName(factoryName: element.factoryName)
            try validateTypeName(generated)
            typeName = generated
        }

        try validateMetadata(element.metadata)
        try validateCaps(element.sinkCaps, parameter: "sinkCaps")
        try validateCaps(element.srcCaps, parameter: "srcCaps")
        let properties = try validateProperties(element.properties, baseClass: .baseTransform)

        return ValidatedBaseTransformRegistration(
            factoryName: element.factoryName,
            typeName: typeName,
            metadata: element.metadata,
            sinkCaps: element.sinkCaps,
            srcCaps: element.srcCaps,
            passthroughOptions: element.passthroughOptions,
            properties: properties
        )
    }

    static func validateBaseTransformOutOfPlace(
        _ element: SwiftBaseTransformOutOfPlaceElement
    ) throws -> ValidatedBaseTransformOutOfPlaceRegistration {
        try validateFactoryName(element.factoryName)

        let typeName: String
        if let explicitTypeName = element.typeName {
            guard !explicitTypeName.isEmpty else {
                throw GStreamerError.invalidArgument(
                    parameter: "typeName",
                    reason: "typeName must not be empty"
                )
            }
            try validateTypeName(explicitTypeName)
            typeName = explicitTypeName
        } else {
            let generated = NativeElementTypeName.generatedBaseTransformOutOfPlaceTypeName(
                factoryName: element.factoryName
            )
            try validateTypeName(generated)
            typeName = generated
        }

        try validateMetadata(element.metadata)
        try validateCaps(element.sinkCaps, parameter: "sinkCaps")
        try validateCaps(element.srcCaps, parameter: "srcCaps")
        let properties = try validateProperties(element.properties, baseClass: .baseTransform)

        return ValidatedBaseTransformOutOfPlaceRegistration(
            factoryName: element.factoryName,
            typeName: typeName,
            metadata: element.metadata,
            sinkCaps: element.sinkCaps,
            srcCaps: element.srcCaps,
            options: element.options,
            properties: properties
        )
    }

    private static func validateFactoryName(_ factoryName: String) throws {
        guard !factoryName.isEmpty else {
            throw GStreamerError.invalidArgument(
                parameter: "factoryName",
                reason: "factoryName must not be empty"
            )
        }

        guard let first = factoryName.unicodeScalars.first, first.isASCIIAlphaNumeric else {
            throw GStreamerError.invalidArgument(
                parameter: "factoryName",
                reason: "factoryName must start with an ASCII letter or digit"
            )
        }

        guard factoryName.unicodeScalars.allSatisfy({ $0.isASCIIAlphaNumeric || $0 == "_" || $0 == "-" }) else {
            throw GStreamerError.invalidArgument(
                parameter: "factoryName",
                reason: "factoryName may contain only ASCII letters, digits, '_' or '-'"
            )
        }
    }

    private static func validateTypeName(_ typeName: String) throws {
        guard NativeElementTypeName.isValidDynamicGTypeName(typeName) else {
            throw GStreamerError.invalidArgument(
                parameter: "typeName",
                reason: "typeName must be a valid dynamic GType name"
            )
        }
    }

    private static func validateMetadata(_ metadata: NativeElementMetadata) throws {
        try requireNonEmpty(metadata.klass, parameter: "metadata.klass")
        try requireNonEmpty(metadata.longName, parameter: "metadata.longName")
        try requireNonEmpty(metadata.description, parameter: "metadata.description")
        try requireNonEmpty(metadata.author, parameter: "metadata.author")
    }

    private static func validateCaps(_ caps: String, parameter: String) throws {
        do {
            let parsedCaps = try Caps(caps)
            guard gst_caps_is_empty(parsedCaps.caps) == 0 else {
                throw GStreamerError.invalidArgument(
                    parameter: parameter,
                    reason: "\(parameter) must not be empty"
                )
            }
        } catch {
            if case GStreamerError.invalidArgument = error {
                throw error
            } else {
                throw GStreamerError.invalidArgument(
                    parameter: parameter,
                    reason: "\(parameter) must parse as GStreamer caps"
                )
            }
        }
    }

    private static func requireNonEmpty(_ value: String, parameter: String) throws {
        guard !value.trimmingWhitespace().isEmpty else {
            throw GStreamerError.invalidArgument(
                parameter: parameter,
                reason: "\(parameter) must not be empty"
            )
        }
    }

    private static func validateProperties(
        _ properties: [NativeElementProperty],
        baseClass: NativeElementBaseClass
    ) throws -> [ValidatedNativeElementProperty] {
        var names = Set<String>()
        var validated: [ValidatedNativeElementProperty] = []
        validated.reserveCapacity(properties.count)

        for property in properties {
            let name = property.propertyName
            try validatePropertyName(name)
            guard names.insert(name).inserted else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "duplicate native element property name '\(name)'"
                )
            }
            guard !inheritedPropertyExists(named: name, baseClass: baseClass) else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "\(baseClass.diagnosticName) property '\(name)' collides with an inherited GObject property"
                )
            }

            validated.append(try validateProperty(property))
        }

        return validated
    }

    private static func validateProperty(_ property: NativeElementProperty) throws -> ValidatedNativeElementProperty {
        switch property {
        case .bool(let name, let defaultValue, let blurb):
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .bool,
                boolDefault: defaultValue,
                intDefault: 0,
                intMin: 0,
                intMax: 0,
                doubleDefault: 0,
                doubleMin: 0,
                doubleMax: 0,
                stringDefault: nil,
                enumCases: [],
                enumDefault: nil,
                enumInputToCanonical: [:]
            )

        case .int(let name, let defaultValue, let min, let max, let blurb):
            guard let intMin = Int32(exactly: min),
                  let intMax = Int32(exactly: max),
                  let intDefault = Int32(exactly: defaultValue)
            else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Int property bounds and default must fit in Int32"
                )
            }
            guard intMin <= intMax else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Int property minimum must be less than or equal to maximum"
                )
            }
            guard intMin...intMax ~= intDefault else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Int property default must be within its descriptor range"
                )
            }
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .int,
                boolDefault: false,
                intDefault: intDefault,
                intMin: intMin,
                intMax: intMax,
                doubleDefault: 0,
                doubleMin: 0,
                doubleMax: 0,
                stringDefault: nil,
                enumCases: [],
                enumDefault: nil,
                enumInputToCanonical: [:]
            )

        case .double(let name, let defaultValue, let min, let max, let blurb):
            guard min.isFinite, max.isFinite, defaultValue.isFinite else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Double property bounds and default must be finite"
                )
            }
            guard min <= max else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Double property minimum must be less than or equal to maximum"
                )
            }
            guard min...max ~= defaultValue else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Double property default must be within its descriptor range"
                )
            }
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .double,
                boolDefault: false,
                intDefault: 0,
                intMin: 0,
                intMax: 0,
                doubleDefault: defaultValue,
                doubleMin: min,
                doubleMax: max,
                stringDefault: nil,
                enumCases: [],
                enumDefault: nil,
                enumInputToCanonical: [:]
            )

        case .string(let name, let defaultValue, let blurb):
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .string,
                boolDefault: false,
                intDefault: 0,
                intMin: 0,
                intMax: 0,
                doubleDefault: 0,
                doubleMin: 0,
                doubleMax: 0,
                stringDefault: defaultValue,
                enumCases: [],
                enumDefault: nil,
                enumInputToCanonical: [:]
            )

        case .stringEnum(let name, let defaultValue, let cases, let blurb):
            let (enumCases, inputMap) = try validateEnumCases(cases, propertyName: name)
            guard let canonicalDefault = inputMap[defaultValue] else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Enum property default must match a declared case name or nick"
                )
            }
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .stringEnum,
                boolDefault: false,
                intDefault: 0,
                intMin: 0,
                intMax: 0,
                doubleDefault: 0,
                doubleMin: 0,
                doubleMax: 0,
                stringDefault: canonicalDefault,
                enumCases: enumCases,
                enumDefault: canonicalDefault,
                enumInputToCanonical: inputMap
            )
        }
    }

    private static func validateEnumCases(
        _ cases: [NativeElementEnumCase],
        propertyName: String
    ) throws -> ([ValidatedNativeElementEnumCase], [String: String]) {
        guard !cases.isEmpty else {
            throw GStreamerError.invalidArgument(
                parameter: "properties.\(propertyName)",
                reason: "Enum property must declare at least one case"
            )
        }

        var names = Set<String>()
        var nicks = Set<String>()
        var inputMap: [String: String] = [:]
        var validated: [ValidatedNativeElementEnumCase] = []
        validated.reserveCapacity(cases.count)

        for enumCase in cases {
            guard !enumCase.name.isEmpty else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(propertyName)",
                    reason: "Enum case names must not be empty"
                )
            }
            guard inputMap[enumCase.name] == nil else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(propertyName)",
                    reason: "Enum case names and nicks must not collide"
                )
            }
            guard names.insert(enumCase.name).inserted else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(propertyName)",
                    reason: "Enum case names must be unique"
                )
            }
            inputMap[enumCase.name] = enumCase.name

            if let nick = enumCase.nick {
                guard !nick.isEmpty else {
                    throw GStreamerError.invalidArgument(
                        parameter: "properties.\(propertyName)",
                        reason: "Enum case nicks must not be empty"
                    )
                }
                guard nicks.insert(nick).inserted else {
                    throw GStreamerError.invalidArgument(
                        parameter: "properties.\(propertyName)",
                        reason: "Enum case nicks must be unique"
                    )
                }
                guard inputMap[nick] == nil else {
                    throw GStreamerError.invalidArgument(
                        parameter: "properties.\(propertyName)",
                        reason: "Enum case names and nicks must not collide"
                    )
                }
                inputMap[nick] = enumCase.name
            }

            validated.append(
                ValidatedNativeElementEnumCase(
                    name: enumCase.name,
                    nick: enumCase.nick,
                    blurb: enumCase.blurb
                )
            )
        }

        return (validated, inputMap)
    }

    private static func validatePropertyName(_ name: String) throws {
        guard let first = name.unicodeScalars.first else {
            throw GStreamerError.invalidArgument(
                parameter: "properties.name",
                reason: "property name must not be empty"
            )
        }
        guard first.isASCIILetter else {
            throw GStreamerError.invalidArgument(
                parameter: "properties.\(name)",
                reason: "property name must start with an ASCII letter"
            )
        }
        guard name.unicodeScalars.allSatisfy({ $0.isASCIIAlphaNumeric || $0 == "-" }) else {
            throw GStreamerError.invalidArgument(
                parameter: "properties.\(name)",
                reason: "property name may contain only ASCII letters, digits, and hyphens"
            )
        }
    }

    private static func inheritedPropertyExists(
        named name: String,
        baseClass: NativeElementBaseClass
    ) -> Bool {
        let types: [GType] = [
            g_object_get_type(),
            gst_object_get_type(),
            gst_element_get_type(),
            baseClass.gtype,
        ]

        return types.contains { type in
            guard let klass = g_type_class_ref(type) else {
                return false
            }
            defer { g_type_class_unref(klass) }
            return name.withCString { namePointer in
                g_object_class_find_property(
                    klass.assumingMemoryBound(to: GObjectClass.self),
                    namePointer
                ) != nil
            }
        }
    }
}

extension Unicode.Scalar {
    var isASCIIAlphaNumeric: Bool {
        isASCIILetter || isASCIIDigit
    }

    var isASCIILetter: Bool {
        ("A"..."Z").contains(self) || ("a"..."z").contains(self)
    }

    var isASCIIDigit: Bool {
        ("0"..."9").contains(self)
    }
}

private extension String {
    init(formatLowercaseHex value: UInt64) {
        let digits = Array("0123456789abcdef")
        var result = ""
        result.reserveCapacity(16)

        for shift in stride(from: 60, through: 0, by: -4) {
            let index = Int((value >> UInt64(shift)) & 0xf)
            result.append(digits[index])
        }

        self = result
    }
}
