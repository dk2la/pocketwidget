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
- **Repository:** made private and the MIT license removed before the public
  announcement. The owner does both.
- **Production purchase test:** done on the signed build: buy, activate,
  deactivate, refund.
- **Postponed:** the seller's legal status in France (micro-entreprise).

## Before Apple signing

- [x] Gravatar switch, off by default
- [x] Site: "Sales open on November 25" on Buy
- [x] Site: `/thanks` page
- [ ] Polar's success URL pointing to `/thanks` (after the page is live)
- [x] Site: Support and "Manage license" links in the footer
- [x] App: "Manage license" link in the license screen
- [ ] Downloads served from `downloads.pocketwidget.tech`
- [ ] Trial server: protection against junk requests
- [ ] Mail DNS: remove Cloudflare from SPF, add DMARC
- [ ] Polar: product icon and the text of the License key email
- [ ] Close issues #54 and #58
- [ ] Merge PR #85 (owner)

## Owner's steps

- [ ] Enrol in the Apple Developer Program as an individual
- [ ] Send the policy examples
- [ ] Make the repository private and remove the MIT license

## After the Apple Developer account

- [ ] Hardened runtime, Developer ID signing, notarization in the release
      workflow
- [ ] Sparkle with its signing key and the feed
- [ ] Rewritten Terms, Privacy and Refund pages
- [ ] Version 1.0.0
- [ ] Production purchase test on the signed build
- [ ] Manual Trial check on a clean install, then close issues #42 and #39
- [ ] Launch day: Buy opens checkout again, the launch price gets its end date
