import SwiftUI
import PhotosUI

/// Type a size measured with a gauge, caliper or ruler and check it against the rules.
struct ManualEntryView: View {
    let species: Species
    var onCancel: () -> Void
    var onContinue: (ScanDraft) -> Void

    @AppStorage(SettingsKey.useMetric) private var useMetric = false
    @State private var sizeText = ""
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var photo: UIImage? = nil
    @FocusState private var sizeFocused: Bool

    private var parsedInches: Double? {
        let text = sizeText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(text), value > 0 else { return nil }
        let inches = useMetric ? Units.inches(fromCentimeters: value) : value
        return inches < 200 ? inches : nil
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    SpeciesGlyph(species: species, size: 48)
                    VStack(alignment: .leading) {
                        Text(species.commonName).font(.headline)
                        Text(species.measurementLabel).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                MeasureDiagram(species: species, height: 110)
            }

            Section {
                HStack {
                    TextField(useMetric ? "e.g. 13.5" : "e.g. 5.25", text: $sizeText)
                        .keyboardType(.decimalPad)
                        .focused($sizeFocused)
                        .font(.title2.monospacedDigit())
                    Text(Units.unitLabel(metric: useMetric))
                        .foregroundStyle(.secondary)
                }
                Text(species.howToMeasure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Size")
            }

            Section {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(photo == nil ? "Add a photo" : "Change photo", systemImage: "photo")
                }
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } header: {
                Text("Photo (optional)")
            }

            Section {
                Button {
                    guard let inches = parsedInches else { return }
                    var draft = ScanDraft(speciesID: species.id, rawInches: inches, uncertaintyInches: 0, method: .manual)
                    draft.photo = photo
                    onContinue(draft)
                } label: {
                    Label("Check the rules", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedInches == nil)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Enter a size")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    photo = image
                }
            }
        }
        .onAppear { sizeFocused = true }
    }
}
