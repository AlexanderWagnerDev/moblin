import SwiftUI

struct MediaPlayerFileSettingsView: View {
    @EnvironmentObject var model: Model
    let player: SettingsMediaPlayer
    let file: SettingsMediaPlayerFile

    private func submitName(value: String) {
        file.name = value.trim()
        model.objectWillChange.send()
        model.updateMediaPlayerSettings(playerId: player.id, settings: player)
    }

    var body: some View {
        Form {
            Section {
                TextEditNavigationView(
                    title: String(localized: "Name"),
                    value: file.name,
                    onSubmit: submitName,
                    capitalize: true
                )
            }
        }
        .navigationTitle("File")
    }
}
