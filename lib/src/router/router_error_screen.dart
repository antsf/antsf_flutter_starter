import 'package:flutter/material.dart';

/// Generic "route not found / navigation error" screen for
/// `GoRouter.errorBuilder`. Generalized from
/// `draiv_logistik_supplier`'s private `_ErrorScreen` — pass an
/// [onGoHome] callback (typically `() => context.go(homePath)`) since this
/// package doesn't know the app's route types.
class RouterErrorScreen extends StatelessWidget {
  const RouterErrorScreen({
    super.key,
    required this.error,
    required this.onGoHome,
    this.canPop = false,
    this.onPop,
    this.title = 'Halaman tidak ditemukan',
    this.homeButtonLabel = 'Kembali ke Beranda',
  });

  final Exception? error;
  final String title;
  final String homeButtonLabel;

  /// Called when the "go home" button is pressed and [canPop] is false (or
  /// [onPop] is null).
  final VoidCallback onGoHome;

  /// Whether the current navigator can pop — if true, the button pops
  /// instead of going home. Pass `context.canPop()` from the call site
  /// (kept as a plain bool here to avoid a go_router import in this file).
  final bool canPop;

  /// Called instead of [onGoHome] when [canPop] is true. Defaults to
  /// [onGoHome] if unset.
  final VoidCallback? onPop;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? 'Terjadi kesalahan saat navigasi',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: canPop ? (onPop ?? onGoHome) : onGoHome,
                icon: Icon(canPop ? Icons.arrow_back : Icons.home),
                label: Text(canPop ? 'Kembali' : homeButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
