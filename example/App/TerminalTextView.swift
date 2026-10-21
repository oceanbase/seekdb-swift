// Copyright (c) 2025 OceanBase.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit

final class TerminalTextView: UITextView, UITextViewDelegate {
    var onSubmit: (([String], String) -> Void)?
    var onInterrupt: (() -> Void)?
    var onEndOfInput: (() -> Void)?
    var onRecall: ((Bool) -> String?)?

    private(set) var isAcceptingInput = false
    private var inputStart = 0
    private var promptText = ""
    private var fontSize: CGFloat
    private var pinchStartSize: CGFloat = 12
    private var hasShownKeyboard = false
    private static let maximumLength = 400_000
    private static let foreground = UIColor(white: 0.88, alpha: 1)

    init() {
        let saved = UserDefaults.standard.double(forKey: "fontSize")
        fontSize = saved > 0 ? CGFloat(saved) : 12
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .black
        tintColor = .white
        textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byCharWrapping
        typingAttributes = attributes
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        inlinePredictionType = .no
        keyboardAppearance = .dark
        keyboardDismissMode = .interactive
        alwaysBounceVertical = true
        dataDetectorTypes = []
        delegate = self
        inputAccessoryView = makeKeyBar()
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var undoManager: UndoManager? {
        nil
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            keyCommand(UIKeyCommand.inputUpArrow, [], #selector(recallOlder)),
            keyCommand(UIKeyCommand.inputDownArrow, [], #selector(recallNewer)),
            keyCommand("c", .control, #selector(interrupt)),
            keyCommand("d", .control, #selector(endOfInput)),
            keyCommand("l", .control, #selector(clearScreen)),
        ]
    }

    var currentInput: String {
        (textStorage.string as NSString).substring(from: inputStart)
    }

    func write(_ text: String) {
        textStorage.append(NSAttributedString(string: text, attributes: attributes))
        trimScrollback()
        scrollToEnd()
    }

    func prompt(_ prompt: String, input: String = "") {
        promptText = prompt
        write(prompt)
        inputStart = textStorage.length
        textStorage.append(NSAttributedString(string: input, attributes: attributes))
        isAcceptingInput = true
        selectedRange = NSRange(location: textStorage.length, length: 0)
        typingAttributes = attributes
        scrollToEnd()
        if !hasShownKeyboard, window != nil {
            hasShownKeyboard = true
            becomeFirstResponder()
        }
    }

    func enter(_ text: String) {
        guard isAcceptingInput else { return }
        submit(replacing: NSRange(location: textStorage.length, length: 0), with: text)
    }

    func cancelInput() {
        guard isAcceptingInput else { return }
        isAcceptingInput = false
        write("^C\n")
    }

    func finishInput() {
        isAcceptingInput = false
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard isAcceptingInput else { return false }
        let end = NSRange(location: textStorage.length, length: 0)
        if text == "\n" {
            submit(replacing: end, with: text)
            return false
        }
        if range.location < inputStart {
            if text.contains(where: \.isNewline) {
                submit(replacing: end, with: text)
            } else if !text.isEmpty {
                insert(text, at: end)
            }
            return false
        }
        if text.contains(where: \.isNewline) {
            submit(replacing: range, with: text)
            return false
        }
        return true
    }

    @objc func clearScreen() {
        guard isAcceptingInput else { return }
        let input = currentInput
        textStorage.setAttributedString(NSAttributedString(string: promptText + input, attributes: attributes))
        inputStart = (promptText as NSString).length
        selectedRange = NSRange(location: textStorage.length, length: 0)
        setContentOffset(.zero, animated: false)
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        return [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: Self.foreground,
            .paragraphStyle: style,
        ]
    }

    private func submit(replacing range: NSRange, with text: String) {
        let relative = NSRange(location: range.location - inputStart, length: range.length)
        let combined = (currentInput as NSString).replacingCharacters(in: relative, with: text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = combined.components(separatedBy: "\n")
        let remainder = lines.removeLast()
        replaceInput(with: lines[0])
        isAcceptingInput = false
        write("\n")
        onSubmit?(lines, remainder)
    }

    private func insert(_ text: String, at range: NSRange) {
        textStorage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
        selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
        scrollRangeToVisible(selectedRange)
    }

    private func replaceInput(with input: String) {
        let range = NSRange(location: inputStart, length: textStorage.length - inputStart)
        textStorage.replaceCharacters(in: range, with: NSAttributedString(string: input, attributes: attributes))
        selectedRange = NSRange(location: textStorage.length, length: 0)
    }

    private func trimScrollback() {
        let excess = textStorage.length - Self.maximumLength
        guard excess > 0 else { return }
        let string = textStorage.string as NSString
        let newline = string.range(of: "\n", options: [], range: NSRange(location: excess, length: string.length - excess))
        guard newline.location != NSNotFound, !isAcceptingInput || newline.location < inputStart else { return }
        textStorage.deleteCharacters(in: NSRange(location: 0, length: newline.location + 1))
        inputStart = max(0, inputStart - (newline.location + 1))
    }

    private func scrollToEnd() {
        scrollRangeToVisible(NSRange(location: textStorage.length, length: 0))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollRangeToVisible(NSRange(location: self.textStorage.length, length: 0))
        }
    }

    private func keyCommand(_ input: String, _ modifiers: UIKeyModifierFlags, _ action: Selector) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func recallOlder() {
        recall(older: true)
    }

    @objc private func recallNewer() {
        recall(older: false)
    }

    private func recall(older: Bool) {
        guard isAcceptingInput, let line = onRecall?(older) else { return }
        replaceInput(with: line)
        scrollToEnd()
    }

    @objc private func interrupt() {
        guard isAcceptingInput else { return }
        onInterrupt?()
    }

    @objc private func endOfInput() {
        guard isAcceptingInput, currentInput.isEmpty else { return }
        onEndOfInput?()
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartSize = fontSize
        case .changed:
            let size = min(max((pinchStartSize * gesture.scale).rounded(), 8), 24)
            guard size != fontSize else { return }
            fontSize = size
            textStorage.addAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
            typingAttributes = attributes
        case .ended, .cancelled:
            UserDefaults.standard.set(Double(fontSize), forKey: "fontSize")
        default:
            break
        }
    }

    private func makeKeyBar() -> UIView {
        let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 46), inputViewStyle: .keyboard)
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        for key in ["↑", "↓", "^C", "^L", ";", "*", "'", "\"", "`", "(", ")", ",", "=", "_", "%", "\\G"] {
            var configuration = UIButton.Configuration.filled()
            configuration.title = key
            configuration.baseBackgroundColor = UIColor(white: 0.3, alpha: 1)
            configuration.baseForegroundColor = .white
            configuration.cornerStyle = .medium
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
                return outgoing
            }
            stack.addArrangedSubview(UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.press(key)
            }))
        }
        scroll.addSubview(stack)
        bar.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.contentLayoutGuide.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6),
        ])
        return bar
    }

    private func press(_ key: String) {
        switch key {
        case "↑":
            recall(older: true)
        case "↓":
            recall(older: false)
        case "^C":
            interrupt()
        case "^L":
            clearScreen()
        default:
            guard isAcceptingInput else { return }
            let range = selectedRange.location < inputStart ? NSRange(location: textStorage.length, length: 0) : selectedRange
            insert(key, at: range)
        }
    }
}
