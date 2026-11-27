import UIKit

#if os(tvOS)
/// "● REC" at the top right while the server still follows the recording.
final class RecordingBadge: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        label.text = RecordingPlayerViewController.recBadgeText
        label.font = .systemFont(ofSize: 26, weight: .bold)
        label.textColor = .white
        label.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            label.widthAnchor.constraint(equalToConstant: 120),
            label.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
#endif
