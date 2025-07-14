import SwiftUI
import Foundation

struct ContentView: View {
    @State private var fileExtension = ""
    @State private var sourceFolder = ""
    @State private var destinationFolder = ""
    @State private var isProcessing = false
    @State private var statusMessage = ""
    @State private var foundFiles: [String] = []
    @State private var copiedCount = 0
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("File Copier")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 15) {
                // Dateityp Eingabe
                VStack(alignment: .leading) {
                    Text("Dateityp (z.B. jpg, pdf, txt):")
                        .font(.headline)
                    TextField("Dateierweiterung eingeben", text: $fileExtension)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .help("Geben Sie die Dateierweiterung ohne Punkt ein")
                }
                
                // Quellordner
                VStack(alignment: .leading) {
                    Text("Quellordner:")
                        .font(.headline)
                    HStack {
                        TextField("Quellordner auswählen", text: $sourceFolder)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(true)
                        Button("Auswählen") {
                            selectSourceFolder()
                        }
                    }
                }
                
                // Zielordner
                VStack(alignment: .leading) {
                    Text("Zielordner:")
                        .font(.headline)
                    HStack {
                        TextField("Zielordner auswählen", text: $destinationFolder)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(true)
                        Button("Auswählen") {
                            selectDestinationFolder()
                        }
                    }
                }
            }
            .padding()
            
            // Kopieren Button
            Button(action: {
                copyFiles()
            }) {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    }
                    Text(isProcessing ? "Kopiere..." : "Dateien kopieren")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canStartCopying() ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!canStartCopying() || isProcessing)
            .padding(.horizontal)
            
            // Status Bereich
            VStack(alignment: .leading, spacing: 10) {
                if !foundFiles.isEmpty {
                    Text("Gefundene Dateien: \(foundFiles.count)")
                        .font(.headline)
                    Text("Kopiert: \(copiedCount)")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            Spacer()
        }
        .frame(minWidth: 500, minHeight: 400)
        .alert("Hinweis", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func canStartCopying() -> Bool {
        return !fileExtension.isEmpty && !sourceFolder.isEmpty && !destinationFolder.isEmpty
    }
    
    private func selectSourceFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        
        if panel.runModal() == .OK {
            sourceFolder = panel.url?.path ?? ""
        }
    }
    
    private func selectDestinationFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK {
            destinationFolder = panel.url?.path ?? ""
        }
    }
    
    private func copyFiles() {
        guard canStartCopying() else { return }
        
        isProcessing = true
        statusMessage = "Suche Dateien..."
        foundFiles = []
        copiedCount = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let sourceURL = URL(fileURLWithPath: sourceFolder)
            let destinationURL = URL(fileURLWithPath: destinationFolder)
            
            // Prüfe Berechtigungen für Quellordner
            guard sourceURL.startAccessingSecurityScopedResource() else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.alertMessage = "Keine Berechtigung für Quellordner!"
                    self.showingAlert = true
                }
                return
            }
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            
            // Prüfe Berechtigungen für Zielordner
            guard destinationURL.startAccessingSecurityScopedResource() else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.alertMessage = "Keine Berechtigung für Zielordner!"
                    self.showingAlert = true
                }
                return
            }
            defer { destinationURL.stopAccessingSecurityScopedResource() }
            
            // Prüfe ob Quellordner existiert
            guard fileManager.fileExists(atPath: sourceFolder) else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.alertMessage = "Quellordner existiert nicht!"
                    self.showingAlert = true
                }
                return
            }
            
            // Erstelle Zielordner falls nicht vorhanden
            if !fileManager.fileExists(atPath: destinationFolder) {
                do {
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                } catch {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.alertMessage = "Zielordner konnte nicht erstellt werden: \(error.localizedDescription)"
                        self.showingAlert = true
                    }
                    return
                }
            }
            
            // Finde alle Dateien mit der gewünschten Erweiterung
            let files = findFiles(in: sourceURL, withExtension: fileExtension.lowercased())
            
            DispatchQueue.main.async {
                self.foundFiles = files.map { $0.lastPathComponent }
                self.statusMessage = "Gefunden: \(files.count) Dateien. Kopiere..."
            }
            
            // Kopiere Dateien
            var successCount = 0
            var errorCount = 0
            var lastError: Error? = nil
            
            for fileURL in files {
                let fileName = fileURL.lastPathComponent
                let destinationFileURL = destinationURL.appendingPathComponent(fileName)
                
                do {
                    // Prüfe ob Datei bereits existiert und erstelle einzigartigen Namen
                    var finalDestinationURL = destinationFileURL
                    var counter = 1
                    
                    while fileManager.fileExists(atPath: finalDestinationURL.path) {
                        let nameWithoutExtension = fileName.prefix(fileName.count - fileURL.pathExtension.count - 1)
                        let newFileName = "\(nameWithoutExtension)_\(counter).\(fileURL.pathExtension)"
                        finalDestinationURL = destinationURL.appendingPathComponent(newFileName)
                        counter += 1
                    }
                    
                    try fileManager.copyItem(at: fileURL, to: finalDestinationURL)
                    successCount += 1
                    
                    DispatchQueue.main.async {
                        self.copiedCount = successCount
                        self.statusMessage = "Kopiert: \(successCount) von \(files.count) Dateien"
                    }
                } catch {
                    errorCount += 1
                    lastError = error
                    print("Fehler beim Kopieren von \(fileName): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                if errorCount == 0 {
                    self.statusMessage = "Erfolgreich \(successCount) Dateien kopiert!"
                    self.alertMessage = "Alle \(successCount) Dateien wurden erfolgreich kopiert!"
                } else {
                    self.statusMessage = "\(successCount) Dateien kopiert, \(errorCount) Fehler"
                    let errorDetail = lastError?.localizedDescription ?? "Unbekannter Fehler"
                    self.alertMessage = "\(successCount) Dateien kopiert, \(errorCount) Dateien konnten nicht kopiert werden.\n\nLetzter Fehler: \(errorDetail)"
                }
                self.showingAlert = true
            }
        }
    }
    
    private func findFiles(in directory: URL, withExtension extension: String) -> [URL] {
        let fileManager = FileManager.default
        var files: [URL] = []
        
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return files
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    if fileURL.pathExtension.lowercased() == `extension` {
                        files.append(fileURL)
                    }
                }
            } catch {
                print("Fehler beim Lesen der Datei \(fileURL): \(error)")
            }
        }
        
        return files
    }
}

#Preview {
    ContentView()
}
