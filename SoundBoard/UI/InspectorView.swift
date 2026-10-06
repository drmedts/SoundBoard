import SwiftUI
import AppKit

/// Editable properties for the selected button — only shown in edit mode.
struct InspectorView: View {
    @ObservedObject var viewModel: BoardViewModel
    let buttonID: SoundButtonConfig.ID

    var body: some View {
        if let config = viewModel.session.buttons.first(where: { $0.id == buttonID }) {
            InspectorContentView(viewModel: viewModel, buttonID: buttonID, config: config)
        } else {
            VStack {
                Spacer()
                Text("Kein Button ausgewählt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(width: 240)
            .background(Color(white: 0.16))
        }
    }
}

private struct InspectorContentView: View {
    @ObservedObject var viewModel: BoardViewModel
    let buttonID: SoundButtonConfig.ID
    let config: SoundButtonConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("BUTTON: \(config.title.uppercased())")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DMColor.label)

                labeled("Titel") {
                    TextField("Titel", text: binding(\.title))
                        .textFieldStyle(.roundedBorder)
                    Text("\\n erzwingt einen Zeilenumbruch auf dem Taster (Statusanzeigen bleiben einzeilig)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                labeled("Farbe") {
                    HStack(spacing: 6) {
                        ForEach(ButtonFace.allCases, id: \.self) { face in
                            Circle()
                                .fill(face.color)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.white, lineWidth: config.face == face ? 2 : 0))
                                .onTapGesture { viewModel.update(buttonID) { $0.face = face } }
                        }
                    }
                }

                Toggle("Beleuchtet", isOn: binding(\.illuminated))

                labeled("Größe") {
                    HStack {
                        Slider(value: binding(\.diameter), in: 40...140, step: 2)
                        Text("\(Int(config.diameter))pt").font(.caption).foregroundStyle(.secondary)
                    }
                }

                ShortcutEditorView(
                    viewModel: viewModel,
                    owner: .button(buttonID),
                    currentShortcut: config.keyboardShortcut
                )
                .id(ShortcutOwner.button(buttonID))

                ButtonStatusConfigurationView(
                    viewModel: viewModel,
                    buttonID: buttonID,
                    config: config
                )

