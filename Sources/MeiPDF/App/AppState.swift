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

    private let recentsKey = "meipdf.recentFiles"

    init() {
        loadRecents()
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
            addRecent(url)
            return doc
        } catch {
            return nil
        }
    }

    func close(_ doc: DocumentState) {
        doc.persist()
        documents.removeAll { $0.id == doc.id }
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
}

@MainActor
let appState = AppState()
