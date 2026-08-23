import SwiftUI

/// Lets the signed-in user self-declare a university + Greek chapter from
/// the verified directory. Self-declared, not verified membership — the
/// picker only ever offers real chapters, it never lets you type one in.
struct AffiliationPickerView: View {
    let onSaved: (University?, GreekChapter?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var universities: [University] = []
    @State private var selectedUniversity: University?
    @State private var chapters: [GreekChapter] = []
    @State private var isLoadingUniversities = true
    @State private var isLoadingChapters = false
    @State private var isSaving = false
    @State private var searchText = ""

    private var filteredUniversities: [University] {
        guard !searchText.isEmpty else { return universities }
        return universities.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()

                if let university = selectedUniversity {
                    chapterStep(university)
                } else {
                    universityStep
                }
            }
            .navigationTitle(selectedUniversity == nil ? "Tu universidad" : "Tu capítulo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if selectedUniversity != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Atrás") { selectedUniversity = nil; chapters = [] }
                    }
                }
            }
            .task { await loadUniversities() }
        }
    }

    private var universityStep: some View {
        VStack(spacing: 0) {
            if isLoadingUniversities {
                ProgressView().tint(Color.bpAmber).padding(.top, 40)
                Spacer()
            } else {
                List {
                    Button {
                        isSaving = true
                        Task {
                            try? await RepositoryDependencies.profileAffiliation.setAffiliation(universityId: nil, chapterId: nil)
                            onSaved(nil, nil)
                            dismiss()
                        }
                    } label: {
                        Text("Sin afiliación").foregroundStyle(Color.bpTextSecondary)
                    }
                    ForEach(filteredUniversities) { uni in
                        Button {
                            selectedUniversity = uni
                            Task { await loadChapters(for: uni) }
                        } label: {
                            HStack {
                                Text(uni.name).foregroundStyle(Color.bpInk)
                                Spacer()
                                Text(uni.city).font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Buscar universidad")
            }
        }
    }

    private func chapterStep(_ university: University) -> some View {
        VStack(spacing: 0) {
            if isLoadingChapters {
                ProgressView().tint(Color.bpAmber).padding(.top, 40)
                Spacer()
            } else if chapters.isEmpty {
                Spacer()
                Text("Todavía no verificamos capítulos para \(university.name)")
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            } else {
                List {
                    Button {
                        save(university: university, chapter: nil)
                    } label: {
                        Text("Solo la universidad, sin capítulo").foregroundStyle(Color.bpTextSecondary)
                    }
                    ForEach(GreekCouncil.allCases, id: \.self) { council in
                        let list = chapters.filter { $0.council == council }
                        if !list.isEmpty {
                            Section(council.label) {
                                ForEach(list) { chapter in
                                    Button {
                                        save(university: university, chapter: chapter)
                                    } label: {
                                        Text(chapter.fraternityName).foregroundStyle(Color.bpInk)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func save(university: University, chapter: GreekChapter?) {
        isSaving = true
        Task {
            try? await RepositoryDependencies.profileAffiliation.setAffiliation(universityId: university.id, chapterId: chapter?.id)
            onSaved(university, chapter)
            dismiss()
        }
    }

    private func loadUniversities() async {
        universities = (try? await RepositoryDependencies.greekLife.allUniversities()) ?? []
        isLoadingUniversities = false
    }

    private func loadChapters(for university: University) async {
        isLoadingChapters = true
        chapters = (try? await RepositoryDependencies.greekLife.chapters(forUniversity: university.id)) ?? []
        isLoadingChapters = false
    }
}
