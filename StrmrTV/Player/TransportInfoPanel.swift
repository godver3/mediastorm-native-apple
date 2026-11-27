import UIKit

/// Down on the transport: AVKit's Info / Stream panel, drawn by the app so every player has it.
/// A tab header ("Info", "Stream") above one card at a time: the Info card (artwork, title,
/// subtitle, description) or the Stream rows (`StreamInfoViewController`'s view). Left / Right
/// switch tabs while it is open (`SoftwareTransportHUD.stepInfoTab`).
final class TransportInfoPanel: UIView {
    enum Tab: Int, CaseIterable { case info, stream }

    private let card: TransportInfoCard
    private let streamHost = UIView()
    private let header = UIStackView()
    private var tabLabels: [UILabel] = []
    private(set) var tab: Tab = .info

    init(title: String, subtitle: String?) {
        card = TransportInfoCard(title: title, subtitle: subtitle)
        super.init(frame: .zero)
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false
        for (index, name) in [String(localized: "Info"), String(localized: "Stream")].enumerated() {
            let label = TabLabel()
            label.text = name
            label.tag = index
            tabLabels.append(label)
            header.addArrangedSubview(label)
        }
        addSubview(header)
        for view in [card, streamHost] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            streamHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            streamHost.heightAnchor.constraint(equalToConstant: StreamInfoViewController.panelHeight),
            streamHost.widthAnchor.constraint(equalToConstant: 1300),
        ])
        select(.info)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setArtwork(_ image: UIImage) { card.setArtwork(image) }
    func setTitle(_ title: String, subtitle: String?) { card.setTitle(title, subtitle: subtitle) }
    func setDetails(_ text: String?) { card.setDetails(text) }
    func setDescription(_ text: String?) { card.setDescription(text) }

    /// The Stream tab's content; without one the header shows only Info.
    func setStreamView(_ view: UIView) {
        streamHost.subviews.forEach { $0.removeFromSuperview() }
        view.frame = streamHost.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        streamHost.addSubview(view)
        select(tab)
    }

    private var hasStream: Bool { !streamHost.subviews.isEmpty }

    func select(_ tab: Tab) {
        self.tab = hasStream ? tab : .info
        card.isHidden = self.tab != .info
        streamHost.isHidden = self.tab != .stream
        tabLabels[Tab.stream.rawValue].isHidden = !hasStream
        for label in tabLabels {
            (label as? TabLabel)?.isSelected = label.tag == self.tab.rawValue
        }
    }

    /// Left / Right: the neighbouring tab, if there is one. True when it moved.
    func step(forward: Bool) -> Bool {
        let next = forward ? Tab.stream : Tab.info
        guard next != tab, hasStream else { return false }
        select(next)
        return true
    }

    /// A tab name in the header: a white capsule when selected, as AVKit's.
    private final class TabLabel: UILabel {
        var isSelected = false {
            didSet {
                backgroundColor = isSelected ? .white : UIColor.white.withAlphaComponent(0.12)
                textColor = isSelected ? .black : UIColor.white.withAlphaComponent(0.8)
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            font = .systemFont(ofSize: 26, weight: .semibold)
            textAlignment = .center
            layer.cornerRadius = 22
            layer.cornerCurve = .continuous
            clipsToBounds = true
            heightAnchor.constraint(equalToConstant: 44).isActive = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(width: size.width + 48, height: 44)
        }
    }
}
