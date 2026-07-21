import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Create or edit a carbohydrate entry, with the quick-gram chip row.
struct CarbEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var existing: CarbEntry?

    @State private var grams: Double = 40
    @State private var timestamp = Date()
    @State private var mealType: MealType = .lunch
    @State private var food = ""
    @State private var note = ""
    @State private var showingFood = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("\(grams.formatted()) g")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.zoneHigh)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: grams)
                        Spacer()
                        Stepper("", value: $grams, in: 0...300, step: 5).labelsHidden()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(env.preferences.carbPresets, id: \.self) { preset in
                                QuickChip(label: "\(preset.formatted()) g", tint: Theme.zoneHigh) {
                                    grams = preset; Haptics.play(.selection)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                if existing == nil {
                    Section {
                        Button {
                            Haptics.play(.selection)
                            showingFood = true
                        } label: {
                            Label("Search or scan food", systemImage: "barcode.viewfinder")
                                .foregroundStyle(Theme.accent)
                        }
                    } footer: {
                        Text("Look up a food's exact carbs from Open Food Facts by name or barcode.")
                    }
                }
                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    TextField("Food (optional)", text: $food)
                    DatePicker("Time", selection: $timestamp)
                }
                Section("Note") { TextField("Optional", text: $note, axis: .vertical) }
                Section("Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label(photoData == nil ? "Add meal photo" : "Change photo", systemImage: "camera")
                            .foregroundStyle(Theme.accent)
                    }
                    #if canImport(UIKit)
                    if let photoData, let uiImage = UIImage(data: photoData) {
                        HStack(spacing: 12) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Spacer()
                            Button("Remove", role: .destructive) {
                                self.photoData = nil
                                self.photoItem = nil
                                Haptics.play(.selection)
                            }
                        }
                    }
                    #endif
                }
                if existing != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let existing { env.entryStore.delete(existing) }
                            Haptics.play(.warning); dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Log carbs" : "Edit carbs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(grams <= 0) }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
            .sheet(isPresented: $showingFood) {
                FoodSearchView(mealType: mealType) {
                    showingFood = false
                    dismiss()
                }
            }
        }
    }

    private func load() {
        guard let existing else { return }
        grams = existing.grams
        timestamp = existing.timestamp
        mealType = existing.mealType
        food = existing.foodDescription ?? ""
        note = existing.note ?? ""
        photoData = existing.photo
    }

    private func save() {
        if let existing {
            existing.grams = grams
            existing.timestamp = timestamp
            existing.mealType = mealType
            existing.foodDescription = food.isEmpty ? nil : food
            existing.note = note.isEmpty ? nil : note
            existing.photo = photoData
            env.entryStore.touch(existing)
        } else {
            let entry = env.entryStore.addCarbs(
                grams: grams, timestamp: timestamp, mealType: mealType,
                foodDescription: food.isEmpty ? nil : food,
                note: note.isEmpty ? nil : note
            )
            // `init` doesn't take a photo, so attach it after creation and
            // re-persist through the store's write path.
            if let photoData {
                entry.photo = photoData
                env.entryStore.touch(entry)
            }
        }
        Haptics.play(.success)
        dismiss()
    }
}
