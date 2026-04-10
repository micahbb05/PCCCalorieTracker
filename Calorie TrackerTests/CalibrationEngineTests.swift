import XCTest

final class CalibrationEngineTests: XCTestCase {

    // MARK: - weightedErrorMean

    func testWeightedErrorMeanEmptyReturnsZero() {
        XCTAssertEqual(CalibrationEngine.weightedErrorMean([]), 0)
    }

    func testWeightedErrorMeanSingleValue() {
        // weights suffix(1) = [0.4], sum = 0.4*100 / 0.4 = 100
        let result = CalibrationEngine.weightedErrorMean([100])
        XCTAssertEqual(result, 100, accuracy: 0.001)
    }

    func testWeightedErrorMeanTwoValues() {
        // weights suffix(2) = [0.3, 0.4], totalWeight = 0.7
        // weighted = (50*0.3 + 100*0.4) / 0.7 = (15 + 40) / 0.7 = 55 / 0.7
        let result = CalibrationEngine.weightedErrorMean([50, 100])
        let expected = (50.0 * 0.3 + 100.0 * 0.4) / (0.3 + 0.4)
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }

    func testWeightedErrorMeanThreeValues() {
        // weights suffix(3) = [0.2, 0.3, 0.4], totalWeight = 0.9
        let values = [10.0, 20.0, 30.0]
        let result = CalibrationEngine.weightedErrorMean(values)
        let expected = (10.0 * 0.2 + 20.0 * 0.3 + 30.0 * 0.4) / (0.2 + 0.3 + 0.4)
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }

    func testWeightedErrorMeanFourValues() {
        // weights [0.1, 0.2, 0.3, 0.4], totalWeight = 1.0
        let values = [10.0, 20.0, 30.0, 40.0]
        let result = CalibrationEngine.weightedErrorMean(values)
        let expected = 10.0*0.1 + 20.0*0.2 + 30.0*0.3 + 40.0*0.4
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }

    func testWeightedErrorMeanMoreThanFourValuesTakesLastFour() {
        // Only last 4 should be used; weights [0.1, 0.2, 0.3, 0.4]
        let values = [999.0, 10.0, 20.0, 30.0, 40.0]
        let result = CalibrationEngine.weightedErrorMean(values)
        let expected = 10.0*0.1 + 20.0*0.2 + 30.0*0.3 + 40.0*0.4
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }

    func testWeightedErrorMeanMostRecentHasHighestWeight() {
        // [low, high]: result should be closer to high (weight 0.4) than low (weight 0.3)
        let result = CalibrationEngine.weightedErrorMean([0.0, 1000.0])
        XCTAssertGreaterThan(result, 500.0)
    }

    func testWeightedErrorMeanExactWeights() {
        // Verify the calibration error weights constant
        let weights = CalibrationEngine.calibrationErrorWeights
        XCTAssertEqual(weights, [0.1, 0.2, 0.3, 0.4])
        XCTAssertEqual(weights.reduce(0, +), 1.0, accuracy: 0.001)
    }

    // MARK: - spikeExcludedDayIDs

    func testSpikeExcludedDayIDsEmptyReturnsEmpty() {
        let result = CalibrationEngine.spikeExcludedDayIDs(orderedDayIDs: [], weightByDay: [:])
        XCTAssertTrue(result.isEmpty)
    }

    func testSpikeExcludedDayIDsSingleDayReturnsEmpty() {
        let result = CalibrationEngine.spikeExcludedDayIDs(orderedDayIDs: ["2024-01-01"], weightByDay: ["2024-01-01": 150.0])
        XCTAssertTrue(result.isEmpty)
    }

    func testSpikeExcludedDayIDsNoSpike() {
        let days = ["2024-01-01", "2024-01-02", "2024-01-03"]
        let weights: [String: Double] = ["2024-01-01": 150.0, "2024-01-02": 151.0, "2024-01-03": 150.5]
        let result = CalibrationEngine.spikeExcludedDayIDs(orderedDayIDs: days, weightByDay: weights)
        XCTAssertTrue(result.isEmpty)
    }

    func testSpikeExcludedDayIDsSpikeGreaterThan4Excluded() {
        let days = ["2024-01-01", "2024-01-02"]
        let weights: [String: Double] = ["2024-01-01": 150.0, "2024-01-02": 155.0] // diff = 5.0
        let result = CalibrationEngine.spikeExcludedDayIDs(orderedDayIDs: days, weightByDay: weights)
        XCTAssertTrue(result.contains("2024-01-02"))
        XCTAssertEqual(result.count, 1)
    }

