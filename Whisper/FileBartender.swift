//
//  FileBartender.swift
//  Walkie_Talkie
//
//  Created by Nathan Wang on 4/24/25.
//

import Foundation
import FirebaseStorage
import Speech
import FirebaseFirestore
import CoreData

class AudioFileManager: ObservableObject {
    static let shared = AudioFileManager()
    @Published var audioFiles: [AppAudioFile] = [] // AudioFile is a struct with name, downloadURL, and timestamp
    private let storage = Storage.storage()
    private let storageRef: StorageReference
    private let translateRef: StorageReference
    
    private init() {
        self.storageRef = storage.reference().child("audio")
        self.translateRef = storage.reference().child("translate")
    }
    
    // MARK: - List Files
    @MainActor
    func fetchAudioFiles() async {
        // Load from Core Data first
        self.audioFiles = fetchAudioFilesFromCoreData().sorted { $0.timestamp > $1.timestamp }
        do {
            let result = try await storageRef.listAll()
            var files: [AppAudioFile] = []
            for item in result.items {
                let metadata = try? await item.getMetadata()
                let timestamp: Date = metadata?.timeCreated ?? Date.distantPast
                let customName = metadata?.customMetadata?["customName"]
                files.append(AppAudioFile(name: item.name, customName: customName, downloadURL: nil, timestamp: timestamp))
            }
            self.audioFiles = files.sorted { $0.timestamp > $1.timestamp }
        } catch {
            print("Failed to list audio files: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Upload File (with optional customName)
    @MainActor
    func uploadAudioFile(_ fileURL: URL, customName: String? = nil) async {
        let fileName = fileURL.lastPathComponent
        let fileRef = storageRef.child(fileName)
        var metadata = StorageMetadata()
        var customMetadata: [String: String] = [:]
        if let customName = customName {
            customMetadata["customName"] = customName
        }
        // Add sender info
        let username = UserDefaults.standard.string(forKey: "username") ?? ""
        let userID = UserDefaults.standard.string(forKey: "userID") ?? ""
        customMetadata["senderUsername"] = username
        customMetadata["senderUserID"] = userID
        metadata.customMetadata = customMetadata
        do {
            _ = try await fileRef.putFileAsync(from: fileURL, metadata: metadata)
            // Add Firestore doc for audio metadata
            let db = Firestore.firestore()
            let docRef = db.collection("audioMetadata").document(fileName)
            try await docRef.setData([
                "fileName": fileName,
                "customName": customName ?? "",
                "senderUsername": username,
                "senderUserID": userID,
                "timestamp": FieldValue.serverTimestamp()
            ])
            // Save to Core Data
            let now = Date()
            saveAudioFileToCoreData(fileName: fileName, customName: customName, senderUsername: username, senderUserID: userID, timestamp: now, localURL: fileURL.path)
            await fetchAudioFiles()
        } catch {
            print("Failed to upload audio file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Delete File
    @MainActor
    func deleteAudioFile(_ file: AppAudioFile) async {
        let fileRef = storageRef.child(file.name)
        do {
            try await fileRef.delete()
            await fetchAudioFiles()
        } catch {
            print("Failed to delete audio file: \(error.localizedDescription)")
        }
    }

    // MARK: - Download File
    func downloadAudioFile(_ file: AppAudioFile) async -> URL? {
        let fileRef = storageRef.child(file.name)
        do {
            let url = try await fileRef.downloadURL()
            return url
        } catch {
            print("Failed to get download URL: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Rename File (update customName in metadata)
    @MainActor
    func renameAudioFile(_ file: AppAudioFile, to newCustomName: String) async -> Bool {
        let fileRef = storageRef.child(file.name)
        do {
            let metadata = StorageMetadata()
            metadata.customMetadata = ["customName": newCustomName]
            _ = try await fileRef.updateMetadata(metadata)
            await fetchAudioFiles()
            return true
        } catch {
            print("Failed to rename audio file: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Transcription
    func transcriptionFileName(for audioFile: AppAudioFile) -> String {
        let base = (audioFile.name as NSString).deletingPathExtension
        return base + ".txt"
    }
    
    func checkTranscriptionExists(for audioFile: AppAudioFile) async -> Bool {
        let fileName = transcriptionFileName(for: audioFile)
        let fileRef = translateRef.child(fileName)
        do {
            _ = try await fileRef.getMetadata()
            return true
        } catch {
            return false
        }
    }
    
    func fetchTranscription(for audioFile: AppAudioFile) async -> String? {
        let fileName = transcriptionFileName(for: audioFile)
        let fileRef = translateRef.child(fileName)
        do {
            let url = try await fileRef.downloadURL()
            let data = try Data(contentsOf: url)
            return String(data: data, encoding: .utf8)
        } catch {
            print("Failed to fetch transcription: \(error.localizedDescription)")
            return nil
        }
    }
    
    func uploadTranscription(for audioFile: AppAudioFile, text: String) async {
        let fileName = transcriptionFileName(for: audioFile)
        let fileRef = translateRef.child(fileName)
        guard let data = text.data(using: .utf8) else { return }
        do {
            _ = try await fileRef.putDataAsync(data)
            // Save to Core Data
            saveTranscriptToCoreData(fileName: fileName, text: text)
        } catch {
            print("Failed to upload transcription: \(error.localizedDescription)")
        }
    }
    
    func transcribeAudioFile(_ audioFile: AppAudioFile, localURL: URL, locale: Locale = Locale(identifier: "en-US")) async -> String? {
        let recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer = recognizer, recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: localURL)
        return await withCheckedContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error = error {
                    print("Transcription error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Core Data Helpers
    private var context: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    private func saveAudioFileToCoreData(fileName: String, customName: String?, senderUsername: String, senderUserID: String, timestamp: Date, localURL: String) {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "AudioFile")
        fetchRequest.predicate = NSPredicate(format: "fileName == %@", fileName)
        if let results = try? context.fetch(fetchRequest), let existing = results.first as? NSManagedObject {
            existing.setValue(customName, forKey: "customName")
            existing.setValue(senderUsername, forKey: "senderUsername")
            existing.setValue(senderUserID, forKey: "senderUserID")
            existing.setValue(timestamp, forKey: "timestamp")
            existing.setValue(localURL, forKey: "localURL")
        } else {
            let entity = NSEntityDescription.entity(forEntityName: "AudioFile", in: context)!
            let audioFile = NSManagedObject(entity: entity, insertInto: context)
            audioFile.setValue(fileName, forKey: "fileName")
            audioFile.setValue(customName, forKey: "customName")
            audioFile.setValue(senderUsername, forKey: "senderUsername")
            audioFile.setValue(senderUserID, forKey: "senderUserID")
            audioFile.setValue(timestamp, forKey: "timestamp")
            audioFile.setValue(localURL, forKey: "localURL")
        }
        try? context.save()
    }

    private func saveTranscriptToCoreData(fileName: String, text: String) {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Transcript")
        fetchRequest.predicate = NSPredicate(format: "fileName == %@", fileName)
        if let results = try? context.fetch(fetchRequest), let existing = results.first as? NSManagedObject {
            existing.setValue(text, forKey: "text")
        } else {
            let entity = NSEntityDescription.entity(forEntityName: "Transcript", in: context)!
            let transcript = NSManagedObject(entity: entity, insertInto: context)
            transcript.setValue(fileName, forKey: "fileName")
            transcript.setValue(text, forKey: "text")
        }
        try? context.save()
    }

    private func fetchAudioFilesFromCoreData() -> [AppAudioFile] {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "AudioFile")
        if let results = try? context.fetch(fetchRequest) {
            return results.compactMap { obj in
                guard let fileName = obj.value(forKey: "fileName") as? String,
                      let timestamp = obj.value(forKey: "timestamp") as? Date else { return nil }
                let customName = obj.value(forKey: "customName") as? String
                // downloadURL is not persisted locally, so set to nil
                return AppAudioFile(name: fileName, customName: customName, downloadURL: nil, timestamp: timestamp)
            }
        }
        return []
    }

    private func fetchTranscriptFromCoreData(fileName: String) -> String? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Transcript")
        fetchRequest.predicate = NSPredicate(format: "fileName == %@", fileName)
        if let results = try? context.fetch(fetchRequest), let transcript = results.first {
            return transcript.value(forKey: "text") as? String
        }
        return nil
    }
}

struct AppAudioFile: Identifiable, Hashable {
    let id = UUID()
    let name: String // unique file name (e.g., UUID or timestamp)
    var customName: String? // user-customized name
    var downloadURL: URL?
    let timestamp: Date
}

