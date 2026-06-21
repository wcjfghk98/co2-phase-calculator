import Foundation
import SwiftUI

enum Phase: String, CaseIterable, Identifiable {
    case supercritical
    case gas
    case liquid
    case solid
    case boundary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .supercritical: return "초임계"
        case .gas: return "기체"
        case .liquid: return "액체"
        case .solid: return "고체"
        case .boundary: return "상 경계"
        }
    }

    var color: Color {
        switch self {
        case .supercritical: return Color(red: 1.0, green: 0.83, blue: 0.38)
        case .gas: return Color(red: 0.76, green: 0.91, blue: 1.0)
        case .liquid: return Color(red: 0.68, green: 0.86, blue: 0.80)
        case .solid: return Color(red: 0.82, green: 0.84, blue: 0.88)
        case .boundary: return Color(red: 0.90, green: 0.94, blue: 0.95)
        }
    }
}

struct PhaseState {
    let phase: Phase?
    let note: String
}

struct RangeResult {
    let range: String?
    let detail: String
}

enum CO2Model {
    static let tripleK = 216.592
    static let tripleC = -56.558
    static let tripleBar = 5.185
    static let criticalK = 304.1282
    static let criticalC = 30.9782
    static let criticalBar = 73.773
    static let gasConstant = 8.314462618
    static let molarMassKgPerMol = 0.0440095
    static let acentricFactor = 0.22394
    static let sublimationHeat = 25230.0

    static let minC = 0.0
    static let maxC = 200.0
    static let minBar = 0.0
    static let maxBar = 200.0

    static func cToK(_ celsius: Double) -> Double {
        celsius + 273.15
    }

    static func kToC(_ kelvin: Double) -> Double {
        kelvin - 273.15
    }

    static func vaporPressureBar(_ kelvin: Double) -> Double {
        guard kelvin >= tripleK, kelvin <= criticalK else { return .nan }
        let theta = 1 - kelvin / criticalK
        let a = [-7.0602087, 1.9391218, -1.6463597, -3.2995634]
        let lnRatio = (criticalK / kelvin) *
            (a[0] * theta + a[1] * pow(theta, 1.5) + a[2] * pow(theta, 2) + a[3] * pow(theta, 4))
        return criticalBar * exp(lnRatio)
    }

    static func sublimationPressureBar(_ kelvin: Double) -> Double {
        guard kelvin <= tripleK else { return .nan }
        return tripleBar * exp((-sublimationHeat / gasConstant) * (1 / kelvin - 1 / tripleK))
    }

    static func meltingPressureBar(_ kelvin: Double) -> Double {
        guard kelvin >= tripleK else { return .nan }
        let aBar = 4030.0
        let b = 2.58
        return tripleBar + aBar * (pow(kelvin / tripleK, b) - 1)
    }

    static func densityKgM3(celsius: Double, bar: Double, phase: Phase) -> Double? {
        let kelvin = cToK(celsius)
        let pressurePa = bar * 100000
        guard kelvin.isFinite, pressurePa.isFinite, kelvin > 0, pressurePa > 0 else { return nil }

        let r = gasConstant
        let tc = criticalK
        let pc = criticalBar * 100000
        let omega = acentricFactor
        let kappa = 0.37464 + 1.54226 * omega - 0.26992 * pow(omega, 2)
        let alpha = pow(1 + kappa * (1 - sqrt(kelvin / tc)), 2)
        let a = 0.45724 * pow(r, 2) * pow(tc, 2) * alpha / pc
        let b = 0.07780 * r * tc / pc
        let A = a * pressurePa / (pow(r, 2) * pow(kelvin, 2))
        let B = b * pressurePa / (r * kelvin)
        let roots = cubicRealRoots(
            a: -(1 - B),
            b: A - 3 * pow(B, 2) - 2 * B,
            c: -(A * B - pow(B, 2) - pow(B, 3))
        )
        .filter { $0.isFinite && $0 > B && $0 > 0 }
        .sorted()

        guard let z = (phase == .liquid || phase == .solid ? roots.first : roots.last) else { return nil }
        return pressurePa * molarMassKgPerMol / (z * r * kelvin)
    }

