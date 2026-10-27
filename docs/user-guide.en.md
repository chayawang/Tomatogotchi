# Installation and user guide

[繁體中文](user-guide.md) · [English](user-guide.en.md) · [日本語](user-guide.ja.md)

The App currently uses Traditional Chinese labels. Original labels are included below to help you find the controls.

## Download and open

The only official App download page is https://github.com/chayawang/Tomatogotchi/releases .

Version 1.0.3 build38 is a public prerelease for Apple Silicon only, without Developer ID signing or Apple notarization. Check the filename and official SHA-256, extract it to a location you choose, then open it. Quit the old App and back up your data before updating. Do not run multiple production versions at once.

If macOS blocks an unidentified developer or an unnotarized App, first verify the source and assess the risk. If you choose to trust it, follow [Apple's instructions](https://support.apple.com/102445) and use “Open Anyway” under System Settings → Privacy & Security for this App; wording varies by OS version. You do not need to give the publisher your Mac or Apple ID password. Stop and report the issue if macOS warns of malware, damage, or harm to your computer. Do not disable Gatekeeper globally or bypass workplace policies. The downloaded App's real Gatekeeper installation flow still needs manual verification.

## Adopt an egg and work

Adopt an unknown egg and optionally name it; you can rename it later. In the device menu, “每輪時間” (round durations) lets you set work and rest to 1–1440 minutes. Work shortcuts are 10/20/30/60 minutes; rest shortcuts are 5/10/15. Apply the settings before starting. Durations are locked during work, including paused work. During rest, you can set the next round without changing the current countdown; the settings apply when you manually start work again.

When work ends, a feeding or walking request appears. Respond to begin rest. Each accumulated three minutes of active unanswered waiting removes one health or mood unit; reaching zero in either causes death. Paused, ended, sleeping, locked, closed, and offline periods do not incur catch-up penalties. The egg remains an egg after the first complete work round. The first successful response to “餵牠吃飯” (feed) or “帶牠晃晃” (walk) plays the crack, wobble, and hatch sequence. Dismissing a reminder or taking an early break does not hatch it. Twelve complete rest rounds produce an adult. The unknown egg's species is fixed to one of five, and restarting does not reroll it.

## Completion reminders

Choose gentle or strong reminders in settings before work ends. Gentle mode, the default, uses a device animation; strong mode also shows a central popup. Both retain macOS notifications, subject to your permission and system settings. Dismissing a reminder leaves the care request pending. Responding to the first care request while hidden reveals the egg before hatching. Adoption and naming keep the original rectangular layout with colors matching the device.

## Modes and walking

The device body is 80% of its original size. Switch to “只顯示寵物” (pet only) in the menu; right-click the pet to return to the normal window. During work, random idle/walk/sleep/play animations stay within a small area in pet-only mode. After responding to “帶牠晃晃” (take a walk), the pet walks freely within the current display's usable desktop, turns at edges, and returns when time ends. Dragging takes priority. Switching modes preserves the same rest interval. Visual movement stops when hidden or when Reduce Motion applies. An existing always-on-top option is available; actual mouse interaction, click-through behavior, OS events, and multi-display appearance still have pending manual checks.

## Deceased pet records

Open “死亡寵物紀錄” (deceased pet records) from the device menu, pet-only right-click menu, or menu bar. Tombstones show the total count, names, egg-adoption meeting times, and death times. A death is recorded immediately and remains after saying goodbye and adopting another egg. Restarting does not duplicate it. Closing the records does not change the previous mode or reset the timer. Partial loading is explicitly indicated when some data cannot be read.

## Data and backups

The default data location is `~/Library/Application Support/Tomatogotchi/` in your account. It includes `pet.json`, `care.json`, `desktop.json`, and the `pet-history` farewell archive. The App selects the actual directory; QA uses a separate one. Quit and back up the entire directory before updating or removing the App. Do not post private saves in public Issues. On a read error, preserve the files and use the App's retry or backup recovery options. Use separate QA tools for testing, never real pet data.

## Other notes

There is no automatic update feature. Hiding and quitting are different; use “結束App” (quit App) to exit. Notifications require your permission in macOS and can be declined. No Apple ID, banking information, or paid verification deposit is required. Report general problems through official Issues; report vulnerabilities privately under [SECURITY](../SECURITY.en.md).
