import SwiftUI

struct SheetPickerView: View {
    let sheets: [GoogleSheet]
    @Binding var selection: GoogleSheet?

    @State private var searchText = ""

    var filteredSheets: [GoogleSheet] {
        if searchText.isEmpty {
            return sheets
        }
        return sheets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search sheets...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
            )

            // Sheet list
            if filteredSheets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "doc.text.magnifyingglass" : "magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)

                    Text(searchText.isEmpty ? "No sheets found" : "No matches for \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredSheets) { sheet in
                            SheetRow(sheet: sheet, isSelected: selection?.id == sheet.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selection = sheet
                                    }
                                }
                        }
                    }
                }
            }
        }
    }
}

struct SheetRow: View {
    let sheet: GoogleSheet
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.green.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: "tablecells")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.green)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(sheet.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let modified = sheet.modifiedTime {
                    Text("Modified \(modified.relativeDescription)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}

#Preview {
    SheetPickerView(
        sheets: [
            GoogleSheet(
                id: "1",
                name: "Budget 2024",
                modifiedTime: Date(),
                webViewLink: nil,
                sheets: []
            ),
            GoogleSheet(
                id: "2",
                name: "Project Tasks",
                modifiedTime: Date().addingTimeInterval(-86400),
                webViewLink: nil,
                sheets: []
            )
        ],
        selection: .constant(nil)
    )
    .frame(width: 400, height: 300)
    .padding()
}
