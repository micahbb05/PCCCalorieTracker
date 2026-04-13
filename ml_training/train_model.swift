#!/usr/bin/env swift
// train_model.swift — trains FoodIconClassifier.mlmodel via CreateML transfer learning.
// Run: swift ml_training/train_model.swift
// Requires macOS 14+, Xcode installed.

import CreateML
import Foundation

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let mlDir = projectRoot.appendingPathComponent("ml_training")

// Merge training + validation CSV so CreateML does its own automatic split
// (the .split strategy is more accurate than our manual split for small datasets)
let trainingURL   = mlDir.appendingPathComponent("training_data.csv")
let validationURL = mlDir.appendingPathComponent("validation_data.csv")
let outputURL     = mlDir.appendingPathComponent("FoodIconClassifier.mlmodel")

print("Loading data...")
var trainingTable   = try MLDataTable(contentsOf: trainingURL)
let validationTable = try MLDataTable(contentsOf: validationURL)

// Combine into one table so CreateML can do a proper stratified split
var combined = trainingTable
combined.append(contentsOf: validationTable)
print("Total rows: \(combined.rows.count)")

print("Configuring transfer learning classifier (elmoEmbedding)...")
let parameters = MLTextClassifier.ModelParameters(
    validation: .split(strategy: .automatic),
    algorithm: .transferLearning(.elmoEmbedding, revision: 1)
)

print("Training — this will take a few minutes...")
// MLDataTable init is deprecated in macOS 13 but still fully functional
let classifier = try MLTextClassifier(
    trainingData: combined,
    textColumn: "text",
    labelColumn: "label",
    parameters: parameters
)

let trainErr = classifier.trainingMetrics.classificationError
let valErr   = classifier.validationMetrics.classificationError
print("")
print("Training accuracy  : \(String(format: "%.1f%%", (1.0 - trainErr) * 100.0))")
print("Validation accuracy: \(String(format: "%.1f%%", (1.0 - valErr) * 100.0))")

let metadata = MLModelMetadata(
    author: "Calorie Tracker",
    shortDescription: "Maps food description strings to icon asset names (65 classes). Transfer learning, iOS 17+.",
    license: nil,
    version: "1.0",
    additional: nil
)

print("Writing model to \(outputURL.path)...")
try classifier.write(to: outputURL, metadata: metadata)
print("Done.")