    static func cubicRealRoots(a: Double, b: Double, c: Double) -> [Double] {
        let p = b - pow(a, 2) / 3
        let q = 2 * pow(a, 3) / 27 - a * b / 3 + c
        let discriminant = pow(q / 2, 2) + pow(p / 3, 3)

        if discriminant > 1e-12 {
            let sqrtD = sqrt(discriminant)
            return [cbrt(-q / 2 + sqrtD) + cbrt(-q / 2 - sqrtD) - a / 3]
        }

        if abs(discriminant) <= 1e-12 {
            let u = cbrt(-q / 2)
            return [2 * u - a / 3, -u - a / 3]
        }

        let radius = 2 * sqrt(-p / 3)
        let angle = acos((3 * q / (2 * p)) * sqrt(-3 / p))
        return (0...2).map { k in
            radius * cos((angle - 2 * .pi * Double(k)) / 3) - a / 3
        }
    }

    static func nearlyEqual(_ a: Double, _ b: Double, tolerance: Double = 0.01) -> Bool {
        abs(a - b) <= max(tolerance, abs(b) * 0.002)
    }

    static func classify(celsius: Double, bar: Double) -> PhaseState {
        let kelvin = cToK(celsius)
        guard kelvin.isFinite, bar.isFinite, bar > 0, kelvin > 0 else {
            return PhaseState(phase: nil, note: "온도는 절대영도보다 높고 압력은 0보다 커야 합니다.")
        }

        if nearlyEqual(kelvin, tripleK, tolerance: 0.08), nearlyEqual(bar, tripleBar, tolerance: 0.04) {
            return PhaseState(phase: .boundary, note: "삼중점 근처입니다. 고체, 액체, 기체가 공존할 수 있습니다.")
        }

        if kelvin < tripleK {
            let pSub = sublimationPressureBar(kelvin)
            if nearlyEqual(bar, pSub) {
                return PhaseState(phase: .boundary, note: "승화선 근처입니다. 고체와 기체가 공존할 수 있습니다.")
            }
            return bar > pSub
                ? PhaseState(phase: .solid, note: "승화압 \(formatBar(pSub))보다 높아 고체 영역입니다.")
                : PhaseState(phase: .gas, note: "승화압 \(formatBar(pSub))보다 낮아 기체 영역입니다.")
        }

        let pMelt = meltingPressureBar(kelvin)
        if bar >= pMelt || nearlyEqual(bar, pMelt, tolerance: 0.2) {
            return nearlyEqual(bar, pMelt, tolerance: 0.2)
                ? PhaseState(phase: .boundary, note: "용융선 근처입니다. 고체와 유체상이 공존할 수 있습니다.")
                : PhaseState(phase: .solid, note: "용융압 \(formatBar(pMelt))보다 높아 고체 영역입니다.")
        }

        if kelvin > criticalK {
            if bar > criticalBar {
                return PhaseState(phase: .supercritical, note: "임계온도와 임계압력을 모두 초과합니다.")
            }
            return PhaseState(phase: .gas, note: "임계온도보다 높지만 임계압력보다 낮아 기체 영역입니다.")
        }

        let pSat = vaporPressureBar(kelvin)
        if nearlyEqual(bar, pSat, tolerance: 0.05) {
            return PhaseState(phase: .boundary, note: "액체-기체 포화선 근처입니다. 두 상이 공존할 수 있습니다.")
        }
        return bar > pSat
            ? PhaseState(phase: .liquid, note: "포화압 \(formatBar(pSat))보다 높고 용융압보다 낮아 액체 영역입니다.")
            : PhaseState(phase: .gas, note: "포화압 \(formatBar(pSat))보다 낮아 기체 영역입니다.")
    }

