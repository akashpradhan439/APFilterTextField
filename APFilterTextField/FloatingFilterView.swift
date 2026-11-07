//
// FloatingFilterView.swift
// APFilterTextfield
//
// Created by Akash on 23/07/26.
//

import UIKit

// MARK: - Delegate

protocol FloatingFilterDelegate: AnyObject {
    func floatingFilter(_ filter: FloatingFilterView, didSelect option: FieldOption)
    func floatingFilterDidShow(_ filter: FloatingFilterView)
    func floatingFilterDidDismiss(_ filter: FloatingFilterView)
}

extension FloatingFilterDelegate {
    func floatingFilterDidShow(_ filter: FloatingFilterView) {}
    func floatingFilterDidDismiss(_ filter: FloatingFilterView) {}
}

// MARK: - Placement

enum FilterPlacement {
    case above
    case below
}

// MARK: - FloatingFilterView

final class FloatingFilterView: UIView, UIGestureRecognizerDelegate {
    
    weak var delegate: FloatingFilterDelegate?
    
    var numberOfCellsToShow: CGFloat = 4
    var numberOfCellsToShowInLandscape: CGFloat = 2
    var dropdownCornerRadius: CGFloat = 13
    var dropdownBorderColor: UIColor = .init(red: 228/255, green: 225/255, blue: 237/255, alpha: 1.0)
    var dropdownBorderWidth: CGFloat = 1.0
    var rowHeight: CGFloat = 44
    var font: UIFont = .systemFont(ofSize: 15, weight: .regular)
    var textColor: UIColor = .init(red: 26/255, green: 23/255, blue: 38/255, alpha: 1.0)
    var separatorColor: UIColor = .init(red: 236/255, green: 234/255, blue: 242/255, alpha: 1.0)
    var dropdownShadowColor: UIColor = .black
    var dropdownShadowOpacity: Float = 0.22
    var dropdownShadowRadius: CGFloat = 5
    var dropdownShadowOffset: CGSize = CGSize(width: 0, height: 2)
    var typeAheadHighlightColor: UIColor = .gray
    
    private(set) var isOpen = false
    
    // MARK: - Private
    
    private var options: [FieldOption] = []
    private var filteredOptions: [FieldOption] = []
    private var currentFilterText: String = ""
    private weak var anchorView: UIView?
    private var containerView: UIView?
    private var containerTapGesture: UITapGestureRecognizer?
    private var containerPanGesture: UIPanGestureRecognizer?
    private var heightConstraint: NSLayoutConstraint?
    private var shadowHeightConstraint: NSLayoutConstraint?
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private var leadingConstraint: NSLayoutConstraint?
    private var placement: FilterPlacement = .below
    private var trailingConstraint: NSLayoutConstraint?
    private var arrowLeadingConstraint: NSLayoutConstraint?
    private var arrowTopConstraint: NSLayoutConstraint?
    private var arrowBottomConstraint: NSLayoutConstraint?
    private var minWidthConstraint: NSLayoutConstraint?
#if swift(>=6.0)
    nonisolated(unsafe) private var keyboardObservers: [NSObjectProtocol] = []
#else
    private var keyboardObservers: [NSObjectProtocol] = []
#endif
    
    private let gap: CGFloat = 4
    private let arrowSize: CGFloat = 14
    