                labeled("Sounddatei") {
                    HStack {
                        Text(config.soundFilePath.isEmpty ? "Keine Datei" : (config.soundFilePath as NSString).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Wählen…") { viewModel.pickSoundFile(for: buttonID) }
                    }
                }

                Toggle("Fade In", isOn: binding(\.fadeInEnabled))
                if config.fadeInEnabled {
                    durationSlider("Fade-In-Dauer", binding(\.fadeInDuration))
                }

                Toggle("Fade Out", isOn: binding(\.fadeOutEnabled))
                if config.fadeOutEnabled {
                    durationSlider("Fade-Out-Dauer", binding(\.fadeOutDuration))
                }

                Toggle("Wiederholung", isOn: binding(\.loopEnabled))

                labeled("Abspielmodus") {
                    Picker("", selection: binding(\.playMode)) {
                        Text("Normal (an/aus)").tag(SoundButtonConfig.PlayMode.toggle)
                        Text("Nur bei Halten").tag(SoundButtonConfig.PlayMode.holdToPlay)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                labeled("Lautstärke") {
                    Slider(value: binding(\.volume), in: 0...1)
                }

                labeled("Ausgabegerät") {
                    Picker("", selection: binding(\.outputDeviceUID)) {
                        Text("Systemstandard").tag(String?.none)
                        ForEach(AudioDeviceManager.outputDevices()) { device in
                            Text(device.name).tag(Optional(device.uid))
                        }
                    }
                    .labelsHidden()
                }

                labeled("Ausgabekanal (Offset)") {
                    Stepper(value: binding(\.outputChannelOffset), in: 0...max(0, maxChannelOffset)) {
                        Text("Kanal \(config.outputChannelOffset + 1)/\(config.outputChannelOffset + 2)")
                            .font(.caption)
                    }
                }

                Spacer(minLength: 8)

                Button("Button löschen", role: .destructive) {
                    viewModel.deleteButton(buttonID)
                }

                if let name = viewModel.sessionURLDisplayName {
                    Text("Sitzung: \(name)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 248, alignment: .leading)
            .padding(16)
            .font(.system(size: 14))
        }
        .frame(width: 280)
        .background(Color(white: 0.16))
    }

    @MainActor private var maxChannelOffset: Int {
        let device = config.outputDeviceUID.flatMap(AudioDeviceManager.device(withUID:)) ?? AudioDeviceManager.defaultOutputDevice()
        return (device?.outputChannelCount ?? 2) - 2
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SoundButtonConfig, Value>) -> Binding<Value> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { newValue in viewModel.update(buttonID) { $0[keyPath: keyPath] = newValue } }
        )
    }

    @ViewBuilder
    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 14)).foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func durationSlider(_ label: String, _ value: Binding<TimeInterval>) -> some View {
        labeled(label) {
            HStack {
                Slider(value: value, in: 0.1...5)
                Text(String(format: "%.1fs", value.wrappedValue)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ButtonStatusConfigurationView: View {
    @ObservedObject var viewModel: BoardViewModel
    let buttonID: SoundButtonConfig.ID
    let config: SoundButtonConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status-LEDs")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DMColor.label)

            Picker("Gruppe", selection: groupBinding) {
                ForEach(viewModel.session.statusGroups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Beschriftungsgröße")
                    .foregroundStyle(.secondary)
                HStack {
                    Slider(value: labelFontSizeBinding, in: 10...22, step: 1)
                    Text("\(Int(config.labelFontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var groupBinding: Binding<StatusLEDGroup.ID?> {
        Binding(
            get: { config.statusGroupID },
            set: { groupID in
                guard let groupID else { return }
                viewModel.assignButton(buttonID, toStatusGroup: groupID)
            }
        )
    }

    private var labelFontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(config.labelFontSize) },
            set: { value in viewModel.update(buttonID) { $0.labelFontSize = CGFloat(value) } }
        )
    }
}

struct StatusPanelInspectorView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("STATUS-BEREICH")
                    .font(.system(size: 16, weight: .bold))

                Text("Schriftgröße")
                    .foregroundStyle(.secondary)
                HStack {
                    Slider(value: fontSizeBinding, in: 9...16, step: 1)
                    Text("\(Int(viewModel.session.statusPanelFontSize)) pt")
                        .monospacedDigit()
                }

                Text("Spalten")
                    .foregroundStyle(.secondary)
                Picker("Spalten", selection: columnsBinding) {
                    Text("1 Spalte").tag(1)
                    Text("2 Spalten").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    Text("Gruppen")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button { viewModel.addStatusGroup() } label: { Image(systemName: "plus") }
                }

                ForEach(viewModel.session.statusGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        StatusGroupEditorRow(viewModel: viewModel, group: group)
                        ForEach(buttons(in: group)) { button in
                            HStack {
                                Text(button.plainTitle).lineLimit(1)
                                Spacer()
                                Button { viewModel.moveButtonInStatusGroup(button.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                    .disabled(!canMove(button, by: -1))
                                Button { viewModel.moveButtonInStatusGroup(button.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                    .disabled(!canMove(button, by: 1))
                            }
                            .buttonStyle(.borderless)
                            .padding(.leading, 8)
                        }
                    }
                }
            }
            .padding(16)
            .font(.system(size: 14))
        }
        .frame(width: 280)
        .background(Color(white: 0.16))
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.session.statusPanelFontSize) },
            set: { viewModel.session.statusPanelFontSize = CGFloat($0) }
        )
    }

    private var columnsBinding: Binding<Int> {
        Binding(
            get: { viewModel.session.statusRailColumns },
            set: { viewModel.session.statusRailColumns = $0 }
        )
    }

    private func buttons(in group: StatusLEDGroup) -> [SoundButtonConfig] {
        viewModel.session.buttons
            .filter { $0.statusGroupID == group.id }
            .sorted { $0.statusOrder < $1.statusOrder }
    }

    private func canMove(_ button: SoundButtonConfig, by offset: Int) -> Bool {
        let values = buttons(in: viewModel.session.statusGroups.first { $0.id == button.statusGroupID } ?? StatusLEDGroup(name: ""))
        guard let index = values.firstIndex(where: { $0.id == button.id }) else { return false }
        return values.indices.contains(index + offset)
    }
}

