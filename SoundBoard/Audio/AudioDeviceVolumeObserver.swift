#if os(macOS)
import CoreAudio
import Foundation

/// Watches a single output device's hardware volume and calls back on the main
/// queue whenever it changes — including changes made outside the app (System
/// Settings, hardware volume keys, another app), not just ones this app made
/// itself. Lets the Volumemaster slider track `Systemstand = Reglerstand` live.
final class AudioDeviceVolumeObserver {
    private let deviceID: AudioDeviceID
    private var registered: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    init(device: AudioOutputDevice, onChange: @escaping @Sendable () -> Void) {
        deviceID = device.id

        var addresses = [
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
        ]
        for channel in 1...max(device.outputChannelCount, 1) {
            addresses.append(AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: AudioObjectPropertyElement(channel)))
        }

        for address in addresses {
            var mutableAddress = address
            guard AudioObjectHasProperty(deviceID, &mutableAddress) else { continue }
            let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            let status = AudioObjectAddPropertyListenerBlock(deviceID, &mutableAddress, DispatchQueue.main, block)
            if status == noErr {
                registered.append((address, block))
            }
        }
    }

    deinit {
        for (address, block) in registered {
            var mutableAddress = address
            AudioObjectRemovePropertyListenerBlock(deviceID, &mutableAddress, DispatchQueue.main, block)
        }
    }
}
#endif
