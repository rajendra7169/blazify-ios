import SwiftUI

/// The palette button's sheet — Blaze's player-design chooser. Classic is live;
/// the other layouts (Ring / Full art / Record / Cassette) are on the roadmap.
struct PlayerDesignSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let designs: [(name: String, icon: String)] = [
        ("Classic", "rectangle.portrait"),
        ("Ring", "circle"),
        ("Full art", "photo"),
        ("Record", "opticaldisc"),
        ("Cassette", "recordingtape"),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(designs.enumerated()), id: \.offset) { index, design in
                    HStack(spacing: 14) {
                        Image(systemName: design.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(index == 0 ? Blaze.amber : .white.opacity(0.5))
                            .frame(width: 28)
                        Text(design.name).foregroundStyle(.white)
                        Spacer()
                        if index == 0 {
                            Image(systemName: "checkmark").foregroundStyle(Blaze.amber)
                        } else {
                            Text("Soon").font(.caption).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    .opacity(index == 0 ? 1 : 0.6)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Blaze.scaffold.ignoresSafeArea())
            .navigationTitle("Player design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Blaze.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