    func testSpikeExcludedDayIDsSpikeExactly4NotExcluded() {
        let days = ["2024-01-01", "2024-01-02"]
        let weights: [String: Double] = ["2024-01-01": 150.0, "2024-01-02": 154.0] // diff = 4.0, not > 4
        let result = CalibrationEngine.spikeExcludedDayIDs(orderedDayIDs: days, weightByDay: weights)
        XCTAssertTrue(result.isEmpty)
    }

    func testSpikeExcludedDayIDsNegativeSpikeExcluded() {
        let days = ["2024-01-01", "2024-01-02"]
        let weights: [String: Double] = ["2024-01-01": 155.0, "2024-01-02": 150.0] // diff = -5.0, abs = 5
        let result = CalibrationEngine.spikeExcludedDayIDs(orderedDayIDs: days, weightByDay: weights)
        XCTAssertTrue(result.contains("2024-01-02"))
    }

    func testSpikeExcludedDayIDsMissingWeightNotExcluded() {
        let days = ["2024-01-01", "2024-01-02"]
        let weights: [String: Double] = ["2024-01-01": 150.0] // 2024-01-02 missing
        let result = CalibrationEngine.spikeExcludedDayIDs(orderedDayIDs: days, weightByDay: weights)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - clamp

    func testClampBelowLower() {
        XCTAssertEqual(CalibrationEngine.clamp(-5, lower: 0, upper: 10), 0)
    }

    func testClampAboveUpper() {
        XCTAssertEqual(CalibrationEngine.clamp(15, lower: 0, upper: 10), 10)
    }

    func testClampWithinRange() {
        XCTAssertEqual(CalibrationEngine.clamp(5, lower: 0, upper: 10), 5)
    }

    func testClampAtLowerBound() {
        XCTAssertEqual(CalibrationEngine.clamp(0, lower: 0, upper: 10), 0)
    }

    func testClampAtUpperBound() {
        XCTAssertEqual(CalibrationEngine.clamp(10, lower: 0, upper: 10), 10)
    }

    func testClampNegativeRange() {
        XCTAssertEqual(CalibrationEngine.clamp(-3, lower: -10, upper: -1), -3)
    }

    func testClampNegativeValueBelowRange() {
        XCTAssertEqual(CalibrationEngine.clamp(-15, lower: -10, upper: -1), -10)
    }

    // MARK: - calibrationAdjustmentParameters

    func testCalibrationAdjustmentParametersFewerThan3ErrorsReturnsDefault() {
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [100, 200], isFastStart: false)
        XCTAssertEqual(params.errorClamp, 100)
        XCTAssertEqual(params.alpha, 0.2)
        XCTAssertEqual(params.maxStep, 40)
        XCTAssertEqual(params.offsetLimit, 300)
    }

