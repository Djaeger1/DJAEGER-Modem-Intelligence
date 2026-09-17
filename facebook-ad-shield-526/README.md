# DJAEGER Facebook Ad Shield 526 — SHADOW1

Experimental LSPosed/Xposed compatibility module for **Facebook `com.facebook.katana` version `526.1.0.66.75` only**.

## Goal

Hide native News Feed units whose visible marker is `Bersponsor` / `Sponsored`, without blocking Facebook DNS/API/CDN hosts.

## Safety boundaries

- Exact Facebook version gate: `526.1.0.66.75`.
- Main Facebook process only.
- No DNS changes.
- No network interception.
- No account/session modification.
- No hooks into other apps.
- No permanent polling loop.
- If the version does not match, the module disables itself.

## SHADOW1 strategy

1. Watch visible `TextView` text and accessibility content descriptions for a short sponsored marker.
2. Prefer collapsing the containing Litho/list row rather than blocking network requests.
3. Run three bounded view-tree scans after activity resume as a fallback.
4. If no safe containing row can be identified, leave the view untouched.

This is intentionally separate from the stable OpenWrt/AdGuard configuration.

## Test procedure

1. Install the APK.
2. Enable it in LSPosed and scope **only** `com.facebook.katana`.
3. Force-stop Facebook and reopen it.
4. Scroll the home feed and verify whether `Bersponsor` units disappear.
5. Confirm normal posts, photos, comments, Reels and Messenger links still work.

If SHADOW1 misses a sponsored unit, do not broaden DNS blocking. The next revision should use runtime structural discovery against the exact Facebook 526 APK rather than unsafe host blocking.
