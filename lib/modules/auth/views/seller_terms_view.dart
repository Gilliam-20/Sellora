import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/user_model.dart';

/// The terms presented to a seller before a store account is created.
/// The accepted version is stored with the seller's user document.
class SellerTermsView extends StatelessWidget {
  const SellerTermsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seller Terms & Conditions')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: context.pageHorizontalPadding,
            vertical: AppSpacing.lg,
          ),
          child: ResponsiveCenter(
            maxWidth: 680,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.manifestGold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.storefront_outlined,
                          color: AppColors.cargoNavy),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text('Sellora seller agreement',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Terms for selling on Sellora',
                    style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: AppSpacing.xs),
                Text('Version $sellerTermsVersion',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.slate)),
                const SizedBox(height: AppSpacing.lg),
                const _TermsSection(
                  title: '1. Your seller account',
                  body:
                      'You must provide accurate contact and store information and keep your account credentials secure. You are responsible for activity carried out through your seller account.',
                ),
                const _TermsSection(
                  title: '2. Your listings and customers',
                  body:
                      'You are responsible for the accuracy, legality, pricing and availability of every product you list. Product descriptions, images and promotions must not be misleading or infringe another party’s rights.',
                ),
                const _TermsSection(
                  title: '3. Orders and fulfilment',
                  body:
                      'You must process orders promptly and communicate honestly with customers about fulfilment, stock changes, delays, returns and refunds. You must comply with applicable consumer-protection laws.',
                ),
                const _TermsSection(
                  title: '4. Fees and subscriptions',
                  body:
                      'Paid seller plans renew according to the plan you choose. Access to paid seller tools may be limited when a subscription is inactive or a payment cannot be collected.',
                ),
                const _TermsSection(
                  title: '5. Acceptable use',
                  body:
                      'Do not use Sellora for unlawful, fraudulent, unsafe or prohibited goods or activity. We may suspend or remove listings and accounts that breach these terms or put customers or the platform at risk.',
                ),
                const _TermsSection(
                  title: '6. Changes and contact',
                  body:
                      'We may update these terms when the service or legal requirements change. Material updates will require acceptance before continued seller use where appropriate. Contact Sellora support with questions about this agreement.',
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.cloud,
                    border: Border.all(color: AppColors.hairline),
                    borderRadius: BorderRadius.circular(AppRadii.stub + 8),
                  ),
                  child: Text(
                    'By selecting the acceptance box during signup, you confirm that you have read and agree to these Seller Terms & Conditions.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TermsSection extends StatelessWidget {
  const _TermsSection({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}
