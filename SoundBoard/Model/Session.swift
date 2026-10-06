import Foundation
import CoreGraphics

struct StatusLEDGroup: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
}

struct KeyboardShortcutConfig: Codable, Hashable {
    var key: String
    var modifiers: Int

    var displayName: String {
        var parts: [String] = []
        if modifiers & 1 != 0 { parts.append("Ctrl") }
        if modifiers & 2 != 0 { parts.append("Option") }
        if modifiers & 4 != 0 { parts.append("Shift") }
        if modifiers & 8 != 0 { parts.append("Cmd") }
        parts.append(key.uppercased())
        return parts.joined(separator: " + ")
    }
}

struct SoundButtonConfig: Codable, Identifiable, Hashable {
    enum PlayMode: String, Codable {
        case toggle      // click to start, click again to stop
        case holdToPlay  // plays only while held down
    }

    var id: UUID = UUID()
    var title: String
    var position: CGPoint
    var diameter: CGFloat = 64
    var labelFontSize: CGFloat = 15

    var face: ButtonFace
    var illuminated: Bool = true

    /// Absolute path to the sound file. Stored as a reference, not a copy — see
    /// [[soundboard-architecture-decisions]]: moved/renamed files are caught by
    /// `SessionHealthChecker`, not silently re-linked.
    var soundFilePath: String

    var volume: Float = 1.0
    var fadeInEnabled: Bool = false
    var fadeInDuration: TimeInterval = 1.0
    var fadeOutEnabled: Bool = false
    var fadeOutDuration: TimeInterval = 1.0
    var loopEnabled: Bool = false
    var playMode: PlayMode = .toggle

    /// `nil` means "system default output device".
    var outputDeviceUID: String?
    /// 0-based index of the first of the two consecutive device channels used for playback.
    var outputChannelOffset: Int = 0

    var statusGroupID: StatusLEDGroup.ID?
    var statusOrder: Int = 0
    var keyboardShortcut: KeyboardShortcutConfig?

    init(
        id: UUID = UUID(),
        title: String,
        position: CGPoint,
        diameter: CGFloat = 64,
        labelFontSize: CGFloat = 15,
        face: ButtonFace,
        illuminated: Bool = true,
        soundFilePath: String,
        volume: Float = 1.0,
        fadeInEnabled: Bool = false,
        fadeInDuration: TimeInterval = 1.0,
        fadeOutEnabled: Bool = false,
        fadeOutDuration: TimeInterval = 1.0,
        loopEnabled: Bool = false,
        playMode: PlayMode = .toggle,
        outputDeviceUID: String? = nil,
        outputChannelOffset: Int = 0,
        statusGroupID: StatusLEDGroup.ID? = nil,
        statusOrder: Int = 0,
        keyboardShortcut: KeyboardShortcutConfig? = nil
    ) {
        self.id = id
        self.title = title
        self.position = position
        self.diameter = diameter
        self.labelFontSize = labelFontSize
        self.face = face
        self.illuminated = illuminated
        self.soundFilePath = soundFilePath
        self.volume = volume
        self.fadeInEnabled = fadeInEnabled
        self.fadeInDuration = fadeInDuration
        self.fadeOutEnabled = fadeOutEnabled
        self.fadeOutDuration = fadeOutDuration
        self.loopEnabled = loopEnabled
        self.playMode = playMode
        self.outputDeviceUID = outputDeviceUID
        self.outputChannelOffset = outputChannelOffset
        self.statusGroupID = statusGroupID
        self.statusOrder = statusOrder
        self.keyboardShortcut = keyboardShortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        position = try container.decode(CGPoint.self, forKey: .position)
        diameter = try container.decodeIfPresent(CGFloat.self, forKey: .diameter) ?? 64
        labelFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .labelFontSize) ?? 15
        face = try container.decode(ButtonFace.self, forKey: .face)
        illuminated = try container.decodeIfPresent(Bool.self, forKey: .illuminated) ?? true
        soundFilePath = try container.decodeIfPresent(String.self, forKey: .soundFilePath) ?? ""
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        fadeInEnabled = try container.decodeIfPresent(Bool.self, forKey: .fadeInEnabled) ?? false
        fadeInDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .fadeInDuration) ?? 1.0
        fadeOutEnabled = try container.decodeIfPresent(Bool.self, forKey: .fadeOutEnabled) ?? false
        fadeOutDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .fadeOutDuration) ?? 1.0
        loopEnabled = try container.decodeIfPresent(Bool.self, forKey: .loopEnabled) ?? false
        playMode = try container.decodeIfPresent(PlayMode.self, forKey: .playMode) ?? .toggle
        outputDeviceUID = try container.decodeIfPresent(String.self, forKey: .outputDeviceUID)
        outputChannelOffset = try container.decodeIfPresent(Int.self, forKey: .outputChannelOffset) ?? 0
        statusGroupID = try container.decodeIfPresent(StatusLEDGroup.ID.self, forKey: .statusGroupID)
        statusOrder = try container.decodeIfPresent(Int.self, forKey: .statusOrder) ?? 0
        keyboardShortcut = try container.decodeIfPresent(KeyboardShortcutConfig.self, forKey: .keyboardShortcut)
    }

    /// Typed in the title's `TextField` (which, being single-line, can't take a
    /// real newline from Return) to request a line break on the button cap only.
    static let lineBreakMarker = "\\n"

    /// Title as shown on the button cap itself: marker → an actual line break.
    var displayTitle: String {
        title.replacingOccurrences(of: Self.lineBreakMarker, with: "\n")
    }

    /// Title everywhere else (status rail, status group lists, …): marker
    /// collapsed to a space so it still reads as plain, single-line text.
    var plainTitle: String {
        title.replacingOccurrences(of: Self.lineBreakMarker, with: " ")
    }
}

