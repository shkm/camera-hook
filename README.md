# camera-hook

Run scripts when your Mac's camera turns on or off.

## Build

```bash
swift build -c release
```

## Usage

```
camera-hook <command>

Commands:
  watch       Start listening for camera events and run scripts
  status      Show whether the launchd agent is installed and running
  install     Install and start the launchd agent for background operation
  uninstall   Stop and remove the launchd agent
  logs [-f]   Show logs (use -f to follow)
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

## Background service

Install as a launchd user agent so it runs automatically:

```bash
camera-hook install
```

Check status:

```bash
camera-hook status
```

View logs:

```bash
camera-hook logs -f
```

Remove:

```bash
camera-hook uninstall
```
