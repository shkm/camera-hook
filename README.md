# camera-hook

Run scripts when your Mac's camera turns on or off.

## Install

```bash
brew install shkm/brew/camera-hook
brew services start camera-hook
```

## Scripts

Place executable scripts in:

```
~/Library/Application Support/camera-hook/on/     # runs when camera turns on
~/Library/Application Support/camera-hook/off/    # runs when camera turns off
```

Scripts are executed in lexical order. Each script receives the environment variable `CAMERA_HOOK_STATE` set to `on` or `off`.

### Example

Copy the included example scripts to get started with notifications:

```bash
mkdir -p ~/Library/Application\ Support/camera-hook/{on,off}
cp examples/on/* ~/Library/Application\ Support/camera-hook/on/
cp examples/off/* ~/Library/Application\ Support/camera-hook/off/
```

## Commands

```
camera-hook watch       Start listening for camera events and run scripts
camera-hook status      Show installed scripts
```

## Releasing

```bash
scripts/release.sh <version>
```

Once the release workflow completes, [trigger the Homebrew formula update](https://github.com/shkm/homebrew-brew/actions/workflows/update-camera-hook.yml).