    static func rangeForTemperature(celsius: Double, phase: Phase) -> RangeResult {
        let kelvin = cToK(celsius)
        guard kelvin.isFinite, kelvin > 0 else {
            return RangeResult(range: nil, detail: "온도는 절대영도보다 높아야 합니다.")
        }
        let pMelt = kelvin >= tripleK ? meltingPressureBar(kelvin) : nil

        switch phase {
        case .solid:
            let boundary = kelvin < tripleK ? sublimationPressureBar(kelvin) : (pMelt ?? .nan)
            return RangeResult(range: "\(formatBar(boundary)) 이상", detail: "이 온도에서는 압력이 \(formatBar(boundary)) 이상이면 고체 영역입니다.")
        case .gas:
            if kelvin < tripleK {
                let pSub = sublimationPressureBar(kelvin)
                return RangeResult(range: "0 ~ \(formatBar(pSub)) 미만", detail: "이 온도에서는 승화압보다 낮은 압력에서 기체입니다.")
            }
            if kelvin < criticalK {
                let pSat = vaporPressureBar(kelvin)
                return RangeResult(range: "0 ~ \(formatBar(pSat)) 미만", detail: "이 온도에서는 포화압보다 낮은 압력에서 기체입니다.")
            }
            return RangeResult(range: "0 ~ \(formatBar(criticalBar)) 미만", detail: "임계온도보다 높으므로 임계압력 미만에서는 기체로 봅니다.")
        case .liquid:
            guard kelvin > tripleK, kelvin < criticalK, let pMelt else {
                return RangeResult(range: nil, detail: "이 온도에서는 안정한 액체 영역이 없습니다.")
            }
            let pSat = vaporPressureBar(kelvin)
            return RangeResult(range: "\(formatBar(pSat)) 초과 ~ \(formatBar(pMelt)) 미만", detail: "포화압보다 높고 용융압보다 낮은 범위가 액체 영역입니다.")
        case .supercritical:
            guard kelvin > criticalK, let pMelt else {
                return RangeResult(range: nil, detail: "초임계는 임계온도 31.0°C를 초과해야 합니다.")
            }
            return RangeResult(range: "\(formatBar(criticalBar)) 초과 ~ \(formatBar(pMelt)) 미만", detail: "임계압력보다 높고, 초고압 고체화 경계보다 낮은 범위입니다.")
        case .boundary:
            return RangeResult(range: nil, detail: "상 경계는 특정 곡선 조건입니다.")
        }
    }

    static func rangeForPressure(bar: Double, phase: Phase) -> RangeResult {
        guard bar.isFinite, bar > 0 else {
            return RangeResult(range: nil, detail: "압력은 0보다 커야 합니다.")
        }
        let hasSublimationRoot = bar <= tripleBar
        let meltTemp = bar >= tripleBar ? invertMonotonic(target: bar, lowK: tripleK, highK: cToK(maxC), fn: meltingPressureBar) : nil

        switch phase {
        case .solid:
            if hasSublimationRoot {
                let tSub = invertMonotonic(target: bar, lowK: cToK(-120), highK: tripleK, fn: sublimationPressureBar)
                return RangeResult(range: "\(formatC(kToC(tSub))) 이하", detail: "이 압력에서는 승화선보다 낮은 온도에서 고체입니다.")
            }
            return RangeResult(range: "\(formatC(kToC(meltTemp ?? tripleK))) 미만", detail: "이 압력에서는 용융선보다 낮은 온도에서 고체입니다.")
        case .gas:
            if bar < tripleBar {
                let tSub = invertMonotonic(target: bar, lowK: cToK(-120), highK: tripleK, fn: sublimationPressureBar)
                return RangeResult(range: "\(formatC(kToC(tSub))) 초과", detail: "이 압력에서는 승화온도보다 높으면 기체입니다.")
            }
            if bar < criticalBar {
                let tSat = invertMonotonic(target: bar, lowK: tripleK, highK: criticalK, fn: vaporPressureBar)
                return RangeResult(range: "\(formatC(kToC(tSat))) 초과", detail: "이 압력에서는 끓는점보다 높은 온도에서 기체입니다.")
            }
            return RangeResult(range: nil, detail: "임계압력 이상에서는 안정한 기체 영역이 없습니다. 임계온도 이상은 초임계입니다.")
        case .liquid:
            guard bar > tripleBar else {
                return RangeResult(range: nil, detail: "삼중점 압력 이하에서는 안정한 액체 영역이 없습니다.")
            }
            if bar < criticalBar {
                let tSat = invertMonotonic(target: bar, lowK: tripleK, highK: criticalK, fn: vaporPressureBar)
                return RangeResult(range: "\(formatC(kToC(meltTemp ?? tripleK))) 초과 ~ \(formatC(kToC(tSat))) 미만", detail: "용융온도와 포화온도 사이가 액체 영역입니다.")
            }
            return RangeResult(range: "\(formatC(kToC(meltTemp ?? tripleK))) 초과 ~ \(formatC(criticalC)) 미만", detail: "임계압력 이상에서는 임계온도 아래의 압축 액체 영역입니다.")
        case .supercritical:
            guard bar > criticalBar else {
                return RangeResult(range: nil, detail: "초임계는 임계압력 73.8 bar를 초과해야 합니다.")
            }
            return RangeResult(range: "\(formatC(criticalC)) 초과 ~ \(formatC(kToC(meltTemp ?? cToK(maxC)))) 미만", detail: "임계온도보다 높고 용융선보다 낮은 범위입니다.")
        case .boundary:
            return RangeResult(range: nil, detail: "상 경계는 특정 곡선 조건입니다.")
        }
    }

