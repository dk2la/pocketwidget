// The one place for the site's outbound links and prices. Every Buy button
// links to `checkoutURL`, every Download button to `downloadURL`.

/**
 * Polar checkout page, with the launch discount already applied.
 *
 * KEEP IN SYNC with the release `LicensingConfig.checkoutURL` in
 * `Sources/Licensing/LicensingConfig.swift`: the website and the app's Buy
 * button must open the same page. Change both files together.
 */
export const checkoutURL = 'https://buy.polar.sh/polar_cl_XRl0NamNTAEMF94jkKTJ4GOc2HNh4grHHmgVw19tmhM';

/**
 * Stable URL of the latest DMG in the public Cloudflare R2 bucket.
 * See "Downloads" in `docs/release-and-licensing.md`.
 */
export const downloadURL = 'https://pub-3c8757d8d4b64f55bbc715c162c7e969.r2.dev/Pocket.dmg';

/**
 * One-time prices as shown on the page, before tax. The store charges the
 * real amount and adds the buyer's local tax on top.
 */
export const price = {
  /** Launch price, the one currently charged. */
  launch: '$19',
  /** Regular price after the launch period. */
  regular: '$24',
} as const;
