import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/store_page.dart';
import '../design/storefront_theme.dart';
import '../shell/storefront_page.dart';
import '../storefront_session.dart';

/// `/s/{slug}/pages/{path}`: one of the store's own pages (About, Contact,
/// a policy), as its seller wrote it. The contact page adds email, phone
/// and WhatsApp buttons.
class StorePageView extends StatelessWidget {
  const StorePageView({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Get.find<StorefrontSession>();
    final kind = StorePageKind.fromPath(Get.parameters['page']);
    return StorefrontPage(
      title: kind?.defaultTitle,
      slivers: (context, store, design) => [
        SliverToBoxAdapter(
          child: StorefrontContent(
            maxWidth: 720,
            child: Obx(() {
              final page = kind == null ? null : session.pages[kind];
              if (page == null) {
                return EmptyState(
                  icon: Icons.description_outlined,
                  title: 'This page isn\'t available',
                  message: '${store.name} hasn\'t published it yet.',
                  actionLabel: 'Back to the shop',
                  onAction: () => Get.offAllNamed(session.path()),
                );
              }
              return StorePageBody(page: page);
            }),
          ),
        ),
      ],
    );
  }
}

/// A store page's title, text and (contact page) ways to get in touch.
/// Also the seller's preview in the page editor.
class StorePageBody extends StatelessWidget {
  const StorePageBody({super.key, required this.page});
  final StorePage page;

  @override
  Widget build(BuildContext context) {
    final style = StoreStyle.of(context);
    final textTheme = Theme.of(context).textTheme;
    final whatsapp = page.whatsappUri;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(style.heading(page.title),
            style: style.headingStyle(textTheme.headlineSmall)),
        if (page.kind.isPolicy && page.updatedAt != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text('Last updated ${Formatters.date(page.updatedAt!)}',
              style: textTheme.bodySmall),
        ],
        const SizedBox(height: AppSpacing.md),
        for (final p in page.paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SelectableText(p, style: textTheme.bodyLarge),
          ),
        if (page.kind == StorePageKind.contact)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (page.email case final email?)
                ElevatedButton.icon(
                  onPressed: () =>
                      launchUrl(Uri(scheme: 'mailto', path: email)),
                  icon: const Icon(Icons.mail_outline),
                  label: Text(email),
                ),
              if (page.phone case final phone?)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                      Uri(scheme: 'tel', path: phone.replaceAll(' ', ''))),
                  icon: const Icon(Icons.phone_outlined),
                  label: Text(phone),
                ),
              if (whatsapp != null)
                OutlinedButton.icon(
                  onPressed: () =>
                      launchUrl(whatsapp, mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
            ],
          ),
      ],
    );
  }
}
