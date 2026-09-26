import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/theme/app_colors.dart';
import '../../data/repositories/auth_repository.dart';
import '../network/api_exception.dart';

/// In-app account deletion, which Google Play requires of apps with
/// sign-up. Confirms first, then [AuthRepository.deleteAccount]; on success
/// the account is signed out and [onDeleted] decides where to land.
class DeleteAccountButton extends StatefulWidget {
  const DeleteAccountButton({super.key, required this.onDeleted});

  final VoidCallback onDeleted;

  @override
  State<DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<DeleteAccountButton> {
  bool _deleting = false;

  Future<void> _confirmAndDelete() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your profile and personal details are removed and you won\'t be '
          'able to sign in again. Records of past orders and payments are '
          'kept, without your name or address, as the law requires. This '
          'can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Get.back(result: true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await Get.find<AuthRepository>().deleteAccount();
      widget.onDeleted();
    } on ApiException catch (e) {
      Get.snackbar('Account not deleted', e.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
      onPressed: _deleting ? null : _confirmAndDelete,
      child: Text(_deleting ? 'Deleting…' : 'Delete account'),
    );
  }
}
