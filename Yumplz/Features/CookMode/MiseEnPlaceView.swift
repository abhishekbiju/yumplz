import SwiftUI

struct MiseEnPlaceView: View {
    let viewModel: MiseEnPlaceViewModel

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.uncheckedItems.isEmpty {
                    Section {
                        ForEach(viewModel.uncheckedItems) { item in
                            ItemRow(item: item) {
                                viewModel.toggle(item: item)
                            }
                        }
                    }
                }

                if !viewModel.checkedItems.isEmpty {
                    Section("Done") {
                        ForEach(viewModel.checkedItems) { item in
                            ItemRow(item: item) {
                                viewModel.toggle(item: item)
                            }
                            .opacity(0.45)
                        }
                    }
                }
            }
            .navigationTitle("Mise en Place")
            .navigationBarTitleDisplayMode(.large)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ItemRow: View {
    let item: MiseEnPlaceItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? Color.mkGreen : .secondary)
                    .font(.title3)

                Text(item.displayText)
                    .font(.mkBody)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                    .strikethrough(item.isChecked)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
