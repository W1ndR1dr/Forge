import SwiftUI

/// Compact sort order picker for list headers
struct SortPicker: View {
    @Binding var selection: SortOrder

    var body: some View {
        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    selection = order
                } label: {
                    Label(order.displayName, systemImage: order.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selection.icon)
                    .font(.system(size: 10))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

#Preview {
    @Previewable @State var order: SortOrder = .recentlyUsed
    SortPicker(selection: $order)
        .padding()
}
