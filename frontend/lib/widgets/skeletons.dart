import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

/// Shared loading skeletons for the bottom-bar pages.
///
/// Each skeleton mirrors the real screen's layout (list rows, item table,
/// cards) with animated shimmer placeholder blocks, so the transition from
/// loading → loaded doesn't shift the page around. Use these instead of a bare
/// [CircularProgressIndicator] on any first-load ("no data yet") state.
///
/// Building blocks:
///   • [ShimmerBox]  — a single rounded grey block that shimmers.
///   • [SkeletonWrapper] — wraps arbitrary [ShimmerBox]es in one shimmer sweep.
/// Page skeletons:
///   • [BillingSkeleton], [ItemsSkeleton], [OrdersListSkeleton],
///     [TablesSkeleton], [KitchenSkeleton], [CustomersSkeleton],
///     [CustomerBillsSkeleton].

/// A single shimmering placeholder block. Must live under a [SkeletonWrapper]
/// (or another Shimmer) to actually animate.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const ShimmerBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = AppRadius.small,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Colour is irrelevant — the shimmer gradient paints over it — but it
        // must be opaque for the mask to show.
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps [child] (a tree of [ShimmerBox]es) in one shared shimmer animation.
class SkeletonWrapper extends StatelessWidget {
  final Widget child;
  const SkeletonWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      // Light, subtle sweep tuned to the app's neutral palette.
      baseColor: AppColors.surfaceVariant,
      highlightColor: AppColors.borderLight,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Billing (HomeScreen) — search bar + category chips + item rows
// ---------------------------------------------------------------------------

class BillingSkeleton extends StatelessWidget {
  const BillingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonWrapper(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Category chip row
          Row(
            children: List.generate(
              4,
              (i) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ShimmerBox(width: 68, height: 30, radius: AppRadius.small),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Item rows
          ...List.generate(9, (_) => const _BillingRow()),
        ],
      ),
    );
  }
}

class _BillingRow extends StatelessWidget {
  const _BillingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 160, height: 14),
                SizedBox(height: 8),
                ShimmerBox(width: 80, height: 12),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Qty stepper placeholder
          const ShimmerBox(width: 96, height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Items (ItemsScreen) — search bar + card list
// ---------------------------------------------------------------------------

class ItemsSkeleton extends StatelessWidget {
  const ItemsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonWrapper(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const ShimmerBox(height: 48, radius: AppRadius.small), // search bar
          const SizedBox(height: 16),
          ...List.generate(6, (_) => const _ItemCard()),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Row(
        children: [
          const ShimmerBox(width: 44, height: 44, radius: AppRadius.small),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 140, height: 14),
                SizedBox(height: 8),
                ShimmerBox(width: 90, height: 12),
              ],
            ),
          ),
          const ShimmerBox(width: 56, height: 20),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Orders sub-tabs: list rows (Open Orders / Credit) and a table grid (Tables)
// ---------------------------------------------------------------------------

/// List-of-cards skeleton — used for Open Orders and Credit sub-tabs.
class OrdersListSkeleton extends StatelessWidget {
  const OrdersListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonWrapper(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(6, (_) => const _ListCard()),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 120, height: 14),
                SizedBox(height: 10),
                ShimmerBox(width: 180, height: 12),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const ShimmerBox(width: 64, height: 24),
        ],
      ),
    );
  }
}

/// Floor-plan grid skeleton — used for the Tables sub-tab.
class TablesSkeleton extends StatelessWidget {
  const TablesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonWrapper(
      child: GridView.count(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1,
        children: List.generate(
          9,
          (_) => const ShimmerBox(height: 100, radius: AppRadius.medium),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kitchen (KitchenScreen) — column of order tickets
// ---------------------------------------------------------------------------

class KitchenSkeleton extends StatelessWidget {
  const KitchenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonWrapper(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(4, (_) => const _KitchenTicket()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Customers (CustomersScreen) — toolbar + customer rows; a customer's bills
// ---------------------------------------------------------------------------

/// First load of the Customers page: search · filter · sort, the count line,
/// then customer rows (checkbox, name + phone/last visit, spend + bills).
class CustomersSkeleton extends StatelessWidget {
  const CustomersSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonWrapper(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const Row(children: [
            Expanded(child: ShimmerBox(height: 40, radius: AppRadius.medium)),
            SizedBox(width: 8),
            ShimmerBox(width: 40, height: 40, radius: 20),
            SizedBox(width: 8),
            ShimmerBox(width: 40, height: 40, radius: 20),
          ]),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShimmerBox(width: 120, height: 12),
                ShimmerBox(width: 90, height: 12),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(7, (_) => const CustomerRowSkeleton()),
        ],
      ),
    );
  }
}

/// One placeholder customer row. Also used, wrapped in a [SkeletonWrapper],
/// as the "loading the next page" footer of the list.
class CustomerRowSkeleton extends StatelessWidget {
  const CustomerRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: const Row(children: [
        ShimmerBox(width: 20, height: 20, radius: 4), // checkbox
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 130, height: 14),
              SizedBox(height: 8),
              ShimmerBox(width: 190, height: 11),
            ],
          ),
        ),
        SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          ShimmerBox(width: 64, height: 14),
          SizedBox(height: 8),
          ShimmerBox(width: 44, height: 10),
        ]),
      ]),
    );
  }
}

/// A customer's bill list while it loads (the header above it is real).
class CustomerBillsSkeleton extends StatelessWidget {
  final int rows;
  const CustomerBillsSkeleton({super.key, this.rows = 7});

  @override
  Widget build(BuildContext context) {
    return SkeletonWrapper(
      child: ListView(
        padding: const EdgeInsets.all(12),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: rows < 7,
        children: List.generate(rows, (_) => const BillRowSkeleton()),
      ),
    );
  }
}

/// One placeholder bill row: number + date line on the left, amount right.
class BillRowSkeleton extends StatelessWidget {
  const BillRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: const Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 90, height: 14),
              SizedBox(height: 8),
              ShimmerBox(width: 170, height: 11),
            ],
          ),
        ),
        SizedBox(width: 12),
        ShimmerBox(width: 70, height: 16),
      ]),
    );
  }
}

class _KitchenTicket extends StatelessWidget {
  const _KitchenTicket();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerBox(width: 100, height: 16),
              ShimmerBox(width: 56, height: 14),
            ],
          ),
          SizedBox(height: 16),
          ShimmerBox(width: 200, height: 12),
          SizedBox(height: 10),
          ShimmerBox(width: 150, height: 12),
          SizedBox(height: 10),
          ShimmerBox(width: 170, height: 12),
        ],
      ),
    );
  }
}