struct Session: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var buttons: [SoundButtonConfig] = []
    var gridSize: CGFloat = 20
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    // Das Status-Panel und die beiden Stop-Taster sind selbst Elemente auf der
    // Oberfläche (frei platzierbar wie Buttons), keine fest angedockte Sidebar.
    var statusPanelPosition: CGPoint = CGPoint(x: 800, y: 110)
    var stopButtonPosition: CGPoint = CGPoint(x: 760, y: 500)
    var emergencyStopPosition: CGPoint = CGPoint(x: 860, y: 500)
    var volumeMasterPosition: CGPoint?
    var statusGroups: [StatusLEDGroup]
    /// 1 = all groups stacked in a single column; 2 = groups distributed across two
    /// narrow, tightly-spaced columns to save vertical space when there are many
    /// buttons/groups. See [[soundboard-visual-design-approved]].
    var statusRailColumns: Int = 1
    var statusPanelFontSize: CGFloat
    var volumeMasterFontSize: CGFloat
    var stopButtonFontSize: CGFloat
    var emergencyStopFontSize: CGFloat
    var stopButtonShortcut: KeyboardShortcutConfig?
    var emergencyStopShortcut: KeyboardShortcutConfig?

    init(
        id: UUID = UUID(),
        name: String,
        buttons: [SoundButtonConfig] = [],
        gridSize: CGFloat = 20,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        statusPanelPosition: CGPoint = CGPoint(x: 800, y: 110),
        stopButtonPosition: CGPoint = CGPoint(x: 760, y: 500),
        emergencyStopPosition: CGPoint = CGPoint(x: 860, y: 500),
        volumeMasterPosition: CGPoint? = nil,
        statusGroups: [StatusLEDGroup] = [],
        statusRailColumns: Int = 1,
        statusPanelFontSize: CGFloat = 12,
        volumeMasterFontSize: CGFloat = 13,
        stopButtonFontSize: CGFloat = 15,
        emergencyStopFontSize: CGFloat = 15,
        stopButtonShortcut: KeyboardShortcutConfig? = nil,
        emergencyStopShortcut: KeyboardShortcutConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.buttons = buttons
        self.gridSize = gridSize
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.statusPanelPosition = statusPanelPosition
        self.stopButtonPosition = stopButtonPosition
        self.emergencyStopPosition = emergencyStopPosition
        self.volumeMasterPosition = volumeMasterPosition
        self.statusGroups = statusGroups.isEmpty ? [StatusLEDGroup(name: "Buttons")] : statusGroups
        self.statusRailColumns = statusRailColumns
        self.statusPanelFontSize = statusPanelFontSize
        self.volumeMasterFontSize = volumeMasterFontSize
        self.stopButtonFontSize = stopButtonFontSize
        self.emergencyStopFontSize = emergencyStopFontSize
        self.stopButtonShortcut = stopButtonShortcut
        self.emergencyStopShortcut = emergencyStopShortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        buttons = try container.decodeIfPresent([SoundButtonConfig].self, forKey: .buttons) ?? []
        gridSize = try container.decodeIfPresent(CGFloat.self, forKey: .gridSize) ?? 20
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        statusPanelPosition = try container.decodeIfPresent(CGPoint.self, forKey: .statusPanelPosition) ?? CGPoint(x: 800, y: 110)
        stopButtonPosition = try container.decodeIfPresent(CGPoint.self, forKey: .stopButtonPosition) ?? CGPoint(x: 760, y: 500)
        emergencyStopPosition = try container.decodeIfPresent(CGPoint.self, forKey: .emergencyStopPosition) ?? CGPoint(x: 860, y: 500)
        volumeMasterPosition = try container.decodeIfPresent(CGPoint.self, forKey: .volumeMasterPosition)
        statusGroups = try container.decodeIfPresent([StatusLEDGroup].self, forKey: .statusGroups) ?? []
        statusRailColumns = try container.decodeIfPresent(Int.self, forKey: .statusRailColumns) ?? 1
        statusPanelFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .statusPanelFontSize) ?? 12
        volumeMasterFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .volumeMasterFontSize) ?? 13
        stopButtonFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .stopButtonFontSize) ?? 15
        emergencyStopFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .emergencyStopFontSize) ?? 15
        stopButtonShortcut = try container.decodeIfPresent(KeyboardShortcutConfig.self, forKey: .stopButtonShortcut)
        emergencyStopShortcut = try container.decodeIfPresent(KeyboardShortcutConfig.self, forKey: .emergencyStopShortcut)

        if statusGroups.isEmpty {
            let legacyGroup = StatusLEDGroup(name: "Buttons")
            statusGroups = [legacyGroup]
            for index in buttons.indices {
                buttons[index].statusGroupID = legacyGroup.id
                buttons[index].statusOrder = index
            }
        }
    }
}
