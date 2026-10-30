import UIKit

/// The same maker artwork as the web picker, bundled rather than fetched.
/// Unknown makers keep their name without substituting a hosting-provider logo.
enum ModelLogo {
    static let names: Set<String> = ["anthropic", "openai", "gemini", "qwen", "deepseek", "mistral", "xai"]

    static func image(for model: ComposerState.Model, traits: UITraitCollection, size: CGFloat = 20) -> UIImage? {
        guard let name = model.iconName, names.contains(name), let source = UIImage(named: "Model-" + name) else { return nil }
        let image = model.invertIcon == true
            ? source.withTintColor(traits.userInterfaceStyle == .dark ? .white : .black, renderingMode: .alwaysOriginal)
            : source
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }.withRenderingMode(.alwaysOriginal)
    }
}
