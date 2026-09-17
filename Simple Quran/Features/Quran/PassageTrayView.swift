import SwiftUI

struct PassageTrayView: View {
    var summary: String
    var onListen: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appBrownText)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Button(action: onListen) {
                    Label(String(localized: "Listen to these"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.olive)
                .accessibilityIdentifier("quran.tray.listen")

                Button(action: onSave) {
                    Label(String(localized: "Save"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.gold)
                .accessibilityIdentifier("quran.tray.save")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}
