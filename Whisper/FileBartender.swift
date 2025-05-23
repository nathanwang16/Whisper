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
        print("Saved audio file to Core Data: \(fileName)")
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
             print("Fetched \(results.count) audio files from Core Data")
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

     func fetchTranscriptFromCoreData(fileName: String) -> String? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Transcript")
        fetchRequest.predicate = NSPredicate(format: "fileName == %@", fileName)
        if let results = try? context.fetch(fetchRequest), let transcript = results.first {
            return transcript.value(forKey: "text") as? String
        }
        return nil
    }

    // MARK: - SYNC METHODS FOR COREDATA-DRIVEN ARCHITECTURE
    @MainActor
    func syncFromFirebaseToCoreData() async {
        do {
            let result = try await storageRef.listAll()
            for item in result.items {
                let metadata = try? await item.getMetadata()
                let timestamp: Date = metadata?.timeCreated ?? Date.distantPast
                let customName = metadata?.customMetadata?["customName"]
                let senderUsername = metadata?.customMetadata?["senderUsername"] ?? ""
                let senderUserID = metadata?.customMetadata?["senderUserID"] ?? ""
                let fileName = item.name
                // Try to find local file path
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let localURL = documentsPath.appendingPathComponent(fileName).path
                saveAudioFileToCoreData(fileName: fileName, customName: customName, senderUsername: senderUsername, senderUserID: senderUserID, timestamp: timestamp, localURL: localURL)
            }
        } catch {
            print("Failed to sync from Firebase: \(error.localizedDescription)")
        }
    }

    func downloadAudioFileFromFirebase(file: AudioFile) async -> URL? {
        guard let fileName = file.fileName else { return nil }
        let fileRef = storageRef.child(fileName)
        do {
            let url = try await fileRef.downloadURL()
            return url
        } catch {
            print("Failed to get download URL: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    func renameAudioFileAndSync(_ file: AudioFile, to newCustomName: String) async -> Bool {
        guard let fileName = file.fileName else { return false }
        // Update Core Data first
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "AudioFile")
        fetchRequest.predicate = NSPredicate(format: "fileName == %@", fileName)
        if let results = try? context.fetch(fetchRequest), let existing = results.first as? NSManagedObject {
            existing.setValue(newCustomName, forKey: "customName")
            try? context.save()
        }
        // Sync to Firebase
        let fileRef = storageRef.child(fileName)
        do {
            let metadata = StorageMetadata()
            metadata.customMetadata = ["customName": newCustomName]
            _ = try await fileRef.updateMetadata(metadata)
            return true
        } catch {
            print("Failed to rename audio file in Firebase: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    func deleteAudioFileAndSync(_ file: AudioFile) async {
        guard let fileName = file.fileName else { return }
        // Delete from Core Data
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "AudioFile")
        fetchRequest.predicate = NSPredicate(format: "fileName == %@", fileName)
        if let results = try? context.fetch(fetchRequest), let existing = results.first as? NSManagedObject {
            context.delete(existing)
            try? context.save()
        }
        // Delete from Firebase
        let fileRef = storageRef.child(fileName)
        do {
            try await fileRef.delete()
        } catch {
            print("Failed to delete audio file in Firebase: \(error.localizedDescription)")
        }
    }

    func transcribeAudioFileFromCoreData(_ file: AudioFile, localURL: URL, locale: Locale = Locale(identifier: "en-US")) async -> String? {
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

    func uploadTranscriptionAndSync(_ file: AudioFile, text: String) async {
        guard let fileName = file.fileName else { return }
        let txtFileName = (fileName as NSString).deletingPathExtension + ".txt"
        let fileRef = translateRef.child(txtFileName)
        guard let data = text.data(using: .utf8) else { return }
        // Save to Core Data
        saveTranscriptToCoreData(fileName: txtFileName, text: text)
        // Upload to Firebase
        do {
            _ = try await fileRef.putDataAsync(data)
        } catch {
            print("Failed to upload transcription to Firebase: \(error.localizedDescription)")
        }
    }

    // MARK: - DM USER MANAGEMENT
    // Search users in Firestore by username prefix
    func searchUsersInFirestore(prefix: String, completion: @escaping ([String]) -> Void) {
        let db = Firestore.firestore()
        let usersRef = db.collection("users")
        // Firestore doesn't support 'startsWith' natively, so use range query
        let end = prefix + "\u{f8ff}"
        usersRef
            .whereField("username", isGreaterThanOrEqualTo: prefix)
            .whereField("username", isLessThanOrEqualTo: end)
            .limit(to: 10)
            .getDocuments { snapshot, error in
                if let docs = snapshot?.documents {
                    let names = docs.compactMap { $0.data()["username"] as? String }
                    completion(names)
                } else {
                    completion([])
                }
            }
    }

    // Add user to local Core Data if exists in Firestore
    func addUserToLocalIfExists(username: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let usersRef = db.collection("users")
        usersRef.whereField("username", isEqualTo: username).getDocuments { snapshot, error in
            guard let doc = snapshot?.documents.first, let userID = doc.data()["uid"] as? String else {
                completion(false)
                return
            }
            let context = PersistenceController.shared.container.viewContext
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "User")
            fetchRequest.predicate = NSPredicate(format: "username == %@", username)
            if let results = try? context.fetch(fetchRequest), results.first != nil {
                completion(true) // Already exists locally
                return
            }
            let entity = NSEntityDescription.entity(forEntityName: "User", in: context)!
            let user = NSManagedObject(entity: entity, insertInto: context)
            user.setValue(username, forKey: "username")
            user.setValue(userID, forKey: "userID")
            try? context.save()
            completion(true)
        }
    }

    // Delete user from local Core Data
    func deleteUserFromLocal(username: String) {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "User")
        fetchRequest.predicate = NSPredicate(format: "username == %@", username)
        if let results = try? context.fetch(fetchRequest) {
            for obj in results {
                if let user = obj as? NSManagedObject {
                    context.delete(user)
                }
            }
            try? context.save()
        }
    }

    // MARK: - DM MESSAGE BACKEND
    // Helper to get DM folder name (sorted UIDs)
    private func dmFolderName(with otherUserID: String) -> String {
        let myUID = UserDefaults.standard.string(forKey: "userID") ?? ""
        return [myUID, otherUserID].sorted().joined(separator: "_")
    }

    // Upload DM message (audio file)
    @MainActor
    func uploadDMMessage(fileURL: URL, receiverUsername: String, receiverUserID: String) async {
        let fileName = fileURL.lastPathComponent
        let myUsername = UserDefaults.standard.string(forKey: "username") ?? ""
        let myUID = UserDefaults.standard.string(forKey: "userID") ?? ""
        let folder = dmFolderName(with: receiverUserID)
        let storageRef = Storage.storage().reference().child("dm/")
        let dmRef = storageRef.child("")
        let fileRef = storageRef.child("dm/")
        let dmFolderRef = Storage.storage().reference().child("dm/")
        let dmFileRef = Storage.storage().reference().child("dm/")
        let dmAudioRef = Storage.storage().reference().child("dm/")
        let dmPath = "dm/\(folder)/\(fileName)"
        let fileRef2 = Storage.storage().reference().child(dmPath)
        var metadata = StorageMetadata()
        metadata.customMetadata = [
            "senderUsername": myUsername,
            "senderUserID": myUID,
            "receiverUsername": receiverUsername,
            "receiverUserID": receiverUserID
        ]
        do {
            _ = try await fileRef2.putFileAsync(from: fileURL, metadata: metadata)
            // Firestore message doc
            let db = Firestore.firestore()
            let messageID = UUID().uuidString
            let now = Date()
            let docRef = db.collection("dmMessages").document(folder).collection("messages").document(messageID)
            try await docRef.setData([
                "messageID": messageID,
                "audioFileName": fileName,
                "senderUsername": myUsername,
                "senderUserID": myUID,
                "receiverUsername": receiverUsername,
                "receiverUserID": receiverUserID,
                "timestamp": Timestamp(date: now)
            ])
            // Save to Core Data
            saveDMMessageToCoreData(messageID: messageID, audioFileName: fileName, senderUsername: myUsername, senderUserID: myUID, receiverUsername: receiverUsername, receiverUserID: receiverUserID, timestamp: now, localURL: fileURL.path)
        } catch {
            print("Failed to upload DM message: \(error.localizedDescription)")
        }
    }

    // Fetch DM messages for a conversation
    func fetchDMMessages(with otherUserID: String, completion: @escaping ([Message]) -> Void) {
        let folder = dmFolderName(with: otherUserID)
        let db = Firestore.firestore()
        db.collection("dmMessages").document(folder).collection("messages").order(by: "timestamp").getDocuments { snapshot, error in
            guard let docs = snapshot?.documents else {
                completion([])
                return
            }
            let messages: [Message] = docs.compactMap { doc in
                let data = doc.data()
                guard let messageID = data["messageID"] as? String,
                      let audioFileName = data["audioFileName"] as? String,
                      let senderUsername = data["senderUsername"] as? String,
                      let senderUserID = data["senderUserID"] as? String,
                      let receiverUsername = data["receiverUsername"] as? String,
                      let receiverUserID = data["receiverUserID"] as? String,
                      let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else { return nil }
                // No localURL for remote fetch
                let context = PersistenceController.shared.container.viewContext
                let entity = NSEntityDescription.entity(forEntityName: "Message", in: context)!
                let msg = Message(entity: entity, insertInto: nil)
                msg.messageID = messageID
                msg.audioFileName = audioFileName
                msg.senderUsername = senderUsername
                msg.senderUserID = senderUserID
                msg.receiverUsername = receiverUsername
                msg.receiverUserID = receiverUserID
                msg.timestamp = timestamp
                return msg
            }
            completion(messages)
        }
    }

    // Save DM message to Core Data
    private func saveDMMessageToCoreData(messageID: String, audioFileName: String, senderUsername: String, senderUserID: String, receiverUsername: String, receiverUserID: String, timestamp: Date, localURL: String?) {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Message")
        fetchRequest.predicate = NSPredicate(format: "messageID == %@", messageID)
        if let results = try? context.fetch(fetchRequest), let existing = results.first as? NSManagedObject {
            existing.setValue(audioFileName, forKey: "audioFileName")
            existing.setValue(senderUsername, forKey: "senderUsername")
            existing.setValue(senderUserID, forKey: "senderUserID")
            existing.setValue(receiverUsername, forKey: "receiverUsername")
            existing.setValue(receiverUserID, forKey: "receiverUserID")
            existing.setValue(timestamp, forKey: "timestamp")
            existing.setValue(localURL, forKey: "localURL")
        } else {
            let entity = NSEntityDescription.entity(forEntityName: "Message", in: context)!
            let msg = NSManagedObject(entity: entity, insertInto: context)
            msg.setValue(messageID, forKey: "messageID")
            msg.setValue(audioFileName, forKey: "audioFileName")
            msg.setValue(senderUsername, forKey: "senderUsername")
            msg.setValue(senderUserID, forKey: "senderUserID")
            msg.setValue(receiverUsername, forKey: "receiverUsername")
            msg.setValue(receiverUserID, forKey: "receiverUserID")
            msg.setValue(timestamp, forKey: "timestamp")
            msg.setValue(localURL, forKey: "localURL")
        }
        try? context.save()
    }

    // Sync all DM messages from Firestore to Core Data for a conversation
    @MainActor
    func syncDMToCoreData(with otherUserID: String) async {
        let folder = dmFolderName(with: otherUserID)
        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("dmMessages").document(folder).collection("messages").order(by: "timestamp").getDocuments()
            for doc in snapshot.documents {
                let data = doc.data()
                guard let messageID = data["messageID"] as? String,
                      let audioFileName = data["audioFileName"] as? String,
                      let senderUsername = data["senderUsername"] as? String,
                      let senderUserID = data["senderUserID"] as? String,
                      let receiverUsername = data["receiverUsername"] as? String,
                      let receiverUserID = data["receiverUserID"] as? String,
                      let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else { continue }
                saveDMMessageToCoreData(messageID: messageID, audioFileName: audioFileName, senderUsername: senderUsername, senderUserID: senderUserID, receiverUsername: receiverUsername, receiverUserID: receiverUserID, timestamp: timestamp, localURL: nil)
            }
        } catch {
            print("Failed to sync DM messages: \(error.localizedDescription)")
        }
    }
}

struct AppAudioFile: Identifiable, Hashable {
    let id = UUID()
    let name: String // unique file name (e.g., UUID or timestamp)
    var customName: String? // user-customized name
    var downloadURL: URL?
    let timestamp: Date
}

