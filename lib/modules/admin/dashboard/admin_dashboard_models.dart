/// The financial measure currently displayed in the platform trend chart.
/// GMV is seller money; service fees are Sellora revenue, so presenting them
/// on separate scales prevents the much smaller fee series being misleadingly
/// flattened against GMV.
enum AdminTrendMetric { gmv, serviceFees }

extension AdminTrendMetricX on AdminTrendMetric {
  String get label => switch (this) {
        AdminTrendMetric.gmv => 'Seller GMV',
        AdminTrendMetric.serviceFees => 'Service fees',
      };
}

/// One daily paid-order bucket for the admin platform-performance chart.
class PlatformTrendPoint {
  const PlatformTrendPoint({
    required this.day,
    required this.gmv,
    required this.serviceFees,
  });

  final DateTime day;
  final double gmv;
  final double serviceFees;

  double amountFor(AdminTrendMetric metric) => switch (metric) {
        AdminTrendMetric.gmv => gmv,
        AdminTrendMetric.serviceFees => serviceFees,
      };
}
