import Foundation
import HealthKit

// ════════════════════════════════════════════════════════════
// Illness Detector — Multi-Signal Z-Score Illness Sentinel
// Extension on HealthEngine for pre-symptomatic illness detection
//
// Research basis:
//   - Mishra/Snyder 2020 (Nature Biomed Eng): 85% pre-symptomatic detection
//     using personalized z-scores. 2-of-3 rule reduces false positives.
//   - Respiratory rate is the earliest signal (~3 days before symptoms)
//   - Extended to 2-of-4 with HealthKit step count (Stanford)
// ════════════════════════════════════════════════════════════

extension HealthEngine {

    // MARK: - HealthKit Step Count

    /// Fetch today's step count from HealthKit (for illness detection + daily activity context)
    func fetchTodaySteps() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let readTypes: Set<HKObjectType> = [stepType]

        healthStore.requestAuthorization(toShare: nil, read: readTypes) { [weak self] granted, _ in
            guard granted else { return }

            let now = Date()
            let startOfDay = Calendar.current.startOfDay(for: now)
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                guard let sum = result?.sumQuantity() else { return }
                let steps = Int(sum.doubleValue(for: .count()))
                DispatchQueue.main.async {
                    self?.todaySteps = steps
                }
            }
            self?.healthStore.execute(query)
        }
    }

    // MARK: - Illness Deviation Check

    func checkIllnessDeviation() {
        var dailyRHR = UserDefaults.standard.array(forKey: dailyRHRKey) as? [Double] ?? []
        var dailyHRV = UserDefaults.standard.array(forKey: dailyHRVKey) as? [Double] ?? []
        var dailyRR = UserDefaults.standard.array(forKey: dailyRRKey) as? [Double] ?? []
        var dailySteps = UserDefaults.standard.array(forKey: dailyStepsKey) as? [Double] ?? []

        // Add today's values
        let todayRHR = recentHR.isEmpty ? baselineRHR : recentHR.suffix(30).reduce(0, +) / Double(min(recentHR.count, 30))
        let todayHRV = currentRMSSD > 0 ? currentRMSSD : baselineHRV
        let todayRR = respiratoryRate > 0 ? respiratoryRate : 15.0
        let stepsValue = Double(todaySteps)

        dailyRHR.append(todayRHR)
        dailyHRV.append(todayHRV)
        dailyRR.append(todayRR)
        if stepsValue > 0 { dailySteps.append(stepsValue) }
        if dailyRHR.count > 16 { dailyRHR.removeFirst(dailyRHR.count - 16) }
        if dailyHRV.count > 16 { dailyHRV.removeFirst(dailyHRV.count - 16) }
        if dailyRR.count > 16 { dailyRR.removeFirst(dailyRR.count - 16) }
        if dailySteps.count > 16 { dailySteps.removeFirst(dailySteps.count - 16) }

        UserDefaults.standard.set(dailyRHR, forKey: dailyRHRKey)
        UserDefaults.standard.set(dailyHRV, forKey: dailyHRVKey)
        UserDefaults.standard.set(dailyRR, forKey: dailyRRKey)
        UserDefaults.standard.set(dailySteps, forKey: dailyStepsKey)

        guard dailyRHR.count >= 7 else { return }

        // 14-day baseline with 1-day lag
        let baseRHR = Array(dailyRHR.dropLast(1).suffix(14))
        let baseHRV = Array(dailyHRV.dropLast(1).suffix(14))
        let baseRR = Array(dailyRR.dropLast(1).suffix(14))
        let baseSteps = Array(dailySteps.dropLast(1).suffix(14))

        // Z-scores against personal baseline
        let rhrZ = zScore(value: todayRHR, baseline: baseRHR)
        let hrvZ = zScore(value: todayHRV, baseline: baseHRV, inverted: true)
        let rrZ = zScore(value: todayRR, baseline: baseRR)
        let stepsZ = stepsValue > 0 ? zScore(value: stepsValue, baseline: baseSteps, inverted: true) : 0

        // Extended 2-of-4 rule
        let threshold: Double = 2.0
        var flagged = 0
        var signals = [String]()
        let totalSignals = stepsValue > 0 ? 4 : 3

        if rhrZ > threshold {
            flagged += 1
            signals.append("RHR +\(String(format: "%.1f", rhrZ))σ")
        }
        if hrvZ > threshold {
            flagged += 1
            signals.append("HRV -\(String(format: "%.1f", hrvZ))σ")
        }
        if rrZ > threshold && respiratoryRate > 0 {
            flagged += 1
            signals.append("RR +\(String(format: "%.1f", rrZ))σ")
        }
        if stepsZ > threshold && stepsValue > 0 {
            flagged += 1
            signals.append("Steps -\(String(format: "%.0f", stepsZ))σ")
        }

        DispatchQueue.main.async {
            self.illnessRisk = flagged
            if flagged >= 2 {
                self.illnessAlert = "⚠️ \(flagged)/\(totalSignals) signals elevated (\(signals.joined(separator: ", "))) — body showing early stress. Consider resting today."
            } else if flagged == 1 {
                self.illnessAlert = "1/\(totalSignals) signal elevated (\(signals[0])) — monitoring"
            } else {
                self.illnessAlert = nil
            }
        }
    }

    // MARK: - Alcohol Impact Score (Finding 6.1)
    // AIS = (RMSSD_baseline - RMSSD_alcohol_night) / RMSSD_baseline × 100
    // Pietilä 2018: ~1 drink = −3.8%, ~2 drinks = −10.9%, 3+ drinks = −24.8%

    /// Compute alcohol impact from overnight HRV depression
    /// Call the morning after an alcohol-flagged event
    func computeAlcoholImpact() {
        let baseline = baselineRMSSD.isEmpty ? baselineHRV : (baselineRMSSD.reduce(0, +) / Double(baselineRMSSD.count))
        guard baseline > 0, currentRMSSD > 0 else { return }

        let impact = ((baseline - currentRMSSD) / baseline) * 100

        DispatchQueue.main.async {
            self.lastAlcoholImpact = round(max(0, impact) * 10) / 10
        }
    }
}