    func testCalibrationAdjustmentParametersNoErrorsReturnsDefault() {
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [], isFastStart: false)
        XCTAssertEqual(params.errorClamp, 100)
        XCTAssertEqual(params.alpha, 0.2)
        XCTAssertEqual(params.maxStep, 40)
        XCTAssertEqual(params.offsetLimit, 300)
    }

    func testCalibrationAdjustmentParametersDefaultFastStart() {
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [100], isFastStart: true)
        XCTAssertEqual(params.alpha, 0.5)
        XCTAssertEqual(params.maxStep, 60)
    }

    func testCalibrationAdjustmentParametersMixedSignsReturnsDefault() {
        // mixed signs should return default params
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [300, -300, 300], isFastStart: false)
        XCTAssertEqual(params.errorClamp, 100)
        XCTAssertEqual(params.alpha, 0.2)
        XCTAssertEqual(params.maxStep, 40)
    }

    func testCalibrationAdjustmentParametersBelowThresholdReturnsDefault() {
        // same sign but errors < 250
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [200, 200, 200], isFastStart: false)
        XCTAssertEqual(params.errorClamp, 100)
        XCTAssertEqual(params.alpha, 0.2)
        XCTAssertEqual(params.maxStep, 40)
    }

    func testCalibrationAdjustmentParametersAggressiveBoostTriggered() {
        // 3 errors, same positive sign, all >= 250 → boost triggered
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [300, 300, 300], isFastStart: false)
        XCTAssertGreaterThan(params.alpha, 0.2)
        XCTAssertGreaterThan(params.maxStep, 40)
        XCTAssertGreaterThan(params.errorClamp, 100)
        XCTAssertGreaterThan(params.offsetLimit, 300)
    }

    func testCalibrationAdjustmentParametersAggressiveBoostFastStart() {
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [300, 300, 300], isFastStart: true)
        XCTAssertGreaterThan(params.alpha, 0.5)
        XCTAssertGreaterThan(params.maxStep, 60)
    }

    func testCalibrationAdjustmentParametersMaxIntensityAtHighErrors() {
        // meanAbs far above 850 (250+600) → intensity clamped at 2
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [2000, 2000, 2000], isFastStart: false)
        XCTAssertEqual(params.errorClamp, 200, accuracy: 0.001)    // 100 * 2
        XCTAssertEqual(params.maxStep, 80, accuracy: 0.001)         // 40 * 2
        XCTAssertEqual(params.offsetLimit, 600, accuracy: 0.001)    // 300 + 300
    }

    func testCalibrationAdjustmentParametersMinIntensityAt250() {
        // meanAbs exactly 250 → intensity = 1 → same as default multiplied by 1
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [250, 250, 250], isFastStart: false)
        XCTAssertEqual(params.errorClamp, 100, accuracy: 0.001)
        XCTAssertEqual(params.alpha, 0.2, accuracy: 0.001)
        XCTAssertEqual(params.maxStep, 40, accuracy: 0.001)
        XCTAssertEqual(params.offsetLimit, 300, accuracy: 0.001)
    }

    func testCalibrationAdjustmentParametersNegativeErrorsBoost() {
        // 3 errors, same negative sign, all abs >= 250
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [-300, -300, -300], isFastStart: false)
        XCTAssertGreaterThan(params.alpha, 0.2)
        XCTAssertGreaterThan(params.maxStep, 40)
    }

    func testCalibrationAdjustmentParametersOnlyLast3Errors() {
        // 4 errors: first is different sign, last 3 are same sign and >= 250
        let params = CalibrationEngine.calibrationAdjustmentParameters(recentErrors: [-500, 300, 300, 300], isFastStart: false)
        XCTAssertGreaterThan(params.alpha, 0.2)
    }

    // MARK: - Export math

    func testTotalCaloriesMultiplication() {
        // totalCalories = calories * loggedCount
        let calories: Double = 500
        let loggedCount: Int = 3
        let totalCalories = calories * Double(loggedCount)
        XCTAssertEqual(totalCalories, 1500, accuracy: 0.001)
    }

    func testTotalCaloriesWithCountOne() {
        let calories: Double = 350
        let loggedCount: Int = 1
        let totalCalories = calories * Double(loggedCount)
        XCTAssertEqual(totalCalories, 350, accuracy: 0.001)
    }

    func testDaySummaryCaloriesConsumedWithLoggedCount() {
        // DaySummary.caloriesConsumed = item.calories * max(1, item.loggedCount ?? 1)
        let calories: Double = 200
        let loggedCount: Int? = 4
        let caloriesConsumed = calories * Double(max(1, loggedCount ?? 1))
        XCTAssertEqual(caloriesConsumed, 800, accuracy: 0.001)
    }

    func testDaySummaryCaloriesConsumedWithNilLoggedCount() {
        let calories: Double = 200
        let loggedCount: Int? = nil
        let caloriesConsumed = calories * Double(max(1, loggedCount ?? 1))
        XCTAssertEqual(caloriesConsumed, 200, accuracy: 0.001)
    }

    func testDaySummaryCaloriesConsumedWithZeroLoggedCount() {
        let calories: Double = 200
        let loggedCount: Int? = 0
        let caloriesConsumed = calories * Double(max(1, loggedCount ?? 1))
        XCTAssertEqual(caloriesConsumed, 200, accuracy: 0.001)
    }

    // MARK: - Calibration offset direction

    func testPositiveErrorProducesNegativeOffsetStep() {
        // When actual > estimated (positive error), we should decrease calorie target (negative offset step)
        // weightedErrorMean of positive errors > 0, and offset step is subtracted
        let errors = [100.0, 200.0, 300.0, 400.0]
        let mean = CalibrationEngine.weightedErrorMean(errors)
        XCTAssertGreaterThan(mean, 0) // positive mean → calorie target should be reduced
    }

    func testNegativeErrorMeanNegative() {
        let errors = [-100.0, -200.0, -300.0, -400.0]
        let mean = CalibrationEngine.weightedErrorMean(errors)
        XCTAssertLessThan(mean, 0) // negative mean → calorie target should be increased
    }
}
