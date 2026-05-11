import GStreamer

@main
struct GstReliableAudioExample {
  static func main() async throws {
    guard let path = CommandLine.arguments.dropFirst().first else {
      print("Usage: gst-reliable-audio <audio-file>")
      return
    }

    print("GStreamer version: \(GStreamer.versionString)")

    let source = try AudioSource.file(path: path)
      .withEncoding(.raw)
      .build()

    var packetCount = 0
    var totalBytes = 0

    do {
      for try await packet in source.reliablePackets() {
        packetCount += 1
        totalBytes += packet.size
      }

      print("Reached EOS after \(packetCount) packets (\(totalBytes) bytes)")
    } catch is CancellationError {
      print("Cancelled after \(packetCount) packets")
    } catch {
      print("Reliable packet iteration failed: \(error)")
      throw error
    }
  }
}
