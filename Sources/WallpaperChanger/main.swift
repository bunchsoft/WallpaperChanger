import Cocoa
import Foundation
import ServiceManagement
import UserNotifications
import CommonCrypto

#if canImport(ServiceManagement)
  import ServiceManagement
#endif

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
  
  // Path to the current wallpaper temporary file
  private var currentWallpaperPath: URL?
  
  // Hash of the current wallpaper for change detection
  private var currentWallpaperHash: String?
  
  // Flags to track notification status
  private var notificationsAuthorized = false
  private var showMessagesEnabled = false

  // UserDefaults keys
  private let kRefreshIntervalKey = "refreshInterval"
  private let kSourceTypeKey = "sourceType"
  private let kStaticUrlKey = "staticUrl"
  private let kJsonApiUrlKey = "jsonApiUrl"
  private let kJsonSelectorKey = "jsonSelector"
  private let kLastResolvedImageUrlKey = "lastResolvedImageUrl"
  private let kLastWallpaperHashKey = "lastWallpaperHash"
  private let kRunAtLoginKey = "runAtLogin"
  private let kShowMessagesEnabledKey = "showMessagesEnabled"

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Set as accessory app (menu bar only)
    NSApp.setActivationPolicy(.accessory)
    
    // Request notification permission
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
      if let error = error {
        print("Error requesting notification authorization: \(error.localizedDescription)")
      }
      
      // Store the authorization status
      self?.notificationsAuthorized = granted
      
      if granted {
        print("Notification permission granted")
      } else {
        print("Notification permission denied")
      }
    }

    // Build a bare-bones Main Menu so that Edit→Select All, Copy, Paste, etc. actually exist.
    let mainMenu = NSMenu()

    // 1) Application menu (with Quit…)
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu(title: "App")
    appMenuItem.submenu = appMenu
    appMenu.addItem(
      withTitle: "Quit Wallpaper Changer",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )

    // 2) Edit menu (with Select All)
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editMenu
    editMenu.addItem(
      withTitle: "Select All",
      action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a"
    )
    editMenu.addItem(
      withTitle: "Copy",
      action: #selector(NSText.copy(_:)),
      keyEquivalent: "c"
    )
    editMenu.addItem(
      withTitle: "Paste",
      action: #selector(NSText.paste(_:)),
      keyEquivalent: "v"
    )

    NSApp.mainMenu = mainMenu

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
        
    menu.addItem(
      NSMenuItem(
        title: "Save Current Wallpaper", action: #selector(saveCurrentWallpaper), keyEquivalent: "s"))

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

    // Run at login option
    let runAtLoginItem = NSMenuItem(
      title: "Run at Login",
      action: #selector(toggleRunAtLogin(_:)),
      keyEquivalent: "")
    runAtLoginItem.state = isRunAtLoginEnabled() ? .on : .off
    menu.addItem(runAtLoginItem)
    
    // Show messages option
    let messagesItem = NSMenuItem(
      title: "Notify on Wallpaper Change",
      action: #selector(toggleShowMessages(_:)),
      keyEquivalent: "")
    messagesItem.state = showMessagesEnabled ? .on : .off
    menu.addItem(messagesItem)

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
          // Skip for JSON API source only if the URL is unchanged
          if case .jsonApi = currentSource {
            print("Image URL unchanged, skipping download")
            return
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
    alert.messageText = "Configure JSON API"
    alert.informativeText = "Enter the API URL and JSON path to the image URL:"

    let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
    stackView.orientation = .vertical
    stackView.spacing = 8

    let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    urlField.placeholderString = "API URL (e.g., https://api.example.com/images)"

    let selectorField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    selectorField.placeholderString = "JSON Path (e.g., data.url)"
    selectorField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

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
    
    // Store the path to the current wallpaper
    currentWallpaperPath = tempFileURL
    
    // Calculate hash of the wallpaper
    let newHash = calculateFileHash(fileURL: tempFileURL)
    
    // Check if wallpaper has changed by comparing hashes
    let wallpaperChanged = currentWallpaperHash != newHash
    
    // Update current hash
    currentWallpaperHash = newHash
    
    // Save the hash to UserDefaults
    UserDefaults.standard.set(newHash, forKey: kLastWallpaperHashKey)
    
    // Set as desktop wallpaper
    try NSWorkspace.shared.setDesktopImageURL(tempFileURL, for: NSScreen.main!, options: [:])
    
    // Show notification if wallpaper has changed (and it's not the first run)
    if wallpaperChanged && UserDefaults.standard.object(forKey: kLastWallpaperHashKey) != nil {
      // Show notification on the main thread
      await MainActor.run {
        self.showSuccessMessage(message: "Wallpaper has been updated", title: "Wallpaper Changed")
      }
    }
  }
  
  @objc func saveCurrentWallpaper() {
    guard let currentWallpaperPath = currentWallpaperPath else {
      // Show an alert if there's no current wallpaper
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "No Wallpaper Available"
      alert.informativeText = "There is no current wallpaper to save."
      alert.addButton(withTitle: "OK")
      alert.runModal()
      return
    }
    
    // Get the Downloads directory
    guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
      // Show an alert if we can't access the Downloads directory
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Cannot Access Downloads Folder"
      alert.informativeText = "Unable to access your Downloads folder."
      alert.addButton(withTitle: "OK")
      alert.runModal()
      return
    }
    
    // Create a filename with timestamp
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
    let timestamp = dateFormatter.string(from: Date())
    let destinationURL = downloadsURL.appendingPathComponent("wallpaper-\(timestamp).jpg")
    
    do {
      // Copy the file to the Downloads directory
      try FileManager.default.copyItem(at: currentWallpaperPath, to: destinationURL)
      
      // Always show success message for saves, regardless of message preference
      self.alwaysShowMessage(message: "Current wallpaper saved to Downloads folder", title: "Wallpaper Saved")
    } catch {
      // Show an alert if the save fails
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Save Failed"
      alert.informativeText = "Failed to save wallpaper: \(error.localizedDescription)"
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  // Calculate a simple hash of a file based on its size and modification date
  private func calculateFileHash(fileURL: URL) -> String {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      let fileSize = attributes[.size] as? UInt64 ?? 0
      let modificationDate = attributes[.modificationDate] as? Date ?? Date()
      
      // Create a hash from the file size and modification date
      let hashString = "\(fileSize)-\(modificationDate.timeIntervalSince1970)"
      return hashString
    } catch {
      print("Error calculating file hash: \(error.localizedDescription)")
      return UUID().uuidString // Fallback to a random string if hash calculation fails
    }
  }
  
  @objc func toggleShowMessages(_ sender: NSMenuItem) {
    // Toggle the state
    showMessagesEnabled = !showMessagesEnabled
    
    // Update the menu item state
    sender.state = showMessagesEnabled ? .on : .off
    
    // Save the preference
    UserDefaults.standard.set(showMessagesEnabled, forKey: kShowMessagesEnabledKey)
    UserDefaults.standard.synchronize()
  }
  
  // Helper method to always show a message, regardless of user preference
  private func alwaysShowMessage(message: String, title: String) {
    if notificationsAuthorized {
      // Show a success notification using UserNotifications framework
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = message
      content.sound = UNNotificationSound.default
      
      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
          print("Error showing notification: \(error.localizedDescription)")
          
          // Fall back to alert if notification fails
          DispatchQueue.main.async {
            self.showSuccessAlert(message: message, title: title)
          }
        }
      }
    } else {
      // Fall back to alert if notifications aren't authorized
      DispatchQueue.main.async {
        self.showSuccessAlert(message: message, title: title)
      }
    }
  }
  
  // Helper method to show success message either as notification or alert, respecting user preference
  private func showSuccessMessage(message: String, title: String) {
    // Only show messages if enabled
    if !showMessagesEnabled {
      return
    }
    
    if notificationsAuthorized {
      // Show a success notification using UserNotifications framework
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = message
      content.sound = UNNotificationSound.default
      
      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
          print("Error showing notification: \(error.localizedDescription)")
          
          // Fall back to alert if notification fails
          DispatchQueue.main.async {
            self.showSuccessAlert(message: message, title: title)
          }
        }
      }
    } else {
      // Fall back to alert if notifications aren't authorized
      DispatchQueue.main.async {
        self.showSuccessAlert(message: message, title: title)
      }
    }
  }
  
  // Helper method to show success alert
  private func showSuccessAlert(message: String, title: String) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
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

