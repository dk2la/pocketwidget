import Foundation

/// Where the Playbooks module is. The list is the root; every other case is
/// one level deep and goes back to it. A new destination is a new case here
/// and one more branch where the module view switches over the route.
enum PlaybooksRoute: Equatable, Sendable {
    /// Every playbook as one grouped list.
    case list
    /// One playbook opened: its icon, its steps in order, Run and Back.
    case playbook(UUID)

    /// The playbook this route shows, if it shows one.
    var openedID: UUID? {
        switch self {
        case .list: nil
        case .playbook(let id): id
        }
    }

    /// The route to show given the playbooks that exist right now: one that
    /// points at a playbook removed meanwhile (in Settings) falls back to
    /// the list.
    func resolved(existing ids: some Sequence<UUID>) -> PlaybooksRoute {
        guard let openedID else { return self }
        return ids.contains(openedID) ? self : .list
    }
}
