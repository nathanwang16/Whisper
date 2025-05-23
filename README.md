Whisper

========================

Frontend xcode+Swift+SwiftUI(instead of UIKit); backend using firebase, where firebase cloud storage
for audio file storage and firebase firestore for meta data storage.

files are also saved locally in a core data model.

usernames, and the device uuid randomly assigned is used to identify the user.

The original view is the contentView, with FileListView as a subview to see all the audio files

Now migrating to DMView. 

FileBartender handles most of the file logics, uploading, downloading, syncing, persisting files.

AudioRecorder plays and records audio files. 

Persistence.swift contains handles for core data model.

Firebase is a required package dependency, simply search and click add

Inject is for my personal use, so to see real-time update from code writen by cursor AI

