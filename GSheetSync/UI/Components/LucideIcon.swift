import SwiftUI

// MARK: - App Icon View (SF Symbols)

struct AppIconView: View {
    let symbol: String
    var size: CGFloat = 16
    var color: Color? = nil

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color ?? .primary)
    }
}

// Backwards compatibility alias
typealias LucideIcon = AppIconView

extension AppIconView {
    init(_ symbol: String, size: CGFloat = 16, color: Color? = nil) {
        self.symbol = symbol
        self.size = size
        self.color = color
    }
}

// MARK: - Common Icon Definitions (SF Symbols)

enum AppIcon {
    // Navigation & Actions
    static let plus = "plus"
    static let minus = "minus"
    static let x = "xmark"
    static let check = "checkmark"
    static let chevronRight = "chevron.right"
    static let chevronLeft = "chevron.left"
    static let chevronDown = "chevron.down"
    static let chevronUp = "chevron.up"
    static let arrowRight = "arrow.right"
    static let arrowLeft = "arrow.left"
    static let externalLink = "arrow.up.right.square"
    static let moreHorizontal = "ellipsis"
    static let moreVertical = "ellipsis.vertical"
    static let menu = "line.3.horizontal"

    // Files & Folders
    static let file = "doc"
    static let fileText = "doc.text"
    static let fileSpreadsheet = "tablecells"
    static let folder = "folder"
    static let folderOpen = "folder.fill"
    static let folderPlus = "folder.badge.plus"
    static let download = "arrow.down.circle"
    static let upload = "arrow.up.circle"

    // Sync & Status
    static let refreshCw = "arrow.triangle.2.circlepath"
    static let rotateCw = "arrow.clockwise"
    static let loader = "arrow.2.circlepath"
    static let checkCircle = "checkmark.circle.fill"
    static let xCircle = "xmark.circle.fill"
    static let alertCircle = "exclamationmark.circle.fill"
    static let alertTriangle = "exclamationmark.triangle.fill"
    static let info = "info.circle"
    static let clock = "clock"
    static let history = "clock.arrow.circlepath"
    static let timer = "timer"
    static let pause = "pause.fill"
    static let play = "play.fill"

    // Data & Tables
    static let table = "tablecells"
    static let grid3x3 = "square.grid.3x3"
    static let columns3 = "rectangle.split.3x1"
    static let rows3 = "rectangle.split.1x2"
    static let database = "cylinder"
    static let sheet = "doc.richtext"

    // Settings & Config
    static let settings = "gearshape"
    static let slidersHorizontal = "slider.horizontal.3"
    static let toggleLeft = "togglepower"
    static let toggleRight = "togglepower"

    // User & Auth
    static let user = "person"
    static let userCheck = "person.badge.checkmark"
    static let userX = "person.badge.minus"
    static let logIn = "rectangle.portrait.and.arrow.right"
    static let logOut = "rectangle.portrait.and.arrow.forward"
    static let key = "key"
    static let lock = "lock"
    static let lockOpen = "lock.open"

    // Cloud & Network
    static let cloud = "cloud"
    static let cloudOff = "cloud.slash"
    static let cloudUpload = "icloud.and.arrow.up"
    static let cloudDownload = "icloud.and.arrow.down"
    static let wifi = "wifi"
    static let wifiOff = "wifi.slash"
    static let globe = "globe"

    // Backup & Storage
    static let hardDrive = "internaldrive"
    static let save = "square.and.arrow.down"
    static let archive = "archivebox"
    static let copy = "doc.on.doc"
    static let clipboard = "clipboard"
    static let trash = "trash"
    static let trash2 = "trash.fill"

    // UI Elements
    static let eye = "eye"
    static let eyeOff = "eye.slash"
    static let search = "magnifyingglass"
    static let listFilter = "line.3.horizontal.decrease"
    static let sortAsc = "arrow.up"
    static let sortDesc = "arrow.down"
    static let maximize = "arrow.up.left.and.arrow.down.right"
    static let minimize = "arrow.down.right.and.arrow.up.left"

    // Misc
    static let zap = "bolt.fill"
    static let sparkles = "sparkles"
    static let star = "star"
    static let heart = "heart"
    static let bell = "bell"
    static let bellOff = "bell.slash"
    static let power = "power"
    static let terminal = "terminal"
    static let code = "chevron.left.forwardslash.chevron.right"
    static let link = "link"
    static let unlink = "link.badge.plus"
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            AppIconView(AppIcon.table, size: 24, color: .green)
            AppIconView(AppIcon.refreshCw, size: 24, color: .blue)
            AppIconView(AppIcon.checkCircle, size: 24, color: .green)
            AppIconView(AppIcon.alertCircle, size: 24, color: .orange)
            AppIconView(AppIcon.xCircle, size: 24, color: .red)
        }

        HStack(spacing: 16) {
            AppIconView(AppIcon.folder, size: 24)
            AppIconView(AppIcon.fileSpreadsheet, size: 24)
            AppIconView(AppIcon.cloud, size: 24)
            AppIconView(AppIcon.settings, size: 24)
            AppIconView(AppIcon.user, size: 24)
        }
    }
    .padding()
}
