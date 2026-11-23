import UIKit

/// "Watching together" card in the player's top corner (the Expo `WatchTogetherPresence`): the
/// joined members, a presence dot each, and Ready / Loading while the room waits for every
/// player. Display only: it takes no touches and can never take focus on TV. It shows when
/// something changes (and while the room waits or someone buffers), then fades after a few seconds.
final class WatchTogetherPresenceView: UIView {
    private let stack = UIStackView()
    private var hideWork: DispatchWorkItem?
    private static let tv = UIDevice.current.userInterfaceIdiom == .tv
    private static let visibleFor: TimeInterval = 8

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityTraits = .staticText
        backgroundColor = UIColor(red: 8 / 255, green: 15 / 255, blue: 29 / 255, alpha: 0.82)
        layer.cornerRadius = Self.tv ? 18 : 14
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 147 / 255, green: 197 / 255, blue: 253 / 255, alpha: 0.32).cgColor
        stack.axis = .vertical
        stack.spacing = Self.tv ? 10 : 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let pad: CGFloat = Self.tv ? 20 : 10
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            widthAnchor.constraint(lessThanOrEqualToConstant: Self.tv ? 460 : 240),
        ])
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var canBecomeFocused: Bool { false }

    func update(_ room: WatchRoom?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let members = room?.joinedMembers ?? []
        guard let room, !members.isEmpty else { return fade(out: true) }
        stack.addArrangedSubview(heading())
        for member in members { stack.addArrangedSubview(row(member, waiting: room.waitingForReady)) }
        let names = members.filter(\.present).map(\.name).joined(separator: ", ")
        accessibilityLabel = String(localized: "Watching together with \(names)")
        fade(out: false)
        hideWork?.cancel()
        // Keeps showing while the room waits for players or someone is buffering.
        guard !room.waitingForReady, !members.contains(where: \.buffering) else { return }
        let work = DispatchWorkItem { [weak self] in self?.fade(out: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
    }

    private func fade(out: Bool) {
        UIView.animate(withDuration: 0.3) { self.alpha = out ? 0 : 1 }
    }

    private func heading() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "person.2.fill"))
        icon.tintColor = UIColor(red: 147 / 255, green: 197 / 255, blue: 253 / 255, alpha: 1)
        let label = Self.label(String(localized: "Watching together"), size: Self.tv ? 23 : 13, weight: .bold)
        label.textColor = UIColor(red: 219 / 255, green: 234 / 255, blue: 254 / 255, alpha: 1)
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = Self.tv ? 10 : 6
        return row
    }

    private func row(_ member: WatchRoomMember, waiting: Bool) -> UIView {
        let size: CGFloat = Self.tv ? 38 : 22
        let avatar = Self.label(member.initial, size: Self.tv ? 17 : 10, weight: .heavy)
        avatar.textAlignment = .center
        avatar.backgroundColor = UIColor(profileHex: member.color) ?? .systemGray
        avatar.layer.cornerRadius = size / 2
        avatar.clipsToBounds = true
        avatar.widthAnchor.constraint(equalToConstant: size).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: size).isActive = true
        let name = Self.label(member.name, size: Self.tv ? 20 : 12, weight: .semibold)
        var views: [UIView] = [avatar, name]
        let state = waiting ? (member.ready ? String(localized: "Ready") : String(localized: "Loading"))
            : member.buffering ? String(localized: "Buffering") : nil
        if let state {
            let label = Self.label(state, size: Self.tv ? 17 : 10, weight: .semibold)
            label.textColor = UIColor(red: 191 / 255, green: 219 / 255, blue: 254 / 255, alpha: 1)
            views.append(label)
        }
        let dot = UIView()
        dot.backgroundColor = member.present ? UIColor(red: 74 / 255, green: 222 / 255, blue: 128 / 255, alpha: 1)
            : UIColor(red: 100 / 255, green: 116 / 255, blue: 139 / 255, alpha: 1)
        dot.layer.cornerRadius = 4
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        views.append(dot)
        let row = UIStackView(arrangedSubviews: views)
        row.alignment = .center
        row.spacing = Self.tv ? 10 : 7
        row.alpha = member.present ? 1 : 0.48
        return row
    }

    private static func label(_ text: String, size: CGFloat, weight: UIFont.Weight) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }
}

extension UIColor {
    /// `#RRGGBB` (a profile colour); nil for anything else.
    convenience init?(profileHex hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespaces), hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
