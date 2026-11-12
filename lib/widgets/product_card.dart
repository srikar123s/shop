import 'package:flutter/material.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.title,
    required this.onTap,
    this.icon,
    this.cartQuantity,
  });

  final String title;
  final VoidCallback onTap;
  final IconData? icon;
  final double? cartQuantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inCart = cartQuantity != null && cartQuantity! > 0;
    final qtyStr = inCart
        ? (cartQuantity! % 1 == 0
            ? cartQuantity!.toInt().toString()
            : cartQuantity!.toString())
        : null;

    return Card(
      elevation: inCart ? 1.5 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: inCart ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
          width: inCart ? 1.8 : 1.0,
        ),
      ),
      color: inCart ? const Color(0xFFF0FDFA) : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        color: inCart
                            ? const Color(0xFF0F766E)
                            : theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: inCart
                            ? const Color(0xFF0F766E)
                            : const Color(0xFF0F172A),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (inCart)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 10, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(
                        qtyStr!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