    static func invertMonotonic(target: Double, lowK: Double, highK: Double, fn: (Double) -> Double) -> Double {
        var low = lowK
        var high = highK
        for _ in 0..<80 {
            let mid = (low + high) / 2
            if fn(mid) < target {
                low = mid
            } else {
                high = mid
            }
        }
        return (low + high) / 2
    }

    static func formatBar(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        if value >= 1000 { return "\(Int(value.rounded())) bar" }
        if value >= 10 { return String(format: "%.1f bar", value) }
        if value >= 1 { return String(format: "%.2f bar", value) }
        return String(format: "%.2g bar", value)
    }

    static func formatC(_ value: Double) -> String {
        String(format: "%.1f°C", value)
    }

    static func formatDensity(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        if value >= 100 { return "\(Int(value.rounded())) kg/m³" }
        if value >= 10 { return String(format: "%.1f kg/m³", value) }
        return String(format: "%.2f kg/m³", value)
    }

    static func densityDetail(celsius: Double, bar: Double, phase: Phase) -> String {
        guard let density = densityKgM3(celsius: celsius, bar: bar, phase: phase) else {
            return "밀도는 계산할 수 없습니다."
        }
        let qualifier = phase == .solid
            ? "Peng-Robinson 유체 EOS 근사값이라 고체 조건에서는 참고용입니다."
            : "Peng-Robinson EOS 근사값입니다."
        return "밀도: \(formatDensity(density)) (\(qualifier))"
    }
}

struct ContentView: View {
    @State private var temperatureText = ""
    @State private var pressureText = ""
    @State private var selectedPhase: Phase?

