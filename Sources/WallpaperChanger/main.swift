import Cocoa
import Foundation

// Create a strong reference to the app delegate
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate

// Start the application
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

class AppDelegate: NSObject, NSApplicationDelegate {
  var statusItem: NSStatusItem!
  var timer: Timer?

  // Configuration
  var refreshInterval: TimeInterval = 3600  // Default: 1 hour
  var currentSource: WallpaperSource = .picsum

  // Cache for last resolved image URL
  private var lastResolvedImageUrl: String?

  // UserDefaults keys
  private let kRefreshIntervalKey = "refreshInterval"
  private let kSourceTypeKey = "sourceType"
  private let kStaticUrlKey = "staticUrl"
  private let kJsonApiUrlKey = "jsonApiUrl"
  private let kJsonSelectorKey = "jsonSelector"
  private let kLastResolvedImageUrlKey = "lastResolvedImageUrl"

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Set as accessory app (menu bar only)
    NSApp.setActivationPolicy(.accessory)

    // Close any windows that might have been created
    NSApp.windows.forEach { $0.close() }

    loadSettings()
    setupMenuBar()
    startTimer()
  }

  func setupMenuBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "photo", accessibilityDescription: "Wallpaper Changer")
    }

    setupMenu()
  }

  func setupMenu() {
    let menu = NSMenu()

    // Refresh Now option
    menu.addItem(
      NSMenuItem(
        title: "Refresh Wallpaper Now", action: #selector(refreshWallpaper), keyEquivalent: "r"))

    menu.addItem(NSMenuItem.separator())

    // Interval submenu
    let intervalMenu = NSMenu()
    for (title, seconds) in [
      ("30 seconds", 30.0),
      ("1 minute", 60.0),
      ("5 minutes", 300.0),
      ("15 minutes", 900.0),
      ("30 minutes", 1800.0),
      ("1 hour", 3600.0),
      ("3 hours", 10800.0),
      ("6 hours", 21600.0),
      ("12 hours", 43200.0),
      ("24 hours", 86400.0),
    ] {
      let item = NSMenuItem(title: title, action: #selector(setInterval(_:)), keyEquivalent: "")
      item.representedObject = seconds
      if seconds == refreshInterval {
        item.state = .on
      }
      intervalMenu.addItem(item)
    }

    let intervalItem = NSMenuItem(title: "Change Interval", action: nil, keyEquivalent: "")
    intervalItem.submenu = intervalMenu
    menu.addItem(intervalItem)

    // Source submenu
    let sourceMenu = NSMenu()

    let picsumItem = NSMenuItem(
      title: "Random (from picsum.photos)", action: #selector(setSource(_:)), keyEquivalent: "")
    picsumItem.representedObject = WallpaperSource.picsum
    if case .picsum = currentSource {
      picsumItem.state = .on
    }
    sourceMenu.addItem(picsumItem)

    let staticUrlItem = NSMenuItem(
      title: "Static URL...", action: #selector(setStaticUrl), keyEquivalent: "")
    if case .staticUrl = currentSource {
      staticUrlItem.state = .on
    }
    sourceMenu.addItem(staticUrlItem)

    let jsonApiItem = NSMenuItem(
      title: "JSON API...", action: #selector(setJsonApi), keyEquivalent: "")
    if case .jsonApi = currentSource {
      jsonApiItem.state = .on
    }
    sourceMenu.addItem(jsonApiItem)

    let sourceItem = NSMenuItem(title: "Image Source", action: nil, keyEquivalent: "")
    sourceItem.submenu = sourceMenu
    menu.addItem(sourceItem)

    menu.addItem(NSMenuItem.separator())

    // Quit option
    menu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

    statusItem.menu = menu
  }

  func startTimer() {
    stopTimer()

    timer = Timer.scheduledTimer(
      timeInterval: refreshInterval,
      target: self,
      selector: #selector(refreshWallpaper),
      userInfo: nil,
      repeats: true)

    // Refresh immediately when starting
    refreshWallpaper()
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  @objc func refreshWallpaper() {
    Task {
      do {
        let imageUrl = try await getImageUrl()
        let urlString = imageUrl.absoluteString

        // Check if the URL has changed since last time
        if urlString == lastResolvedImageUrl {
          // For static URLs and JSON API, skip if unchanged
          switch currentSource {
          case .staticUrl, .jsonApi:
            print("Image URL unchanged, skipping download")
            return
          default:
            break
          }
        }

        // Update the last resolved URL
        lastResolvedImageUrl = urlString
        saveSettings()

        try await downloadAndSetWallpaper(from: imageUrl)
      } catch {
        print("Error refreshing wallpaper: \(error)")

        // Show alert with detailed error information
        await MainActor.run {
          let alert = NSAlert()
          alert.alertStyle = .warning
          alert.icon = NSImage(
            systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
          alert.messageText = "Wallpaper Error"
          alert.informativeText = "Failed to update wallpaper. See below for details."

          // Add detailed error information
          let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 450, height: 200))
          textView.isEditable = false
          textView.string = error.localizedDescription

          let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 450, height: 200))
          scrollView.documentView = textView
          scrollView.hasVerticalScroller = true
          scrollView.hasHorizontalScroller = true
          scrollView.autohidesScrollers = true

          alert.accessoryView = scrollView
          alert.addButton(withTitle: "OK")

          alert.runModal()
        }
      }
    }
  }

  @objc func setInterval(_ sender: NSMenuItem) {
    guard let seconds = sender.representedObject as? TimeInterval else { return }

    refreshInterval = seconds
    saveSettings()
    startTimer()
    setupMenu()  // Refresh menu to update checkmarks
  }

  @objc func setSource(_ sender: NSMenuItem) {
    guard let source = sender.representedObject as? WallpaperSource else { return }

    currentSource = source
    saveSettings()
    setupMenu()  // Refresh menu to update checkmarks
    refreshWallpaper()
  }

  @objc func setStaticUrl() {
    let alert = NSAlert()
    alert.messageText = "Enter Custom Image URL"
    alert.informativeText = "Enter the direct URL to an image file:"

    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    if case .staticUrl(let url) = currentSource {
      textField.stringValue = url
    }

    alert.accessoryView = textField
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      let url = textField.stringValue
      if !url.isEmpty {
        currentSource = .staticUrl(url)
        saveSettings()
        setupMenu()
        refreshWallpaper()
      }
    }
  }

  @objc func setJsonApi() {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.icon = NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: "JSON API")
    alert.messageText = "Configure JSON API"
    alert.informativeText = "Enter the API URL and JSON path to the image URL:"

    let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
    stackView.orientation = .vertical
    stackView.spacing = 8

    let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    urlField.placeholderString = "API URL (e.g., https://api.example.com/images)"

    let selectorField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    selectorField.placeholderString = "JSON Path (e.g., data.url)"

    if case .jsonApi(let url, let selector) = currentSource {
      urlField.stringValue = url
      selectorField.stringValue = selector
    }

    stackView.addArrangedSubview(urlField)
    stackView.addArrangedSubview(selectorField)

    alert.accessoryView = stackView
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
      let url = urlField.stringValue
      let selector = selectorField.stringValue

      if !url.isEmpty && !selector.isEmpty {
        currentSource = .jsonApi(url, selector)
        saveSettings()
        setupMenu()
        refreshWallpaper()
      }
    }
  }

  func getImageUrl() async throws -> URL {
    switch currentSource {
    case .picsum:
      // Get screen size for appropriate image dimensions
      let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1920, height: 1080)
      let width = Int(screenSize.width)
      let height = Int(screenSize.height)
      return URL(string: "https://picsum.photos/\(width)/\(height)")!

    case .staticUrl(let urlString):
      guard let url = URL(string: urlString) else {
        throw WallpaperError.invalidImageUrl(urlString: urlString)
      }
      return url

    case .jsonApi(let apiUrlString, let jsonPath):
      guard let apiUrl = URL(string: apiUrlString) else {
        throw WallpaperError.invalidImageUrl(urlString: apiUrlString)
      }

      let (data, _) = try await URLSession.shared.data(from: apiUrl)

      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw WallpaperError.invalidJsonResponse
      }

      // Parse the JSON path
      let pathComponents = jsonPath.components(separatedBy: ".")
      var currentValue: Any = json

      // Convert JSON to pretty-printed string for error reporting
      let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
      let jsonString = String(data: jsonData, encoding: .utf8) ?? "Unable to stringify JSON"

      for component in pathComponents {
        if let dict = currentValue as? [String: Any], let value = dict[component] {
          currentValue = value
        } else if let array = currentValue as? [Any], let index = Int(component),
          index < array.count
        {
          currentValue = array[index]
        } else {
          throw WallpaperError.jsonPathNotFound(path: jsonPath, json: jsonString)
        }
      }

      guard let urlString = currentValue as? String else {
        throw WallpaperError.jsonPathNotFound(
          path: jsonPath, json: jsonString + "\n\nFound value is not a string: \(currentValue)")
      }

      guard let url = URL(string: urlString) else {
        throw WallpaperError.invalidImageUrl(urlString: urlString)
      }

      return url
    }
  }

  func downloadAndSetWallpaper(from url: URL) async throws {
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw WallpaperError.downloadFailed
    }

    guard let image = NSImage(data: data) else {
      throw WallpaperError.invalidImageData
    }

    // Save image to temporary file
    let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "wallpaper-\(UUID().uuidString).jpg")

    guard let imageRep = NSBitmapImageRep(data: image.tiffRepresentation!) else {
      throw WallpaperError.imageConversionFailed
    }

    guard let jpegData = imageRep.representation(using: .jpeg, properties: [:]) else {
      throw WallpaperError.imageConversionFailed
    }

    try jpegData.write(to: tempFileURL)

    // Set as desktop wallpaper
    try NSWorkspace.shared.setDesktopImageURL(tempFileURL, for: NSScreen.main!, options: [:])

  }

}

