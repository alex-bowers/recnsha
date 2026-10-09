# Recnsha for macOS

A menu-bar app that captures screenshots and screen recordings, uploads them to your own [share server](../server/README.md), and copies a link you can paste anywhere.

## Requirements

- macOS 26 or later
- Xcode 27 or later, with the licence accepted (`sudo xcodebuild -license`)
- An Apple ID added to Xcode under Xcode › Settings › Accounts. A free account is enough; it gives you a "Personal Team" for signing.
- A deployed share server and its upload token

## Build and run

1. Create your local settings, which are not committed:

   ```bash
   cp Local.example.xcconfig Local.xcconfig
   ```

2. In `Local.xcconfig`, set `DEVELOPMENT_TEAM` to your team ID (Xcode › Settings › Accounts, select your Apple ID, then your team) and `RECNSHA_BUNDLE_ID_PREFIX` to your own reverse domain, for example `uk.co.yourname`.
3. Open `Recnsha.xcodeproj` and press ⌘R.

Signing with your own team matters: macOS ties the Screen Recording permission to the app's signature, and a build signed only to run locally loses it after every rebuild. Without `Local.xcconfig`, the app still builds and its tests run, signed to run locally with the bundle ID `com.example.Recnsha`.

Set the team in `Local.xcconfig` rather than in Xcode's **Signing & Capabilities** tab: choosing a team there writes it into the shared project file. Shared settings live in `Config.xcconfig`.

Run only one copy at a time. Two copies compete for the same global shortcuts.

### From the command line

Build:

```bash
xcodebuild -project Recnsha.xcodeproj -scheme Recnsha -destination 'platform=macOS' -derivedDataPath build build
```

Run the unit tests:

```bash
xcodebuild -project Recnsha.xcodeproj -scheme Recnsha -destination 'platform=macOS' -derivedDataPath build test
```

The built app is at `build/Build/Products/Debug/Recnsha.app`.

## First use

1. Settings opens on first launch. Enter your server address, for example `https://share.example.com`.
2. Paste your upload token and choose **Save Token**. The token is stored in your login keychain, never in a file.
3. Choose **Test Connection**. You should see "Connected."
4. Press ⌃⇧1. macOS asks for Screen Recording permission. Allow Recnsha in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen Recnsha.

## Capturing

| Shortcut | Action |
|---|---|
| ⌃⇧1 | Screenshot |
| ⌃⇧2 | Start or stop a screen recording |
| ⌃⇧L | Open the Library |

You can change every shortcut in Settings › Shortcuts. A shortcut must include ⌘ or ⌃, because macOS ignores global shortcuts that use only ⌥ and ⇧.

When the screen dims:

- **Drag** to select an area.
- **Click** a window to select the whole window.
- Press **Esc** or **right-click** to cancel.

Screenshots and recordings are captured at your display's full resolution. An area that spans two displays is captured from the display holding its centre.

**Delay:** choose 3, 5 or 10 seconds from the menu's **Delay** submenu or in Settings. The countdown starts after you select, so you can open a menu or hover over something before the capture.

**Recordings** are MP4 video at 30 frames per second with the pointer visible and no sound. A red border marks the recorded area, and a small control below it shows the elapsed time with **Cancel** and **Stop** buttons. Neither the border nor the control appears in the recording.

- **Stop** (or ⌃⇧2 again, or **Stop Recording** in the menu) finishes and uploads the recording.
- **Cancel** (or **Cancel Recording** in the menu) stops and deletes it without uploading.

After each upload, a message at the bottom of the screen confirms what happened, and a notification appears if notifications are allowed. Click the notification to open the share page.

## What gets copied

Choose what is copied after each capture in Settings › Capture or at the top of the Library:

| Option | Example |
|---|---|
| Share page link (default) | `https://share.example.com/AbCdEfGhIjKl` |
| Markdown | `![Screenshot](https://share.example.com/AbCdEfGhIjKl.png)` |
| Direct image link | `https://share.example.com/AbCdEfGhIjKl.png` |

For a recording, Markdown embeds its GIF, if it has one, linked to the video page. Otherwise it is a plain link to the page.

## Library

Open the Library with ⌃⇧L, the menu's **Library…** item, or by opening Recnsha again from Spotlight or Finder while it is running.

- Click a thumbnail to open its share page.
- The copy button copies in your chosen format. The **⋯** button and right-click offer Copy Link, Copy Markdown, Copy Image Link, Open in Browser and Delete….
- Recordings show a **Video** badge, or **Video · GIF** when they have a GIF. The thumbnail of a recording with a GIF is the GIF; the video itself is unchanged.
- Older uploads load as you scroll. Press ⌘R to refresh.

### Dragging into GitHub and other apps

Drag a card out of the Library to drop its file somewhere else, for example into a GitHub issue or pull request comment, which attaches it. GitHub plays MP4 recordings inline, which a link to your share page cannot do.

Rest the pointer on the card for a moment before dragging: Recnsha downloads the file first, so it is ready to hand over. The most recent 20 downloads are kept in `~/Library/Containers/<bundle ID>/Data/Library/Caches/Recnsha/Downloads`, and deleting an upload removes its copy.

GitHub limits attached videos to 10 MB on free plans and 100 MB on paid plans.

### Deleting several uploads

1. Choose **Select**.
2. Click cards to select them. Shift-click selects a range, and ⌘A selects everything loaded.
3. Choose **Delete (N)…** or press ⌫, then confirm.

Deleted links stop working for everyone. If some deletions fail, the rest still go ahead, and the failed ones stay selected so you can try again.

## Making a GIF from a recording

GIFs are never made automatically. To make one:

1. In the Library, choose **⋯** › **Make GIF…** on a recording. The menu's Recent Uploads offers it too.
2. Set **Start** and **Length**. A GIF can be up to 6 seconds long.
3. Choose **Preview Segment** to watch just that part, then **Create GIF**.

GIFs are 12 frames per second, up to 640 pixels wide, and loop. Making a GIF again replaces the previous one; its link changes, so caches show the new GIF.

## If something goes wrong

| Problem | What to do |
|---|---|
| No menu-bar icon | On a MacBook, the notch can hide menu-bar icons when the bar is full. Quit some menu-bar apps, or check System Settings › Menu Bar. Opening Recnsha again from Spotlight opens the Library, or Settings if it is not set up. |
| "Upload failed" | The capture is kept. Choose **Retry Failed Uploads** from the menu once the connection is back. |
| "The server rejected the upload token" | The token in Settings does not match the server's `UPLOAD_TOKEN`. Paste it again. |
| "Recnsha isn't set up" | Open Settings and add the server address and upload token. |
| "Recording stopped early" | macOS ended the recording, for example because a display was disconnected. What was recorded is kept; choose **Retry Failed Uploads**. |
| "Storage limit of N GB reached" | Delete old uploads in the Library, or raise `MAX_STORAGE_GB` on the server. |
| Screen Recording keeps asking for permission | Make sure the app is signed with your team (see [Build and run](#build-and-run)), then grant permission again and reopen Recnsha. |
| A shortcut does nothing | Another app or another copy of Recnsha may own it. Settings shows a message under the shortcut if so; choose a different one. |

## Privacy

Captures go only to the server you configure. The app has no analytics and makes no other network requests. Nothing is saved on your Mac, except recent downloads for dragging (see above) and captures whose upload failed; these are kept until they are retried, in `~/Library/Containers/<bundle ID>/Data/Library/Application Support/Recnsha/Failed Uploads`.
