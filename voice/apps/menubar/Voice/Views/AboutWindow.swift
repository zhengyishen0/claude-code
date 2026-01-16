import Cocoa

class AboutWindowController: NSWindowController {

    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Voca"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        guard let window = window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true

        // Icon
        let iconView = NSImageView(frame: NSRect(x: 110, y: 240, width: 80, height: 80))
        if let icon = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Voca") {
            let config = NSImage.SymbolConfiguration(pointSize: 60, weight: .regular)
            iconView.image = icon.withSymbolConfiguration(config)
            iconView.contentTintColor = .labelColor
        }
        contentView.addSubview(iconView)

        // App name
        let nameLabel = NSTextField(labelWithString: "Voca")
        nameLabel.frame = NSRect(x: 0, y: 200, width: 300, height: 30)
        nameLabel.alignment = .center
        nameLabel.font = NSFont.boldSystemFont(ofSize: 20)
        contentView.addSubview(nameLabel)

        // Tagline
        let taglineLabel = NSTextField(labelWithString: "Voice-to-text for macOS")
        taglineLabel.frame = NSRect(x: 0, y: 175, width: 300, height: 20)
        taglineLabel.alignment = .center
        taglineLabel.font = NSFont.systemFont(ofSize: 13)
        taglineLabel.textColor = .secondaryLabelColor
        contentView.addSubview(taglineLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.frame = NSRect(x: 0, y: 155, width: 300, height: 16)
        versionLabel.alignment = .center
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        contentView.addSubview(versionLabel)

        // Created by
        let createdByLabel = NSTextField(labelWithString: "Created by")
        createdByLabel.frame = NSRect(x: 0, y: 115, width: 300, height: 16)
        createdByLabel.alignment = .center
        createdByLabel.font = NSFont.systemFont(ofSize: 12)
        createdByLabel.textColor = .secondaryLabelColor
        contentView.addSubview(createdByLabel)

        // Author link
        let authorButton = NSButton(frame: NSRect(x: 75, y: 90, width: 150, height: 22))
        authorButton.title = "Zhengyi Shen"
        authorButton.bezelStyle = .inline
        authorButton.isBordered = false
        authorButton.contentTintColor = .linkColor
        authorButton.font = NSFont.systemFont(ofSize: 13)
        authorButton.target = self
        authorButton.action = #selector(openAuthorLink)
        contentView.addSubview(authorButton)

        // GitHub link
        let githubButton = NSButton(frame: NSRect(x: 75, y: 50, width: 150, height: 22))
        githubButton.title = "View on GitHub"
        githubButton.bezelStyle = .inline
        githubButton.isBordered = false
        githubButton.contentTintColor = .linkColor
        githubButton.font = NSFont.systemFont(ofSize: 12)
        githubButton.target = self
        githubButton.action = #selector(openGitHub)
        contentView.addSubview(githubButton)

        // License
        let licenseLabel = NSTextField(labelWithString: "MIT License")
        licenseLabel.frame = NSRect(x: 0, y: 30, width: 300, height: 16)
        licenseLabel.alignment = .center
        licenseLabel.font = NSFont.systemFont(ofSize: 11)
        licenseLabel.textColor = .tertiaryLabelColor
        contentView.addSubview(licenseLabel)

        window.contentView = contentView
    }

    @objc private func openAuthorLink() {
        if let url = URL(string: "https://github.com/zhengyishen") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/anthropics/claude-code") {
            NSWorkspace.shared.open(url)
        }
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
