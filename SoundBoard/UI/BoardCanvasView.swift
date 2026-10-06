import SwiftUI

/// Freeform, snap-to-grid canvas holding the sound buttons plus the status panel
/// and the two stop controls — all three are draggable board elements now, not
/// fixed UI chrome. The whole board scales uniformly to fill the available window
/// space (clamped to the aspect ratio of `referenceSize` so buttons stay round).
struct BoardCanvasView: View {
    @ObservedObject var viewModel: BoardViewModel
    @State private var selectionStart: CGPoint?
    @State private var selectionCurrent: CGPoint?
    @State private var selectionModifiers: EventModifiers = []

    static let referenceSize = CGSize(width: 980, height: 600)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.referenceSize.width, geo.size.height / Self.referenceSize.height)
            content
                .frame(width: Self.referenceSize.width, height: Self.referenceSize.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            DMColor.panel
                .contentShape(Rectangle())
                .gesture(viewModel.mode == .edit ? selectionGesture : nil)
                .onTapGesture {
                    if viewModel.mode == .edit {
                        viewModel.deselectAll()
                    }
                }
                .contextMenu {
                    if viewModel.mode == .edit {
                        Button("Einfügen") { viewModel.pasteButtons() }
                            .disabled(!viewModel.hasButtonClipboard)
                    }
                }

            if viewModel.mode == .edit {
                gridOverlay
                    .allowsHitTesting(false)
            }

            titleView
                .padding(.leading, 20)
                .padding(.top, 14)

            if let selectionRect {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .allowsHitTesting(false)
            }

            ForEach(viewModel.session.buttons) { config in
                BoardButtonHost(
                    viewModel: viewModel,
                    config: config,
                    extendsSelection: selectionModifiers.contains(.control) || selectionModifiers.contains(.command)
                )
            }

            DraggableElement(
                viewModel: viewModel,
                position: viewModel.session.statusPanelPosition,
                keyPath: \.statusPanelPosition,
                isSelected: viewModel.inspectorSelection == .statusPanel
            ) {
                StatusRail(
                    outputActive: viewModel.isOutputActive,
                    ready: viewModel.isReady,
                    deviceMissing: viewModel.health.hasMissingDevice,
                    fileMissing: viewModel.health.hasMissingFile,
                    outputDevices: viewModel.outputDeviceStatus,
                    buttonGroups: viewModel.statusButtonGroups,
                    fontSize: viewModel.session.statusPanelFontSize,
                    columns: viewModel.session.statusRailColumns
                )
            }
            .onTapGesture {
                if viewModel.mode == .edit {
                    viewModel.selectStatusPanel()
                }
            }

            DraggableElement(
                viewModel: viewModel,
                position: viewModel.session.stopButtonPosition,
                keyPath: \.stopButtonPosition,
                isSelected: viewModel.inspectorSelection == .stopButton
            ) {
                stopFadeControl
            }
            .onTapGesture {
                if viewModel.mode == .edit { viewModel.selectStopButton() }
                else { viewModel.stopAllFading() }
            }

            DraggableElement(
                viewModel: viewModel,
                position: viewModel.session.emergencyStopPosition,
                keyPath: \.emergencyStopPosition,
                isSelected: viewModel.inspectorSelection == .emergencyStop
            ) {
                EmergencyStopButtonView(fontSize: viewModel.session.emergencyStopFontSize)
            }
            .onTapGesture {
                if viewModel.mode == .edit { viewModel.selectEmergencyStop() }
                else { viewModel.emergencyStopAll() }
            }

            if let volumeMasterPosition = viewModel.session.volumeMasterPosition {
                VolumeMasterBoardElement(
                    viewModel: viewModel,
                    position: volumeMasterPosition,
                    deviceSelectionKey: viewModel.session.buttons
                        .map { $0.outputDeviceUID ?? "__default__" }
                        .sorted()
                        .joined(separator: "|")
                )
            }
        }
        .coordinateSpace(.named("boardCanvas"))
        .onModifierKeysChanged(mask: [.control, .command]) { _, newModifiers in
            selectionModifiers = newModifiers
        }
    }

    private var selectionRect: CGRect? {
        guard let selectionStart, let selectionCurrent else { return nil }
        return CGRect(
            x: min(selectionStart.x, selectionCurrent.x),
            y: min(selectionStart.y, selectionCurrent.y),
            width: abs(selectionCurrent.x - selectionStart.x),
            height: abs(selectionCurrent.y - selectionStart.y)
        )
    }

    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("boardCanvas"))
            .onChanged { value in
                selectionStart = value.startLocation
                selectionCurrent = value.location
            }
            .onEnded { value in
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                viewModel.selectButtons(
                    in: rect,
                    extendingSelection: selectionModifiers.contains(.control) || selectionModifiers.contains(.command)
                )
                selectionStart = nil
                selectionCurrent = nil
            }
    }

    @ViewBuilder
    private var titleView: some View {
        if viewModel.mode == .edit {
            TextField("Board-Titel", text: Binding(
                get: { viewModel.session.name },
                set: { viewModel.session.name = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(DMColor.label)
            .frame(width: 260, alignment: .leading)
        } else {
            Text(viewModel.session.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(DMColor.label)
                .frame(width: 260, alignment: .leading)
        }
    }

    private var stopFadeControl: some View {
        VStack(spacing: 4) {
            Text("Stop (Fade)")
                .font(.system(size: viewModel.session.stopButtonFontSize))
                .foregroundStyle(DMColor.label)
            Circle()
                .fill(LinearGradient(colors: [ButtonFace.yellow.shades.light, ButtonFace.yellow.shades.base],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
        }
    }

    private var gridOverlay: some View {
        Canvas { context, size in
            let step = max(viewModel.session.gridSize, 8)
            var x: CGFloat = 0
            while x < size.width {
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                                with: .color(.white.opacity(0.04)))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                                with: .color(.white.opacity(0.04)))
                y += step
            }
        }
    }
}

/// Generic wrapper for a board element (status panel, stop buttons) that can be
/// dragged around in edit mode, snapping to the board's grid like buttons do.
private struct DraggableElement<Content: View>: View {
    @ObservedObject var viewModel: BoardViewModel
    let position: CGPoint
    let keyPath: WritableKeyPath<Session, CGPoint>
    var isSelected = false
    @ViewBuilder var content: () -> Content

    @State private var dragPosition: CGPoint?

    var body: some View {
        content()
            .overlay {
                if isSelected && viewModel.mode == .edit {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-4)
                }
            }
            .position(dragPosition ?? position)
            .gesture(viewModel.mode == .edit ? drag : nil)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("boardCanvas"))
            .onChanged { value in
                dragPosition = CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                )
            }
            .onEnded { value in
                viewModel.moveElement(keyPath, to: CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                ))
                dragPosition = nil
            }
    }
}

