//
// APFilterTextField.swift
// APFilterTextField
//
// Created by Akash on 25/07/26.
//

import UIKit

// MARK: - Delegate

public protocol APFilterFieldDelegate: AnyObject {
    func filterField(_ field: APFilterField, didSelect option: FieldOption)
    func filterField(_ field: APFilterField, didChangeText text: String)
    func filterField(_ field: APFilterField, shouldSelect option: FieldOption) -> Bool
    func filterField(_ field: APFilterField, didShowOptions options: [FieldOption])
    func filterField(_ field: APFilterField, didDismissOptions options: [FieldOption])
}

public extension APFilterFieldDelegate {
    func filterField(_ field: APFilterField, didChangeText text: String) {}
    func filterField(_ field: APFilterField, shouldSelect option: FieldOption) -> Bool { return true }
    func filterField(_ field: APFilterField, didShowOptions options: [FieldOption]) {}
    func filterField(_ field: APFilterField, didDismissOptions options: [FieldOption]) {}
}

// MARK: - APFilterField

@available(iOS 9.0, *)
@IBDesignable
open class APFilterField: UITextField {
    
    // MARK: - Public Properties
    
    public var options: [FieldOption] = []
    
    @IBInspectable public var showsOnFocus: Bool = true
    @IBInspectable public var fillsOnSelect: Bool = true
    @IBInspectable public var dismissesOnSelect: Bool = true
    
    public weak var filterDelegate: APFilterFieldDelegate?
    
    // MARK: - IBInspectables (Appearance)
    
    @IBInspectable public var fieldCornerRadius: CGFloat = 13 {
        didSet { layer.cornerRadius = fieldCornerRadius }
    }
    
    @IBInspectable public var fieldBorderWidth: CGFloat = 1 {
        didSet { layer.borderWidth = fieldBorderWidth }
    }
    
    @IBInspectable public var fieldBorderColor: UIColor = UIColor(red: 228/255, green: 225/255, blue: 237/255, alpha: 1.0) {
        didSet { layer.borderColor = fieldBorderColor.cgColor }
    }
    
    @IBInspectable public var fieldBackgroundColor: UIColor = .white {
        didSet { backgroundColor = fieldBackgroundColor }
    }
    
    @IBInspectable public var fieldTextColor: UIColor = UIColor(red: 26/255, green: 23/255, blue: 38/255, alpha: 1.0) {
        didSet { textColor = fieldTextColor }
    }
    
    @IBInspectable public var filterItemFont: UIFont = .systemFont(ofSize: 15, weight: .regular) {
        didSet { floatingFilterView.font = filterItemFont }
    }
    
    @IBInspectable public var dropdownCornerRadius: CGFloat = 13 {
        didSet { floatingFilterView.dropdownCornerRadius = dropdownCornerRadius }
    }
    
    @IBInspectable public var dropdownBorderColor: UIColor = .init(red: 228/255, green: 225/255, blue: 237/255, alpha: 1) {
        didSet { floatingFilterView.dropdownBorderColor = dropdownBorderColor }
    }
    
    public var numberOfCellsToShow: CGFloat = 4 {
        didSet { floatingFilterView.numberOfCellsToShow = numberOfCellsToShow }
    }
    
    public var numberOfCellsToShowInLandscape: CGFloat = 2 {
        didSet { floatingFilterView.numberOfCellsToShowInLandscape = numberOfCellsToShowInLandscape }
    }
    
    /// Color for the user-typed portion in dropdown cells (default: gray).
    /// The remaining predicted text uses the normal `fieldTextColor`.
    @IBInspectable public var typeAheadHighlightColor: UIColor = .gray {
        didSet { floatingFilterView.typeAheadHighlightColor = typeAheadHighlightColor }
    }
    
    // MARK: - Internal
    
    let floatingFilterView = FloatingFilterView()
    nonisolated(unsafe) private var keyboardObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var textDidChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var orientationObserver: NSObjectProtocol?
    private var currentPlacement: FilterPlacement = .below
    
    private static let filterGap: CGFloat = 4
    private static let keyboardGap: CGFloat = 12
    
