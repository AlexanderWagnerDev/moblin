import SwiftUI

struct DuplicateButtonView: View {
    @Environment(\.dismiss) var dismiss
    let action: () -> Void

    var body: some View {
        Section {
            HCenter {
                Button {
                    action()
                    dismiss()
                } label: {
                    Text("Duplicate")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}
