#if os(macOS)
import Foundation

/// Drives the status LEDs from the approved design (Bereit / Gerät fehlt / Datei fehlt
/// plus one per-button LED) — see [[soundboard-visual-design-approved]].
struct SessionHealth {
    var missingFileButtonIDs: Set<UUID> = []
    var missingDeviceButtonIDs: Set<UUID> = []

    var isReady: Bool { missingFileButtonIDs.isEmpty && missingDeviceButtonIDs.isEmpty }
    var hasMissingFile: Bool { !missingFileButtonIDs.isEmpty }
    var hasMissingDevice: Bool { !missingDeviceButtonIDs.isEmpty }
}

enum SessionHealthChecker {
    static func check(_ session: Session) -> SessionHealth {
        let availableUIDs = Set(AudioDeviceManager.outputDevices().map(\.uid))

        var health = SessionHealth()
        for button in session.buttons {
            if !FileManager.default.fileExists(atPath: button.soundFilePath) {
                health.missingFileButtonIDs.insert(button.id)
            }
            if let uid = button.outputDeviceUID, !availableUIDs.contains(uid) {
                health.missingDeviceButtonIDs.insert(button.id)
            }
        }
        return health
    }
}
#endif
