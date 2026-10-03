import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/routes/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/plan_change.dart';
import '../../../data/models/billing_history_entry_model.dart';
import '../../../data/models/billing_profile_model.dart';
import '../../../data/models/subscription_plan_model.dart';
import '../../../data/models/subscription_usage_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/subscription_repository.dart';
import '../../../data/services/intasend_service.dart';
import 'invoice.dart';

/// The seller's billing page (TODO §17): plan, status, usage, payment
/// method, history and invoices, and every change to the plan.
class SellerSubscriptionController extends GetxController {
  final SubscriptionRepository _subscriptionRepo =
      Get.find<SubscriptionRepository>();
  final AuthRepository authRepo = Get.find<AuthRepository>();

  final plans = <SubscriptionPlanModel>[].obs;
  final usage = Rxn<SubscriptionUsageModel>();
  final history = <BillingHistoryEntryModel>[].obs;
  final billingProfile = Rxn<BillingProfileModel>();
  final isLoading = true.obs;
  final isPaying = false.obs;
  final isRefreshing = false.obs;
  final isChangingStatus = false.obs;
  final isSavingProfile = false.obs;

  /// The billing entry whose payment is being re-checked, if any.
  final checkingEntryId = RxnString();
  final errorMessage = RxnString();
  final loadError = RxnString();

  SubscriptionPlanModel? get currentPlan => plans
      .firstWhereOrNull((p) => p.id == authRepo.cachedUser?.subscriptionPlanId);

  /// What the seller can buy: active plans, plus their own if it's been
  /// retired (they may still renew it).
  List<SubscriptionPlanModel> get offeredPlans =>
      SubscriptionPlanModel.offered(plans,
          currentPlanId: authRepo.cachedUser?.subscriptionPlanId);

  PlanChange changeTo(SubscriptionPlanModel plan) =>
      PlanChange(from: currentPlan, to: plan);

  /// Paid entries, newest first: the seller's invoices.
  List<BillingHistoryEntryModel> get invoices =>
      history.where((e) => e.hasInvoice).toList();

  /// Payments started in the last day that haven't been confirmed. Older
  /// ones were almost certainly abandoned, so they're not offered a check.
  List<BillingHistoryEntryModel> get pendingPayments => history
      .where((e) =>
          e.status == 'pending' &&
          DateTime.now().difference(e.createdAt) < const Duration(days: 1))
      .toList();

  /// The cheapest offered plan with room for more of what the seller is
  /// close to running out of (80%+ of the listing or order limit), or null.
  /// Stores aren't counted: every seller has one, so a one-store plan would
  /// always read as full, and adding a second store isn't built yet.
  SubscriptionPlanModel? get suggestedUpgrade {
    final u = usage.value;
    if (u == null) return null;
    bool near(int used, int limit) => limit > 0 && used >= limit * 0.8;
    final candidates = [
      if (near(u.listingCount, u.listingLimit))
        PlanChange.roomFor(offeredPlans,
            current: currentPlan,
            limitOf: (p) => p.listingLimit,
            used: u.listingCount),
      if (near(u.orderCount, u.orderLimit))
        PlanChange.roomFor(offeredPlans,
            current: currentPlan,
            limitOf: (p) => p.orderLimit,
            used: u.orderCount),
    ].whereType<SubscriptionPlanModel>();
    return candidates.firstOrNull;
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    loadError.value = null;
    try {
      plans.value = await _subscriptionRepo.fetchPlans();
      final uid = authRepo.cachedUser?.uid;
      if (uid != null) {
        final results = await Future.wait([
          _subscriptionRepo.fetchUsage(uid),
          _subscriptionRepo.billingHistory(uid),
          _subscriptionRepo.fetchBillingProfile(uid),
        ]);
        usage.value = results[0] as SubscriptionUsageModel;
        history.value = results[1] as List<BillingHistoryEntryModel>;
        billingProfile.value = results[2] as BillingProfileModel?;
      }
    } catch (e) {
      debugPrint('SellerSubscriptionController.load: $e');
      loadError.value = 'Couldn\'t load your billing details.';
    } finally {
      isLoading.value = false;
    }
  }

