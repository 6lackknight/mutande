# Windows alpha release

Windows builds **cannot** run on macOS. Use GitHub Actions:

1. **Actions** → **Release Windows alpha** → **Run workflow**
2. Download the `mutande-alpha-windows` artifact (`mutande-alpha-windows.zip`)
3. Copy the zip into `web/public/downloads/` and deploy the site (zip is gitignored)

The zip is **unsigned**. SmartScreen will show “Windows protected your PC”; users choose **More info → Run anyway**. Authenticode/EV signing is deferred.

Mac notarized DMGs remain the primary channel (`scripts/release-macos-dmg.sh`).