private struct VolumeMasterBoardElement: View {
    @ObservedObject var viewModel: BoardViewModel
    let position: CGPoint
    let deviceSelectionKey: String

    @State private var dragPosition: CGPoint?
    @State private var devices: [AudioOutputDevice] = []
    @State private var volumes: [String: Float] = [:]
    @State private var devicesWithoutVolumeControl: Set<String> = []
    @State private var volumeObservers: [AudioDeviceVolumeObserver] = []

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VolumeMasterView(
                devices: devices,
                volumes: $volumes,
                devicesWithoutVolumeControl: devicesWithoutVolumeControl,
                fontSize: viewModel.session.volumeMasterFontSize
            )

            if viewModel.mode == .edit {
                Button {
                    viewModel.removeVolumeMaster()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Volumemaster entfernen")
                .padding(8)
            }
        }
        .overlay {
            if viewModel.inspectorSelection == .volumeMaster && viewModel.mode == .edit {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(-4)
            }
        }
        .position(dragPosition ?? position)
        .gesture(viewModel.mode == .edit ? dragGesture : nil)
        .task(id: deviceSelectionKey) {
            reloadDevices()
        }
        .onTapGesture {
            if viewModel.mode == .edit {
                viewModel.selectVolumeMaster()
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("boardCanvas"))
            .onChanged { value in
                dragPosition = CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                )
            }
            .onEnded { value in
                viewModel.moveVolumeMaster(to: CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                ))
                dragPosition = nil
            }
    }

    private func reloadDevices() {
        let allDevices = AudioDeviceManager.outputDevices()
        let defaultDevice = AudioDeviceManager.defaultOutputDevice()
        let requestedUIDs = Set(viewModel.session.buttons.compactMap(\.outputDeviceUID))
        var resolvedDevices = allDevices.filter { requestedUIDs.contains($0.uid) }

        if viewModel.session.buttons.contains(where: { $0.outputDeviceUID == nil }),
           let defaultDevice,
           !resolvedDevices.contains(where: { $0.uid == defaultDevice.uid }) {
            resolvedDevices.append(defaultDevice)
        }

        devices = resolvedDevices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var newVolumes: [String: Float] = [:]
        var unsupportedDevices: Set<String> = []
        for device in devices {
            if let volume = AudioDeviceManager.volume(for: device) {
                newVolumes[device.uid] = volume
            } else {
                newVolumes[device.uid] = 0
                unsupportedDevices.insert(device.uid)
            }
        }
        volumes = newVolumes
        devicesWithoutVolumeControl = unsupportedDevices

        volumeObservers = devices.map { device in
            AudioDeviceVolumeObserver(device: device) {
                Task { @MainActor in
                    volumes[device.uid] = AudioDeviceManager.volume(for: device) ?? 0
                }
            }
        }
    }
}

private struct VolumeMasterView: View {
    let devices: [AudioOutputDevice]
    @Binding var volumes: [String: Float]
    let devicesWithoutVolumeControl: Set<String>
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Volumemaster", systemImage: "speaker.wave.3.fill")
                .font(.system(size: fontSize + 2, weight: .semibold))
                .foregroundStyle(DMColor.label)