    private lazy var shadowBackingView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .white
        view.layer.cornerRadius = dropdownCornerRadius
        view.layer.shadowColor = dropdownShadowColor.cgColor
        view.layer.shadowOpacity = dropdownShadowOpacity
        view.layer.shadowRadius = dropdownShadowRadius
        view.layer.shadowOffset = dropdownShadowOffset
        view.clipsToBounds = false
        view.isUserInteractionEnabled = false
        return view
    }()
    
    private lazy var arrowView: UIView = {
        let size = arrowSize
        let width = size * 2
        let view = UIView(frame: CGRect(x: 0, y: 0, width: width, height: size))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        
        let tipRadius: CGFloat = size * 0.3  // rounding at the tip
        
        // Build path: triangle with rounded tip, sharp bottom corners
        func buildPath() -> UIBezierPath {
            let p = UIBezierPath()
            
            // Start at bottom-left corner (sharp)
            p.move(to: CGPoint(x: 0, y: size))
            
            // Left edge straight up toward the tip
            p.addLine(to: CGPoint(x: size - tipRadius, y: tipRadius * 0.55))
            
            // Rounded tip
            p.addQuadCurve(
                to: CGPoint(x: size + tipRadius, y: tipRadius * 0.55),
                controlPoint: CGPoint(x: size, y: -tipRadius * 0.35)
            )
            
            // Right edge straight down to bottom-right corner (sharp)
            p.addLine(to: CGPoint(x: width, y: size))
            
            return p
        }
        
        // Closed path for fill and shadow
        let fillPath = buildPath()
        fillPath.close()
        
        // Fill layer — closed path, no stroke
        let fillLayer = CAShapeLayer()
        fillLayer.fillColor = UIColor.white.cgColor
        fillLayer.strokeColor = nil
        fillLayer.path = fillPath.cgPath
        
        // Open path for stroke — only the side edges and tip, no bottom line
        let strokePath = buildPath()
        // NOT closed — bottom edge has no stroke
        
        // Stroke layer — open path, no fill
        let strokeLayer = CAShapeLayer()
        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = dropdownBorderColor.cgColor
        strokeLayer.lineWidth = dropdownBorderWidth
#if swift(>=4.2)
        strokeLayer.lineJoin = .round
        strokeLayer.lineCap = .round
#else
        strokeLayer.lineJoin = kCALineJoinRound
        strokeLayer.lineCap = kCALineCapRound
#endif
        strokeLayer.path = strokePath.cgPath
        
        view.layer.addSublayer(fillLayer)
        view.layer.addSublayer(strokeLayer)
        
        return view
    }()
    
    internal var effectiveMaxHeight: CGFloat {
        let isLandscape: Bool = UIApplication.shared.statusBarOrientation.isLandscape
        let count = isLandscape ? numberOfCellsToShowInLandscape : numberOfCellsToShow
        return count * rowHeight
    }
    
    private var tableViewHeight: CGFloat {
        return min(effectiveMaxHeight, CGFloat(filteredOptions.count) * rowHeight)
    }
    
    // MARK: - Table
    
    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.layer.cornerRadius = dropdownCornerRadius
        tv.layer.borderWidth = dropdownBorderWidth
        tv.layer.borderColor = dropdownBorderColor.cgColor
        tv.clipsToBounds = true
        tv.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tv.separatorColor = separatorColor
        tv.rowHeight = rowHeight
        tv.backgroundColor = .white
        tv.dataSource = self
        tv.delegate = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "FloatingOptionCell")
        return tv
    }()
    
    // MARK: - Init
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupKeyboardObservers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeyboardObservers()
    }
    
    deinit {
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    // MARK: - API
    
    func configure(options: [FieldOption]) {
        self.options = options
        self.filteredOptions = options
        tableView.reloadData()
    }
    
    func filter(with text: String) {
        currentFilterText = text
        if !text.isEmpty {
            filteredOptions = options.filter { $0.value.localizedCaseInsensitiveContains(text) }
        }else {
            filteredOptions = options
        }
        tableView.reloadData()
        updateHeight()
    }
    
    func show(above anchorView: UIView, placement: FilterPlacement = .below) {
        self.anchorView = anchorView
        self.placement = placement
        guard let window = anchorView.window else { return }
        
        forceRemoveContainer()
        isOpen = true
        
        let container = PassthroughContainerView(frame: window.bounds)
        container.backgroundColor = .clear
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.anchorView = anchorView
        self.containerView = container
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleContainerTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        container.addGestureRecognizer(tap)
        self.containerTapGesture = tap
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleContainerPan))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        container.addGestureRecognizer(pan)
        self.containerPanGesture = pan
        
        container.addSubview(shadowBackingView)
        container.addSubview(tableView)
        container.addSubview(arrowView)
        window.addSubview(container)
        
        applyPositionConstraints()
        
        // Pin shadow backing to match tableView edges
        NSLayoutConstraint.activate([
            shadowBackingView.topAnchor.constraint(equalTo: tableView.topAnchor),
            shadowBackingView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            shadowBackingView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
        ])
        shadowHeightConstraint = shadowBackingView.heightAnchor.constraint(equalTo: tableView.heightAnchor)
        shadowHeightConstraint?.isActive = true
        
        let minWidth = tableView.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
        minWidth.isActive = true
        minWidthConstraint = minWidth
        
        heightConstraint = tableView.heightAnchor.constraint(equalToConstant: tableViewHeight)
        heightConstraint?.isActive = true
        
        containerView?.layoutIfNeeded()
        
        tableView.alpha = 0
        arrowView.alpha = 0
        shadowBackingView.alpha = 0
        UIView.animate(withDuration: 0.2, animations: {
            self.tableView.alpha = 1
            self.arrowView.alpha = 1
            self.shadowBackingView.alpha = 1
        }, completion: { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.floatingFilterDidShow(strongSelf)
        })
    }
    
    func hide() {
        guard isOpen else { return }
        isOpen = false
        
        let containerSnapshot = containerView
        UIView.animate(withDuration: 0.15, animations: {
            self.tableView.alpha = 0
            self.arrowView.alpha = 0
            self.shadowBackingView.alpha = 0
        }, completion: { [weak self] _ in
            guard let strongSelf = self, strongSelf.containerView === containerSnapshot else { return }
            strongSelf.teardownContainer()
            strongSelf.delegate?.floatingFilterDidDismiss(strongSelf)
        })
    }
    
    func forceHide() {
        guard isOpen else { return }
        isOpen = false
        teardownContainer()
        delegate?.floatingFilterDidDismiss(self)
    }
    
    func toggle(above anchorView: UIView) {
        isOpen ? hide() : show(above: anchorView)
    }
    
    // MARK: - Private Helpers
    
    private func forceRemoveContainer() {
        containerView?.layer.removeAllAnimations()
        tableView.layer.removeAllAnimations()
        teardownContainer()
    }
    
    private func teardownContainer() {
#if swift(>=4.1)
        NSLayoutConstraint.deactivate([
            topConstraint,
            bottomConstraint,
            leadingConstraint,
            trailingConstraint,
            heightConstraint,
            shadowHeightConstraint,
            minWidthConstraint
        ].compactMap { $0 })
#else
        NSLayoutConstraint.deactivate([
            topConstraint,
            bottomConstraint,
            leadingConstraint,
            trailingConstraint,
            heightConstraint,
            shadowHeightConstraint,
            minWidthConstraint
        ].flatMap { $0 })
#endif
        containerView?.removeFromSuperview()
        containerView = nil
        containerTapGesture = nil
        containerPanGesture = nil
        heightConstraint = nil
        shadowHeightConstraint = nil
        topConstraint = nil
        bottomConstraint = nil
        leadingConstraint = nil
        trailingConstraint = nil
        minWidthConstraint = nil
    }
    
    // MARK: - Repositioning
    
    func reposition(placement: FilterPlacement? = nil) {
        if let p = placement { self.placement = p }
        guard isOpen, let anchorView = anchorView, let _ = anchorView.window else { return }
        
        deactivatePositionConstraints()
        applyPositionConstraints()
        updateHeight(animated: false)
    }
    
    private func deactivatePositionConstraints() {
        topConstraint?.isActive = false
        bottomConstraint?.isActive = false
        leadingConstraint?.isActive = false
        trailingConstraint?.isActive = false
        topConstraint = nil
        bottomConstraint = nil
        leadingConstraint = nil
        trailingConstraint = nil
        deactivateArrowConstraints()
    }
    
    private func applyPositionConstraints() {
        guard let containerView = containerView, let anchorView = anchorView, let window = anchorView.window else { return }
        let anchorFrame = anchorView.convert(anchorView.bounds, to: window)
        
        deactivateArrowConstraints()
        
        switch placement {
        case .below:
            let top = tableView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: anchorFrame.maxY + gap)
            top.isActive = true
            topConstraint = top
            
            // Overlap arrow into table by borderWidth so arrow fill covers the table's top border
            let arrowTop = arrowView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: anchorFrame.maxY + gap - arrowSize + dropdownBorderWidth)
            arrowTop.isActive = true
            arrowTopConstraint = arrowTop
            
            arrowView.transform = .identity
            
        case .above:
            let bottom = tableView.bottomAnchor.constraint(equalTo: containerView.topAnchor, constant: anchorFrame.minY - gap)
            bottom.isActive = true
            bottomConstraint = bottom
            
            // Overlap arrow into table by borderWidth so arrow fill covers the table's bottom border
            let arrowBottom = arrowView.bottomAnchor.constraint(equalTo: containerView.topAnchor, constant: anchorFrame.minY - gap + arrowSize - dropdownBorderWidth)
            arrowBottom.isActive = true
            arrowBottomConstraint = arrowBottom
            
            arrowView.transform = CGAffineTransform(rotationAngle: .pi)
        }
        
        let leading = tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: anchorFrame.origin.x)
        let trailing = tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -(window.bounds.width - anchorFrame.maxX))
        leading.isActive = true
        trailing.isActive = true
        leadingConstraint = leading
        trailingConstraint = trailing
        
        let anchorCenterX = anchorFrame.midX
        let arrowCenterX = arrowView.centerXAnchor.constraint(equalTo: containerView.leadingAnchor, constant: anchorCenterX)
        arrowCenterX.isActive = true
        arrowLeadingConstraint = arrowCenterX
    }
    
    private func deactivateArrowConstraints() {
        arrowLeadingConstraint?.isActive = false
        arrowTopConstraint?.isActive = false
        arrowBottomConstraint?.isActive = false
        arrowLeadingConstraint = nil
        arrowTopConstraint = nil
        arrowBottomConstraint = nil
    }
    
    // MARK: - Height
    
    private func updateHeight(animated: Bool = true) {
        let target = tableViewHeight
        heightConstraint?.constant = target
        let shouldHide = target == 0
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.arrowView.alpha = shouldHide ? 0 : 1
                self.tableView.alpha = shouldHide ? 0 : 1
                self.shadowBackingView.alpha = shouldHide ? 0 : 1
                self.containerView?.layoutIfNeeded()
            }
        } else {
            self.arrowView.alpha = shouldHide ? 0 : 1
            self.tableView.alpha = shouldHide ? 0 : 1
            self.shadowBackingView.alpha = shouldHide ? 0 : 1
            self.containerView?.layoutIfNeeded()
        }
    }
    
    // MARK: - Touch Handling
    
    @objc private func handleContainerTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: tableView)
        if !tableView.bounds.contains(point) {
            if let anchorView = anchorView {
                let anchorPoint = gesture.location(in: anchorView)
                if !anchorView.bounds.contains(anchorPoint) {
                    hide()
                }
            } else {
                hide()
            }
        }
    }
    
    @objc private func handleContainerPan(_ gesture: UIPanGestureRecognizer) {
        guard let containerView = containerView else { return }
        let point = gesture.location(in: containerView)
        
        if !tableView.frame.contains(point) {
            if let anchorView = anchorView {
                let anchorPoint = gesture.location(in: anchorView)
                if !anchorView.bounds.contains(anchorPoint) {
                    hide()
                }
            } else {
                hide()
            }
        }
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let anchorView = anchorView {
            let point = touch.location(in: anchorView)
            if anchorView.bounds.contains(point) {
                return false
            }
        }
        return true
    }
    
    // MARK: - Keyboard
    
    private func setupKeyboardObservers() {
        let hideObserver = NotificationCenter.default.addObserver(
            forName: {
#if swift(>=4.2)
                return UIResponder.keyboardWillHideNotification
#else
                return NSNotification.Name.UIKeyboardWillHide
#endif
            }(),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
        
        keyboardObservers = [hideObserver]
    }
}

// MARK: - UITableViewDataSource & Delegate

extension FloatingFilterView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredOptions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FloatingOptionCell", for: indexPath)
        let optionValue = filteredOptions[indexPath.row].value
        
        if !currentFilterText.isEmpty,
           let matchRange = optionValue.range(of: currentFilterText, options: .caseInsensitive) {
            let attributed = NSMutableAttributedString(
                string: optionValue,
                attributes: [
                    .font: font,
                    .foregroundColor: textColor
                ]
            )
            // Gray out the typed (matched) portion
            let nsRange = NSRange(matchRange, in: optionValue)
            attributed.addAttribute(.foregroundColor, value: typeAheadHighlightColor, range: nsRange)
            cell.textLabel?.attributedText = attributed
        } else {
            cell.textLabel?.attributedText = nil
            cell.textLabel?.text = optionValue
            cell.textLabel?.font = font
            cell.textLabel?.textColor = textColor
        }
        
        cell.selectionStyle = .default
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let option = filteredOptions[indexPath.row]
        delegate?.floatingFilter(self, didSelect: option)
        hide()
    }
}

