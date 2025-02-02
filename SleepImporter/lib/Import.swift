//
//  Import.swift
//  SleepImporter
//
//  Created by Eric McConkie on 2025-02-02.
//
import Foundation
import HealthKit
// MARK: - Data Structures
struct SleepRecord {
    let id: String
    let date: Date
    let startTime: Date
    let endTime: Date
    let duration: Double  // in minutes
    let remDuration: Double?
    let awakeDuration: Double?
    let deepSleepDuration: Double?
    let lightSleepDuration: Double?
    let unknownSleepDuration: Double?
    let hrLowest: Int?
    let hrAverage: Int?
    let respirationRate: Double?
    let quality: Int?
}

protocol SleepDataImporterDelegate: AnyObject {
    func dataAddedToHealth(records: [SleepRecord])
}

class SleepDataImporter {
    private let healthStore = HKHealthStore()
    private var fileContents = String()
    weak var delegate: SleepDataImporterDelegate?

    // MARK: - Authorization
    func requestAuthorization() async throws {
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!
        ]
        
        try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToWrite)
    }
    func parseAndAddToHealth(urlPath:String,completion:@escaping([SleepRecord]) -> Void)->Void{
        
        do {
            let contents = try String(contentsOf: URL(fileURLWithPath: urlPath), encoding: .utf8)
            DispatchQueue.main.async {
                self.fileContents = contents
                Task{
                    await self._unwrapAndPersistData(completion: completion)
                }
            }
        } catch {
            print("Error reading file: \(error.localizedDescription)")
        }
    }
    private func _unwrapAndPersistData(completion:@escaping([SleepRecord]) -> Void) async{
        do{
            let authd = try await requestAuthorization()
            print(authd)
        }catch{
            print("User denied health access")
            return;
        }
        
        let records: [SleepRecord] = parseSleepCSV(csvString: fileContents)
        do{
            let addedRecords = try await self.saveSleepData(records)
            print("Added \(addedRecords) records")
//            self.delegate?.dataAddedToHealth(records: records)
            completion(records)
        }catch{
            print("Error writing data records: \(error.localizedDescription)")
        }
    }
    // MARK: - CSV Parsing
    func parseSleepCSV(csvString: String) -> [SleepRecord] {
        var records: [SleepRecord] = []
        let rows = csvString.components(separatedBy: "\n")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        // Skip header row
        for row in rows.dropFirst() where !row.isEmpty {
            let columns = row.components(separatedBy: ",")
            guard columns.count >= 14 else { continue }
            
            let dateStr = columns[1]
            let startTimeStr = columns[2]
            let endTimeStr = columns[3]
            
            guard let date = dateFormatter.date(from: dateStr),
                  let startTime = timeFormatter.date(from: startTimeStr),
                  let endTime = timeFormatter.date(from: endTimeStr) else {
                continue
            }
            
            // Combine date with time
            var calendar = Calendar.current
            calendar.timeZone = TimeZone.current
            
            var startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            var endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
            
            let finalStartDate = calendar.date(bySettingHour: startComponents.hour ?? 0,
                                             minute: startComponents.minute ?? 0,
                                             second: 0,
                                             of: date)!
            
            // Handle cases where end time is on the next day
            var finalEndDate = calendar.date(bySettingHour: endComponents.hour ?? 0,
                                           minute: endComponents.minute ?? 0,
                                           second: 0,
                                           of: date)!
            
            if finalEndDate < finalStartDate {
//                finalEndDate = calendar.date(byAddingUnit: .day, value: 1, to: finalEndDate)!
                // FIXME - being explicit here with '!'
                finalEndDate = calendar.date(byAdding: .day, value: 1, to: finalEndDate)!
            }
            
            let record = SleepRecord(
                id: columns[0],
                date: date,
                startTime: finalStartDate,
                endTime: finalEndDate,
                duration: Double(columns[4]) ?? 0,
                remDuration: Double(columns[5]),
                awakeDuration: Double(columns[6]),
                deepSleepDuration: Double(columns[7]),
                lightSleepDuration: Double(columns[8]),
                unknownSleepDuration: Double(columns[9]),
                hrLowest: Int(columns[10]),
                hrAverage: Int(columns[11]),
                respirationRate: Double(columns[12]),
                quality: Int(columns[13])
            )
            
            records.append(record)
        }
        
        return records
    }
    
    // MARK: - HealthKit Writing
    func saveSleepData(_ records: [SleepRecord]) async throws {
        for record in records {
            // Create sleep analysis samples
            var samples: [HKCategorySample] = []
            
            // Core sleep period
            let sleepSample = HKCategorySample(
                type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                start: record.startTime,
                end: record.endTime
            )
            samples.append(sleepSample)
            
            // Add detailed sleep stages if available
            if let remDuration = record.remDuration, remDuration > 0 {
                let remSample = HKCategorySample(
                    type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                    value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    start: record.startTime,
                    end: record.startTime.addingTimeInterval(remDuration * 60)
                )
                samples.append(remSample)
            }
            
            if let deepDuration = record.deepSleepDuration, deepDuration > 0 {
                let deepSample = HKCategorySample(
                    type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                    value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    start: record.startTime,
                    end: record.startTime.addingTimeInterval(deepDuration * 60)
                )
                samples.append(deepSample)
            }
            
            // Save heart rate if available
            if let avgHR = record.hrAverage {
                let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
                let hrQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()),
                                          doubleValue: Double(avgHR))
                let hrSample = HKQuantitySample(type: hrType,
                                              quantity: hrQuantity,
                                              start: record.startTime,
                                              end: record.endTime)
                try await healthStore.save(hrSample)
            }
            
            // Save respiratory rate if available
            if let respRate = record.respirationRate {
                let respType = HKObjectType.quantityType(forIdentifier: .respiratoryRate)!
                let respQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()),
                                            doubleValue: respRate)
                let respSample = HKQuantitySample(type: respType,
                                                quantity: respQuantity,
                                                start: record.startTime,
                                                end: record.endTime)
                try await healthStore.save(respSample)
            }
            
            // Save all sleep samples
            try await healthStore.save(samples)
        }
    }
}
