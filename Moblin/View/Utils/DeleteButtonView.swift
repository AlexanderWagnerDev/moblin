import SwiftUI

struct DeleteButtonView: View {
    @Environment(\.dismiss) var dismiss
    let action: () -> Void

    var body: some View {
        Section {
            HCenter {
                Button {
                    action()
                    dismiss()
                } label: {
                    Text("Delete")
                        .foregroundColor(.red)
                }
            }
        }
    }
}
