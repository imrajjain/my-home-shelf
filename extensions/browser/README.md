# Add to Shelf — browser extension

Manifest V3. Works in Chrome, Arc, Brave, Edge and other Chromium browsers.

- **Toolbar popup / ⌥⇧S:** preview the page, pick a shelf and status, add a note.
- **⌥⇧A:** add the current page instantly. Any selected text is saved as a quote.
- **Right-click:** add the page, a link, an image's page, or selected text.

Install: `chrome://extensions` → Developer mode → **Load unpacked** → this folder.
Then paste the pairing code from Shelf → Settings → Capture.

The extension posts to `http://127.0.0.1:47291/v1/items` with an
`X-Shelf-Token` header. If the app isn't running, it opens
`shelf://add?…` instead, which launches Shelf.
