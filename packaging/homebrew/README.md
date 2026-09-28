# Homebrew publishing

Install with:

```sh
brew install tkoenig/tap/contactctl
```

Homebrew expands `tkoenig/tap` to `https://github.com/tkoenig/homebrew-tap` and reads `Formula/contactctl.rb`. The formula downloads a versioned public source archive. `tkoeng` is a different GitHub account.

The template builds from source with Swift 6 (Xcode 16+). It installs an ad-hoc-signed executable with an embedded Contacts permission description. No Contacts permission is needed during build or formula tests. Ad-hoc signing does not guarantee permission persistence across upgrades.

## Release checklist

1. The project and tap are public and MIT-licensed. Keep release source archives publicly accessible; this formula does not configure private-repository authentication.
2. Set the same release version in `ContactCLI.swift` and `Resources/Info.plist`. Run `make build`, `make test`, and `python3 scripts/smoke-test.py`.
3. Commit the release source, push it, and publish an immutable `vX.Y.Z` tag. Do not tag an older commit that lacks the desired features.
4. Download the exact GitHub-generated source archive. Do not substitute a locally generated tarball: its bytes/checksum may differ.

   ```sh
   VERSION=0.1.0 # replace with the actual release
   curl --fail --location \
     "https://github.com/tkoenig/contactctl/archive/refs/tags/v${VERSION}.tar.gz" \
     --output "/tmp/contactctl-${VERSION}.tar.gz"
   python3 scripts/render-homebrew-formula.py "v${VERSION}" "/tmp/contactctl-${VERSION}.tar.gz" \
     > /path/to/homebrew-tap/Formula/contactctl.rb
   ```

5. Commit and push the rendered formula to `tkoenig/homebrew-tap`.
6. Run `brew install tkoenig/tap/contactctl`, `brew test tkoenig/tap/contactctl`, and verify `contactctl --version`. On this machine, update `~/.dotfiles/Brewfile` before installing persistently.

The renderer verifies the archive's CLI version and computes its SHA-256. It does not create repositories, tags, releases, or change visibility. Future prebuilt bottles could avoid the local Xcode build requirement, but are not included in this initial packaging.