  /// Buys [plan]: a switch, or a renewal when it's the current plan.
  /// Paying before the period ends adds a period to its end rather than
  /// restarting it, so renewing early loses nothing. With
  /// [rememberMethod], the method (and number) become the saved default.
  Future<void> pay(
    SubscriptionPlanModel plan, {
    required BillingPaymentMethod method,
    String? mpesaPhone,
    bool rememberMethod = false,
  }) async {
    final user = authRepo.cachedUser;
    if (user == null) return;
    isPaying.value = true;
    errorMessage.value = null;
    try {
      final phone = method == BillingPaymentMethod.mpesa
          ? Formatters.toMpesaFormat(mpesaPhone ?? '')
          : null;
      final entry = await _subscriptionRepo.subscribeSeller(
          sellerId: user.uid, planId: plan.id);
      final intasend = Get.find<IntasendService>();

      if (method == BillingPaymentMethod.mpesa) {
        await intasend.payBillingMpesa(billingEntryId: entry.id, phone: phone!);
      } else {
        final url = await intasend.payBillingCard(
          billingEntryId: entry.id,
          method: 'CARD-PAYMENT',
          // Hash routing: back to this page, where "Check payment" confirms.
          redirectUrl: kIsWeb
              ? Uri.base.replace(fragment: Routes.sellerSubscription).toString()
              : null,
        );
        final uri = url == null ? null : Uri.tryParse(url);
        if (uri == null || !uri.hasScheme) {
          throw StateError('No checkout URL returned');
        }
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (rememberMethod) {
        await _saveMethodQuietly(method, phone);
      }
      // No live confirmation channel: the webhook activates the plan. The
      // pending entry this created shows on the page with "Check payment".
      Get.back();
      Get.snackbar(
          'Almost there',
          method == BillingPaymentMethod.mpesa
              ? 'Complete the M-Pesa prompt on your phone, then tap "Check payment".'
              : 'Finish paying in the page that just opened, then tap "Check payment".');
      await load();
    } on ApiException catch (e) {
      // A 4xx carries the server's own caller-facing reason, e.g. a
      // downgrade refused until the seller unlists some products.
      final status = e.statusCode;
      errorMessage.value = status != null && status >= 400 && status < 500
          ? e.message
          : _payFailed(method);
    } catch (e) {
      debugPrint('SellerSubscriptionController.pay: $e');
      errorMessage.value = _payFailed(method);
    } finally {
      isPaying.value = false;
    }
  }

  static String _payFailed(BillingPaymentMethod method) =>
      method == BillingPaymentMethod.mpesa
          ? 'Payment didn\'t go through. Check the number and try again.'
          : 'Couldn\'t open the card payment page. Please try again.';

  /// A payment worked, so a failure to remember the method shouldn't
  /// read as a failed payment.
  Future<void> _saveMethodQuietly(
      BillingPaymentMethod method, String? phone) async {
    try {
      await _saveProfile(method: method, mpesaPhone: phone);
    } catch (e) {
      debugPrint('SellerSubscriptionController: saving method failed: $e');
    }
  }

  /// Saves the payment method and invoice details. Returns whether it
  /// worked; [errorMessage] says why not.
  Future<bool> saveBillingProfile({
    required BillingPaymentMethod method,
    String? mpesaPhone,
    String? billingName,
    String? taxId,
  }) async {
    isSavingProfile.value = true;
    errorMessage.value = null;
    try {
      final phone = mpesaPhone == null || mpesaPhone.trim().isEmpty
          ? null
          : Formatters.toMpesaFormat(mpesaPhone);
      await _saveProfile(
        method: method,
        mpesaPhone: phone,
        billingName: billingName,
        taxId: taxId,
        fromPayment: false,
      );
      return true;
    } catch (e) {
      debugPrint('SellerSubscriptionController.saveBillingProfile: $e');
      errorMessage.value = 'Couldn\'t save. Check the details and try again.';
      return false;
    } finally {
      isSavingProfile.value = false;
    }
  }

  Future<void> _saveProfile({
    required BillingPaymentMethod method,
    String? mpesaPhone,
    String? billingName,
    String? taxId,
    bool fromPayment = true,
  }) async {
    final user = authRepo.cachedUser;
    if (user == null) return;
    final existing = billingProfile.value;
    String? clean(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
    final profile = BillingProfileModel(
      sellerId: user.uid,
      paymentMethod: method,
      // Paying by card keeps the saved number for next time; the edit
      // sheet sets every field as shown.
      mpesaPhone: fromPayment ? mpesaPhone ?? existing?.mpesaPhone : mpesaPhone,
      billingName: fromPayment ? existing?.billingName : clean(billingName),
      taxId: fromPayment ? existing?.taxId : clean(taxId),
    );
    await _subscriptionRepo.saveBillingProfile(profile);
    billingProfile.value = profile;
  }

  /// Ends the plan at its period end. Nothing is charged automatically,
  /// so this stops reminders and tells the seller the date it ends.
  Future<void> cancel({String? reason}) async {
    isChangingStatus.value = true;
    try {
      await _subscriptionRepo.cancelSubscription(reason: reason);
      Get.back();
      await load();
      final end = usage.value?.currentPeriodEnd;
      Get.snackbar(
          'Plan cancelled',
          end == null
              ? 'Your plan won\'t renew.'
              : 'Your plan stays active until ${Formatters.date(end)}.');
    } catch (e) {
      debugPrint('SellerSubscriptionController.cancel: $e');
      Get.snackbar('Couldn\'t cancel', 'Please try again.');
    } finally {
      isChangingStatus.value = false;
    }
  }

  Future<void> resume() async {
    isChangingStatus.value = true;
    try {
      await _subscriptionRepo.resumeSubscription();
      await load();
      Get.snackbar('Plan resumed', 'You\'ll be reminded before it ends.');
    } catch (e) {
      debugPrint('SellerSubscriptionController.resume: $e');
      Get.snackbar('Couldn\'t resume',
          'If your plan has already ended, renew it instead.');
    } finally {
      isChangingStatus.value = false;
    }
  }

  /// Asks the server (which asks IntaSend) whether [entry] has been paid.
  /// A confirmed payment activates the plan server-side, so the page
  /// reloads against the new state.
  Future<void> checkPayment(BillingHistoryEntryModel entry) async {
    checkingEntryId.value = entry.id;
    try {
      final status =
          await Get.find<IntasendService>().confirmBillingPayment(entry.id);
      switch (status) {
        case PaymentStatus.completed:
          await authRepo.refreshCurrentUser();
          await load();
          Get.snackbar(
              'Payment received', 'Your ${entry.planName} plan is active.');
        case PaymentStatus.failed:
          await load();
          Get.snackbar(
              'Payment failed', 'Nothing was charged. You can try again.');
        case PaymentStatus.pending:
          Get.snackbar('Still pending',
              'We haven\'t received the payment yet. Try again in a moment.');
      }
    } catch (e) {
      debugPrint('SellerSubscriptionController.checkPayment: $e');
      Get.snackbar('Couldn\'t check', 'Please try again in a moment.');
    } finally {
      checkingEntryId.value = null;
    }
  }

  Invoice invoiceFor(BillingHistoryEntryModel entry) => Invoice.of(entry,
      user: authRepo.cachedUser, profile: billingProfile.value);

  /// Saves (web) or shares (Android) [entry]'s invoice as a PDF.
  Future<void> downloadInvoice(BillingHistoryEntryModel entry) async {
    final invoice = invoiceFor(entry);
    try {
      await Printing.sharePdf(
          bytes: await invoice.toPdf(theme: await _pdfTheme()),
          filename: invoice.fileName);
    } catch (e) {
      debugPrint('SellerSubscriptionController.downloadInvoice: $e');
      Get.snackbar('Couldn\'t create the PDF', 'Please try again.');
    }
  }

  /// Inter (Meridian's UI face), which also covers names the PDF's
  /// built-in Helvetica can't draw. Fetched once from Google Fonts; without
  /// a connection the invoice falls back to Helvetica.
  static pw.ThemeData? _invoiceTheme;
  Future<pw.ThemeData?> _pdfTheme() async {
    if (_invoiceTheme != null) return _invoiceTheme;
    try {
      return _invoiceTheme = pw.ThemeData.withFont(
        base: await PdfGoogleFonts.interRegular(),
        bold: await PdfGoogleFonts.interBold(),
      );
    } catch (e) {
      debugPrint('SellerSubscriptionController: invoice font: $e');
      return null;
    }
  }

  /// Re-reads the signed-in user's profile (bypassing the in-memory
  /// cache) in case the webhook has activated a plan switch since this
  /// screen was opened, then reloads usage against whatever plan is
  /// current now.
  Future<void> refreshStatus() async {
    isRefreshing.value = true;
    try {
      await authRepo.refreshCurrentUser();
      await load();
    } finally {
      isRefreshing.value = false;
    }
  }
}
