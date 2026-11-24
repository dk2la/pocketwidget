import Foundation

/// Where the Playbooks module is. The list is the root; an opened playbook
/// is one level deep, and the editor sits over whatever it was opened from.
/// A new destination is a new case here and one more branch where the
/// module view switches over the route.
enum PlaybooksRoute: Equatable, Sendable {
    /// Every playbook as one grouped list.
    case list
    /// One playbook opened: its icon, its steps in order, Run and Back.
    case playbook(UUID)
    /// The editor: a new playbook (nil, opened from the list) or an
    /// existing one (opened from that playbook).
    case editor(UUID?)

    /// The playbook this route shows opened, if it shows one.
    var openedID: UUID? {
        switch self {
        case .list, .editor: nil
        case .playbook(let id): id
        }
    }

    var isEditor: Bool {
        if case .editor = self { true } else { false }
    }

    /// Where Back leads — and Save and Cancel, for the editor: the list
    /// after adding, the opened playbook after editing.
    var back: PlaybooksRoute {
        switch self {
        case .list, .playbook, .editor(nil): .list
        case .editor(let id?): .playbook(id)
        }
    }

    /// The playbook this route cannot be shown without.
    private var requiredID: UUID? {
        switch self {
        case .list, .editor(nil): nil
        case .playbook(let id), .editor(let id?): id
        }
    }

    /// The route to show given the playbooks that exist right now: one that
    /// points at a playbook removed meanwhile (in Settings, or by Delete in
    /// the editor) falls back to the list.
    func resolved(existing ids: some Sequence<UUID>) -> PlaybooksRoute {
        guard let requiredID else { return self }
        return ids.contains(requiredID) ? self : .list
    }
}
