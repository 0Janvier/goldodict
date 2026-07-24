import AppKit

/// Glyphe de la barre des menus, dessiné plutôt qu'importé.
///
/// À dix-huit points de côté, l'icône de l'application n'est plus lisible : les ailes,
/// la crête et les arcs de la bouche se referment en une tache. Le glyphe ne garde donc
/// que la visière et les deux yeux, qui suffisent à la reconnaître, et il est produit
/// en tracés purs pour rester net sur tous les facteurs d'échelle.
///
/// L'image est déclarée `template` : macOS l'inverse lui-même selon le thème de la
/// barre. Une image en couleurs y resterait noire sur fond sombre.
enum StatusIcon {

    private static let side: CGFloat = 18

    static let idle: NSImage = make(recording: false)
    static let recording: NSImage = make(recording: true)

    private static func make(recording: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let path = NSBezierPath()

            // Visière : trapèze plus large en haut, comme sur l'icône.
            path.move(to: NSPoint(x: 2.0, y: 16.0))
            path.line(to: NSPoint(x: 16.0, y: 16.0))
            path.line(to: NSPoint(x: 14.6, y: 11.4))
            path.line(to: NSPoint(x: 3.4, y: 11.4))
            path.close()

            // Les deux yeux sont évidés dans la visière plutôt que posés dessus :
            // remplis, ils disparaîtraient dans la masse noire du glyphe.
            path.append(diamond(centre: NSPoint(x: 6.1, y: 13.8), width: 2.6, height: 1.9, rising: false))
            path.append(diamond(centre: NSPoint(x: 11.9, y: 13.8), width: 2.6, height: 1.9, rising: true))
            path.windingRule = .evenOdd

            NSColor.black.setFill()
            path.fill()

            // Bouche : la barre parlante de la famille, réduite à un trait, et ses
            // deux arcs. Pendant la dictée elle s'ouvre, ce qui distingue l'état actif
            // sans recourir à la couleur, absente des images template.
            let mouth = NSBezierPath(
                roundedRect: NSRect(x: 4.2, y: recording ? 5.6 : 6.6, width: 6.6, height: recording ? 3.2 : 1.6),
                xRadius: 0.8,
                yRadius: 0.8
            )
            mouth.fill()

            for (index, radius) in [1.9, 3.3].enumerated() {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: NSPoint(x: 11.2, y: 7.4),
                    radius: radius,
                    startAngle: -42,
                    endAngle: 42
                )
                arc.lineWidth = index == 0 ? 1.5 : 1.2
                arc.lineCapStyle = .round
                NSColor.black.withAlphaComponent(index == 0 ? 1 : 0.7).setStroke()
                arc.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Losange, forme de l'œil dans toute la famille Goldo. `rising` incline la
    /// pointe vers le haut, pour que les deux yeux se regardent en miroir.
    private static func diamond(
        centre: NSPoint,
        width: CGFloat,
        height: CGFloat,
        rising: Bool
    ) -> NSBezierPath {
        let tilt: CGFloat = rising ? 0.45 : -0.45
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centre.x - width / 2, y: centre.y - tilt))
        path.line(to: NSPoint(x: centre.x, y: centre.y + height / 2 - tilt / 2))
        path.line(to: NSPoint(x: centre.x + width / 2, y: centre.y + tilt))
        path.line(to: NSPoint(x: centre.x, y: centre.y - height / 2 + tilt / 2))
        path.close()
        return path
    }
}
