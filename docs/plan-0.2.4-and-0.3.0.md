# Plan for 0.2.4 and 0.3.0

Decisions from the 2026-11-25 planning session, after feedback on release
0.2.3. The work is split into two releases: 0.2.4 is small and ships first,
0.3.0 carries the rest. Tick an item when it is done and merged.

## What was wrong in 0.2.3

- **Empty screens** got animated devices that the owner does not want.
- **Assistant would not connect for testers.** Pocket runs the `claude` and
  `codex` command-line programs. It only checks that the program file exists,
  never whether the person is signed in, and it cannot use the sign-in of the
  Claude or ChatGPT desktop apps. Nothing connects by itself: the person has
  to open Settings → Accounts and press Save.
- **`env: node: No such file or directory` with Codex.** Pocket finds `codex`
  but starts it with the short `PATH` that apps launched from Finder get. An
  npm-installed `codex` starts with `#!/usr/bin/env node`, and `node` is not
  on that `PATH`. The `PATH` is never extended (`CLIAssistantClient.swift`,
  `runBlocking`), and nvm, fnm and pnpm folders are not searched.
- **Provider setup is hard to find.** It lives in Settings → Accounts, and the
  text in the unconfigured chat only mentions API endpoints.
- **Two displays.** There is one strip and it can already be dragged to
  another display, but the display is kept in memory only: a relaunch or any
  screen change sends the strip back to the built-in screen. The capsule is a
  separate window fixed to the top centre of the notch screen, so it opens on
  the MacBook even when the strip is on the external monitor. The module
  panel's maximum width is taken from the MacBook's width.
- **System module** opens with a carousel of animated meters that does not
  match the other modules.

## 0.2.4

- [x] **Real `PATH` for the command-line programs.** Read the person's `PATH`
  once from their login shell and pass it to `claude` and `codex`, together
  with the folder of the program itself. If the shell does not answer, fall
  back to the current list of folders, extended with nvm
  (`~/.nvm/versions/node/*/bin`), fnm and pnpm.
- [x] **Empty screens without devices.** All nine modules show the centred
  title and sublabel, as before 0.2.2, plus the bottom action bar where one
  exists (add mail, add playbook, new event, own hotkey). Timer and Shelf keep
  their own buttons. The device views used on empty screens are deleted, not
  hidden behind a flag.

## 0.3.0

### Assistant: setup inside the module

- [x] Provider setup moves into the Assistant module and is removed from
  Settings → Accounts. First open shows a chooser: Claude, ChatGPT, own key.
- [x] A small button in the chat header shows the current provider and opens
  the same chooser. Changing the provider keeps the conversation on screen.
- [x] Pocket looks for `claude` and `codex` by itself. A program that is found
  is marked "found on this Mac" and connects with one click: no fields, no
  Save. Pocket never picks a provider silently.
- [x] After the click Pocket sends a test request. A "not signed in" answer
  leads to the sign-in step below; the raw error text no longer lands in the
  chat.
- [x] **"Install and sign in" button.** Opens Terminal with the command
  already running: install, then sign-in. If the program is installed the
  button reads "Sign in" and only runs sign-in. Terminal is opened through a
  temporary `.command` file, so no extra permission prompt appears.
- [x] While Terminal is open the card shows "Waiting for sign-in…" and checks
  every couple of seconds. When the test request passes, the provider is
  connected and the chat opens. There is no Check button.
- [x] **Desktop app only.** If Claude.app or ChatGPT.app is installed but the
  command-line program is not, the card says the app was found, that Pocket
  needs one more component, and offers the same button.
- [x] **Codex with no way to install.** If Codex has no installer without
  dependencies and the Mac has neither `node` nor Homebrew, the ChatGPT card
  shows step-by-step instructions instead of the button. Pocket does not
  install Node for the person.
- [x] Own key: same fields as today (presets, base URL, model, API key), moved
  into the module.
- [x] The "Connect" button in onboarding opens the Assistant module on the
  chooser.
- [x] Pocket does not read other programs' credentials from Keychain.

### Assistant: suggestions

- [x] In an empty chat, four pills in one scrolling row above the text box:
  "What's on my calendar today?", "Any unread email?", "Set a 25-minute
  timer", "What's playing?". They are shown in the app's language.
- [x] Clicking a pill sends the message at once. The pills disappear after the
  first message.
- [x] All four are always shown. If something is not connected, the assistant
  answers by asking for access.
- [x] The empty chat has no device: a short centred text and the pills.

### Displays

- [x] The strip's display is saved together with its edge and offset. A screen
  change no longer resets it.
- [x] If the strip's display is disconnected, the strip moves to the built-in
  screen at the same edge and offset. It does not jump back when the display
  returns.
- [x] The capsule and its hover zone sit at the top centre of the display the
  strip is on, and move when the strip is dragged to another display. On a
  display without a notch the capsule uses the existing fallback size.
- [x] Module panel size limits are taken from the strip's display.
- [x] Placement logic is covered by tests with fake screens. Before release, a
  tester with an external monitor checks it by hand; the owner has no monitor.
  **The hand check is still to do.**

### System module

- [x] The carousel of meters is removed and its code deleted.
- [x] Top: one large block with the chart of the selected metric, in the same
  card as the other modules.
- [x] Below it a section heading, "Metrics", styled like the headings in Shelf
  and Notes, then the five cards with small charts (CPU, memory, network,
  battery, volume), made larger. The selected card is highlighted. The row of
  pills is removed.
- [x] CPU is selected on first open; the last choice is remembered.
- [x] Volume keeps its slider in the top block.
- [x] Chart history still starts empty on each open; Pocket does not sample in
  the background.

## To check during the work

- Whether Codex has an installer that needs neither `node` nor Homebrew. This
  decides which branch of "Codex with no way to install" most people see.
  **Checked 2026-11-25:** it has one,
  `curl -fsSL https://chatgpt.com/codex/install.sh | sh`. Almost everyone
  gets the "Install and sign in" button; the instructions show only when
  `curl`, Homebrew and npm are all missing.
- Whether `--safe-mode`, which Pocket passes to `claude`, fails on older
  versions of the program. **Checked 2026-11-25:** the flag appeared in
  `claude` 2.1.169; an older program is expected to refuse it (not run on a
  real old build). Pocket repeats the request without the flag.
- Ask the tester who saw the `node` error to run `which node` in Terminal. A
  path confirms the `PATH` cause; no output means `node` is missing.
