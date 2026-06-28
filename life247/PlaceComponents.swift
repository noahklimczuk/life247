//
//  PlaceComponents.swift
//  life247
//
//  Reusable place (geofence) creation & editing UI.
//

import SwiftUI
import CoreLocation

struct PlaceEditorView: View {
    enum Mode {
        case add(coordinate: CLLocationCoordinate2D, suggestedName: String)
        case edit(zone: GeofenceZone)
    }

    let mode: Mode
    let onSave: (GeofenceZone) -> Void
    var onDelete: ((GeofenceZone) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "📍"
    @State private var radius: Double = 150

    private let emojiChoices = ["🏠", "🏢", "🏫", "🛒", "🏋️", "☕️", "🌳", "🏥", "✈️", "❤️", "⭐️", "📍"]

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Home, Work, Gym", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiChoices, id: \.self) { symbol in
                            Text(symbol)
                                .font(.title2)
                                .frame(width: 42, height: 42)
                                .background(
                                    Circle().fill(emoji == symbol ? Color.purple.opacity(0.2) : Color(.tertiarySystemFill))
                                )
                                .overlay(
                                    Circle().stroke(emoji == symbol ? Color.purple : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture { emoji = symbol }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Radius")
                            Spacer()
                            Text("\(Int(radius)) m").foregroundColor(.secondary)
                        }
                        Slider(value: $radius, in: 50...1000, step: 25).tint(.purple)
                    }
                } header: {
                    Text("Arrival Radius")
                } footer: {
                    Text("How close you need to be for this place to register an arrival.")
                }

                if isEditing, let onDelete, case .edit(let zone) = mode {
                    Section {
                        Button(role: .destructive) {
                            onDelete(zone)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Place")
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Place" : "New Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: seed)
        }
    }

    private func seed() {
        switch mode {
        case .add(_, let suggestedName):
            if name.isEmpty { name = suggestedName }
        case .edit(let zone):
            name = zone.name
            emoji = zone.emojiIcon
            radius = zone.radius
        }
    }

    private func save() {
        let zone: GeofenceZone
        switch mode {
        case .add(let coordinate, _):
            zone = GeofenceZone(
                id: UUID(),
                name: trimmedName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radius: radius,
                emojiIcon: emoji
            )
        case .edit(let existing):
            zone = GeofenceZone(
                id: existing.id,
                name: trimmedName,
                latitude: existing.latitude,
                longitude: existing.longitude,
                radius: radius,
                emojiIcon: emoji
            )
        }
        onSave(zone)
        dismiss()
    }
}

/// Lightweight wrapper so a pending "add place" result can drive a `.sheet(item:)`.
struct PendingPlace: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let suggestedName: String
}