    private var temperature: Double? {
        Double(temperatureText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var pressure: Double? {
        Double(pressureText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var result: (chip: String, color: Color, title: String, detail: String, marker: ChartMarker?) {
        if let temperature, let pressure {
            let state = CO2Model.classify(celsius: temperature, bar: pressure)
            guard let phase = state.phase else {
                return ("입력 확인", Color(.systemGray5), "계산할 수 없는 조건입니다.", state.note, nil)
            }
            let densityText = CO2Model.densityDetail(celsius: temperature, bar: pressure, phase: phase)
            return (
                phase.label,
                phase.color,
                "\(CO2Model.formatC(temperature)), \(CO2Model.formatBar(pressure))에서는 \(phase.label)입니다.",
                "\(state.note)\n\(densityText)",
                ChartMarker(celsius: temperature, bar: pressure)
            )
        }

        if (temperature != nil || pressure != nil), selectedPhase == nil {
            return ("상을 선택하세요", Color(.systemGray5), "원하는 상을 선택하면 가능한 조건 범위를 보여줍니다.", "온도나 압력 중 하나만 입력한 경우에는 원하는 상을 먼저 선택해 주세요.", nil)
        }

        if let temperature, let selectedPhase {
            let range = CO2Model.rangeForTemperature(celsius: temperature, phase: selectedPhase)
            if let rangeText = range.range {
                return (selectedPhase.label, selectedPhase.color, "\(CO2Model.formatC(temperature))에서 \(selectedPhase.label) 압력 범위: \(rangeText)", range.detail, nil)
            }
            return (selectedPhase.label, selectedPhase.color, "\(CO2Model.formatC(temperature))에서 \(selectedPhase.label) 조건이 없습니다.", range.detail, nil)
        }

        if let pressure, let selectedPhase {
            let range = CO2Model.rangeForPressure(bar: pressure, phase: selectedPhase)
            if let rangeText = range.range {
                return (selectedPhase.label, selectedPhase.color, "\(CO2Model.formatBar(pressure))에서 \(selectedPhase.label) 온도 범위: \(rangeText)", range.detail, nil)
            }
            return (selectedPhase.label, selectedPhase.color, "\(CO2Model.formatBar(pressure))에서 \(selectedPhase.label) 조건이 없습니다.", range.detail, nil)
        }

        return ("조건을 입력하세요", Color(.systemGray5), "온도와 압력을 입력하거나, 한 조건과 원하는 상을 선택해 주세요.", "두 값을 모두 넣으면 현재 상을 판정하고 상평형도에 포인트를 표시합니다.", nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    inputPanel
                    resultPanel
                    phaseDiagram
                    Text("순수 CO2 기준의 근사 계산입니다. 그래프는 0-200°C, 0-200 bar 범위를 선형 축으로 표시합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }
                .padding()
            }
            .background(Color(red: 0.97, green: 0.98, blue: 0.98))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Carbon Dioxide Phase Calculator")
                    .font(.caption.bold())
                    .foregroundStyle(Color(red: 0.07, green: 0.37, blue: 0.35))
                Text("CO2 상 계산기")
                    .font(.system(size: 34, weight: .black, design: .default))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("임계점")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("31.0°C · 73.8 bar")
                    .font(.subheadline.bold())
            }
        }
    }

    private var inputPanel: some View {
        VStack(spacing: 12) {
            labeledTextField(title: "온도", unit: "°C", placeholder: "예: 25", text: $temperatureText)
            labeledTextField(title: "압력", unit: "bar", placeholder: "예: 80", text: $pressureText)
            VStack(alignment: .leading, spacing: 7) {
                Text("원하는 상")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("원하는 상", selection: $selectedPhase) {
                    Text("선택").tag(nil as Phase?)
                    ForEach([Phase.supercritical, .gas, .liquid, .solid]) { phase in
                        Text(phase.label).tag(Optional(phase))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.78, green: 0.82, blue: 0.84)))
            }
            Button("초기화") {
                temperatureText = ""
                pressureText = ""
                selectedPhase = nil
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.85, green: 0.88, blue: 0.89)))
    }

    private func labeledTextField(title: String, unit: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                Text(unit)
                    .font(.body.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.78, green: 0.82, blue: 0.84)))
        }
    }

    private var resultPanel: some View {
        let current = result
        return VStack(alignment: .leading, spacing: 10) {
            Text(current.chip)
                .font(.subheadline.bold())
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(current.color)
                .clipShape(Capsule())
            Text(current.title)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(current.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.85, green: 0.88, blue: 0.89)))
    }

    private var phaseDiagram: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("상평형도")
                .font(.headline)
            PhaseDiagramView(marker: result.marker)
                .frame(height: 330)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.85, green: 0.88, blue: 0.89)))
    }
}

struct ChartMarker {
    let celsius: Double
    let bar: Double
}

struct PhaseDiagramView: View {
    let marker: ChartMarker?