struct VolumeMasterInspectorView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("VOLUMEMASTER")
                .font(.system(size: 16, weight: .bold))
            Text("Schriftgröße")
                .foregroundStyle(.secondary)
            HStack {
                Slider(value: fontSizeBinding, in: 9...18, step: 1)
                Text("\(Int(viewModel.session.volumeMasterFontSize)) pt")
                    .monospacedDigit()
            }
            Spacer()
        }
        .frame(width: 248, alignment: .leading)
        .padding(16)
        .font(.system(size: 14))
        .frame(width: 280)
        .background(Color(white: 0.16))
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.session.volumeMasterFontSize) },
            set: { viewModel.session.volumeMasterFontSize = CGFloat($0) }
        )
    }
}

struct StopButtonInspectorView: View {
    @ObservedObject var viewModel: BoardViewModel
    let emergency: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(emergency ? "NOT-STOP" : "STOP (FADE)")
                .font(.system(size: 16, weight: .bold))
            Text("Schriftgröße")
                .foregroundStyle(.secondary)
            HStack {
                Slider(value: fontSizeBinding, in: 10...22, step: 1)
                Text("\(Int(fontSizeBinding.wrappedValue)) pt")
                    .monospacedDigit()
            }
            ShortcutEditorView(
                viewModel: viewModel,
                owner: emergency ? .emergencyStop : .stopButton,
                currentShortcut: emergency ? viewModel.session.emergencyStopShortcut : viewModel.session.stopButtonShortcut
            )
            .id(emergency ? ShortcutOwner.emergencyStop : ShortcutOwner.stopButton)
            Spacer()
        }
        .frame(width: 248, alignment: .leading)
        .padding(16)
        .font(.system(size: 14))
        .frame(width: 280)
        .background(Color(white: 0.16))
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(emergency ? viewModel.session.emergencyStopFontSize : viewModel.session.stopButtonFontSize) },
            set: {
                if emergency { viewModel.session.emergencyStopFontSize = CGFloat($0) }
                else { viewModel.session.stopButtonFontSize = CGFloat($0) }
            }
        )
    }
}

private struct ShortcutEditorView: View {
    @ObservedObject var viewModel: BoardViewModel
    let owner: ShortcutOwner
    let currentShortcut: KeyboardShortcutConfig?
    @State private var pendingShortcut: KeyboardShortcutConfig?

    init(viewModel: BoardViewModel, owner: ShortcutOwner, currentShortcut: KeyboardShortcutConfig?) {
        self.viewModel = viewModel
        self.owner = owner
        self.currentShortcut = currentShortcut
        _pendingShortcut = State(initialValue: currentShortcut)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Tastaturkürzel")
                .foregroundStyle(.secondary)
            HStack {
                ShortcutRecorderField(shortcut: $pendingShortcut)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 24, maxHeight: 24)
                Button {
                    viewModel.setShortcut(pendingShortcut, for: owner)
                } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(pendingShortcut == currentShortcut || conflict != nil)
                .help("Tastaturkürzel übernehmen")
                Button {
                    pendingShortcut = nil
                    viewModel.setShortcut(nil, for: owner)
                } label: {
                    Image(systemName: "xmark")
                }
                .disabled(currentShortcut == nil && pendingShortcut == nil)
                .help("Tastaturkürzel entfernen")
            }
            if let conflict {
                Text("Bereits belegt durch „\(conflict)“. Speichern nicht möglich.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Feld anklicken und gewünschtes Kürzel drücken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var conflict: String? {
        pendingShortcut.flatMap { viewModel.shortcutConflict($0, excluding: owner) }
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcutConfig?

    func makeCoordinator() -> Coordinator { Coordinator(shortcut: $shortcut) }

    func makeNSView(context: Context) -> ShortcutTextField {
        let field = ShortcutTextField()
        field.placeholderString = "Hier Tastaturkürzel eingeben"
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.alignment = .center
        field.onShortcut = { context.coordinator.shortcut.wrappedValue = $0 }
        return field
    }

    func updateNSView(_ field: ShortcutTextField, context: Context) {
        field.stringValue = shortcut?.displayName ?? ""
        field.onShortcut = { context.coordinator.shortcut.wrappedValue = $0 }
    }

    final class Coordinator {
        var shortcut: Binding<KeyboardShortcutConfig?>
        init(shortcut: Binding<KeyboardShortcutConfig?>) { self.shortcut = shortcut }
    }
}

private final class ShortcutTextField: NSTextField {
    var onShortcut: ((KeyboardShortcutConfig?) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
        } else if event.keyCode == 51 || event.keyCode == 117 {
            onShortcut?(nil)
        } else if let shortcut = KeyboardShortcutConfig(event: event) {
            onShortcut?(shortcut)
        } else {
            NSSound.beep()
        }
    }
}

struct MultipleButtonsInspectorView: View {
    @ObservedObject var viewModel: BoardViewModel
    let buttonIDs: Set<SoundButtonConfig.ID>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(buttonIDs.count) BUTTONS")
                .font(.system(size: 16, weight: .bold))

