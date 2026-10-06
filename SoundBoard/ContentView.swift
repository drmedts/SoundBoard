import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = BoardViewModel()

    var body: some View {
        HStack(spacing: 0) {
            BoardCanvasView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.mode == .edit {
                switch viewModel.inspectorSelection {
                case .buttons:
                    if let selected = viewModel.selectedButtonID {
                        InspectorView(viewModel: viewModel, buttonID: selected)
                            .padding(.top, 10)
                    } else if !viewModel.selectedButtonIDs.isEmpty {
                        MultipleButtonsInspectorView(
                            viewModel: viewModel,
                            buttonIDs: viewModel.selectedButtonIDs
                        )
                        .padding(.top, 10)
                    }
                case .statusPanel:
                    StatusPanelInspectorView(viewModel: viewModel)
                        .padding(.top, 10)
                case .volumeMaster:
                    VolumeMasterInspectorView(viewModel: viewModel)
                        .padding(.top, 10)
                case .stopButton:
                    StopButtonInspectorView(viewModel: viewModel, emergency: false)
                        .padding(.top, 10)
                case .emergencyStop:
                    StopButtonInspectorView(viewModel: viewModel, emergency: true)
                        .padding(.top, 10)
                case nil:
                    EmptyView()
                }
            }
        }
        .background(Color(red: 0.08, green: 0.07, blue: 0.06))
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup {
                Picker("Modus", selection: $viewModel.mode) {
                    Text("Einrichten").tag(BoardMode.edit)
                    Text("Nutzung").tag(BoardMode.live)
                }
                .pickerStyle(.segmented)

                if viewModel.mode == .edit {
                    Menu {
                        Button("Sound-Button") {
                            viewModel.addButton(at: CGPoint(x: 120, y: 120))
                        }
                        Button("Volumemaster") {
                            viewModel.addVolumeMaster(at: CGPoint(x: 490, y: 300))
                        }
                        .disabled(viewModel.session.volumeMasterPosition != nil)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .help("Bedienelement hinzufügen")
                }

                Button("Neu") { viewModel.newSession() }
                Button("Öffnen…") { viewModel.open() }
                Button("Sichern") { viewModel.save() }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
