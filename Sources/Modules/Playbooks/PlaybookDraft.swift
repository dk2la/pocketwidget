import Foundation

/// A playbook while it is in the editor. The editor changes only this copy;
/// the store hears about it on Save. A draft that is dropped — Cancel, Back,
/// the panel closed by hand — leaves no trace: no half-made playbook, no
/// change to the one it was made from.
struct PlaybookDraft: Equatable {
    /// What the editor's fields are bound to.
    var playbook: Playbook
    /// True for "Add playbook", false when an existing one is edited.
    let isNew: Bool
    /// The playbook as it was when the editor opened.
    private let original: Playbook

    /// `existing == nil` starts a new, empty playbook.
    init(editing existing: Playbook?) {
        let start = existing ?? Playbook(name: "")
        playbook = start
        original = start
        isNew = existing == nil
    }

    /// A playbook needs a name; steps may come later.
    var canSave: Bool {
        !playbook.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The user has typed or changed something since the editor opened.
    var isChanged: Bool {
        playbook != original
    }

    mutating func moveStep(_ id: UUID, by offset: Int) {
        guard let index = playbook.steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard playbook.steps.indices.contains(target) else { return }
        playbook.steps.swapAt(index, target)
    }

    mutating func removeStep(_ id: UUID) {
        playbook.steps.removeAll { $0.id == id }
    }

    /// The draft as it is saved: trimmed, so the runner never sees blank
    /// lines or padded names.
    var cleaned: Playbook {
        var cleaned = playbook
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespaces)
        cleaned.steps = cleaned.steps.map { step in
            switch step {
            case .runShortcut(let id, let name):
                .runShortcut(id: id, name: name.trimmingCharacters(in: .whitespaces))
            case .setFocus(let id, let name):
                .setFocus(id: id, shortcutName: name.trimmingCharacters(in: .whitespaces))
            case .openURLs(let id, let urls):
                .openURLs(
                    id: id,
                    urls: urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                )
            default:
                step
            }
        }
        return cleaned
    }

    /// Writes the draft to the store: a new playbook is added, an edited
    /// one replaces the playbook it was made from. Returns false, leaving
    /// the store alone, when the draft cannot be saved yet.
    @MainActor
    @discardableResult
    mutating func save(to store: PlaybookStore) -> Bool {
        guard canSave else { return false }
        playbook = cleaned
        if isNew {
            store.add(playbook)
        } else {
            store.update(playbook)
        }
        return true
    }

    /// Removes the playbook this draft was made from. A new draft has
    /// nothing in the store yet.
    @MainActor
    func delete(from store: PlaybookStore) {
        guard !isNew else { return }
        store.remove(original)
    }
}
