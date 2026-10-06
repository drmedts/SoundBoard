import SwiftUI

// Gemeinsame visuelle Bausteine im Doppelmayr-Bedienpult-Stil.
// Siehe [[soundboard-visual-design-approved]] — dies ist die abgenommene Optik,
// ursprünglich in DesignMockup.swift erarbeitet und von dort hierher übernommen,
// damit echte Views (nicht nur Previews) sie verwenden können.

enum DMColor {
    static let panel = LinearGradient(
        colors: [Color(red: 0.17, green: 0.14, blue: 0.12), Color(red: 0.08, green: 0.07, blue: 0.06)],
        startPoint: .top, endPoint: .bottom
    )
    static let bezelLight = Color(white: 0.92)
    static let bezelDark = Color(white: 0.55)
    static let label = Color(white: 0.92)
    static let statusGreen = Color(red: 0.2, green: 0.8, blue: 0.3)
    static let statusRed = Color(red: 0.9, green: 0.15, blue: 0.1)
    static let statusAmber = Color(red: 0.95, green: 0.7, blue: 0.15)
}

struct FaceShades {
    let light: Color
    let base: Color
    let dark: Color
}

enum ButtonFace: String, Codable, CaseIterable, Hashable {
    case black, white, blue, yellow, green, red

    var shades: FaceShades {
        switch self {
        case .black: return FaceShades(light: Color(white: 0.28), base: Color(white: 0.09), dark: .black)
        case .white: return FaceShades(light: Color(white: 1.0), base: Color(white: 0.86), dark: Color(white: 0.6))
        case .blue: return FaceShades(light: Color(red: 0.42, green: 0.70, blue: 0.93), base: Color(red: 0.11, green: 0.52, blue: 0.80), dark: Color(red: 0.05, green: 0.28, blue: 0.48))
        case .yellow: return FaceShades(light: Color(red: 1.0, green: 0.90, blue: 0.40), base: Color(red: 0.95, green: 0.76, blue: 0.10), dark: Color(red: 0.72, green: 0.54, blue: 0.0))
        case .green: return FaceShades(light: Color(red: 0.50, green: 0.86, blue: 0.55), base: Color(red: 0.20, green: 0.66, blue: 0.30), dark: Color(red: 0.08, green: 0.40, blue: 0.15))
        case .red: return FaceShades(light: Color(red: 0.96, green: 0.45, blue: 0.40), base: Color(red: 0.84, green: 0.16, blue: 0.14), dark: Color(red: 0.52, green: 0.04, blue: 0.04))
        }
    }

    var color: Color { shades.base }
}

/// Runder Industrie-Taster: breiter Alu-Bezel, Schattenrille, flache matte Kappe (ohne Glanzlicht).
/// Echtes Blinken (Fade/kurz vor Ende) wird nicht hier, sondern vom Aufrufer erzeugt, indem er
/// `isOn` im Taktgeber-Rhythmus an- und abschaltet — das spart einen zweiten Animationszustand.
struct PanelButtonView: View {
    let title: String
    let face: ButtonFace
    var illuminated: Bool = true
    var isOn: Bool = false
    var diameter: CGFloat = 64
    var labelFontSize: CGFloat = 15

    private var capDiameter: CGFloat { diameter * 0.62 }

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: labelFontSize, weight: .regular))
                .foregroundStyle(DMColor.label)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: diameter + 36, height: 38, alignment: .bottom)

            ZStack {
                // Alu-Bezel
                Circle()
                    .fill(LinearGradient(colors: [DMColor.bezelLight, DMColor.bezelDark, DMColor.bezelLight],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: diameter, height: diameter)
                    .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))

                // Schattenrille zwischen Bezel und Kappe
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: capDiameter + 10, height: capDiameter + 10)
                    .blur(radius: 1.5)

                // Flache, matte Kappe
                Circle()
                    .fill(LinearGradient(
                        colors: illuminated && isOn
                            ? [face.shades.light, face.shades.base]
                            : [face.shades.base, face.shades.dark],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: capDiameter, height: capDiameter)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                    .shadow(color: illuminated && isOn ? face.shades.base.opacity(0.9) : .clear, radius: isOn ? 9 : 0)
            }
        }
    }
}

/// Rote Notstop-Pilztaste mit gelbem Kragen.
struct EmergencyStopButtonView: View {
    var fontSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 4) {
            Text("Not-Stop")
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(DMColor.label)
            ZStack {
                Circle().fill(Color(red: 0.95, green: 0.76, blue: 0.10)).frame(width: 74, height: 74)
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.84, green: 0.16, blue: 0.14), Color(red: 0.52, green: 0.04, blue: 0.04)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 58, height: 58)
                    .shadow(color: .red.opacity(0.7), radius: 6)
            }
        }
    }
}

