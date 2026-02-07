import SwiftUI

struct AddSyncView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSheet: GoogleSpreadsheetListResponse.SpreadsheetFile?
    @State private var selectedTabs: Set<String> = []
    @State private var localPath: URL?
    @State private var bookmarkData: Data?
    @State private var customFileName: String = ""
    @State private var fileFormat: FileFormat = .xlsx
    @State private var syncFrequency: TimeInterval = 30

    @State private var sheets: [GoogleSpreadsheetListResponse.SpreadsheetFile] = []
    @State private var sheetTabs: [GoogleSheet.SheetTab] = []
    @State private var isLoadingSheets = false
    @State private var isLoadingTabs = false
    @State private var errorMessage: String?

    @State private var currentStep: SetupStep = .selectSheet

    enum SetupStep: Int, CaseIterable {
        case selectSheet = 0
        case selectTabs = 1
        case configure = 2
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    switch currentStep {
                    case .selectSheet:
                        sheetSelectionView
                    case .selectTabs:
                        tabSelectionView
                    case .configure:
                        configurationView
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer
            footerView
        }
    }

    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add Sync")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    closeWindow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Progress indicator
            HStack(spacing: 8) {
                ForEach(SetupStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
        }
        .padding(20)
    }

    private var sheetSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select a Google Sheet")
                .font(.headline)

            if isLoadingSheets {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading sheets...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if sheets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No sheets found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Refresh") {
                        loadSheets()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sheets, id: \.id) { sheet in
                        SpreadsheetRow(
                            sheet: sheet,
                            isSelected: selectedSheet?.id == sheet.id
                        ) {
                            selectedSheet = sheet
                        }
                    }
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            if sheets.isEmpty {
                loadSheets()
            }
        }
    }

    private var tabSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select tabs to sync")
                .font(.headline)

            Text("Choose which tabs from \"\(selectedSheet?.name ?? "")\" to sync")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isLoadingTabs {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading tabs...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 8) {
                    // Select all option
                    Button {
                        if selectedTabs.count == sheetTabs.count {
                            selectedTabs.removeAll()
                        } else {
                            selectedTabs = Set(sheetTabs.map(\.title))
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedTabs.count == sheetTabs.count ? "checkmark.square.fill" : "square")
                            Text("Select All")
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    ForEach(sheetTabs, id: \.id) { tab in
                        Button {
                            if selectedTabs.contains(tab.title) {
                                selectedTabs.remove(tab.title)
                            } else {
                                selectedTabs.insert(tab.title)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedTabs.contains(tab.title) ? "checkmark.square.fill" : "square")
                                Text(tab.title)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(tab.rowCount) rows")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            if sheetTabs.isEmpty, let sheet = selectedSheet {
                loadTabs(for: sheet.id)
            }
        }
    }

    private var configurationView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configure sync")
                .font(.headline)

            // File format (select first so save dialog has correct extension)
            VStack(alignment: .leading, spacing: 8) {
                Text("File format")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("Format", selection: $fileFormat) {
                    Text("Excel (.xlsx)").tag(FileFormat.xlsx)
                    Text("CSV (.csv)").tag(FileFormat.csv)
                    Text("JSON (.json)").tag(FileFormat.json)
                }
                .pickerStyle(.segmented)
            }

            // Save location (uses NSSavePanel)
            VStack(alignment: .leading, spacing: 8) {
                Text("Save as")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    if let path = localPath {
                        Text("\(path.path)/\(customFileName.isEmpty ? (selectedSheet?.name ?? "file") : customFileName).\(fileFormat.fileExtension)")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Choose save location...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Choose...") {
                        selectSaveLocation()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Sync frequency
            VStack(alignment: .leading, spacing: 8) {
                Text("Sync frequency")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("Frequency", selection: $syncFrequency) {
                    Text("15s").tag(TimeInterval(15))
                    Text("30s").tag(TimeInterval(30))
                    Text("1m").tag(TimeInterval(60))
                    Text("5m").tag(TimeInterval(300))
                    Text("15m").tag(TimeInterval(900))
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var footerView: some View {
        HStack {
            if currentStep != .selectSheet {
                Button("Back") {
                    withAnimation {
                        currentStep = SetupStep(rawValue: currentStep.rawValue - 1) ?? .selectSheet
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(currentStep == .configure ? "Create Sync" : "Next") {
                if currentStep == .configure {
                    createSync()
                } else {
                    withAnimation {
                        currentStep = SetupStep(rawValue: currentStep.rawValue + 1) ?? .configure
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canProceed)
        }
        .padding(20)
    }

    private var canProceed: Bool {
        switch currentStep {
        case .selectSheet:
            return selectedSheet != nil
        case .selectTabs:
            return !selectedTabs.isEmpty
        case .configure:
            return localPath != nil
        }
    }

    private func loadSheets() {
        isLoadingSheets = true
        errorMessage = nil

        Task {
            do {
                let response = try await GoogleSheetsAPIClient.shared.listSpreadsheets()
                await MainActor.run {
                    sheets = response.files
                    isLoadingSheets = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingSheets = false
                }
            }
        }
    }

    private func loadTabs(for sheetId: String) {
        isLoadingTabs = true

        Task {
            do {
                let response = try await GoogleSheetsAPIClient.shared.getSpreadsheet(id: sheetId)
                await MainActor.run {
                    sheetTabs = response.sheets.map { sheet in
                        GoogleSheet.SheetTab(
                            id: sheet.properties.sheetId,
                            title: sheet.properties.title,
                            index: sheet.properties.index,
                            rowCount: sheet.properties.gridProperties?.rowCount ?? 0,
                            columnCount: sheet.properties.gridProperties?.columnCount ?? 0
                        )
                    }
                    // Select all by default
                    selectedTabs = Set(sheetTabs.map(\.title))
                    isLoadingTabs = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingTabs = false
                }
            }
        }
    }

    private func selectSaveLocation() {
        guard let sheet = selectedSheet else { return }

        // Ensure app is active for menu bar apps
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = "Save Synced File"
        panel.message = "Choose where to save '\(sheet.name)'"
        panel.nameFieldStringValue = "\(customFileName.isEmpty ? sheet.name : customFileName).\(fileFormat.fileExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        // Set allowed file types based on format
        if let contentType = fileFormat.contentType {
            panel.allowedContentTypes = [contentType]
        }

        if panel.runModal() == .OK, let url = panel.url {
            localPath = url.deletingLastPathComponent()
            customFileName = url.deletingPathExtension().lastPathComponent
            // Create security-scoped bookmark for persistent access to the directory
            bookmarkData = SyncConfiguration.createBookmark(for: localPath!)
        }
    }

    private func createSync() {
        guard let sheet = selectedSheet, let path = localPath else { return }

        let fileName = customFileName.isEmpty ? sheet.name : customFileName

        let config = SyncConfiguration(
            id: UUID(),
            googleSheetId: sheet.id,
            googleSheetName: sheet.name,
            selectedSheetTabs: Array(selectedTabs),
            syncNewTabs: true,
            localFilePath: path,
            bookmarkData: bookmarkData,
            customFileName: fileName,
            syncFrequency: syncFrequency,
            fileFormat: fileFormat,
            isEnabled: true,
            needsInitialFileConfirmation: false,  // Already confirmed via NSSavePanel
            backupSettings: BackupSettings()
        )

        appState.addSyncConfiguration(config)
        closeWindow()
    }

    private func closeWindow() {
        WindowManager.shared.closeWindow(id: "add-sync")
    }
}

struct SpreadsheetRow: View {
    let sheet: GoogleSpreadsheetListResponse.SpreadsheetFile
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "tablecells")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sheet.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    if let modified = sheet.modifiedTime {
                        Text("Modified: \(modified)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddSyncView()
        .environmentObject(AppState.shared)
        .frame(width: 520, height: 580)
}