    var body: some View {
        Canvas { context, size in
            let margin = EdgeInsets(top: 20, leading: 54, bottom: 42, trailing: 18)
            let plot = CGRect(
                x: margin.leading,
                y: margin.top,
                width: size.width - margin.leading - margin.trailing,
                height: size.height - margin.top - margin.bottom
            )

            func project(_ celsius: Double, _ bar: Double) -> CGPoint {
                let x = plot.minX + ((celsius - CO2Model.minC) / (CO2Model.maxC - CO2Model.minC)) * plot.width
                let y = plot.minY + (1 - ((bar - CO2Model.minBar) / (CO2Model.maxBar - CO2Model.minBar))) * plot.height
                return CGPoint(x: x, y: y)
            }

            func drawText(_ text: String, at point: CGPoint, color: Color = .secondary, size: CGFloat = 12, weight: Font.Weight = .bold) {
                context.draw(
                    Text(text).font(.system(size: size, weight: weight)).foregroundStyle(color),
                    at: point
                )
            }

            var superPath = Path()
            superPath.move(to: project(CO2Model.criticalC, CO2Model.criticalBar))
            superPath.addLine(to: project(CO2Model.maxC, CO2Model.criticalBar))
            superPath.addLine(to: project(CO2Model.maxC, CO2Model.maxBar))
            superPath.addLine(to: project(CO2Model.criticalC, CO2Model.maxBar))
            superPath.closeSubpath()
            context.fill(superPath, with: .color(Color(red: 1.0, green: 0.83, blue: 0.38).opacity(0.62)))

            for bar in stride(from: 0.0, through: 200.0, by: 50.0) {
                let a = project(0, bar)
                let b = project(200, bar)
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(path, with: .color(Color(red: 0.90, green: 0.93, blue: 0.94)), lineWidth: 1)
                drawText("\(Int(bar))", at: CGPoint(x: 20, y: a.y))
            }

            for temp in stride(from: 0.0, through: 200.0, by: 50.0) {
                let a = project(temp, 0)
                let b = project(temp, 200)
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(path, with: .color(Color(red: 0.90, green: 0.93, blue: 0.94)), lineWidth: 1)
                drawText("\(Int(temp))", at: CGPoint(x: a.x, y: size.height - 18))
            }

            var axes = Path()
            axes.move(to: CGPoint(x: plot.minX, y: plot.minY))
            axes.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            axes.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            context.stroke(axes, with: .color(Color(red: 0.20, green: 0.25, blue: 0.28)), lineWidth: 2)

            drawText("온도 (°C)", at: CGPoint(x: plot.midX, y: size.height - 4), color: Color(red: 0.32, green: 0.38, blue: 0.42), size: 13)

            context.drawLayer { layer in
                layer.translateBy(x: 9, y: plot.midY)
                layer.rotate(by: .degrees(-90))
                layer.draw(
                    Text("압력 (bar)").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(red: 0.32, green: 0.38, blue: 0.42)),
                    at: .zero
                )
            }

            drawText("기체", at: project(115, 38), color: Color.black.opacity(0.66), size: 20, weight: .black)
            drawText("액체", at: project(14, 142), color: Color.black.opacity(0.66), size: 20, weight: .black)
            drawText("초임계", at: project(118, 142), color: Color.black.opacity(0.66), size: 20, weight: .black)

            var vaporPath = Path()
            var startedVaporPath = false
            let steps = 120
            for index in 0...steps {
                let celsius = CO2Model.minC + (CO2Model.criticalC - CO2Model.minC) * Double(index) / Double(steps)
                let bar = CO2Model.vaporPressureBar(CO2Model.cToK(celsius))
                guard bar.isFinite, bar >= 0, bar <= CO2Model.maxBar else { continue }
                let point = project(celsius, bar)
                if startedVaporPath {
                    vaporPath.addLine(to: point)
                } else {
                    vaporPath.move(to: point)
                    startedVaporPath = true
                }
            }
            context.stroke(vaporPath, with: .color(Color(red: 0.02, green: 0.47, blue: 0.34)), lineWidth: 3)

            let critical = project(CO2Model.criticalC, CO2Model.criticalBar)
            context.fill(Path(ellipseIn: CGRect(x: critical.x - 4, y: critical.y - 4, width: 8, height: 8)), with: .color(Color(red: 0.15, green: 0.20, blue: 0.22)))
            drawText("임계점", at: CGPoint(x: critical.x + 26, y: critical.y - 14))

            if let marker,
               marker.celsius >= CO2Model.minC, marker.celsius <= CO2Model.maxC,
               marker.bar >= CO2Model.minBar, marker.bar <= CO2Model.maxBar {
                let point = project(marker.celsius, marker.bar)
                context.stroke(Path(ellipseIn: CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)), with: .color(.red.opacity(0.28)), lineWidth: 3)
                context.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)), with: .color(.red))
                context.stroke(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)), with: .color(.white), lineWidth: 2)
            }
        }
    }
}

#Preview {
    ContentView()
}
