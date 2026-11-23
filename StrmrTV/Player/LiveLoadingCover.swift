import UIKit

/// The channel's logo and name over black until the first frame is up.
final class LiveLoadingCover: UIView {
    private let note = UILabel()
    #if os(iOS)
    /// The cover sits over every control while a channel tunes, so a phone needs its own way out.
    var onClose: (() -> Void)?
    #endif

    init(channel: LiveChannel, program: EPGProgram?) {
        super.init(frame: .zero)
        backgroundColor = .black
        let logo = UIImageView()
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = channel.name
        title.font = .preferredFont(forTextStyle: .title2)
        title.textColor = .white
        let subtitle = UILabel()
        subtitle.text = program?.title
        subtitle.font = .preferredFont(forTextStyle: .callout)
        subtitle.textColor = .lightGray
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.startAnimating()
        note.font = .preferredFont(forTextStyle: .callout)
        note.textColor = .white
        note.isHidden = true
        let stack = UIStackView(arrangedSubviews: [logo, title, subtitle, spinner, note])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 320),
            logo.heightAnchor.constraint(equalToConstant: 180),
        ])
        #if os(iOS)
        installCloseButton()
        #endif
        if let url = channel.logoURL {
            Task { [weak logo] in
                let image = await ImagePipeline.load(url, size: CGSize(width: 320, height: 180), mode: .fit,
                                                     scale: ImagePipeline.scale)
                logo?.image = image
                logo?.isHidden = image == nil
            }
        } else {
            logo.isHidden = true
        }
    }

    /// A line under the spinner saying what the player is doing (Stremio failover); nil clears it.
    func show(note text: String?) {
        note.text = text
        note.isHidden = text == nil
    }

    #if os(iOS)
    private func installCloseButton() {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(weight: .semibold))
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.15)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.onClose?() })
        button.accessibilityLabel = String(localized: "Close")
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            button.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
    }
    #endif

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
