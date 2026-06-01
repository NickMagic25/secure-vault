import SwiftUI

struct PasswordEditorSheet: View {
    enum Mode {
        case create
        case edit(VaultItem)

        var title: String {
            switch self {
            case .create: "New Password"
            case .edit: "Update Password"
            }
        }
    }

    let mode: Mode
    let onSave: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var app: String
    @State private var username: String
    @State private var password = ""

    init(mode: Mode, onSave: @escaping (String, String, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _app = State(initialValue: "")
            _username = State(initialValue: "")
        case .edit(let item):
            _app = State(initialValue: item.app ?? "")
            _username = State(initialValue: item.username ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("App", text: $app)
                    .disabled(isEditing)
                TextField("Username", text: $username)
                    .disabled(isEditing)
                SecureField("Password", text: $password)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(saveTitle) {
                    onSave(app, username, password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 430)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var saveTitle: String {
        isEditing ? "Update" : "Create"
    }

    private var canSave: Bool {
        !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !password.isEmpty
    }
}

struct SecretEditorSheet: View {
    enum Mode {
        case create
        case edit(VaultItem, String?)

        var title: String {
            switch self {
            case .create: "New Secret"
            case .edit: "Update Secret"
            }
        }
    }

    let mode: Mode
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var json: String

    init(mode: Mode, onSave: @escaping (String, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _json = State(initialValue: "{\n  \"KEY\": \"value\"\n}")
        case .edit(let item, let currentJSON):
            _name = State(initialValue: item.secretName ?? "")
            _json = State(initialValue: currentJSON ?? "{\n  \n}")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Name", text: $name)
                    .disabled(isEditing)

                TextEditor(text: $json)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 240)
                    .scrollContentBackground(.hidden)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(saveTitle) {
                    onSave(name, json)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 540, height: 460)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var saveTitle: String {
        isEditing ? "Update" : "Create"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
