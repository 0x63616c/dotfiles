// Run locally: swift opencode/setup-jev-key.swift
// A masked prompt writes directly to Keychain; no key in argv, stdout or files.
import AppKit
import Security

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// Standalone NSApplication scripts have no default Edit menu. Without this,
// Command-V never reaches the secure field's editor even though it accepts paste.
let menu = NSMenu()
let editItem = NSMenuItem()
let edit = NSMenu(title: "Edit")
edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editItem.submenu = edit
menu.addItem(editItem)
app.mainMenu = menu

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "opencode-jev-openrouter",
    kSecAttrAccount as String: "openrouter",
]

func launcherAccess() -> (OSStatus, SecAccess?) {
    var trusted: SecTrustedApplication?
    var status = SecTrustedApplicationCreateFromPath("/usr/bin/security", &trusted)
    guard status == errSecSuccess, let trusted = trusted else { return (status, nil) }
    var access: SecAccess?
    status = SecAccessCreate("OpenCode Jev — OpenRouter" as CFString, [trusted] as CFArray, &access)
    return (status, access)
}

func authorizeLauncher() -> OSStatus {
    var lookup = query
    lookup[kSecReturnRef as String] = true
    var item: CFTypeRef?
    let found = SecItemCopyMatching(lookup as CFDictionary, &item)
    guard found == errSecSuccess, let item = item else { return found }
    let (status, access) = launcherAccess()
    guard status == errSecSuccess, let access = access else { return status }
    return SecKeychainItemSetAccess(item as! SecKeychainItem, access)
}

if CommandLine.arguments.dropFirst() == ["--authorize-launcher"] {
    let approval = NSAlert()
    approval.messageText = "Allow Jev to read its OpenRouter key?"
    approval.informativeText = "Allow the signed macOS /usr/bin/security utility to read the single OpenCode Jev key without a background approval prompt. Other Keychain items are unchanged. The key will not be displayed."
    approval.addButton(withTitle: "Allow Jev launcher")
    approval.addButton(withTitle: "Cancel")
    app.activate(ignoringOtherApps: true)
    guard approval.runModal() == .alertFirstButtonReturn else {
        print("Cancelled; Keychain access unchanged.")
        exit(1)
    }
    let status = authorizeLauncher()
    guard status == errSecSuccess else {
        print("Keychain access update failed (status \(status)); no key was printed.")
        exit(1)
    }
    print("Authorized /usr/bin/security for the Jev key only. Reconnect the Jev MCP.")
    exit(0)
}
guard CommandLine.arguments.count == 1 else {
    print("Usage: swift setup-jev-key.swift [--authorize-launcher]")
    exit(2)
}
let alert = NSAlert()
alert.messageText = "OpenRouter key for Jev"
alert.informativeText = "Enter your OpenRouter API key privately. It will be saved in macOS Keychain, not chat or Git, with /usr/bin/security allowed to read this one item for the Jev launcher. No API request is made by this prompt."
alert.addButton(withTitle: "Save to Keychain")
alert.addButton(withTitle: "Cancel")
let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
field.placeholderString = "OpenRouter API key"
alert.accessoryView = field
alert.window.initialFirstResponder = field
app.activate(ignoringOtherApps: true)
guard alert.runModal() == .alertFirstButtonReturn else {
    print("Cancelled; Keychain unchanged.")
    exit(1)
}
let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
field.stringValue = ""
guard key.hasPrefix("sk-or-"), key.count > 12, !key.contains(where: { $0.isWhitespace }) else {
    print("Not a valid OpenRouter key format; Keychain unchanged.")
    exit(1)
}
let data = Data(key.utf8)
var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
if status == errSecItemNotFound {
    var item = query
    item[kSecValueData as String] = data
    item[kSecAttrLabel as String] = "OpenCode Jev — OpenRouter"
    let (accessStatus, access) = launcherAccess()
    guard accessStatus == errSecSuccess, let access = access else {
        print("Could not prepare launcher access (status \(accessStatus)); Keychain unchanged.")
        exit(1)
    }
    item[kSecAttrAccess as String] = access
    status = SecItemAdd(item as CFDictionary, nil)
} else if status == errSecSuccess {
    status = authorizeLauncher()
}
guard status == errSecSuccess else {
    print("Keychain write failed (status \(status)); no key was printed.")
    exit(1)
}
print("Saved to Keychain. Reconnect the Jev MCP in OpenCode /mcps.")
