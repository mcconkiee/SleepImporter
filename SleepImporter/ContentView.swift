//
//  ContentView.swift
//  SleepImporter
//
//  Created by Eric McConkie on 2025-02-02.
//

import SwiftUI

struct ContentView: View {
    @State private var isFileImporterPresented = false
    @State private var selectedFileURL: URL?
    let sleepDataImporter = SleepDataImporter()
    @State private var isImporting = false;
    
    var body: some View {
        
        VStack {
            ProgressView().opacity(!isImporting ? 0 : 1)
            Button("Import CSV File") {
                isFileImporterPresented = true
            }.opacity(isImporting ? 0 : 1)
            .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.commaSeparatedText]) { result in
                switch result {
                case .success(let url):
                    selectedFileURL = url
                    isImporting = true
                    print("Imported file: \(url.path)")
                    sleepDataImporter.parseAndAddToHealth(urlPath:url.path,completion: { records in
                        DispatchQueue.main.async {
                            print("allDone!")
                            let ok = UIAlertAction(title: "Ok", style: .default,handler: {(alert: UIAlertAction!) in isImporting = false})
                            let alertController = UIAlertController(title: "Import Complete", message: "\(records.count) records imported successfully", preferredStyle: .alert)
                            alertController.addAction(ok)
                            //...
                            var rootViewController = UIApplication.shared.keyWindow?.rootViewController
                            
                            rootViewController?.present(alertController, animated: true, completion: nil)
                        }
                    })
                case .failure(let error):
                    print("Error selecting file: \(error.localizedDescription)")
                }
            }
        }
    }
}


#Preview {
    ContentView()
}
