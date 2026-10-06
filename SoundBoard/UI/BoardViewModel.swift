#if os(macOS)
import AppKit
import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers

private let audioLogger = Logger(subsystem: "SoundBoard", category: "Audio")

enum BoardMode {
    case edit
    case live
}

enum BoardInspectorSelection: Equatable {
    case buttons
    case statusPanel
    case volumeMaster
    case stopButton
    case emergencyStop
}

enum ShortcutOwner: Hashable {
    case button(SoundButtonConfig.ID)
    case stopButton
    case emergencyStop
}

/// Owns the session, the live audio players, and all playback/editing logic.
/// Drives the status LEDs from [[soundboard-visual-design-approved]]: `playingButtonIDs`
/// is the solid-on set, `blinkingButtonIDs` covers fade windows and "near the end".
@MainActor
final class BoardViewModel: NSObject, ObservableObject {
    @Published var session: Session
    @Published var mode: BoardMode = .edit
    @Published private(set) var selectedButtonIDs: Set<SoundButtonConfig.ID> = []
    @Published private(set) var inspectorSelection: BoardInspectorSelection?
    @Published private(set) var health = SessionHealth()
    @Published private(set) var playingButtonIDs: Set<SoundButtonConfig.ID> = []
    @Published private(set) var blinkingButtonIDs: Set<SoundButtonConfig.ID> = []
    /// Live translation of an in-progress drag on the multi-selection, so every
    /// selected button's view (not just the one the gesture is attached to) can
    /// render the group moving together. Reset to `.zero` once the drag ends.
    @Published var groupDragOffset: CGSize = .zero
    private var fadingButtonIDs: Set<SoundButtonConfig.ID> = []
    /// Flips every tick while anything is blinking — callers alternate their "on"
    /// state with this to produce a real flash instead of a static dim.
    @Published private(set) var blinkPhase = false

    private(set) var sessionURL: URL?
    private var players: [SoundButtonConfig.ID: ChannelRoutedPlayer] = [:]
    private var statusTimer: Timer?
    private var keyEventMonitor: Any?
    private var buttonClipboard: [SoundButtonConfig] = []
    private var pasteCount = 0

    var hasButtonClipboard: Bool { !buttonClipboard.isEmpty }

    var isReady: Bool { health.isReady }
    var isOutputActive: Bool { !playingButtonIDs.isEmpty }
    var sessionURLDisplayName: String? { sessionURL?.lastPathComponent }

    var selectedButtonID: SoundButtonConfig.ID? {
        get { selectedButtonIDs.count == 1 ? selectedButtonIDs.first : nil }
        set {
            selectedButtonIDs = newValue.map { [$0] } ?? []
            inspectorSelection = newValue == nil ? nil : .buttons
        }
    }

    var statusButtonGroups: [StatusIndicatorGroup] {
        session.statusGroups.map { group in
            let indicators = session.buttons
                .filter { $0.statusGroupID == group.id }
                .sorted { $0.statusOrder < $1.statusOrder }
                .map {
                    StatusIndicator(
                        id: "button:\($0.id.uuidString)",
                        label: $0.plainTitle,
                        lit: isEffectivelyLit($0.id)
                    )
                }
            return StatusIndicatorGroup(id: group.id, name: group.name, indicators: indicators)
        }
    }

