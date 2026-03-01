import SwiftUI

struct FriendCodeEntryRow: View {
    @Binding var inviteCodeInput: String
    let palette: PBTheme.Palette
    let type: PBTypography
    let onAdd: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Enter friend code (ABCD-1234)", text: $inviteCodeInput)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .font(type.body)
                .padding(10)
                .pbSurfaceCard(palette: palette)

            Button("Add") {
                let code = inviteCodeInput
                inviteCodeInput = ""
                onAdd(code)
            }
            .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
            .accessibilityLabel(Text("Add friend"))
            .accessibilityHint(Text("Sends a friend request using the entered code"))
        }
    }
}
