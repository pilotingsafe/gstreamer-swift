import Testing
@testable import GStreamer

private let nanosPerSecond: UInt64 = 1_000_000_000
private let maxWholeSeconds = UInt64.max / nanosPerSecond
private let maxRemainder = UInt64.max % nanosPerSecond

@Suite("Reliable Duration Conversion")
struct ReliableDurationConversionTests {

    @Test("Zero converts to zero nanoseconds")
    func zeroConvertsToZeroNanoseconds() {
        #expect(ReliableDurationConversion.nanosecondsClampingNegativeToZero(.zero) == 0)
    }

    @Test("Small exact duration converts to nanoseconds")
    func smallExactDurationConvertsToNanoseconds() {
        let duration = Duration.seconds(2) + .milliseconds(500)

        #expect(
            ReliableDurationConversion.nanosecondsClampingNegativeToZero(duration)
                == 2_500_000_000
        )
    }

    @Test("Negative one nanosecond clamps to zero")
    func negativeOneNanosecondClampsToZero() {
        #expect(
            ReliableDurationConversion.nanosecondsClampingNegativeToZero(.nanoseconds(-1))
                == 0
        )
    }

    @Test("Negative duration with positive remainder clamps to zero")
    func negativeDurationWithPositiveRemainderClampsToZero() {
        let duration = Duration.seconds(-2) + .nanoseconds(1)

        #expect(
            ReliableDurationConversion.nanosecondsClampingNegativeToZero(duration)
                == 0
        )
    }

    @Test("Maximum representable nanosecond duration returns UInt64 max")
    func maximumRepresentableNanosecondDurationReturnsUInt64Max() {
        let duration = Duration.seconds(Int64(maxWholeSeconds))
            + .nanoseconds(Int64(maxRemainder))

        #expect(
            ReliableDurationConversion.nanosecondsClampingNegativeToZero(duration)
                == UInt64.max
        )
    }

    @Test("One nanosecond past UInt64 max saturates to UInt64 max")
    func oneNanosecondPastUInt64MaxSaturatesToUInt64Max() {
        let duration = Duration.seconds(Int64(maxWholeSeconds))
            + .nanoseconds(Int64(maxRemainder + 1))

        #expect(
            ReliableDurationConversion.nanosecondsClampingNegativeToZero(duration)
                == UInt64.max
        )
    }

    @Test("One whole second past UInt64 max saturates to UInt64 max")
    func oneWholeSecondPastUInt64MaxSaturatesToUInt64Max() {
        let duration = Duration.seconds(Int64(maxWholeSeconds + 1))

        #expect(
            ReliableDurationConversion.nanosecondsClampingNegativeToZero(duration)
                == UInt64.max
        )
    }

    @Test("Int64 max seconds saturates to UInt64 max")
    func int64MaxSecondsSaturatesToUInt64Max() {
        #expect(
            ReliableDurationConversion.nanosecondsClampingNegativeToZero(.seconds(Int64.max))
                == UInt64.max
        )
    }
}
