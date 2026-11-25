# SwitchboardiOSDemo

A simple Xcode-based speech-to-text, text-to-speech and voice assistant demo application for iOS.

## Setup

No manual setup step is required. The Switchboard SDK and its extensions are declared as a
Swift Package Manager dependency
([switchboard-sdk-ios](https://github.com/switchboard-sdk/switchboard-sdk-ios), pinned to
**3.3.0**). Xcode resolves and downloads the packages automatically the first time you build.

> **Note:** the SwitchboardSDK Swift package vends all of its extensions as binary targets, so
> the first resolve downloads every artifact (a few GB in total) even though these demos only use
> a handful. Subsequent builds use the cached artifacts.

## Build & Run

Open `SwitchboardiOSDemo.xcworkspace` in Xcode, wait for package resolution to finish, then run
one of the demo schemes (WhisperSTT, SherpaTTS, WhisperSTTtoSherpaTTS or OpenAILive). To run on
a device, select your team under Signing & Capabilities.

## OpenAILive

OpenAILive holds a voice conversation with OpenAI GPT-Live through the
[`OpenAI.Live` node](https://docs.switchboard.audio/extensions/openai/openai-live-node).

It needs your own Switchboard app: [register one](https://console.switchboard.audio/register), then
replace `"demo"` with its `appID` and `appSecret` in `demos/OpenAILive/Sources/App.swift`.

Press Start and allow the microphone. Then talk; the transcript shows as you go. Say "play some
music" or "pause the music" to try the tools. Press Stop to end.

## Documentation

- [Register a Switchboard app](https://console.switchboard.audio/register)
- [Switchboard SDK](https://docs.switchboard.audio/)
- [iOS integration](https://docs.switchboard.audio/integration/ios)
- [OpenAI Live credentials and billing](https://docs.switchboard.audio/extensions/openai/openai-live-node#credentials-and-billing)
- [OpenAI Live Toolkit for React Native](https://github.com/switchboard-sdk/openai-live-toolkit)
