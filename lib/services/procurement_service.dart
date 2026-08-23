import 'package:shop/models/order.dart';

class ProcurementService {
  const ProcurementService();

  List<OrderItemEntity> itemsToProcure(List<OrderItemEntity> items) {
    return items
        .where((item) => item.procurementStatus == ProcurementStatus.toProcure)
        .toList();
  }
}
