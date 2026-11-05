import SwiftUI

struct FormSheetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var form: FormInfo

    @State private var textValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]
    @State private var multiValues: [String: Set<String>] = [:]
    @State private var submitting = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.ocViolet.opacity(0.11))
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.ocViolet)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(form.title)
                        .font(.ocRounded(18, weight: .bold))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text("The agent needs a little more information to continue.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.ocTextSecondary)
                }
                Spacer()
                if model.pendingForms.count > 1 {
                    Tag(text: "\(model.pendingForms.count) pending", tint: .ocWarning)
                }
                Button {
                    Task { await model.cancelForm(form) }
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color.ocHover))
                .foregroundStyle(Color.ocTextSecondary)
            }
            .padding(20)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    ForEach(form.fields.filter { $0.hidden != true }) { field in
                        fieldView(field)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 460)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            HStack {
                Text(requiredRemaining == 0 ? "All required fields set" : "\(requiredRemaining) required remaining")
                    .font(.ocMono(8.5))
                    .foregroundStyle(requiredRemaining == 0 ? Color.ocSuccess : Color.ocTextTertiary)
                Spacer()
                Button("Cancel") {
                    Task { await model.cancelForm(form) }
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button {
                    submit()
                } label: {
                    if submitting {
                        HStack(spacing: 6) {
                            Spinner(size: 10, tint: .white)
                            Text("Sending…")
                        }
                    } else {
                        Label("Send answer", systemImage: "arrow.up.circle.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(submitting || requiredRemaining > 0)
            }
            .padding(16)
        }
        .frame(width: 560)
        .background(Color.ocCanvas)
        .onAppear {
            seedValues()
            withAnimation(Motion.smooth.delay(0.08)) { appeared = true }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    @ViewBuilder
    private func fieldView(_ field: FormField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(field.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.ocTextPrimary)
                if field.required == true {
                    Text("*")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.ocDanger)
                }
                Spacer()
                Text(field.type.uppercased())
                    .font(.ocMono(7.5, weight: .semibold))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            if let description = field.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ocTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch field.type {
            case "boolean":
                Toggle("", isOn: bindingForBool(field))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            case "multiselect":
                multiselect(field)
            case "external":
                if let url = field.url.flatMap(URL.init(string:)) {
                    Link(destination: url) {
                        Label("Open external form", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
            default:
                if let options = field.options, !options.isEmpty {
                    Picker("", selection: bindingForText(field)) {
                        Text("Select an option").tag("")
                        ForEach(options) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } else {
                    TextField(field.placeholder ?? "", text: bindingForText(field))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.ocSurfaceSunken))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ocBorder, lineWidth: 0.6))
                }
            }
        }
    }

    private func multiselect(_ field: FormField) -> some View {
        let options = field.options ?? []
        return FlowLayout(spacing: 6) {
            ForEach(options) { option in
                let selected = multiValues[field.key]?.contains(option.value) ?? false
                Button {
                    var set = multiValues[field.key] ?? []
                    if selected { set.remove(option.value) } else { set.insert(option.value) }
                    multiValues[field.key] = set
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 9))
                        Text(option.label)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(selected ? Color.ocAccent : Color.ocTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(selected ? Color.ocAccent.opacity(0.10) : Color.ocHover)
                    )
                    .overlay(Capsule().strokeBorder(selected ? Color.ocAccent.opacity(0.22) : Color.ocBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var requiredRemaining: Int {
        form.fields.filter { field in
            guard field.required == true, field.type != "external" else { return false }
            switch field.type {
            case "boolean": return false
            case "multiselect": return (multiValues[field.key] ?? []).isEmpty
            default: return (textValues[field.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            }
        }.count
    }

    private func seedValues() {
        for field in form.fields {
            switch field.type {
            case "boolean":
                boolValues[field.key] = field.default?.bool ?? false
            case "multiselect":
                multiValues[field.key] = Set(field.default?.array?.compactMap(\.string) ?? [])
            case "number", "integer":
                if let number = field.default?.double {
                    textValues[field.key] = number.rounded() == number ? String(Int(number)) : String(number)
                } else {
                    textValues[field.key] = ""
                }
            default:
                textValues[field.key] = field.default?.string ?? ""
            }
        }
    }

    private func bindingForText(_ field: FormField) -> Binding<String> {
        Binding(
            get: { textValues[field.key] ?? "" },
            set: { textValues[field.key] = $0 }
        )
    }

    private func bindingForBool(_ field: FormField) -> Binding<Bool> {
        Binding(
            get: { boolValues[field.key] ?? false },
            set: { boolValues[field.key] = $0 }
        )
    }

    private func submit() {
        var answer: [String: JSONValue] = [:]
        for field in form.fields where field.hidden != true {
            switch field.type {
            case "boolean":
                answer[field.key] = .bool(boolValues[field.key] ?? false)
            case "multiselect":
                answer[field.key] = .array((multiValues[field.key] ?? []).sorted().map(JSONValue.string))
            case "number":
                if let value = Double(textValues[field.key] ?? "") { answer[field.key] = .number(value) }
            case "integer":
                if let value = Double(textValues[field.key] ?? "") { answer[field.key] = .number(value.rounded()) }
            case "external":
                break
            default:
                let value = textValues[field.key] ?? ""
                if !value.isEmpty { answer[field.key] = .string(value) }
            }
        }
        submitting = true
        Task {
            await model.replyForm(form, answer: answer)
            submitting = false
            dismiss()
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
