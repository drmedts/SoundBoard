#if os(macOS)
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let outputChannelCount: Int
}

enum AudioDeviceManager {
    /// All devices on the system that can produce audio output (output channel count > 0).
    static func outputDevices() -> [AudioOutputDevice] {
        guard let deviceIDs = allDeviceIDs() else { return [] }
        return deviceIDs.compactMap { id in makeDevice(id: id) }
    }

    static func device(withID id: AudioDeviceID) -> AudioOutputDevice? {
        makeDevice(id: id)
    }

    static func device(withUID uid: String) -> AudioOutputDevice? {
        outputDevices().first { $0.uid == uid }
    }

    static func defaultOutputDevice() -> AudioOutputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        guard status == noErr else { return nil }
        return makeDevice(id: deviceID)
    }

    /// Returns the device's master output volume. Devices without a master
    /// control fall back to the average of their writable channel volumes.
    static func volume(for device: AudioOutputDevice) -> Float? {
        if let master = volume(deviceID: device.id, element: kAudioObjectPropertyElementMain) {
            return master
        }

        let channelVolumes = (1...device.outputChannelCount).compactMap {
            volume(deviceID: device.id, element: AudioObjectPropertyElement($0))
        }
        guard !channelVolumes.isEmpty else { return nil }
        return channelVolumes.reduce(0, +) / Float(channelVolumes.count)
    }

    /// Sets the device's master output volume, or all writable output channels
    /// when the hardware exposes no master volume control.
    @discardableResult
    static func setVolume(_ volume: Float, for device: AudioOutputDevice) -> Bool {
        let clampedVolume = min(max(volume, 0), 1)
        if setVolume(clampedVolume, deviceID: device.id, element: kAudioObjectPropertyElementMain) {
            return true
        }

        var changedChannel = false
        for channel in 1...device.outputChannelCount {
            changedChannel = setVolume(
                clampedVolume,
                deviceID: device.id,
                element: AudioObjectPropertyElement(channel)
            ) || changedChannel
        }
        return changedChannel
    }

    // MARK: - Private

    private static func allDeviceIDs() -> [AudioDeviceID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return nil }
        return deviceIDs
    }

    private static func makeDevice(id: AudioDeviceID) -> AudioOutputDevice? {
        let channels = outputChannelCount(for: id)
        guard channels > 0 else { return nil }
        guard let name = string(for: id, selector: kAudioObjectPropertyName) else { return nil }
        let uid = string(for: id, selector: kAudioDevicePropertyDeviceUID) ?? "\(id)"
        return AudioOutputDevice(id: id, uid: uid, name: name, outputChannelCount: channels)
    }

    private static func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawPointer)
        guard status == noErr else { return 0 }

        let bufferList = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func volume(
        deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var value: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private static func setVolume(
        _ volume: Float,
        deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isSettable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue else { return false }

        var value = Float32(volume)
        let dataSize = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &value) == noErr
    }

    private static func string(for deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }
}
#endif