            if devices.isEmpty {
                Text("Noch kein Ausgabegerät verwendet")
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices) { device in
                    DeviceVolumeRow(
                        device: device,
                        volume: volumeBinding(for: device),
                        supportsVolume: !devicesWithoutVolumeControl.contains(device.uid),
                        fontSize: fontSize
                    )
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .topLeading)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func volumeBinding(for device: AudioOutputDevice) -> Binding<Float> {
        Binding(
            get: { volumes[device.uid] ?? 0 },
            set: { newValue in
                volumes[device.uid] = newValue
                AudioDeviceManager.setVolume(newValue, for: device)
            }
        )
    }
}

private struct DeviceVolumeRow: View {
    let device: AudioOutputDevice
    @Binding var volume: Float
    let supportsVolume: Bool
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(device.name)
                    .lineLimit(1)
                Spacer()
                if supportsVolume {
                    Text(volume, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("nicht regelbar")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: fontSize))

            Slider(value: $volume, in: 0...1)
                .disabled(!supportsVolume)
        }
        .foregroundStyle(DMColor.label)
    }
}

private struct BoardButtonHost: View {
    @ObservedObject var viewModel: BoardViewModel
    let config: SoundButtonConfig
    let extendsSelection: Bool

    @State private var dragPosition: CGPoint?
    @State private var isHoldPressed = false

    private var isOn: Bool { viewModel.isEffectivelyLit(config.id) }
    private var isSelected: Bool { viewModel.selectedButtonIDs.contains(config.id) }
    private var isMissing: Bool {
        viewModel.health.missingFileButtonIDs.contains(config.id) ||
        viewModel.health.missingDeviceButtonIDs.contains(config.id)
    }
    /// True while this button is part of a multi-selection being dragged as a
    /// group — in that case every selected button tracks the same shared offset
    /// instead of only the one the drag gesture is actually attached to.
    private var isGroupDragging: Bool { isSelected && viewModel.selectedButtonIDs.count > 1 }

    private var renderedPosition: CGPoint {
        if isGroupDragging {
            let offset = viewModel.groupDragOffset
            return CGPoint(x: config.position.x + offset.width, y: config.position.y + offset.height)
        }
        return dragPosition ?? config.position
    }

    var body: some View {
        PanelButtonView(
            title: config.displayTitle,
            face: config.face,
            illuminated: config.illuminated,
            isOn: isOn,
            diameter: config.diameter,
            labelFontSize: config.labelFontSize
        )
        .overlay(alignment: .center) {
            if isSelected && viewModel.mode == .edit {
                Circle().stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: config.diameter + 16, height: config.diameter + 16)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isMissing {
                Circle().fill(DMColor.statusRed).frame(width: 8, height: 8)
                    .offset(x: 2, y: -2)
            }
        }
        .position(renderedPosition)
        .gesture(viewModel.mode == .edit ? dragGesture : nil)
        .onTapGesture {
            if viewModel.mode == .edit {
                viewModel.selectButton(config.id, extendingSelection: extendsSelection)
            } else if config.playMode == .toggle {
                viewModel.togglePlay(config.id)
            }
        }
        .simultaneousGesture(holdGesture, including: viewModel.mode == .live && config.playMode == .holdToPlay ? .all : .subviews)
        .contextMenu {
            if viewModel.mode == .edit {
                Button("Kopieren") {
                    viewModel.copyButtons(isSelected ? viewModel.selectedButtonIDs : [config.id])
                }
                Button("Duplizieren") { viewModel.duplicateButton(config.id) }
                Divider()
                Button("Einfügen") { viewModel.pasteButtons() }
                    .disabled(!viewModel.hasButtonClipboard)
                Divider()
                Button("Löschen", role: .destructive) { viewModel.deleteButton(config.id) }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("boardCanvas"))
            .onChanged { value in
                if isGroupDragging {
                    viewModel.groupDragOffset = value.translation
                } else {
                    dragPosition = CGPoint(
                        x: config.position.x + value.translation.width,
                        y: config.position.y + value.translation.height
                    )
                }
            }
            .onEnded { value in
                if isGroupDragging {
                    viewModel.moveSelectedButtons(by: value.translation)
                    viewModel.groupDragOffset = .zero
                } else {
                    if !viewModel.selectedButtonIDs.contains(config.id) {
                        viewModel.selectButton(config.id)
                    }
                    viewModel.moveButton(config.id, to: CGPoint(
                        x: config.position.x + value.translation.width,
                        y: config.position.y + value.translation.height
                    ))
                    dragPosition = nil
                }
            }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isHoldPressed else { return }
                isHoldPressed = true
                viewModel.beginHold(config.id)
            }
            .onEnded { _ in
                isHoldPressed = false
                viewModel.endHold(config.id)
            }
    }
}
