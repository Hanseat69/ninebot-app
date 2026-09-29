//
//  DocumentViews.swift
//  Oberfläche für die Dokumentenablage: Liste, Face-ID-Sperre, Ansicht,
//  Hinzufügen per Kamera-Scan, aus Fotos oder als Datei.
//

import SwiftUI
import PDFKit
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

struct DocumentsView: View {
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var addingKind: DocumentKind?

    var body: some View {
        Group {
            if store.isAccessible {
                documentList
            } else {
                lockedView
            }
        }
        .overlay {
            if scenePhase != .active && store.requireFaceID {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            }
        }
        .navigationTitle("Dokumente")
        .onAppear {
            if !store.isAccessible { store.unlock() }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundColor(.secondary)
            Text("Die Dokumente sind geschützt.").font(.headline)
            if let error = store.lockError {
                Text(error).font(.footnote).foregroundColor(.secondary)
            }
            Button("Mit Face ID entsperren") { store.unlock() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var documentList: some View {
        List {
            ForEach(DocumentKind.allCases) { kind in
                let documents = store.current.filter { $0.kind == kind }
                Section {
                    ForEach(documents) { document in
                        NavigationLink {
                            DocumentDetailView(documentID: document.id)
                        } label: {
                            DocumentRow(document: document)
                        }
                    }
                    Button {
                        addingKind = kind
                    } label: {
                        Label(addTitle(kind, isEmpty: documents.isEmpty), systemImage: "plus")
                    }
                } header: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }

            if !store.archive.isEmpty {
                Section {
                    NavigationLink {
                        DocumentArchiveView()
                    } label: {
                        Label("Archiv (\(store.archive.count))", systemImage: "archivebox")
                    }
                }
            }

            Section {
                Toggle("Mit Face ID schützen", isOn: $store.requireFaceID)
                Toggle("Alte Versionen archivieren", isOn: $store.keepArchive)
            } footer: {
                Text("Die Dokumente bleiben verschlüsselt auf deinem iPhone und werden nirgendwohin übertragen (nur im normalen iPhone-Backup gesichert). Die digitale Kopie ersetzt im Zweifel nicht die Originale, die du mitführen musst.")
            }
        }
        .sheet(item: $addingKind) { kind in
            DocumentEditor(kind: kind, existing: nil)
        }
    }

    private func addTitle(_ kind: DocumentKind, isEmpty: Bool) -> String {
        if isEmpty { return "Hinzufügen" }
        return kind.replacesPrevious ? "Neue Version (ersetzt die aktuelle)" : "Weiteres hinzufügen"
    }
}

struct DocumentRow: View {
    let document: ScooterDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(document.title.isEmpty ? document.kind.title : document.title)
            if !document.plate.isEmpty {
                Text("Kennzeichen \(document.plate)").font(.caption).foregroundColor(.secondary)
            }
            if let until = document.validUntil {
                Text("\(document.kind.dateLabel) \(until.formatted(date: .abbreviated, time: .omitted))"
                     + (document.isExpired ? " — abgelaufen" : ""))
                    .font(.caption)
                    .foregroundColor(document.isExpired ? .red : (document.expiresSoon ? .orange : .secondary))
            }
        }
    }
}

struct DocumentDetailView: View {
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    @State private var editing = false

    init(documentID: UUID) {
        self.documentID = documentID
    }

    @State private var shareURL: URL?
    @State private var confirmDelete = false

    var body: some View {
        DocumentLockGate {
            detail
        }
    }

