import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Callback Registration Lifecycle Tests", .timeLimit(.minutes(1)))
struct CallbackRegistrationLifecycleTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Disconnect while callback is in flight balances context retains")
    func disconnectWhileCallbackIsInFlightBalancesContextRetains() {
        let result = swift_gst_test_callback_registration_disconnect_while_in_flight()

        #expect(
            result.success != 0,
            """
            status=\(result.status.rawValue), \
            callback_count=\(result.callback_count), \
            retain_count=\(result.retain_count), \
            release_count=\(result.release_count)
            """
        )
        #expect(result.status == SWIFT_GST_TEST_CALLBACK_REGISTRATION_RACE_OK)
        #expect(result.callback_count == 1)
        #expect(result.retain_count == 2)
        #expect(result.release_count == 2)
        #expect(result.retain_count == result.release_count)
    }
}
