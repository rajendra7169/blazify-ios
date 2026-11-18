<div align="center">

<img src="assets/logo.png" alt="Blazify" width="96" />

# Install Blazify (or any .ipa) on iPhone

**No jailbreak. No Mac. Any computer works: Windows, macOS or Linux.**

You need the computer once, at the start. After that everything happens on the iPhone.

<a href="https://youtu.be/H0TF7mbJVbM"><img src="https://img.youtube.com/vi/H0TF7mbJVbM/maxresdefault.jpg" width="560" alt="Watch the video" /></a>

**▶ [Prefer watching? The whole guide as an 8-minute video](https://youtu.be/H0TF7mbJVbM)**

</div>

---

## Contents

- [What you need](#what-you-need)
- [How it works](#how-it-works)
- [Step 1 · Download LocalDevVPN](#step-1--download-localdevvpn)
- [Step 2 · Download iloader](#step-2--download-iloader)
- [Step 3 · Install iloader](#step-3--install-iloader)
- [Step 4 · Connect your iPhone](#step-4--connect-your-iphone)
- [Step 5 · Install SideStore](#step-5--install-sidestore)
- [Step 6 · Trust the developer](#step-6--trust-the-developer)
- [Step 7 · Turn on Developer Mode](#step-7--turn-on-developer-mode)
- [Step 8 · Connect LocalDevVPN](#step-8--connect-localdevvpn)
- [Step 9 · Sign in to SideStore](#step-9--sign-in-to-sidestore)
- [Step 10 · Download Blazify](#step-10--download-blazify)
- [Step 11 · Install Blazify](#step-11--install-blazify)
- [Keep your apps working: automatic refresh](#keep-your-apps-working-automatic-refresh)
- [Test it](#test-it)
- [Quick fixes](#quick-fixes)

---

## What you need

| | |
|---|---|
| **iPhone** | iOS 17 or newer for Blazify (other apps may run on older iOS) |
| **A computer** | Windows, macOS or Linux, only for the first install |
| **A USB cable** | the one you charge your iPhone with |
| **An Apple Account** | the one you use for the App Store is fine; it's only sent to Apple |

> [!IMPORTANT]
> **Two limits of a free Apple Account**
> - You can have **3 apps** installed this way at a time, and **SideStore counts as one**, so 2 more.
> - Apps installed this way must be **refreshed every 7 days**, or they stop opening. The shortcuts at the end of this guide do it for you.

## How it works

| Piece | Where | What it does |
|---|---|---|
| **iloader** | computer | Puts SideStore on your iPhone. Used once. |
| **SideStore** | iPhone | Installs `.ipa` files, like Blazify, and refreshes them. |
| **LocalDevVPN** | iPhone | Lets SideStore talk to your own iPhone, so no computer is needed later. Your data never leaves the phone. |
| **Shortcuts** | iPhone | Apple's own app. Runs the refresh for you every few days. |

---

## Step 1 · Download LocalDevVPN

On the iPhone:

1. Open the **App Store** and tap **Search** at the bottom.
2. Type **LocalDevVPN** and tap **Search** on the keyboard.
3. Tap **Get**, then confirm with Face ID or your password if asked.
4. Wait until it's installed. You don't need to open it yet.

## Step 2 · Download iloader

On the computer:

1. Open **[github.com/nab138/iloader/releases](https://github.com/nab138/iloader/releases)**.
2. Under the latest release, open **Assets** and download the file for your computer:

| Computer | File |
|---|---|
| Windows | the one ending in **`.msi`** |
| macOS | the one ending in **`.dmg`** |
| Linux | **`.deb`** (Ubuntu, Debian), **`.rpm`** (Fedora), or the **AppImage** |

## Step 3 · Install iloader

- **Windows:** open the `.msi` and click **Next › Install › Finish**.
  Also install **iTunes from [apple.com](https://www.apple.com/itunes/)**. It adds the driver that lets the computer see your iPhone.
- **macOS:** open the `.dmg` and drag **iloader** into **Applications**.
- **Linux:** install the `.deb`/`.rpm` (or run the AppImage), and install **usbmuxd**:
  ```bash
  sudo apt install usbmuxd      # Ubuntu / Debian
  sudo dnf install usbmuxd      # Fedora
  ```

## Step 4 · Connect your iPhone

1. Connect the iPhone to the computer with the USB cable and **unlock** it.
2. The iPhone asks **Trust This Computer?** Tap **Trust** and enter your passcode.
3. Open **iloader**. After a moment it shows your iPhone.

## Step 5 · Install SideStore

1. In iloader, sign in with your **Apple Account** and click **Sign in**.
2. Select your iPhone and click **Install SideStore (Stable)**.
3. Wait until it says **Done**. iloader also places the **pairing file**: the key that lets SideStore talk to your iPhone later without a computer.
4. That's all for the computer. Unplug the iPhone.

## Step 6 · Trust the developer

If you open SideStore now it says **Untrusted Developer**. Allow it once:

**Settings › General › VPN & Device Management › your Apple Account (under Developer App) › Trust › Trust**

## Step 7 · Turn on Developer Mode

SideStore says **Developer Mode Required** until this is on:

1. **Settings › Privacy & Security**, scroll to the bottom, tap **Developer Mode**.
2. Turn it on and tap **Restart**.
3. After the restart, unlock the iPhone, tap **Turn On** and enter your passcode.

## Step 8 · Connect LocalDevVPN

1. Open **LocalDevVPN** and tap **Connect**.
2. The first time, iOS asks to **add a VPN configuration**: tap **Allow** and enter your passcode.
3. **VPN** shows at the top of the screen once it's connected.

## Step 9 · Sign in to SideStore

1. Open **SideStore**.
2. Sign in with the **same Apple Account** you used in iloader.

> [!TIP]
> SideStore can only install or refresh apps when the iPhone is on **Wi-Fi** and **LocalDevVPN is connected**.

## Step 10 · Download Blazify

1. In Safari, open **[github.com/rajendra7169/blazify-ios/releases](https://github.com/rajendra7169/blazify-ios/releases/latest)**.
2. Under the latest release, open **Assets** and tap **`Blazify.ipa`**, then **Download**.
3. It's saved to **Files › Downloads**.

## Step 11 · Install Blazify

1. In SideStore, open **My Apps** and tap **+** at the top.
2. Open **Downloads** and tap **`Blazify.ipa`**.
3. SideStore signs and installs it. This takes a minute, so keep SideStore open.
4. Blazify appears on the home screen. 🎵

> [!NOTE]
> **Any other `.ipa` installs exactly the same way**, as long as you stay within the free limit of 3 apps.

---

## Keep your apps working: automatic refresh

Apps installed this way stop opening after **7 days** unless SideStore refreshes them. These two shortcuts and one automation refresh them by themselves **every 3 days, whenever you open Blazify**.

These are the steps in the Shortcuts app on iOS 26 and 27. Older versions look a little different, but the actions are the same.

### Shortcut 1 · Refresh App

1. Open **Shortcuts**, tap **+** at the bottom. Tap the name at the top › **Rename** › `Refresh App`.
2. Add these actions in this order, using **Search** at the bottom to find each one:

| # | Action | Set it to |
|---|---|---|
| 1 | **Enable LocalDevVPN** | |
| 2 | **Wait** | `10 seconds` |
| 3 | **Refresh All Apps** (SideStore) | |
| 4 | **Disable LocalDevVPN** | |
| 5 | **Text** | tap inside it and choose **Current Date** |
| 6 | **Save File** | reads *Save Text to Shortcuts*. Tap its arrow: **Ask Where To Save** off · **Subpath** `lastrefresh.txt` · **Overwrite If File Exists** on |

> [!NOTE]
> If Save File says **"Files requires Face ID"**, tap **Unlock Action**.

3. Tap **▶ once** to run it. When it says **All apps have been refreshed**, tap **Done**. This creates the date file the next shortcut reads.

### Shortcut 2 · Refresh If Due

New shortcut, renamed `Refresh If Due`, with these actions:

| # | Action | Set it to |
|---|---|---|
| 1 | **Get File** | *Get file from **Shortcuts** at path `lastrefresh.txt`*. Tap its arrow: **Error If Not Found** off |
| 2 | **Get Dates** | *Get dates from **File*** |
| 3 | **Get Time Between Dates** | *Get **Days** between **Dates** and **Current Date*** (change Minutes to Days) |
| 4 | **If** | *If **Time Between Dates** **is less than** `3`* (Otherwise and End If are added for you) |
| 5 | **Stop This Shortcut** | drag it up so it sits **inside the If**, right under it |
| 6 | **Run Shortcut** | at the very bottom, after End If · choose **Refresh App** |

It should read:

```
Get file from Shortcuts at path lastrefresh.txt
Get dates from File
Get Days between Dates and Current Date
If Time Between Dates is less than 3
    Stop this shortcut
Otherwise
End If
Run Refresh App
```

### The automation

1. In Shortcuts, open **Automation** and tap **+**.
2. Tap the **Automation** button above the list and choose **When App Is Opened**.
3. Tap the app, choose **Blazify**, tap **+** and add **SideStore** too. Leave it on **Opened**.
4. Search **Run Shortcut**, add it, and choose **Refresh If Due**.
5. Tap the **settings button** at the top: **Automation** on, **Notify** off.

On older iOS: **Automation › New Automation › App › choose the apps › Is Opened › Run Immediately › Next › Refresh If Due**.

## Test it

Close Blazify and open it again. If 3 days have passed, **VPN** shows at the top for a few seconds while your apps refresh. If not, the shortcut just stops, which is normal. In SideStore the counter goes back to **7 DAYS** after each refresh.

---

## Quick fixes

| Problem | Fix |
|---|---|
| The computer doesn't see the iPhone | Windows: install iTunes from apple.com. Linux: install `usbmuxd`. Unlock the iPhone and tap **Trust**. Try another cable or port. |
| **Untrusted Developer** | Settings › General › VPN & Device Management › your Apple Account › **Trust** |
| **Developer Mode Required** | [Step 7](#step-7--turn-on-developer-mode) |
| SideStore: pairing file missing or invalid | Plug the iPhone into the computer, open iloader › **Manage Pairing File** › **Place** next to SideStore |
| SideStore can't sign in | In SideStore's Settings, try another **Anisette** server, then sign in again |
| Refresh fails | Connect LocalDevVPN, stay on Wi-Fi, try again. Still failing: replace the pairing file (above) |
| **Files requires Face ID** | Tap **Unlock Action** once |
| Apps stopped opening | More than 7 days passed. Connect LocalDevVPN and open SideStore › My Apps › **Refresh All** |
| The automation never runs | Shortcuts › Automation: check it's still there and **Automation** is on |
| "Maximum number of apps" | The free account allows 3 apps including SideStore. Remove one in SideStore › My Apps |

Still stuck? **[Open an issue](https://github.com/rajendra7169/blazify-ios/issues)** and say which step it is.
