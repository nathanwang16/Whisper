//
//  FileBartender.swift
//  Walkie_Talkie
//
//  Created by Nathan Wang on 4/24/25.
//

import Foundation
import FirebaseStorage

class AudioFileManager: ObservableObject {
    static let shared = AudioFileManager()
    @Published var audioFiles: [AudioFile] = [] // AudioFile is a struct with name, downloadURL, and timestamp
    private let storage = Storage.storage()
    private let storageRef: StorageReference
    
    private init() {
        self.storageRef = storage.reference().child("audio")
    }
    
    // MARK: - List Files
    @MainActor
    func fetchAudioFiles() async {
        do {
            let result = try await storageRef.listAll()
            var files: [AudioFile] = []
            for item in result.items {
                let metadata = try? await item.getMetadata()
                let timestamp = metadata?.timeCreated ?? Date.distantPast
                files.append(AudioFile(name: item.name, downloadURL: nil, timestamp: timestamp))
            }
            self.audioFiles = files.sorted { $0.timestamp > $1.timestamp }
        } catch {
            print("Failed to list audio files: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Upload File
    @MainActor
    func uploadAudioFile(_ fileURL: URL) async {
        let fileName = fileURL.lastPathComponent
        let fileRef = storageRef.child(fileName)
        do {
            _ = try await fileRef.putFileAsync(from: fileURL)
            await fetchAudioFiles()
        } catch {
            print("Failed to upload audio file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Delete File
    @MainActor
    func deleteAudioFile(_ file: AudioFile) async {
        let fileRef = storageRef.child(file.name)
        do {
            try await fileRef.delete()
            await fetchAudioFiles()
        } catch {
            print("Failed to delete audio file: \(error.localizedDescription)")
        }
    }

    // MARK: - Download File
    func downloadAudioFile(_ file: AudioFile) async -> URL? {
        let fileRef = storageRef.child(file.name)
        do {
            let url = try await fileRef.downloadURL()
            return url
        } catch {
            print("Failed to get download URL: \(error.localizedDescription)")
            return nil
        }
    }
}

struct AudioFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var downloadURL: URL?
    let timestamp: Date
}

