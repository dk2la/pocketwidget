/// Which modules the strip shows and in what order. Settings is a module
/// like the others — it has an icon and can be reordered — but it can never
/// be switched off, or there would be no way back to the switches.
enum StripLineup {
    /// The module that is always enabled.
    static let alwaysEnabled: ModuleTab = .settings

    /// Stored order with modules it does not know appended: new modules in
    /// declaration order, then Settings last. Both an upgrade (an order
    /// saved before Settings was a module) and a fresh install (nothing
    /// stored) end with Settings, and nothing the user arranged moves.
    static func loadedOrder(stored: [ModuleTab]) -> [ModuleTab] {
        var order: [ModuleTab] = []
        for tab in stored where !order.contains(tab) {
            order.append(tab)
        }
        for tab in ModuleTab.allCases where tab != alwaysEnabled && !order.contains(tab) {
            order.append(tab)
        }
        if !order.contains(alwaysEnabled) {
            order.append(alwaysEnabled)
        }
        return order
    }

    /// The stored enabled set, with Settings always in it.
    static func loadedEnabled(_ stored: Set<ModuleTab>) -> Set<ModuleTab> {
        stored.union([alwaysEnabled])
    }

    /// Settings never switches; the last enabled module other than Settings
    /// stays on — Settings alone is not module content.
    static func canToggle(_ tab: ModuleTab, enabled: Set<ModuleTab>) -> Bool {
        guard tab != alwaysEnabled else { return false }
        guard enabled.contains(tab) else { return true }
        return enabled.subtracting([alwaysEnabled]).count > 1
    }

    /// `enabled` with `tab` flipped, or unchanged when it may not flip.
    static func toggled(_ tab: ModuleTab, in enabled: Set<ModuleTab>) -> Set<ModuleTab> {
        guard canToggle(tab, enabled: enabled) else { return enabled }
        var result = enabled
        if result.contains(tab) {
            result.remove(tab)
        } else {
            result.insert(tab)
        }
        return result
    }

    /// The strip's icons: enabled modules in the user's order.
    static func visible(order: [ModuleTab], enabled: Set<ModuleTab>) -> [ModuleTab] {
        order.filter { enabled.contains($0) }
    }
}
