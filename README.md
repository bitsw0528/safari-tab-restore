# Tab Restore – Safari Tab Recovery Utility

Tab Restore is a lightweight macOS app that lets you reopen the Safari windows of tabs you closed most recently, without digging through Safari’s history.

## Features

<img width="732" height="632" alt="image" src="https://github.com/user-attachments/assets/299dfd9f-a054-4d2f-975a-bbed3470bca5" />

- Reads Safari’s Recently Closed Tabs list
- Lets you pick only the tabs or windows you want to reopen

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later

## Installation

   ```
   git clone https://github.com/bitsw0528/safari-tab-restore
   cd /Documents/GitHub/safari-tab-restore
   ./build.sh
   ```

## Usage

1. Launch Tab Restore. On first launch the app asks for permission to read your Safari data.
2. Click “Grant File Access” and point the dialog to your `~/Library/Safari` folder.
3. Review the list of windows and tabs, and keep the checkboxes enabled for the ones you want.
4. Click “Restore Selected” to reopen them in Safari.

## Permissions

- **File access** to read `RecentlyClosedTabs.plist` from the Safari Library.
- **AppleScript automation** to instruct Safari to open the selected URLs.

## Troubleshooting

If Safari tabs do not populate or nothing reopens:
1. Open **System Settings → Privacy & Security → Files and Folders** and make sure Tab Restore can access Safari data.
2. Reopen the app and click “Grant File Access” again to re-authorize the folder if needed.

## License

CCO License – see the `LICENSE` file for details.

## Contributing

Issues and pull requests are welcome. Feel free to share ideas that make recovering tabs faster or safer.
