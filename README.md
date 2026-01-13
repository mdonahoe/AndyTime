# AndyTime

An iOS app made just for Andy - a video streaming experience that simulates continuous live TV across multiple channels.

## Features

- **Channel-Based Video Organization**: Videos are automatically organized into channels based on their filename prefix
- **Synchronized Playback**: All channels share a global playback time, simulating live TV
- **Swipe Navigation**: Browse between channels and photos using horizontal swipe gestures
- **Photo Gallery**: Display photos alongside video channels
- **Admin Panel**: Control playback time and debug playback state

## How It Works

AndyTime tracks time from a fixed start date and uses that elapsed time to determine which video should be playing and at what position. When you switch between channels, the app calculates the correct playback position based on the total time elapsed since the start date.

### Video Organization

Videos are organized into channels based on their filename. Use the naming convention:

```
{ChannelName}-{VideoTitle}.mp4
```

For example:
- `animals-bear.mp4` → Channel: "animals"
- `animals-lion.mp4` → Channel: "animals"
- `nature-sunset.mp4` → Channel: "nature"
- `nature-ocean.mp4` → Channel: "nature"

All videos with the same prefix are grouped into the same channel and played in sequence.

## Setup

### Adding Content

1. Connect your iOS device to your computer
2. Open Finder (macOS) or iTunes (Windows)
3. Select your device and navigate to the File Sharing section
4. Drag and drop your media files into the AndyTime documents folder:
   - **Videos**: MP4 files with the `{ChannelName}-{VideoTitle}.mp4` naming convention
   - **Photos**: JPG or HEIC image files

### Requirements

- iOS device
- MP4 video files organized by channel prefix
- Optional: JPG/HEIC photos for the photo gallery

## Usage

1. Launch the app
2. Swipe horizontally to navigate between:
   - **Admin Panel** (leftmost) - Control and debug playback
   - **Video Channels** - One view per channel
   - **Photos** - One view per image
3. Videos automatically play when you navigate to a channel
4. Use the Admin Panel to:
   - View current playback time
   - Advance or rewind time by 10 minutes
   - Reset playback time to current moment
   - Switch channels using Prev/Next buttons

## Architecture

```
AppDelegate
    └── StartViewController (initialization)
            └── AndyViewController (page navigation)
                    ├── AdminViewController (debug controls)
                    ├── VideoViewController (video playback)
                    └── PhotoViewController (image display)

PlaybackManager (singleton - central state management)
```

### Key Components

- **PlaybackManager**: Singleton that manages all playback state, video organization, and time synchronization
- **AndyViewController**: Main UI controller managing page-based navigation
- **VideoViewController**: Handles individual video playback for a channel
- **PhotoViewController**: Displays static images
- **AdminViewController**: Debug interface for controlling playback

## License

Copyright (c) Matt Donahoe
