import SwiftUI

/// Section management. Every change takes effect from the selected month onward.
struct OrganizeSheet: View {
    let month: YearMonth
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var addingSection = false
    @State private var newSectionName = ""
    /// NavigationLink doesn't fire while a list is in edit mode, so rows push onto this path instead.
    @State private var path: [UUID] = []

    private var categories: [MonthCategory] { model.store.view(for: month).allCategories }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(categories) { category in
                        Button { path.append(category.id) } label: {
                            HStack {
                                Text(category.title).foregroundStyle(CushnColor.primaryText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CushnColor.secondaryText)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("organizeRow.\(category.title)")
                    }
                    .onMove { source, destination in
                        var ids = categories.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        model.attempt { try model.store.reorderCategories(ids, month: month) }
                    }
                    .listRowBackground(CushnColor.canvas)
                } footer: {
                    Text("Changes apply from \(DateText.monthName(month)) onward. Earlier months stay as they are.")
                        .foregroundStyle(CushnColor.secondaryText)
                }
                Section {
                    Button("Add section") {
                        newSectionName = ""
                        addingSection = true
                    }
                    .tint(CushnColor.primaryText)
                    .accessibilityIdentifier("addSection")
                    .listRowBackground(CushnColor.canvas)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CushnColor.surface)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Organize")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { SectionEditorView(categoryID: $0, month: month) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("New section", isPresented: $addingSection) {
                TextField("Name", text: $newSectionName)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    let name = newSectionName
                    model.attempt { try model.store.addCategory(name: name, month: month) }
                }
                .disabled(newSectionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// A section's editor on its own, opened from its heading on Home.
struct SectionEditorSheet: View {
    let categoryID: UUID
    let month: YearMonth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SectionEditorView(categoryID: categoryID, month: month)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

/// Rename, classify, reorder rows in, or remove one section.
struct SectionEditorView: View {
    let categoryID: UUID
    let month: YearMonth
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmingRemove = false

    private var view: MonthView { model.store.view(for: month) }
    private var category: MonthCategory? { view.allCategories.first { $0.id == categoryID } }
    private var rows: [MonthRow] { view.sections.first { $0.id == categoryID }?.rows ?? [] }

    var body: some View {
        List {
            Section("Name") {
                TextField("Section name", text: $name)
                    .submitLabel(.done)
                    .onSubmit(commitName)
                    .accessibilityIdentifier("sectionNameField")
            }
            if let category {
                Section {
                    Picker("Counts as", selection: Binding(
                        get: { category.kind },
                        set: { kind in model.attempt { try model.store.setCategoryKind(id: categoryID, kind: kind, month: month) } }
                    )) {
                        ForEach(ReportingKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("Only used for the Estimated expenses figure in Overview.")
                }
            }
            if !rows.isEmpty {
                Section("Order") {
                    ForEach(rows) { Text($0.name) }
                        .onMove { source, destination in
                            var ids = rows.map(\.id)
                            ids.move(fromOffsets: source, toOffset: destination)
                            model.attempt { try model.store.reorderPayments(ids, month: month) }
                        }
                }
                .environment(\.editMode, .constant(.active))
            }
            if category?.isOther == false {
                Section {
                    Button("Remove section", role: .destructive) { confirmingRemove = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CushnColor.surface)
        .navigationTitle(category?.title ?? "Section")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = category?.title ?? "" }
        .onDisappear(perform: commitName)
        .alert("Remove section from \(DateText.monthName(month)) onward?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                model.attempt { try model.store.removeCategory(id: categoryID, month: month) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its payments move to Other from \(DateText.monthName(month)). Earlier months stay as they are.")
        }
    }

    private func commitName() {
        guard let category, name != category.title,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.attempt { try model.store.renameCategory(id: categoryID, name: name, month: month) }
    }
}

extension ReportingKind {
    var title: String {
        switch self {
        case .expense: "Expense"
        case .creditRepayment: "Credit repayment"
        case .investment: "Investment"
        case .transfer: "Transfer"
        case .unclassified: "Unclassified"
        }
    }
}
