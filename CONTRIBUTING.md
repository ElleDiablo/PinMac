# Contributing to PinMac

Thanks for helping! Bug reports, ideas, and pull requests are all welcome.

## Reporting bugs and ideas

Use the [issue templates](../../issues/new/choose). For bugs, include your
PinMac and macOS versions and which app's window was pinned; window behavior
often depends on the app.

## Working on the code

You need macOS 14 or later and the Xcode Command Line Tools
(`xcode-select --install`) or Xcode.

```bash
git clone https://github.com/ElleDiablo/PinMac.git
cd PinMac
scripts/build.sh            # builds build/PinMac.app and a DMG
open build/PinMac.app
```

Tip: ad-hoc builds lose their permissions on every rebuild. Sign with your own
certificate to keep them:
`SIGN_IDENTITY="Apple Development: you@example.com" scripts/build.sh`

The [README](README.md#project-layout) lists what each source file does.

## Pull requests

- Keep each pull request to one change, with a clear description.
- Match the style of the surrounding code.
- Test the change in the real app: pin a few windows from different apps,
  switch between them, and try any shortcuts you touched.
- Update the README and the `Unreleased` section of the [CHANGELOG](CHANGELOG.md)
  if users will notice the change.

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
