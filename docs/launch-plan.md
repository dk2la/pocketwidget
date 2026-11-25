# Launch plan

Decisions from the 2026-11-19 planning session, and what is left before
Pocket goes on sale. Terms are defined in [`GLOSSARY.md`](../GLOSSARY.md); the
longer background is in [`release-and-licensing.md`](release-and-licensing.md).
Tick an item when it is done and merged.

## Decisions

- **Launch:** 2026-11-25, as version 1.0.0. Pocket is not sold without Apple
  signing and notarization. If the Apple Developer account is not ready by
  then, the date is decided again on 2026-11-25.
- **Price:** $19 from 2026-11-25 through 2026-12-09, then $24. Tax is added on
  top at checkout. The end date of the launch price is shown on the site.
- **Buy button on the site:** until launch, clicking it shows "Sales open on
  November 25" instead of opening checkout. The Buy button inside the released
  0.1.3 build is left as it is.
- **Gravatar:** a switch in the mail settings, off by default.
- **Updates:** Sparkle. The feed is `https://pocketwidget.tech/appcast.xml`;
  DMGs are served from `downloads.pocketwidget.tech`. Pocket checks once a day
  and asks before installing; the menu has "Check for Updates".
- **Thank-you page:** `/thanks`, with the same background and widget as the
  home page, "Thanks for buying Pocket" in the centre and three steps for
  entering the License key. Polar sends buyers there after payment.
- **Links:** Support (`mailto:support@pocketwidget.tech`) and "Manage license"
  (the Polar customer portal) in the site footer; "Manage license" also in the
  app's license screen.
- **Policies:** Terms, Privacy and Refund are rewritten in full from examples
  the owner provides. This blocks the launch. The refund rule stays: 14 days,
  only if the License key was never activated.
- **Repository:** stays public under the source-available `LICENSE`, which
  replaced MIT.
- **Production purchase test:** done on the signed build: buy, activate,
  deactivate, refund.
- **Postponed:** the seller's legal status in France (micro-entreprise).

## Before Apple signing

- [x] Gravatar switch, off by default
- [x] Site: "Sales open on November 25" on Buy
- [x] Site: `/thanks` page
- [x] Polar's success URL pointing to `/thanks`
- [x] Site: Support and "Manage license" links in the footer
- [x] App: "Manage license" link in the license screen
- [x] Downloads served from `downloads.pocketwidget.tech`
- [x] Trial server: at most 5 new Trials a minute from one address. Measured
      live on 2026-11-19, the limiter is loose (it turned away 3 of 30
      requests sent at once), so it slows a flood rather than stopping it. A
      Cloudflare rate limiting rule on the zone would be the strict version.
- [ ] Later, not a launch blocker: mail DNS. Remove Cloudflare from SPF,
      add DMARC. Mail works without it
- [x] Polar: product icon and the text of the License key email
- [x] Close issues #54 and #58
- [x] Merge PR #85 (owner)

## Owner's steps

- [x] Enrol in the Apple Developer Program as an individual
- [x] Send the policy examples
- [x] Replace the MIT license with the source-available `LICENSE`

## After the Apple Developer account

- [x] Hardened runtime, Developer ID signing, notarization in the release
      workflow. The workflow published 0.2.0 this way on 2026-11-19; the
      downloaded DMG and app pass Gatekeeper as "Notarized Developer ID"
- [x] Sparkle with its signing key and the feed. Not yet seen working end to
      end: that needs two published versions
- [x] App icon and a DMG that opens as an install window (PR #88). Its first
      release is 0.2.1
- [x] Rewritten Terms, Privacy and Refund pages (PRs #89, #90, #91; the
      Refund page on 2026-11-23)
- [x] The signed build run by hand: players, dictation, calendar, "Check for
      Updates", and an update from 0.2.0 to a newer version
- [x] ~~Version 1.0.0~~ Dropped: Pocket launches as 0.3.1
- [x] Production purchase test on the signed build (a $1 purchase with a
      promo code)
- [x] Manual Trial check on a clean install, then close issues #42 and #39
- [x] Launch day (2026-11-25): Buy opens checkout again, the launch price gets its end date
