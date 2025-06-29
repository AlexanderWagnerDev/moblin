import Foundation
import SwiftUI

private struct QuickButtonMicMicView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var mic: SettingsMicsMic

    var body: some View {
        HStack {
            DraggableItemPrefixView()
            if !mic.isAlwaysConnected() && !mic.isExternal() {
                Image(systemName: mic.connected ? "cable.connector" : "cable.connector.slash")
            }
            Text(mic.name)
                .lineLimit(1)
            Spacer()
            Image(systemName: "checkmark")
                .foregroundColor(mic == model.currentMic ? .blue : .clear)
                .bold()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // logger.info("xxx selecting \(mic.name)")
            model.selectMicById(id: mic.id)
        }
    }
}

struct QuickButtonMicView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var mics: SettingsMics

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(mics.mics) { mic in
                        QuickButtonMicMicView(mic: mic)
                            .deleteDisabled(mic == model.currentMic)
                    }
                    .onDelete { offsets in
                        mics.mics.remove(atOffsets: offsets)
                    }
                    .onMove { froms, to in
                        mics.mics.move(fromOffsets: froms, toOffset: to)
                    }
                }
            } footer: {
                VStack(alignment: .leading) {
                    Text("Highest priority mic at the top of the list.")
                    Text("")
                    SwipeLeftToDeleteHelpView(kind: String(localized: "a mic"))
                }
            }
            if false {
                Section {
                    Toggle("Auto switch", isOn: $mics.autoSwitch)
                } footer: {
                    Text("Automatically switch to highest priority mic when plugged in.")
                }
            }
        }
        .navigationTitle("Mic")
    }
}
