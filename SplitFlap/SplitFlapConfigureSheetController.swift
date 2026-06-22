import AppKit

final class SplitFlapConfigureSheetController: NSObject, NSWindowDelegate {
    private var configuration: SplitFlapConfiguration
    private let onSave: (SplitFlapConfiguration) -> Void

    let window: NSWindow
    var onClose: (() -> Void)?

    private let modePopup = NSPopUpButton()
    private let messageTextView = NSTextView()
    private let orderPopup = NSPopUpButton()
    private let waveSlider = NSSlider(value: 8, minValue: 2, maxValue: 60, target: nil, action: nil)
    private let waveValueLabel = NSTextField(labelWithString: "")
    private let idleShuffleButton = NSButton(checkboxWithTitle: "Shuffle idle panels between waves", target: nil, action: nil)
    private let idleDensitySlider = NSSlider(value: 0.04, minValue: 0, maxValue: 0.2, target: nil, action: nil)
    private let idleDensityValueLabel = NSTextField(labelWithString: "")
    private let rowsSlider = NSSlider(value: 9, minValue: 4, maxValue: 24, target: nil, action: nil)
    private let rowsValueLabel = NSTextField(labelWithString: "")
    private let themePopup = NSPopUpButton()

    init(configuration: SplitFlapConfiguration, onSave: @escaping (SplitFlapConfiguration) -> Void) {
        self.configuration = configuration
        self.onSave = onSave
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init()
        buildWindow()
        loadConfiguration()
    }

    private func buildWindow() {
        window.title = "Flapline Options"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        modePopup.addItems(withTitles: SplitFlapDisplayMode.allCases.map(\.title))
        orderPopup.addItems(withTitles: SplitFlapMessageOrder.allCases.map(\.title))
        themePopup.addItems(withTitles: SplitFlapTheme.allCases.map(\.title))

        messageTextView.minSize = NSSize(width: 0, height: 120)
        messageTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        messageTextView.isVerticallyResizable = true
        messageTextView.isHorizontallyResizable = false
        messageTextView.autoresizingMask = [.width]
        messageTextView.textContainer?.containerSize = NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
        messageTextView.textContainer?.widthTracksTextView = true
        messageTextView.font = .systemFont(ofSize: 13)
        messageTextView.frame = NSRect(x: 0, y: 0, width: 500, height: 120)

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = messageTextView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 130).isActive = true
        scrollView.widthAnchor.constraint(equalToConstant: 500).isActive = true

        [waveSlider, idleDensitySlider, rowsSlider].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.target = self
            $0.action = #selector(sliderChanged(_:))
            $0.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }

        stack.addArrangedSubview(row(label: "Display", control: modePopup))
        stack.addArrangedSubview(labeledBlock(label: "Messages", control: scrollView))
        stack.addArrangedSubview(row(label: "Message order", control: orderPopup))
        stack.addArrangedSubview(sliderRow(label: "Wave interval", slider: waveSlider, valueLabel: waveValueLabel))
        stack.addArrangedSubview(idleShuffleButton)
        stack.addArrangedSubview(sliderRow(label: "Idle density", slider: idleDensitySlider, valueLabel: idleDensityValueLabel))
        stack.addArrangedSubview(sliderRow(label: "Board rows", slider: rowsSlider, valueLabel: rowsValueLabel))
        stack.addArrangedSubview(row(label: "Theme", control: themePopup))

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        let save = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        save.keyEquivalent = "\r"
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(save)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        stack.addArrangedSubview(buttons)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])
    }

    private func loadConfiguration() {
        modePopup.selectItem(at: SplitFlapDisplayMode.allCases.firstIndex(of: configuration.displayMode) ?? 0)
        messageTextView.string = configuration.messageText
        orderPopup.selectItem(at: SplitFlapMessageOrder.allCases.firstIndex(of: configuration.messageOrder) ?? 0)
        waveSlider.doubleValue = configuration.waveIntervalSeconds
        idleShuffleButton.state = configuration.idleShuffleEnabled ? .on : .off
        idleDensitySlider.doubleValue = configuration.idleDensity
        rowsSlider.integerValue = configuration.targetRows
        themePopup.selectItem(at: SplitFlapTheme.allCases.firstIndex(of: configuration.theme) ?? 0)
        updateValueLabels()
    }

    private func row(label: String, control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func sliderRow(label: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true
        return row(label: label, control: NSStackView(views: [slider, valueLabel]))
    }

    private func labeledBlock(label: String, control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        let block = NSStackView(views: [labelView, control])
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 6
        return block
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        updateValueLabels()
    }

    private func updateValueLabels() {
        waveValueLabel.stringValue = "\(Int(waveSlider.doubleValue.rounded())) sec"
        idleDensityValueLabel.stringValue = "\(Int((idleDensitySlider.doubleValue * 100).rounded()))%"
        rowsValueLabel.stringValue = "\(rowsSlider.integerValue)"
    }

    @objc private func save(_ sender: Any?) {
        configuration.displayMode = SplitFlapDisplayMode.allCases[safe: modePopup.indexOfSelectedItem] ?? .messages
        configuration.messageText = messageTextView.string
        configuration.messageOrder = SplitFlapMessageOrder.allCases[safe: orderPopup.indexOfSelectedItem] ?? .sequential
        configuration.waveIntervalSeconds = waveSlider.doubleValue.rounded()
        configuration.idleShuffleEnabled = idleShuffleButton.state == .on
        configuration.idleDensity = idleDensitySlider.doubleValue
        configuration.targetRows = rowsSlider.integerValue
        configuration.theme = SplitFlapTheme.allCases[safe: themePopup.indexOfSelectedItem] ?? .classic

        onSave(configuration)
        closeSheet()
    }

    @objc private func cancel(_ sender: Any?) {
        closeSheet()
    }

    private func closeSheet() {
        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