    var outputDeviceStatus: [StatusIndicator] {
        let devices = AudioDeviceManager.outputDevices()
        let defaultDevice = AudioDeviceManager.defaultOutputDevice()
        let devicesByUID = Dictionary(uniqueKeysWithValues: devices.map { ($0.uid, $0) })

        let usedUIDs = Set(session.buttons.compactMap { button -> String? in
            button.outputDeviceUID ?? defaultDevice?.uid
        })
        let activeUIDs = Set(session.buttons.compactMap { button -> String? in
            guard playingButtonIDs.contains(button.id) else { return nil }
            return button.outputDeviceUID ?? defaultDevice?.uid
        })

        return usedUIDs.compactMap { uid in
            guard let device = devicesByUID[uid] ?? (defaultDevice?.uid == uid ? defaultDevice : nil) else { return nil }
            return StatusIndicator(
                id: "device:\(uid)",
                label: device.name,
                lit: activeUIDs.contains(uid)
            )
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    init(session: Session? = nil) {
        self.session = session ?? Session(name: "Neue Sitzung")
        super.init()
        refreshHealth()
        statusTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { @MainActor [weak self] event in
            guard let self else { return event }
            return self.handleShortcutEvent(event) ? nil : event
        }
    }

    @objc private func timerFired() {
        tick()
    }

    deinit {
        statusTimer?.invalidate()
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
    }

    // MARK: - Board editing

    func selectButton(_ id: SoundButtonConfig.ID, extendingSelection: Bool = false) {
        if extendingSelection {
            if selectedButtonIDs.contains(id) {
                selectedButtonIDs.remove(id)
            } else {
                selectedButtonIDs.insert(id)
            }
        } else {
            selectedButtonIDs = [id]
        }
        inspectorSelection = selectedButtonIDs.isEmpty ? nil : .buttons
    }

    func selectButtons(in rect: CGRect, extendingSelection: Bool = false) {
        let matches = Set(session.buttons.filter { rect.contains($0.position) }.map(\.id))
        selectedButtonIDs = extendingSelection ? selectedButtonIDs.union(matches) : matches
        inspectorSelection = selectedButtonIDs.isEmpty ? nil : .buttons
    }

    /// A plain click on the empty canvas clears the whole selection — buttons and
    /// any selected free-floating element (status panel, stop buttons, …) alike.
    func deselectAll() {
        selectedButtonIDs.removeAll()
        inspectorSelection = nil
    }

    func selectStatusPanel() {
        selectedButtonIDs.removeAll()
        inspectorSelection = .statusPanel
    }

    func selectVolumeMaster() {
        selectedButtonIDs.removeAll()
        inspectorSelection = .volumeMaster
    }

    func selectStopButton() {
        selectedButtonIDs.removeAll()
        inspectorSelection = .stopButton
    }

    func selectEmergencyStop() {
        selectedButtonIDs.removeAll()
        inspectorSelection = .emergencyStop
    }

    func shortcutConflict(_ shortcut: KeyboardShortcutConfig, excluding owner: ShortcutOwner) -> String? {
        if owner != .stopButton, session.stopButtonShortcut == shortcut { return "Stop (Fade)" }
        if owner != .emergencyStop, session.emergencyStopShortcut == shortcut { return "Not-Stop" }
        for button in session.buttons where button.keyboardShortcut == shortcut {
            if owner != .button(button.id) { return button.plainTitle }
        }
        return nil
    }

    func setShortcut(_ shortcut: KeyboardShortcutConfig?, for owner: ShortcutOwner) {
        switch owner {
        case .button(let id):
            update(id) { $0.keyboardShortcut = shortcut }
        case .stopButton:
            session.stopButtonShortcut = shortcut
        case .emergencyStop:
            session.emergencyStopShortcut = shortcut
        }
    }

    func addButton(at position: CGPoint) {
        let snapped = snap(position)
        let groupID = session.statusGroups.first?.id
        let order = session.buttons.filter { $0.statusGroupID == groupID }.count
        let config = SoundButtonConfig(
            title: "Neuer Sound",
            position: snapped,
            face: .blue,
            soundFilePath: "",
            statusGroupID: groupID,
            statusOrder: order
        )
        session.buttons.append(config)
        selectedButtonID = config.id
        refreshHealth()
    }

    /// Copies the current selection (or, if `ids` is given, exactly those buttons)
    /// onto the in-memory clipboard so the same style/settings can be reused.
    func copyButtons(_ ids: Set<SoundButtonConfig.ID>? = nil) {
        let targetIDs = ids ?? selectedButtonIDs
        let configs = session.buttons.filter { targetIDs.contains($0.id) }
        guard !configs.isEmpty else { return }
        buttonClipboard = configs
        pasteCount = 0
    }

    /// Inserts clipboard buttons as new copies, offset diagonally from the
    /// originals (cascading further with each repeated paste), and selects them.
    func pasteButtons() {
        guard !buttonClipboard.isEmpty else { return }
        pasteCount += 1
        let offset = (session.gridSize > 0 ? session.gridSize : 20) * CGFloat(pasteCount)

        var pastedIDs: Set<SoundButtonConfig.ID> = []
        for original in buttonClipboard {
            var copy = original
            copy.id = UUID()
            copy.position = snap(CGPoint(x: original.position.x + offset, y: original.position.y + offset))
            copy.keyboardShortcut = nil
            copy.statusOrder = session.buttons.filter { $0.statusGroupID == copy.statusGroupID }.count
            session.buttons.append(copy)
            pastedIDs.insert(copy.id)
        }
        selectedButtonIDs = pastedIDs
        inspectorSelection = .buttons
        refreshHealth()
    }

    /// Copies and immediately pastes a single button — a quick one-step duplicate.
    func duplicateButton(_ id: SoundButtonConfig.ID) {
        copyButtons([id])
        pasteButtons()
    }

    func addVolumeMaster(at position: CGPoint) {
        guard session.volumeMasterPosition == nil else { return }
        session.volumeMasterPosition = snap(position)
    }

    func moveVolumeMaster(to position: CGPoint) {
        session.volumeMasterPosition = snap(position)
    }

    func removeVolumeMaster() {
        session.volumeMasterPosition = nil
    }

    func moveButton(_ id: SoundButtonConfig.ID, to position: CGPoint) {
        guard let index = session.buttons.firstIndex(where: { $0.id == id }) else { return }
        session.buttons[index].position = snap(position)
    }

    /// Moves every selected button by the same translation (each snapped
    /// individually), so a drag on one button carries the whole selection along.
    func moveSelectedButtons(by translation: CGSize) {
        for index in session.buttons.indices where selectedButtonIDs.contains(session.buttons[index].id) {
            let moved = CGPoint(
                x: session.buttons[index].position.x + translation.width,
                y: session.buttons[index].position.y + translation.height
            )
            session.buttons[index].position = snap(moved)
        }
    }

    func deleteButton(_ id: SoundButtonConfig.ID) {
        stop(id)
        retirePlayer(id)
        session.buttons.removeAll { $0.id == id }
        if selectedButtonID == id { selectedButtonID = nil }
        refreshHealth()
    }

    func update(_ id: SoundButtonConfig.ID, _ transform: (inout SoundButtonConfig) -> Void) {
        guard let index = session.buttons.firstIndex(where: { $0.id == id }) else { return }
        transform(&session.buttons[index])
        retirePlayer(id) // config changed (file/device/channel) — rebuild lazily on next play
        refreshHealth()
    }

    private func retirePlayer(_ id: SoundButtonConfig.ID) {
        guard let player = players.removeValue(forKey: id) else { return }
        player.stopImmediately()
        playingButtonIDs.remove(id)
        fadingButtonIDs.remove(id)
        blinkingButtonIDs.remove(id)
    }

    func addStatusGroup() {
        session.statusGroups.append(StatusLEDGroup(name: "Neue Gruppe"))
    }

    func renameStatusGroup(_ id: StatusLEDGroup.ID, to name: String) {
        guard let index = session.statusGroups.firstIndex(where: { $0.id == id }) else { return }
        session.statusGroups[index].name = name
    }

    func moveStatusGroup(_ id: StatusLEDGroup.ID, by offset: Int) {
        guard let source = session.statusGroups.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard session.statusGroups.indices.contains(destination) else { return }
        session.statusGroups.swapAt(source, destination)
    }

    func deleteStatusGroup(_ id: StatusLEDGroup.ID) {
        guard session.statusGroups.count > 1,
              let groupIndex = session.statusGroups.firstIndex(where: { $0.id == id }) else { return }
        let fallbackID = session.statusGroups.first { $0.id != id }!.id
        let nextOrder = session.buttons.filter { $0.statusGroupID == fallbackID }.count
        var movedOffset = 0
        for index in session.buttons.indices where session.buttons[index].statusGroupID == id {
            session.buttons[index].statusGroupID = fallbackID
            session.buttons[index].statusOrder = nextOrder + movedOffset
            movedOffset += 1
        }
        session.statusGroups.remove(at: groupIndex)
    }

    func assignButton(_ buttonID: SoundButtonConfig.ID, toStatusGroup groupID: StatusLEDGroup.ID) {
        let order = session.buttons.filter { $0.statusGroupID == groupID }.count
        update(buttonID) {
            $0.statusGroupID = groupID
            $0.statusOrder = order
        }
    }

    func moveButtonInStatusGroup(_ buttonID: SoundButtonConfig.ID, by offset: Int) {
        guard let button = session.buttons.first(where: { $0.id == buttonID }) else { return }
        let orderedIDs = session.buttons
            .filter { $0.statusGroupID == button.statusGroupID }
            .sorted { $0.statusOrder < $1.statusOrder }
            .map(\.id)
        guard let source = orderedIDs.firstIndex(of: buttonID) else { return }
        let destination = source + offset
        guard orderedIDs.indices.contains(destination),
              let otherIndex = session.buttons.firstIndex(where: { $0.id == orderedIDs[destination] }),
              let buttonIndex = session.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
        let otherOrder = session.buttons[otherIndex].statusOrder
        session.buttons[otherIndex].statusOrder = session.buttons[buttonIndex].statusOrder
        session.buttons[buttonIndex].statusOrder = otherOrder
    }

    private func snap(_ point: CGPoint) -> CGPoint {
        let grid = session.gridSize
        guard grid > 0 else { return point }
        return CGPoint(x: (point.x / grid).rounded() * grid, y: (point.y / grid).rounded() * grid)
    }

    /// Moves one of the free-floating board elements (status panel, stop buttons).
    func moveElement(_ keyPath: WritableKeyPath<Session, CGPoint>, to position: CGPoint) {
        session[keyPath: keyPath] = snap(position)
    }

    /// Resolved on/off state for a button's lamp or its status-panel LED: solid
    /// while playing, alternating with `blinkPhase` during fade/near-end windows.
    func isEffectivelyLit(_ id: SoundButtonConfig.ID) -> Bool {
        guard playingButtonIDs.contains(id) else { return false }
        if blinkingButtonIDs.contains(id) { return blinkPhase }
        return true
    }

    // MARK: - Playback

    func togglePlay(_ id: SoundButtonConfig.ID) {
        if playingButtonIDs.contains(id) {
            stop(id)
        } else {
            start(id)
        }
    }

    func beginHold(_ id: SoundButtonConfig.ID) {
        guard !playingButtonIDs.contains(id) else { return }
        start(id)
    }

    func endHold(_ id: SoundButtonConfig.ID) {
        guard playingButtonIDs.contains(id) else { return }
        stop(id)
    }

    private func start(_ id: SoundButtonConfig.ID) {
        guard let config = session.buttons.first(where: { $0.id == id }) else { return }
        do {
            let player = try players[id] ?? ChannelRoutedPlayer(config: config)
            players[id] = player
            fadingButtonIDs.remove(id)
            playingButtonIDs.insert(id)
            try player.play(
                loop: config.loopEnabled,
                fadeInDuration: config.fadeInEnabled ? config.fadeInDuration : 0,
                fadeOutDuration: config.fadeOutEnabled ? config.fadeOutDuration : 0
            ) { [self] in
                Task { @MainActor [self] in
                    self.playingButtonIDs.remove(id)
                    self.fadingButtonIDs.remove(id)
                    self.blinkingButtonIDs.remove(id)
                }
            }
        } catch {
            audioLogger.error("Could not start button '\(config.plainTitle, privacy: .public)': \(String(describing: error), privacy: .public)")
            playingButtonIDs.remove(id)
            players[id] = nil
        }
    }

    private func stop(_ id: SoundButtonConfig.ID) {
        guard let player = players[id] else {
            playingButtonIDs.remove(id)
            fadingButtonIDs.remove(id)
            return
        }
        let config = session.buttons.first { $0.id == id }
        let fadeOut = (config?.fadeOutEnabled ?? false) ? (config?.fadeOutDuration ?? 0) : 0
        if fadeOut > 0 {
            fadingButtonIDs.insert(id)
        }
        player.requestStop(fadeOutDuration: fadeOut) { [self] in
            Task { @MainActor [self] in
                self.playingButtonIDs.remove(id)
                self.fadingButtonIDs.remove(id)
                self.blinkingButtonIDs.remove(id)
            }
        }
    }

    /// "Stop" — fades out everything currently playing.
    func stopAllFading() {
        for id in playingButtonIDs {
            guard let player = players[id] else { continue }
            let config = session.buttons.first { $0.id == id }
            let fadeOut = (config?.fadeOutEnabled ?? false) ? (config?.fadeOutDuration ?? 0) : 1.0
            if fadeOut > 0 {
                fadingButtonIDs.insert(id)
            }
            player.requestStop(fadeOutDuration: fadeOut) { [self] in
                Task { @MainActor [self] in
                    self.playingButtonIDs.remove(id)
                    self.fadingButtonIDs.remove(id)
                    self.blinkingButtonIDs.remove(id)
                }
            }
        }
    }

    /// "Not-Stop" — cuts everything immediately, no fade.
    func emergencyStopAll() {
        for player in players.values {
            player.stopImmediately()
        }
        playingButtonIDs.removeAll()
        fadingButtonIDs.removeAll()
        blinkingButtonIDs.removeAll()
    }

    /// True while an `NSTextView` (TextField/TextEditor editor) has keyboard focus,
    /// so Cmd+C/Cmd+V over the canvas don't hijack ordinary text copy/paste in the Inspector.
    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    private func handleShortcutEvent(_ event: NSEvent) -> Bool {
        guard NSApp.isActive, NSApp.keyWindow != nil else { return false }

        if mode == .edit, event.type == .keyDown, !event.isARepeat, !isEditingText,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                guard !selectedButtonIDs.isEmpty else { return false }
                copyButtons()
                return true
            case "v":
                guard hasButtonClipboard else { return false }
                pasteButtons()
                return true
            default:
                break
            }
        }

        guard mode == .live, let shortcut = KeyboardShortcutConfig(event: event) else { return false }

        if shortcut == session.stopButtonShortcut {
            if event.type == .keyDown && !event.isARepeat { stopAllFading() }
            return true
        }
        if shortcut == session.emergencyStopShortcut {
            if event.type == .keyDown && !event.isARepeat { emergencyStopAll() }
            return true
        }
        guard let button = session.buttons.first(where: { $0.keyboardShortcut == shortcut }) else { return false }
        switch button.playMode {
        case .toggle:
            if event.type == .keyDown && !event.isARepeat { togglePlay(button.id) }
        case .holdToPlay:
            if event.type == .keyDown && !event.isARepeat { beginHold(button.id) }
            if event.type == .keyUp { endHold(button.id) }
        }
        return true
    }