// MARK: - Supporting Types

enum WallpaperSource {
  case picsum
  case staticUrl(String)
  case jsonApi(String, String)  // URL and JSON path
}

enum WallpaperError: Error, LocalizedError {
  case invalidUrl
  case downloadFailed
  case invalidImageData
  case imageConversionFailed
  case invalidJsonResponse
  case jsonPathNotFound(path: String, json: String)
  case invalidImageUrl(urlString: String)

  var errorDescription: String? {
    switch self {
    case .invalidUrl:
      return "Invalid URL provided"
    case .downloadFailed:
      return "Failed to download image"
    case .invalidImageData:
      return "Invalid image data received"
    case .imageConversionFailed:
      return "Failed to convert image format"
    case .invalidJsonResponse:
      return "Invalid JSON response from API"
    case .jsonPathNotFound(let path, let json):
      return "JSON path '\(path)' not found in response: \(json)"
    case .invalidImageUrl(let urlString):
      return "Invalid image URL in JSON response: '\(urlString)'"
    }
  }
}

// MARK: - Settings Persistence

extension AppDelegate {
  func saveSettings() {
    let defaults = UserDefaults.standard

    // Save refresh interval
    defaults.set(refreshInterval, forKey: kRefreshIntervalKey)

    // Save source type and related data
    switch currentSource {
    case .picsum:
      defaults.set(0, forKey: kSourceTypeKey)
    case .staticUrl(let url):
      defaults.set(1, forKey: kSourceTypeKey)
      defaults.set(url, forKey: kStaticUrlKey)
    case .jsonApi(let url, let selector):
      defaults.set(2, forKey: kSourceTypeKey)
      defaults.set(url, forKey: kJsonApiUrlKey)
      defaults.set(selector, forKey: kJsonSelectorKey)
    }

    // Save last resolved image URL
    if let lastUrl = lastResolvedImageUrl {
      defaults.set(lastUrl, forKey: kLastResolvedImageUrlKey)
    }

    // Force save to disk
    defaults.synchronize()
  }

  func loadSettings() {
    let defaults = UserDefaults.standard

    // Load refresh interval
    if defaults.object(forKey: kRefreshIntervalKey) != nil {
      refreshInterval = defaults.double(forKey: kRefreshIntervalKey)
    }

    // Load source type and related data
    if defaults.object(forKey: kSourceTypeKey) != nil {
      let sourceType = defaults.integer(forKey: kSourceTypeKey)

      switch sourceType {
      case 0:
        currentSource = .picsum
      case 1:
        if let url = defaults.string(forKey: kStaticUrlKey), !url.isEmpty {
          currentSource = .staticUrl(url)
        }
      case 2:
        if let url = defaults.string(forKey: kJsonApiUrlKey),
          let selector = defaults.string(forKey: kJsonSelectorKey),
          !url.isEmpty && !selector.isEmpty
        {
          currentSource = .jsonApi(url, selector)
        }
      default:
        break
      }
    }

    // Load last resolved image URL
    lastResolvedImageUrl = defaults.string(forKey: kLastResolvedImageUrlKey)
  }
}
