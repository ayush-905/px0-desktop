import Foundation
import WebKit

/// The extra px0 themes this app ships (Themes/*.css in the app bundle), added to
/// every page before px0's own scripts run. px0 finds themes by reading the page's
/// stylesheets, so these appear in its theme picker next to the built-in ones.
enum ThemeScript {
    static let userScript = make()

    private static func make() -> WKUserScript {
        let folder = Bundle.main.resourceURL?.appendingPathComponent("Themes")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder ?? URL(fileURLWithPath: "/nonexistent"),
                                                                    includingPropertiesForKeys: nil)) ?? []
        let css = files.filter { $0.pathExtension == "css" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let literal = (try? JSONEncoder().encode(css)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        return WKUserScript(source: source.replacingOccurrences(of: "__CSS__", with: literal),
                            injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Cursor's themes colour some keywords apart from the rest: Dark Modern shows
    /// if, return and import in purple but const and func in blue, while px0 marks
    /// every keyword alike. This tags those words so a theme can tell them apart.
    /// It only runs while a cursor-* theme is on.
    private static let source = """
    (() => {
      const style = document.createElement('style');
      style.id = 'px0-desktop-themes';
      style.textContent = __CSS__;
      document.documentElement.appendChild(style);

      const control = new Set(['if', 'else', 'elif', 'elsif', 'for', 'foreach', 'while', 'do', 'switch', 'case',
        'default', 'break', 'continue', 'return', 'goto', 'try', 'catch', 'except', 'finally', 'throw', 'raise',
        'import', 'export', 'from', 'as', 'await', 'yield', 'with', 'pass', 'del', 'assert', 'go', 'defer',
        'select', 'range', 'fallthrough', 'loop', 'match', 'when', 'unless', 'until', 'then', 'end', 'rescue',
        'ensure', 'using']);
      const constants = new Set(['true', 'false', 'null', 'nil', 'undefined', 'None', 'True', 'False', 'NaN']);
      const selves = new Set(['this', 'self', 'super', 'cls']);
      const root = document.documentElement;
      const active = () => (root.dataset.theme || '').startsWith('cursor-');

      const tag = node => {
        if (node.nodeType !== 1) return;
        const spans = node.matches('.k, .nb') ? [node] : [];
        for (const span of [...spans, ...node.querySelectorAll('.k, .nb')]) {
          const word = span.textContent;
          if (selves.has(word)) span.classList.add('px0d-self');
          else if (!span.classList.contains('k')) continue;
          else if (control.has(word)) span.classList.add('px0d-control');
          else if (constants.has(word)) span.classList.add('px0d-constant');
        }
      };

      new MutationObserver(records => {
        if (!active()) return;
        for (const record of records) record.addedNodes.forEach(tag);
      }).observe(root, { childList: true, subtree: true });
      new MutationObserver(() => { if (active()) tag(root); })
        .observe(root, { attributes: true, attributeFilter: ['data-theme'] });
    })();
    """
}
