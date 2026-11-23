import sys

path = r'lib\screens\customer_khata_passbook_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

old_block = """                                                    Flexible(
                                                      child: Text(
                                                        title,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    if (modeLabel.isNotEmpty &&
                                                        !isDebit) ...["""

new_block = """                                                    Flexible(
                                                      child: Text(
                                                        title,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    if (orderId != null &&
                                                        isDebit &&
                                                        !subtitle.contains('Manual Udhaar')) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 5, vertical: 1.5),
                                                        decoration: BoxDecoration(
                                                          color: Colors.grey.shade100,
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.grey.shade300),
                                                        ),
                                                        child: Text(
                                                          '#ORD-${orderId.toString().padLeft(4, "0")}',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            color: Colors.grey.shade700,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                    if (modeLabel.isNotEmpty &&
                                                        !isDebit) ...["""

if old_block in content:
    content = content.replace(old_block, new_block, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("SUCCESS")
else:
    print("NOT FOUND")