    @ViewBuilder private var detail: some View {
        if let document = store.documents.first(where: { $0.id == documentID }) {
            List {
                Section {
                    PDFKitView(url: store.fileURL(for: document))
                        .frame(height: 420)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    ValueRow(title: "Art", value: document.kind.title)
                    if !document.insurer.isEmpty { ValueRow(title: "Versicherer", value: document.insurer) }
                    if !document.plate.isEmpty { ValueRow(title: "Kennzeichen", value: document.plate) }
                    if !document.contractNumber.isEmpty { ValueRow(title: "Vertragsnummer", value: document.contractNumber) }
                    if let until = document.validUntil {
                        ValueRow(title: document.kind.dateLabel, value: until.formatted(date: .long, time: .omitted))
                    }
                    if !document.notes.isEmpty { Text(document.notes) }
                    ValueRow(title: "Hinzugefügt", value: document.added.formatted(date: .abbreviated, time: .omitted))
                }
                Section {
                    if let url = shareURL {
                        ShareLink(item: url) {
                            Label("Als PDF teilen", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Bearbeiten") { editing = true }
                    Button(document.archived ? "Aus dem Archiv holen" : "Ins Archiv") {
                        store.setArchived(document.id, !document.archived)
                        dismiss()
                    }
                    Button("Löschen", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(document.title.isEmpty ? document.kind.title : document.title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { shareURL = store.shareURL(for: document) }
            .sheet(isPresented: $editing) {
                DocumentEditor(kind: document.kind, existing: document)
            }
            .confirmationDialog("Dokument endgültig löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    store.delete(document)
                    dismiss()
                }
            }
        }
    }
}

struct DocumentArchiveView: View {
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        DocumentLockGate {
            List(store.archive) { document in
                NavigationLink {
                    DocumentDetailView(documentID: document.id)
                } label: {
                    DocumentRow(document: document)
                }
            }
        }
        .navigationTitle("Archiv")
    }
}

/// Zeigt den Inhalt nur, wenn die Dokumente entsperrt sind, und verdeckt ihn,
/// sobald die App in den Hintergrund geht (auch in der App-Übersicht).
struct DocumentLockGate<Content: View>: View {
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.scenePhase) private var scenePhase
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            if store.isAccessible {
                content()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.system(size: 44)).foregroundColor(.secondary)
                    Button("Mit Face ID entsperren") { store.unlock() }
                        .buttonStyle(.borderedProminent)
                }
                .onAppear { store.unlock() }
            }
            if scenePhase != .active && store.requireFaceID {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Hinzufügen / Bearbeiten

struct DocumentEditor: View {
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    let kind: DocumentKind
    let existing: ScooterDocument?

    init(kind: DocumentKind, existing: ScooterDocument?) {
        self.kind = kind
        self.existing = existing
    }

    @State private var title = ""
    @State private var insurer = ""
    @State private var plate = ""
    @State private var contractNumber = ""
    @State private var hasDate = false
    @State private var validUntil = Date()
    @State private var notes = ""

    @State private var images: [UIImage] = []
    @State private var importedPDF: Data?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var scanning = false
    @State private var importingFile = false
    @State private var errorText: String?

    private var pageCount: Int {
        images.count + (importedPDF.flatMap { PDFDocumentPageCounter.count($0) } ?? 0)
    }

    private var canSave: Bool { existing != nil || pageCount > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if pageCount > 0 {
                        Label("\(pageCount) Seite(n) bereit", systemImage: "doc.on.doc")
                        Button("Seiten verwerfen", role: .destructive) {
                            images = []
                            importedPDF = nil
                        }
                    } else if existing != nil {
                        Text("Nur hinzufügen, wenn die Datei ersetzt werden soll.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    if VNDocumentCameraViewController.isSupported {
                        Button { scanning = true } label: {
                            Label("Mit der Kamera scannen", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("Aus Fotos", systemImage: "photo")
                    }
                    Button { importingFile = true } label: {
                        Label("PDF oder Bild aus Dateien", systemImage: "folder")
                    }
                    if let error = errorText {
                        Text(error).font(.footnote).foregroundColor(.red)
                    }
                } header: {
                    Text(existing == nil ? "Dokument" : "Datei ersetzen")
                }

                Section("Angaben") {
                    TextField("Bezeichnung (optional)", text: $title)
                    if kind == .insurance {
                        TextField("Versicherer", text: $insurer)
                        TextField("Versicherungskennzeichen", text: $plate)
                            .textInputAutocapitalization(.characters)
                        TextField("Vertragsnummer", text: $contractNumber)
                    }
                    Toggle(kind.dateLabel, isOn: $hasDate)
                    if hasDate {
                        DatePicker(kind.dateLabel, selection: $validUntil, displayedComponents: .date)
                    }
                    TextField("Notiz", text: $notes, axis: .vertical)
                }

                if kind == .insurance {
                    Section {
                        Text("Das Versicherungsjahr für E-Scooter läuft vom 1. März bis Ende Februar. Die App erinnert dich 4 Wochen und 1 Woche vorher.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(existing == nil ? kind.title : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(!canSave)
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { scanned in
                    images.append(contentsOf: scanned)
                    scanning = false
                } onCancel: {
                    scanning = false
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.pdf, .image]) { result in
                importFile(result)
            }
            .onChange(of: photoItems) { items in
                loadPhotos(items)
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        if let doc = existing {
            title = doc.title
            insurer = doc.insurer
            plate = doc.plate
            contractNumber = doc.contractNumber
            notes = doc.notes
            hasDate = doc.validUntil != nil
            validUntil = doc.validUntil ?? Date()
        } else if kind == .insurance {
            hasDate = true
            validUntil = DocumentStore.insuranceYearEnd()
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        for item in items {
            _ = item.loadTransferable(type: Data.self) { result in
                DispatchQueue.main.async {
                    if case .success(let data?) = result, let image = UIImage(data: data) {
                        images.append(image)
                    } else {
                        errorText = "Ein Foto konnte nicht geladen werden."
                    }
                }
            }
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorText = "Datei konnte nicht gelesen werden."
            return
        }
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            guard PDFDocument(data: data) != nil else {
                errorText = "Die PDF-Datei ist beschädigt oder geschützt."
                return
            }
            if let current = importedPDF {
                importedPDF = PDFDocumentPageCounter.append(data, to: current) ?? current
            } else {
                importedPDF = data
            }
        } else if let image = UIImage(data: data) {
            images.append(image)
        } else {
            errorText = "Nur PDF-Dateien und Bilder werden unterstützt."
        }
    }

    private func save() {
        let pdf = pageCount > 0 ? DocumentStore.makePDF(base: importedPDF, images: images) : nil
        if pageCount > 0 && pdf == nil {
            errorText = "Das PDF konnte nicht erstellt werden."
            return
        }
        var document = existing ?? ScooterDocument(kind: kind, title: "", fileName: "")
        document.title = title.trimmingCharacters(in: .whitespaces)
        document.insurer = insurer.trimmingCharacters(in: .whitespaces)
        document.plate = plate.trimmingCharacters(in: .whitespaces).uppercased()
        document.contractNumber = contractNumber.trimmingCharacters(in: .whitespaces)
        document.validUntil = hasDate ? validUntil : nil
        document.notes = notes

        if existing != nil {
            store.update(document, newPDF: pdf)
        } else if let pdf = pdf {
            store.add(document, pdf: pdf)
        }
        if hasDate { store.requestNotificationPermission() }
        dismiss()
    }
}

/// Kleine PDF-Hilfen für den Editor.
enum PDFDocumentPageCounter {
    static func count(_ data: Data) -> Int? {
        PDFDocument(data: data)?.pageCount
    }

    static func append(_ data: Data, to base: Data) -> Data? {
        guard let first = PDFDocument(data: base), let second = PDFDocument(data: data) else { return nil }
        for i in 0..<second.pageCount {
            if let page = second.page(at: i) { first.insert(page, at: first.pageCount) }
        }
        return first.dataRepresentation()
    }
}

// MARK: - Kamera-Scanner (VisionKit)

struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }
}
