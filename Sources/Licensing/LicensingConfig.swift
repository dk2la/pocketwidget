import Foundation

/// Where licensing talks to, and whether it is enforced. None of these are
/// secrets. Release builds use the real Polar store; debug builds use
/// Polar's sandbox, where purchases are made with test cards.
enum LicensingConfig {
    /// Base URL of the Trial server (the Cloudflare Worker in `worker/`).
    /// Released versions keep calling this address, so it must never change.
    static var trialServerURL: URL? {
        #if DEBUG
        // `--trial-server <url>`: point a debug build at a local Worker.
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--trial-server"), index + 1 < args.count {
            return URL(string: args[index + 1])
        }
        #endif
        return URL(string: "https://trial.pocketwidget.tech")
    }

    #if DEBUG
    /// Polar's API host.
    static let storeAPIURL = URL(string: "https://sandbox-api.polar.sh")
    /// The Polar organization that sells Pocket.
    static let organizationID = "fc15fe0a-3a90-4e83-b75f-3604800fbf3c"
    /// The license-key benefit of the Pocket product; keys granted by any
    /// other benefit are rejected.
    static let productID = "aa9a54ee-cabe-4ab1-8a28-78439293703d"
    /// Checkout page the Buy button opens.
    static let checkoutURL = URL(
        string: "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_rbf6vKmFqPI9exJBdh8Bp7KYFQ2bZ6S3cLsYA38RkJs/redirect"
    )
    #else
    /// Polar's API host.
    static let storeAPIURL = URL(string: "https://api.polar.sh")
    /// The Polar organization that sells Pocket.
    static let organizationID = "f5c899bd-4224-4879-b310-d8dcfb667356"
    /// The license-key benefit of the Pocket product; keys granted by any
    /// other benefit are rejected.
    static let productID = "82267c83-259b-4417-8ba2-3b3210fea3f5"
    /// Checkout page the Buy button opens. KEEP IN SYNC with `checkoutURL`
    /// in `site/src/config.ts`.
    static let checkoutURL = URL(string: "https://buy.polar.sh/polar_cl_XRl0NamNTAEMF94jkKTJ4GOc2HNh4grHHmgVw19tmhM")
    #endif

    /// The store's customer portal: a buyer signs in with the email they
    /// paid with and sees their License key and Activations. KEEP IN SYNC
    /// with `licensePortalURL` in `site/src/config.ts`.
    #if DEBUG
    static let portalURL = URL(string: "https://sandbox.polar.sh/pocketwidget/portal")
    #else
    static let portalURL = URL(string: "https://polar.sh/pocketwidget/portal")
    #endif

    /// Release builds always enforce licensing. Debug builds skip it, so
    /// daily work and demo recordings are not blocked; `--licensing` turns
    /// it on for testing the real flow.
    static var isEnforced: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--licensing")
        #else
        true
        #endif
    }
}