            Picker("Gruppe", selection: groupBinding) {
                if isMixed(\.statusGroupID) {
                    Text("Mehrere ausgewählt").tag(StatusLEDGroup.ID?.none)
                }
                ForEach(viewModel.session.statusGroups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }

            Text("Ausgabegerät")
                .foregroundStyle(.secondary)
            Picker("", selection: deviceSelectionBinding) {
                if isMixed(\.outputDeviceUID) {
                    Text("Mehrere ausgewählt").tag(DeviceSelection.mixed)
                }
                Text("Systemstandard").tag(DeviceSelection.systemDefault)
                ForEach(AudioDeviceManager.outputDevices()) { device in
                    Text(device.name).tag(DeviceSelection.device(device.uid))
                }
            }
            .labelsHidden()

            Text("Beschriftungsgröße")
                .foregroundStyle(.secondary)
            HStack {
                Slider(value: fontSizeBinding, in: 10...22, step: 1)
                Text("\(Int(referenceButton?.labelFontSize ?? 15)) pt")
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(16)
        .font(.system(size: 14))
        .frame(width: 280)
        .background(Color(white: 0.16))
    }

    private var referenceButton: SoundButtonConfig? {
        viewModel.session.buttons.first { buttonIDs.contains($0.id) }
    }

    /// True when the selected buttons don't all share the same value for `keyPath`.
    private func isMixed<Value: Equatable>(_ keyPath: KeyPath<SoundButtonConfig, Value>) -> Bool {
        let values = viewModel.session.buttons.filter { buttonIDs.contains($0.id) }.map { $0[keyPath: keyPath] }
        guard let first = values.first else { return false }
        return values.contains { $0 != first }
    }

    private enum DeviceSelection: Hashable {
        case mixed
        case systemDefault
        case device(String)
    }

    private var deviceSelectionBinding: Binding<DeviceSelection> {
        Binding(
            get: {
                if isMixed(\.outputDeviceUID) { return .mixed }
                if let uid = referenceButton?.outputDeviceUID { return .device(uid) }
                return .systemDefault
            },
            set: { newValue in
                let uid: String?
                switch newValue {
                case .mixed: return
                case .systemDefault: uid = nil
                case .device(let deviceUID): uid = deviceUID
                }
                for id in buttonIDs { viewModel.update(id) { $0.outputDeviceUID = uid } }
            }
        )
    }

    private var groupBinding: Binding<StatusLEDGroup.ID?> {
        Binding(
            get: { isMixed(\.statusGroupID) ? nil : referenceButton?.statusGroupID },
            set: { groupID in
                guard let groupID else { return }
                for id in buttonIDs { viewModel.assignButton(id, toStatusGroup: groupID) }
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(referenceButton?.labelFontSize ?? 15) },
            set: { value in
                for id in buttonIDs { viewModel.update(id) { $0.labelFontSize = CGFloat(value) } }
            }
        )
    }
}

private struct StatusGroupEditorRow: View {
    @ObservedObject var viewModel: BoardViewModel
    let group: StatusLEDGroup

    var body: some View {
        HStack(spacing: 5) {
            TextField("Gruppenname", text: nameBinding)
                .textFieldStyle(.roundedBorder)

            Button {
                viewModel.moveStatusGroup(group.id, by: -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(groupIndex == 0)

            Button {
                viewModel.moveStatusGroup(group.id, by: 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .disabled(groupIndex == viewModel.session.statusGroups.count - 1)

            Button(role: .destructive) {
                viewModel.deleteStatusGroup(group.id)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(viewModel.session.statusGroups.count <= 1)
        }
        .buttonStyle(.borderless)
    }

    private var groupIndex: Int {
        viewModel.session.statusGroups.firstIndex(where: { $0.id == group.id }) ?? 0
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: {
                viewModel.session.statusGroups.first(where: { $0.id == group.id })?.name ?? group.name
            },
            set: { viewModel.renameStatusGroup(group.id, to: $0) }
        )
    }
}