    private func tick() {
        refreshHealth()
        blinkPhase.toggle()

        var blinking = fadingButtonIDs
        for id in playingButtonIDs {
            guard let player = players[id], let config = session.buttons.first(where: { $0.id == id }) else { continue }
            let duration = player.duration
            guard duration > 0 else { continue }
            let position = player.elapsedTime.truncatingRemainder(dividingBy: duration)

            let inFadeIn = config.fadeInEnabled && position < config.fadeInDuration
            let nearEndThreshold = config.fadeOutEnabled ? config.fadeOutDuration : 2.0
            let nearEnd = (duration - position) <= nearEndThreshold

            if inFadeIn || nearEnd {
                blinking.insert(id)
            }
        }
        blinkingButtonIDs = blinking
    }

    // MARK: - Health

    func refreshHealth() {
        health = SessionHealthChecker.check(session)
    }

    // MARK: - Persistence

    func newSession() {
        emergencyStopAll()
        players.removeAll()
        session = Session(name: "Neue Sitzung")
        sessionURL = nil
        selectedButtonID = nil
        refreshHealth()
    }

    func save() {
        if let url = sessionURL {
            try? SessionStore.save(session, to: url)
        } else {
            saveAs()
        }
    }

    func pickSoundFile(for id: SoundButtonConfig.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        update(id) { $0.soundFilePath = url.path }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: SessionStore.fileExtension) ?? .json]
        panel.nameFieldStringValue = session.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sessionURL = url
        try? SessionStore.save(session, to: url)
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: SessionStore.fileExtension) ?? .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let loaded = try? SessionStore.load(from: url) else { return }

        emergencyStopAll()
        players.removeAll()
        session = loaded
        sessionURL = url
        selectedButtonID = nil
        refreshHealth()
    }
}

extension KeyboardShortcutConfig {
    init?(event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers,
              let character = characters.first,
              !character.isWhitespace else { return nil }
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        var value = 0
        if flags.contains(.control) { value |= 1 }
        if flags.contains(.option) { value |= 2 }
        if flags.contains(.shift) { value |= 4 }
        if flags.contains(.command) { value |= 8 }
        key = String(character).lowercased()
        modifiers = value
    }
}
#endif
