import Foundation
import PDFKit
import SwiftUI

@MainActor
@Observable
final class AppState {
    var documents: [DocumentState] = []
    var recentFiles: [RecentFile] = []
    var preferences = Preferences()
    var pendingPasswordURL: URL?
    /// Currently active document. `nil` falls back to the most recently opened one.
    var selectedID: DocumentState.ID? = nil
    /// Transient toast message (e.g. "已保存为默认设置"); cleared automatically.
    var toastMessage: String? = nil
    private var toastTask: Task<Void, Never>? = nil

    // MARK: Inspector / Slideshow (overlay surfaces)
    /// Document whose metadata the Inspector sheet shows (⌘I). `nil` closes it.
    var inspectorDocID: DocumentState.ID? = nil
    var inspectorDoc: DocumentState? {
        guard let id = inspectorDocID else { return nil }
        return selectedDocument(id: id)
    }
    /// Document the Slideshow window was launched on (captured at launch time).
    var slideshowDocID: DocumentState.ID? = nil
    /// Whether the signature-capture sheet is presented (set by the 签名 tool).
    var showSignatureCapture: Bool = false

    // MARK: Sidebar (shared between the content view and the View menu)
    /// Whether the left sidebar (缩略图/目录/书签/标注) is visible.
    var showSidebar: Bool = true
    /// Which sidebar tab is active.
    var sidebarTab: SidebarTab = .thumbnails
    /// Sidebar width (points) — adjustable by dragging the divider.
    var sidebarWidth: CGFloat = 260
    /// Set by the Edit menu's "查找…" (⌘F) to focus the toolbar search field.
    var focusSearchRequested: Bool = false

    private let recentsKey = "meipdf.recentFiles"
    private let sidebarWidthKey = "meipdf.sidebarWidth"

    // MARK: Toast

    func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { toastMessage = nil }
        }
    }

    init() {
        loadRecents()
        let stored = UserDefaults.standard.double(forKey: sidebarWidthKey)
        if stored >= 180, stored <= 520 { sidebarWidth = CGFloat(stored) }
    }

    // MARK: Opening

    @discardableResult
    func open(_ url: URL) -> DocumentState? {
        let secured = url.startAccessingSecurityScopedResource()
        // If already open, just return existing instance.
        if let existing = documents.first(where: { $0.fileURL?.path == url.path }) {
            if secured { url.stopAccessingSecurityScopedResource() }
            return existing
        }
        do {
            let doc = try DocumentState(url: url, preferences: preferences)
            if doc.isLocked {
                pendingPasswordURL = url
                if secured { url.stopAccessingSecurityScopedResource() }
                return nil
            }
            documents.append(doc)
            selectedID = doc.id
            addRecent(url)
            if secured { url.stopAccessingSecurityScopedResource() }
            return doc
        } catch {
            if secured { url.stopAccessingSecurityScopedResource() }
            return nil
        }
    }

    /// Opens a freshly unlocked document (called after password sheet).
    func openUnlocked(_ url: URL, password: String) -> DocumentState? {
        if let existing = documents.first(where: { $0.fileURL?.path == url.path }) {
            if existing.unlock(with: password) { existing.finishUnlock() }
            return existing
        }
        do {
            let doc = try DocumentState(url: url, preferences: preferences)
            if doc.unlock(with: password) { doc.finishUnlock() }
            documents.append(doc)
            selectedID = doc.id
            addRecent(url)
            return doc
        } catch {
            return nil
        }
    }

    func close(_ doc: DocumentState) {
        let wasSelected = (selectedID == doc.id)
        doc.persist()
        documents.removeAll { $0.id == doc.id }
        if wasSelected {
            selectedID = documents.last?.id
        }
    }

    func closeOthers(keep id: DocumentState.ID) {
        for d in documents where d.id != id {
            d.persist()
            documents.removeAll { $0.id == d.id }
        }
        selectedID = id
    }

    func closeAll() {
        for d in documents { d.persist() }
        documents.removeAll()
        selectedID = nil
    }

    /// Reorder tabs: move the document identified by `sourceID` so it sits just
    /// before `beforeID`. Drag-and-drop sorting in the top tab bar calls this.
    func moveDocument(_ sourceID: DocumentState.ID, before beforeID: DocumentState.ID) {
        guard sourceID != beforeID,
              let from = documents.firstIndex(where: { $0.id == sourceID }),
              let to = documents.firstIndex(where: { $0.id == beforeID }) else { return }
        let doc = documents.remove(at: from)
        var target = documents.firstIndex(where: { $0.id == beforeID }) ?? documents.endIndex
        if from < to { target += 1 }
        documents.insert(doc, at: min(target, documents.count))
    }

    func selectedDocument(id: DocumentState.ID?) -> DocumentState? {
        if let id, let d = documents.first(where: { $0.id == id }) { return d }
        return documents.last
    }

    // MARK: Recents

    func addRecent(_ url: URL) {
        let path = url.path
        recentFiles.removeAll { $0.path == path }
        recentFiles.insert(RecentFile(id: UUID(), path: path, name: url.lastPathComponent, lastOpened: Date()), at: 0)
        if recentFiles.count > 20 { recentFiles.removeSubrange(20...) }
        saveRecents()
    }

    func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let list = try? JSONDecoder().decode([RecentFile].self, from: data) else { return }
        recentFiles = list
    }

    func saveRecents() {
        if let data = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    func saveSidebarWidth() {
        UserDefaults.standard.set(Double(sidebarWidth), forKey: sidebarWidthKey)
    }
}

@MainActor
let appState = AppState()