    // MARK: - Init
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    deinit {
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let observer = textDidChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Setup
    
    private func setup() {
        layer.cornerRadius = fieldCornerRadius
        layer.borderWidth = fieldBorderWidth
        layer.borderColor = fieldBorderColor.cgColor
        backgroundColor = fieldBackgroundColor
        textColor = fieldTextColor
        floatingFilterView.font = filterItemFont
        floatingFilterView.dropdownCornerRadius = dropdownCornerRadius
        floatingFilterView.dropdownBorderColor = dropdownBorderColor
        floatingFilterView.numberOfCellsToShow = numberOfCellsToShow
        floatingFilterView.numberOfCellsToShowInLandscape = numberOfCellsToShowInLandscape
        floatingFilterView.typeAheadHighlightColor = typeAheadHighlightColor
        
        floatingFilterView.delegate = self
        setupKeyboardObservers()
        setupTextDidChangeObserver()
        setupOrientationObserver()
    }
    
    private func setupTextDidChangeObserver() {
        textDidChangeObserver = NotificationCenter.default.addObserver(
            forName: {
#if swift(>=4.2)
                return UITextField.textDidChangeNotification
#else
                return .UITextFieldTextDidChange
#endif
            }(),
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let currentText = self.text ?? ""
            self.floatingFilterView.filter(with: currentText)
            if !self.floatingFilterView.isOpen {
                self.showFilterView()
            }
            self.filterDelegate?.filterField(self, didChangeText: currentText)
        }
    }

    private func setupOrientationObserver() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: {
#if swift(>=4.2)
                return UIDevice.orientationDidChangeNotification
#else
                return NSNotification.Name.UIDeviceOrientationDidChange
#endif
            }(),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isFirstResponder else { return }
            self.resignFirstResponder()
        }
    }

    
    private func setupKeyboardObservers() {
#if swift(>=4.2)
        let keyboardFrameUserInfoKey = UIResponder.keyboardFrameEndUserInfoKey
        let keyboardAnimationDurationUserInfoKey = UIResponder.keyboardAnimationDurationUserInfoKey
        let keyboardAnimationCurveUserInfoKey = UIResponder.keyboardAnimationCurveUserInfoKey
#else
        let keyboardFrameUserInfoKey = UIKeyboardFrameEndUserInfoKey
        let keyboardAnimationDurationUserInfoKey = UIKeyboardAnimationDurationUserInfoKey
        let keyboardAnimationCurveUserInfoKey = UIKeyboardAnimationCurveUserInfoKey
#endif
        
        let showObserver = NotificationCenter.default.addObserver(
            forName: {
#if swift(>=4.2)
                return UIResponder.keyboardWillShowNotification
#else
                return .UIKeyboardWillShow
#endif
            }(),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  self.isFirstResponder,
                  self.window != nil,
                  let keyboardFrame = notification.userInfo?[keyboardFrameUserInfoKey] as? CGRect,
                  let vc = self.findViewController(),
                  let rootView = vc.view else { return }
            
            let duration = (notification.userInfo?[keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            let curveRaw = (notification.userInfo?[keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
            let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
            
            rootView.transform = .identity
            
            let tfFrameInWindow = self.convert(self.bounds, to: nil)
            let tfBottom = tfFrameInWindow.maxY
            let tfTop = tfFrameInWindow.minY
            let keyboardTop = keyboardFrame.minY
            let neededSpace = self.floatingFilterView.effectiveMaxHeight + Self.filterGap
            
            var shift: CGFloat = 0
            
            if tfBottom >= keyboardTop {
                self.currentPlacement = .above
                shift = tfBottom - keyboardTop + Self.keyboardGap
                let spaceAbove = tfTop - shift
                if spaceAbove < neededSpace {
                    shift += (neededSpace - spaceAbove)
                }
            } else {
                self.currentPlacement = .below
                let availableSpaceBelow = keyboardTop - tfBottom
                if availableSpaceBelow < neededSpace + Self.keyboardGap {
                    shift = neededSpace + Self.keyboardGap - availableSpaceBelow
                }
            }
            
            UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
                rootView.transform = CGAffineTransform(translationX: 0, y: -shift)
            })
            
            self.floatingFilterView.reposition(placement: self.currentPlacement)
        }
        
        let hideObserver = NotificationCenter.default.addObserver(
            forName: {
#if swift(>=4.2)
                return UIResponder.keyboardWillHideNotification
#else
                return .UIKeyboardWillHide
#endif
            }(),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let vc = self.findViewController(),
                  let rootView = vc.view else { return }
            
            let duration = (notification.userInfo?[keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            let curveRaw = (notification.userInfo?[keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
            let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
            
            UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
                rootView.transform = .identity
            })
        }
        
        keyboardObservers = [showObserver, hideObserver]
    }
    
    // MARK: - First Responder
    
    @discardableResult
    open override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result && showsOnFocus {
            showFilterView()
        }
        return result
    }
    
    @discardableResult
    open override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            floatingFilterView.forceHide()
        }
        return result
    }
    
    // MARK: - Filter View
    
    private func showFilterView() {
        guard let vc = findViewController(), vc.view != nil else { return }
        
        reloadOptions()
        
        if !floatingFilterView.isOpen {
            floatingFilterView.show(above: self, placement: currentPlacement)
        } else {
            floatingFilterView.reposition(placement: currentPlacement)
        }
    }
    
    private func hideFilterView() {
        floatingFilterView.hide()
    }
    
    private func showFilterBelow() {
        if floatingFilterView.isOpen {
            floatingFilterView.reposition(placement: currentPlacement)
        }
    }

    public func reloadOptions() {
        floatingFilterView.configure(options: options)
        floatingFilterView.filter(with: text ?? "")
    }
    
    // MARK: - Helpers
    
    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}

// MARK: - FloatingFilterDelegate

extension APFilterField: FloatingFilterDelegate {
    func floatingFilter(_ filter: FloatingFilterView, didSelect option: FieldOption) {
        let shouldProceed = filterDelegate?.filterField(self, shouldSelect: option) ?? true
        guard shouldProceed else { return }
        
        if fillsOnSelect {
            text = option.value
        }
        filterDelegate?.filterField(self, didSelect: option)
        if dismissesOnSelect {
            resignFirstResponder()
        }
    }
    
    func floatingFilterDidShow(_ filter: FloatingFilterView) {
        filterDelegate?.filterField(self, didShowOptions: options)
    }
    
    func floatingFilterDidDismiss(_ filter: FloatingFilterView) {
        resignFirstResponder()
        filterDelegate?.filterField(self, didDismissOptions: options)
    }
}
