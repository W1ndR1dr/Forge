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
            return Surface.highlighted
        } else if isHovered {
            return Surface.elevated.opacity(0.8)
        }
        return Surface.elevated
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
                    .foregroundColor(canSubmit ? Accent.primary : .secondary.opacity(0.5))
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
                    .stroke(
                        isFocused ? Accent.primary.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: .black.opacity(isFocused ? 0.1 : 0.05),
                radius: isFocused ? 8 : 2,
                y: isFocused ? 4 : 1
            )
            .animation(SpringPreset.snappy, value: isFocused)
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

// MARK: - Scope Creep Indicator
// Shows as-you-type feedback about feature complexity
// Uses /api/quick-scope for smarter detection with local fallback

struct ScopeCreepIndicator: View {
    let text: String
    @State private var analysis: ScopeAnalysis?
    @State private var debounceTask: Task<Void, Never>?

    private let apiClient = APIClient()

    var body: some View {
        Group {
            if let analysis = analysis, analysis.hasWarning {
                HStack(spacing: Spacing.small) {
                    Image(systemName: analysis.icon)
                        .foregroundColor(analysis.color)

                    Text(analysis.message)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .background(analysis.color.opacity(0.1))
                .cornerRadius(CornerRadius.medium)
                .transition(.scaleAndFade)
            }
        }
        .animation(SpringPreset.smooth, value: analysis?.hasWarning)
        .onChange(of: text) { _, newValue in
            analyzeTextDebounced(newValue)
        }
    }

    /// Debounce analysis to avoid API spam
    private func analyzeTextDebounced(_ text: String) {
        // Cancel previous pending analysis
        debounceTask?.cancel()

        // Immediate local check for obvious issues
        if let localAnalysis = quickLocalCheck(text) {
            analysis = localAnalysis
            return
        }

        // Clear analysis for short text
        guard text.count >= 10 else {
            analysis = nil
            return
        }

        // Debounce API call (300ms)
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }

            await analyzeTextRemote(text)
        }
    }

    /// Quick local check for immediate feedback
    private func quickLocalCheck(_ text: String) -> ScopeAnalysis? {
        let lowered = text.lowercased()

        if text.count > 100 {
            return ScopeAnalysis(
                hasWarning: true,
                message: "This might be too big for one feature. Consider breaking it down.",
                icon: "exclamationmark.triangle",
                color: Accent.warning
            )
        } else if lowered.contains(" and also ") || lowered.contains(" plus ") {
            return ScopeAnalysis(
                hasWarning: true,
                message: "Scope creep detected. Focus on one thing.",
                icon: "arrow.left.arrow.right",
                color: Accent.warning
            )
        } else if lowered.contains(" additionally ") || lowered.contains(" as well as ") {
            return ScopeAnalysis(
                hasWarning: true,
                message: "Multiple features detected. Pick the most important one.",
                icon: "arrow.triangle.branch",
                color: Accent.warning
            )
        }

        return nil
    }

    /// Call quick-scope API for smarter analysis
    private func analyzeTextRemote(_ text: String) async {
        do {
            let response = try await apiClient.quickScopeCheck(text: text)

            await MainActor.run {
                if response.hasWarnings, let firstWarning = response.warnings.first {
                    analysis = ScopeAnalysis(
                        hasWarning: true,
                        message: firstWarning,
                        icon: "exclamationmark.triangle",
                        color: Accent.warning
                    )
                } else {
                    analysis = nil
                }
            }
        } catch {
            // Silent fail - local analysis is good enough
            print("Quick scope check unavailable: \(error)")
        }
    }
}

struct ScopeAnalysis: Equatable {
    let hasWarning: Bool
    let message: String
    let icon: String
    let color: Color
}

// MARK: - Enhanced Vibe Input with Scope Detection

struct VibeInputWithScope: View {
    @Binding var text: String
    let onSubmit: (String) -> Void
    let isAnalyzing: Bool
    let slotsRemaining: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            VibeInput(
                text: $text,
                isAnalyzing: isAnalyzing,
                slotsRemaining: slotsRemaining,
                onSubmit: onSubmit
            )

            ScopeCreepIndicator(text: text)
        }
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

            Divider()

            // Full state
            VibeInput(
                text: .constant(""),
                placeholder: "Slots full...",
                isAnalyzing: false,
                slotsRemaining: 0,
                onSubmit: { _ in }
            )
            .disabled(true)

            Spacer()
        }
        .padding(Spacing.large)
        .frame(width: 500, height: 300)
        .background(Surface.window)
    }
}

#Preview {
    VibeInputPreview()
}
#endif
