import SwiftUI

struct GymPlanImportPasteView: View {
    @Binding var pastedText: String
    var isAnalysing: Bool
    var errorMessage: String?
    var showsRetry: Bool = false
    var onAnalyse: () -> Void
    var onRetry: () -> Void
    var onCancel: () -> Void

    var body: some View {
        Form {
            Section {
                TextEditor(text: $pastedText)
                    .frame(minHeight: 220)
                    .accessibilityLabel("Trainer program text")
            } header: {
                Text("Paste program")
            } footer: {
                Text("Paste the workout program your trainer sent you. Nothing is saved until you review and tap Save Plan.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(DSColor.destructiveCoral)
                    if showsRetry {
                        Button("Retry", action: onRetry)
                    }
                }
            }
        }
        .navigationTitle("Paste Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isAnalysing ? "Analysing…" : "Analyse") {
                    onAnalyse()
                }
                .disabled(isAnalysing || pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct GymPlanImportSourcePickerView: View {
    var onPaste: () -> Void
    var onPhoto: () -> Void
    var onFile: () -> Void
    var onCancel: () -> Void

    var body: some View {
        List {
            Section {
                Button {
                    onPaste()
                } label: {
                    Label("Paste Text", systemImage: "doc.text")
                }
                Button {
                    onPhoto()
                } label: {
                    Label("Photo of Program", systemImage: "camera")
                }
                Button {
                    onFile()
                } label: {
                    Label("PDF or File", systemImage: "doc.richtext")
                }
            } footer: {
                Text("Your trainer’s source is only used for analysis and is not saved unless you choose to keep it.")
            }
        }
        .navigationTitle("Import Trainer Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
