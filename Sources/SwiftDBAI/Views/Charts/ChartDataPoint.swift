// ChartDataPoint.swift
// SwiftDBAI
//
// Shared data model used by all chart views.

import Foundation

/// A single data point for chart rendering.
///
/// Pairs a string label (category) with a numeric value.
/// Used as the common data format across BarChartView,
/// LineChartView, and PieChartView.
struct ChartDataPoint: Sendable, Identifiable {
    var id: String { label }

    /// The category label (x-axis or slice label).
    let label: String

    /// The numeric value (y-axis or slice size).
    let value: Double
}
