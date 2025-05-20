# Wallpaper Changer

A macOS menu bar application that automatically changes your desktop wallpaper at customizable intervals.

## Features

-   🖼️ Automatically changes your desktop wallpaper at customizable intervals
-   ⏱️ Set refresh intervals from 30 seconds to 24 hours
-   🔄 Manually refresh wallpaper with a single click
-   🌐 Multiple wallpaper sources:
    -   Random images from [picsum.photos](https://picsum.photos)
    -   Custom static URL
    -   JSON API with selector for dynamic sources
-   ⚙️ Easy configuration through menu bar

## Installation

### Option 1: Build from Source

1. Clone this repository
2. Open Terminal and navigate to the project directory
3. Build the application:
    ```
    cd WallpaperChanger
    swift build -c release
    ```
4. The built application will be in `.build/release/WallpaperChanger`
5. Copy the application to your Applications folder or run it directly

### Option 2: Download Release

1. Download the latest release from the Releases page
2. Extract the zip file
3. Move WallpaperChanger.app to your Applications folder
4. Launch the application

## Usage

1. Launch the application
2. The app will appear as an icon in your menu bar (photo icon)
3. Click the icon to access the menu
4. Use the menu to:
    - Refresh wallpaper immediately
    - Change refresh interval
    - Change image source
    - Quit the application

## Configuration

### Refresh Interval

You can set how often the wallpaper changes from the menu:

-   Change Interval → Select from options ranging from 30 seconds to 24 hours

### Wallpaper Sources

The app supports three types of wallpaper sources:

1. **Random (picsum.photos)**

    - Uses random images from picsum.photos
    - Automatically adapts to your screen resolution

2. **Static URL**

    - Enter a direct URL to an image file
    - The image will be used as your wallpaper

3. **JSON API**
    - Enter an API URL that returns JSON
    - Specify a JSON path to extract the image URL
    - Example: If your API returns `{"data": {"imageUrl": "https://example.com/image.jpg"}}`, use the JSON path `data.imageUrl`

## Requirements

-   macOS 12.0 or later

## License

This project is licensed under the WTFPL License - see the LICENSE file for details.
