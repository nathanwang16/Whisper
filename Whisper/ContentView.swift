//
//  ContentView.swift
//  Walkie_Talkie
//
//  Created by Nathan Wang on 4/19/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        VStack {
            Spacer()
            Circle()
                .foregroundStyle(.tint)
                .scaleEffect(viewModel.isPressed ? 1.5 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isPressed)
                .aspectRatio(1.618, contentMode: .fit)
                .padding()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            viewModel.handleGestureChange()
                        }
                        .onEnded { _ in
                            viewModel.handleGestureEnd()
                        }
                )
                .padding(.bottom, 50)
            Spacer()
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .frame(width: 300, height: 60)
                .foregroundStyle(.black)
                .overlay(
                    Text("Files")
                        .foregroundColor(.white)
                        .font(.headline)
                )
                .onTapGesture {
                    viewModel.showAudioFiles()
                }
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.isShowingAudioFiles) {
            AudioFilesListView()
        }
    }
}