/// Glänzende "Gummibonbon"-LED-Linse wie auf dem Pult.
struct LEDDome: View {
    let color: Color
    var lit: Bool = true
    var diameter: CGFloat = 13

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: diameter, height: diameter)
                .offset(y: diameter * 0.18)
                .blur(radius: 2)

            Circle()
                .fill(RadialGradient(
                    colors: lit ? [color.opacity(1), color, color.opacity(0.75)] : [Color(white: 0.3), Color(white: 0.12)],
                    center: .topLeading, startRadius: 0, endRadius: diameter))
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
                .shadow(color: lit ? color.opacity(0.85) : .clear, radius: lit ? 5 : 0)

            Ellipse()
                .fill(Color.white.opacity(lit ? 0.8 : 0.15))
                .frame(width: diameter * 0.4, height: diameter * 0.22)
                .offset(x: -diameter * 0.18, y: -diameter * 0.22)
        }
    }
}

/// Eine Status-Zeile: LED + Beschriftung, Teil einer senkrechten Liste (nicht versetzt/diagonal).
struct StatusRow: View {
    let label: String
    let color: Color
    var lit: Bool = true
    var diameter: CGFloat = 13
    var fontSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 8) {
            LEDDome(color: color, lit: lit, diameter: diameter)
            Text(label)
                .font(.system(size: fontSize))
                .foregroundStyle(DMColor.label.opacity(0.9))
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct StatusIndicator: Identifiable {
    let id: String
    let label: String
    let lit: Bool
}

struct StatusIndicatorGroup: Identifiable {
    let id: StatusLEDGroup.ID
    let name: String
    let indicators: [StatusIndicator]
}

private struct RailRow: Identifiable {
    let id: String
    let label: String
    let color: Color
    let lit: Bool
}

private struct RailSection: Identifiable {
    let id: String
    let title: String
    let rows: [RailRow]
}

/// Kompaktes, frei platzierbares Status-Panel mit Systemzustand,
/// Ausgabegeräten und benannten, sortierbaren Button-Gruppen.
///
/// Der Systemstatus ist eine gewöhnliche Sektion wie die Geräte-/Button-Gruppen
/// (eine Zeile pro LED, keine eigene 2x2-Optik) und steht immer an erster Stelle.
/// Bei `columns == 2` werden alle Sektionen eng beieinander auf zwei Spalten
/// verteilt (nach Zeilenzahl ausbalanciert), um vertikalen Platz zu sparen.
struct StatusRail: View {
    var outputActive: Bool = false
    var ready: Bool = true
    var deviceMissing: Bool = false
    var fileMissing: Bool = false
    let outputDevices: [StatusIndicator]
    let buttonGroups: [StatusIndicatorGroup]
    let fontSize: CGFloat
    var columns: Int = 1

    private var sections: [RailSection] {
        var result: [RailSection] = [
            RailSection(id: "system", title: "Systemstatus", rows: [
                RailRow(id: "system:output", label: "Ausgabe", color: DMColor.statusGreen, lit: outputActive),
                RailRow(id: "system:ready", label: "Bereit", color: DMColor.statusGreen, lit: ready),
                RailRow(id: "system:deviceMissing", label: "Gerät fehlt", color: DMColor.statusRed, lit: deviceMissing),
                RailRow(id: "system:fileMissing", label: "Datei fehlt", color: DMColor.statusRed, lit: fileMissing),
            ])
        ]

        if !outputDevices.isEmpty {
            result.append(RailSection(
                id: "devices",
                title: "Ausgabegeräte",
                rows: outputDevices.map { RailRow(id: $0.id, label: $0.label, color: DMColor.statusGreen, lit: $0.lit) }
            ))
        }

        for group in buttonGroups where !group.indicators.isEmpty {
            result.append(RailSection(
                id: "group:\(group.id)",
                title: group.name,
                rows: group.indicators.map { RailRow(id: $0.id, label: $0.label, color: DMColor.statusAmber, lit: $0.lit) }
            ))
        }

        return result
    }

    /// Greedily assigns whole sections to whichever column currently has fewer
    /// rows, keeping both columns roughly equal in height regardless of how the
    /// section sizes happen to fall.
    private var sectionColumns: [[RailSection]] {
        guard columns >= 2 else { return [sections] }

        var columnRows = [Int](repeating: 0, count: columns)
        var result = [[RailSection]](repeating: [], count: columns)
        for section in sections {
            let target = columnRows.indices.min { columnRows[$0] < columnRows[$1] } ?? 0
            result[target].append(section)
            columnRows[target] += section.rows.count + 1
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: columns >= 2 ? 10 : 0) {
            ForEach(Array(sectionColumns.enumerated()), id: \.offset) { columnIndex, column in
                if columnIndex > 0 {
                    StatusVerticalDivider()
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(column.enumerated()), id: \.element.id) { sectionIndex, section in
                        if sectionIndex > 0 {
                            StatusDivider()
                        }
                        RailSectionView(section: section, fontSize: fontSize)
                    }
                }
                .frame(width: columns >= 2 ? 148 : 222, alignment: .topLeading)
            }
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct RailSectionView: View {
    let section: RailSection
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatusSectionTitle(title: section.title, fontSize: fontSize)
            ForEach(section.rows) { row in
                StatusRow(label: row.label, color: row.color, lit: row.lit, diameter: 11, fontSize: fontSize)
            }
        }
    }
}

private struct StatusVerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1)
    }
}

private struct StatusSectionTitle: View {
    let title: String
    let fontSize: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: fontSize + 1, weight: .semibold))
            .foregroundStyle(DMColor.label)
    }
}

private struct StatusDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
    }
}
