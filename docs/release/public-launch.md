# Flapline Public Launch

This is the public-facing launch checklist for Flapline.

## Name And Domain

- Product name: **Flapline**
- Canonical domain: **flapline.app**
- macOS bundle identifier: **app.flapline.screensaver**
- Public tagline: **A split-flap screensaver with somewhere to be.**
- Short description: **A quiet split-flap screensaver for macOS with custom messages, clocks, dates, Unicode, and themes.**

Use only `flapline.app` for the public site. Do not launch a parallel `www`
site.

## Domain Registration

Register only:

```text
flapline.app
```

Suggested DNS for GitHub Pages apex hosting:

```text
A     @    185.199.108.153
A     @    185.199.109.153
A     @    185.199.110.153
A     @    185.199.111.153
AAAA  @    2606:50c0:8000::153
AAAA  @    2606:50c0:8001::153
AAAA  @    2606:50c0:8002::153
AAAA  @    2606:50c0:8003::153
```

Keep the domain locked after registration. Enable auto-renew if the registrar
account has a safe payment method.

## Website

The static site lives in:

```text
website/
```

The GitHub Pages workflow publishes that folder to:

```text
https://flapline.app
```

The `website/CNAME` file is the source of truth for the custom domain.

## Apple Signing Answer

Yes. Public downloads should be signed with a Developer ID certificate and
notarized before release.

Unsigned local builds are fine for development and personal testing, but a
public `.saver` download should avoid Gatekeeper friction. Apple documents that
Gatekeeper checks Developer ID certificates for software distributed outside the
Mac App Store, and Apple recommends notarization for additional trust on modern
macOS.

For this project, plan on:

1. Build a Release `.saver`.
2. Sign with Developer ID Application.
3. Package as a `.zip`, `.dmg`, or `.pkg`.
4. Submit to Apple notary service with `xcrun notarytool`.
5. Staple the ticket when the package format supports it.
6. Attach the notarized artifact to the GitHub Release.

## Release Checklist

Before `v1.0.0`:

- [ ] Confirm `flapline.app` is registered and DNS is configured.
- [ ] Confirm GitHub Pages serves `https://flapline.app`.
- [ ] Confirm `make build` produces `Flapline.saver`.
- [ ] Confirm `make install` installs `~/Library/Screen Savers/Flapline.saver`.
- [ ] Confirm the settings sheet opens and saves options.
- [ ] Confirm idle CPU behavior after ScreenSaverEngine stops.
- [ ] Sign with Developer ID.
- [ ] Notarize the release artifact.
- [ ] Create a GitHub Release with the signed/notarized artifact.
- [ ] Update `website/index.html` download links if the release artifact path changes.

## Suggested First Release Copy

Title:

```text
Flapline 1.0.0
```

Release summary:

```text
Flapline is a macOS screensaver inspired by classic split-flap departure boards.
It supports custom messages, clock and date modes, Unicode text, themes,
configurable wave timing, and idle-friendly Core Animation rendering.
```

Install note:

```text
Download the signed release, open it, and install Flapline.saver into
~/Library/Screen Savers. Then choose Flapline from System Settings -> Screen Saver.
```