// MARK: - Login Item Management

extension AppDelegate {
  @objc func toggleRunAtLogin(_ sender: NSMenuItem) {
    let currentState = isRunAtLoginEnabled()
    let newState = !currentState

    let success = setLoginItemEnabled(newState)

    if success {
      // Update UserDefaults
      UserDefaults.standard.set(newState, forKey: kRunAtLoginKey)

      // Update menu item state
      sender.state = newState ? .on : .off
    } else {
      // Show error alert
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Login Item Error"
      alert.informativeText =
        "Failed to \(newState ? "add" : "remove") Wallpaper Changer from login items."
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }

  func isRunAtLoginEnabled() -> Bool {
    // First check our saved preference
    if UserDefaults.standard.object(forKey: kRunAtLoginKey) != nil {
      return UserDefaults.standard.bool(forKey: kRunAtLoginKey)
    }

    // Otherwise check actual registration status
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    } else {
      // For older macOS versions, just return the saved preference or false
      return UserDefaults.standard.bool(forKey: kRunAtLoginKey)
    }
  }

  func setLoginItemEnabled(_ enabled: Bool) -> Bool {
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
        return true
      } catch {
        print("Failed to \(enabled ? "register" : "unregister") login item: \(error)")
        return false
      }
    } else {
      // For older macOS versions, use the legacy approach
      // This is a simplified implementation that just saves the preference
      // In a real app, you would use LSSharedFileList API for older macOS versions
      UserDefaults.standard.set(enabled, forKey: kRunAtLoginKey)
      return true
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

    // Check if we need to register for login
    if defaults.bool(forKey: kRunAtLoginKey) {
      // Try to register for login at startup
      _ = setLoginItemEnabled(true)
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
    
    // Load last wallpaper hash
    currentWallpaperHash = defaults.string(forKey: kLastWallpaperHashKey)
    
    // Load show messages preference (default to false)
    showMessagesEnabled = defaults.bool(forKey: kShowMessagesEnabledKey)
  }
}
