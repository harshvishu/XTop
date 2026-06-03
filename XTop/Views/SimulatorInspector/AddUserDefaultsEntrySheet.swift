import SwiftUI

struct AddUserDefaultsEntrySheet: View {
    let existingKeys: Set<String>
    let onAdd: (String, Any) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key: String = ""
    @State private var type: PlistValueType = .string
    @State private var stringValue: String = ""
    @State private var boolValue: Bool = false
    @State private var dateValue: Date = .now
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Add UserDefaults Key")
                .font(DesignSystem.Typography.sectionTitle)

            Form {
                TextField("Key", text: $key)
                Picker("Type", selection: $type) {
                    ForEach(PlistValueType.allCases) { type in
                        if type != .array && type != .dictionary {
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                editor
            }
            .formStyle(.grouped)

            if let error {
                Text(error)
                    .font(DesignSystem.Typography.rowSecondary)
                    .foregroundStyle(DesignSystem.Colors.destructive)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 460)
    }

    @ViewBuilder
    private var editor: some View {
        switch type {
        case .bool:
            Toggle("Value", isOn: $boolValue)
        case .date:
            DatePicker("Value", selection: $dateValue, displayedComponents: [.date, .hourAndMinute])
        case .data:
            TextField("Base64 data", text: $stringValue, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
        case .array, .dictionary:
            EmptyView()
        default:
            TextField("Value", text: $stringValue, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
        }
    }

    private func commit() {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { error = "Key cannot be empty."; return }
        guard !existingKeys.contains(trimmedKey) else { error = "Key already exists."; return }
        do {
            let value = try PlistValueCoder.encodeScalar(
                stringValue: stringValue,
                boolValue: boolValue,
                dateValue: dateValue,
                type: type
            )
            onAdd(trimmedKey, value)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Encodes scalar plist values from UI inputs, preserving plist type semantics.
enum PlistValueCoder {
    enum CoderError: Error, LocalizedError {
        case invalidInteger
        case invalidDouble
        case invalidBase64
        case unsupportedType

        var errorDescription: String? {
            switch self {
            case .invalidInteger: return "Value is not a valid integer."
            case .invalidDouble: return "Value is not a valid number."
            case .invalidBase64: return "Value is not valid base64."
            case .unsupportedType: return "Cannot encode this value type."
            }
        }
    }

    static func encodeScalar(
        stringValue: String,
        boolValue: Bool,
        dateValue: Date,
        type: PlistValueType
    ) throws -> Any {
        switch type {
        case .bool:
            return NSNumber(value: boolValue)
        case .integer:
            guard let int = Int(stringValue.trimmingCharacters(in: .whitespaces)) else {
                throw CoderError.invalidInteger
            }
            return NSNumber(value: int)
        case .double:
            guard let double = Double(stringValue.trimmingCharacters(in: .whitespaces)) else {
                throw CoderError.invalidDouble
            }
            return NSNumber(value: double)
        case .string:
            return stringValue
        case .date:
            return dateValue
        case .data:
            guard let data = Data(base64Encoded: stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw CoderError.invalidBase64
            }
            return data
        case .array, .dictionary:
            throw CoderError.unsupportedType
        }
    }
}
