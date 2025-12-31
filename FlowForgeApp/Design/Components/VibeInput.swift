import SwiftUI

// MARK: - Vibe Input
// The iconic UX: just type what you want to ship
//
// Influenced by: Bret Victor (immediate feedback), Dieter Rams (innovative, understandable)
// "Natural language in, structured feature out"

struct VibeInput: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: (String) -> Void
    let isAnalyzing: Bool
    let slotsRemaining: Int

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    init(
        text: Binding<String>,
        placeholder: String = "What do you want to ship?",
        isAnalyzing: Bool = false,
        slotsRemaining: Int = 3,
        onSubmit: @escaping (String) -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isAnalyzing = isAnalyzing
        self.slotsRemaining = slotsRemaining
        self.onSubmit = onSubmit
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isAnalyzing &&
        slotsRemaining > 0
    }

    private var inputBackground: Color {
        if isFocused {
            return Linear.surface
        } else if isHovered {
            return Linear.hoverBackground
        }
        return Linear.surface
    }

    private var borderColor: Color {
        if isFocused {
            return Linear.borderFocus
        } else if isHovered {
            return Linear.borderHover
        }
        return Linear.border
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            // Main input container
            HStack(spacing: Spacing.medium) {
                // Input field
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(Typography.vibeInput)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .lineLimit(1...3)
                    .onSubmit {
                        if canSubmit {
                            submitFeature()
                        }
                    }

                // Submit button
                Button(action: submitFeature) {
                    Group {
                        if isAnalyzing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                        }
                    }
                    .foregroundColor(canSubmit ? Linear.accent : Linear.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .pressable(isPressed: false)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, Spacing.standard)
            .padding(.vertical, Spacing.medium)
            .background(inputBackground)
            .cornerRadius(CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(borderColor, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }

            // Ideas are unlimited - discipline comes at START, not CAPTURE
        }
    }

    private func submitFeature() {
        guard canSubmit else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(trimmed)
    }
}

// MARK: - Enhanced Vibe Input (Real AI analysis happens on submit, not as-you-type)

struct VibeInputWithScope: View {
    @Binding var text: String
    let onSubmit: (String) -> Void
    let isAnalyzing: Bool
    let slotsRemaining: Int

    var body: some View {
        // Just the input - real AI analysis happens when you submit
        VibeInput(
            text: $text,
            isAnalyzing: isAnalyzing,
            slotsRemaining: slotsRemaining,
            onSubmit: onSubmit
        )
    }
}

// MARK: - Preview

#if DEBUG
struct VibeInputPreview: View {
    @State private var text = ""
    @State private var isAnalyzing = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            // Normal state
            VibeInputWithScope(
                text: $text,
                onSubmit: { idea in
                    print("Submitted: \(idea)")
                    isAnalyzing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isAnalyzing = false
                        text = ""
                    }
                },
                isAnalyzing: isAnalyzing,
                slotsRemaining: 2
            )

            Spacer()
        }
        .padding(Spacing.large)
        .frame(width: 500, height: 300)
        .background(Linear.background)
    }
}

#Preview {
    VibeInputPreview()
}
#endif
