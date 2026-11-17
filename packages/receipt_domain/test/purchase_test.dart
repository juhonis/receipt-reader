import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:test/test.dart';

void main() {
  final branch = ReceiptBranch(id: DurableId.generate(), name: 'TEST');
  final productId = DurableId.generate(), origin = DurableId.generate();
  final productRow = DurableId.generate();
  ProductPurchase purchase({
    int cents = 400,
    int? quantity = 2,
    int scale = 0,
    QuantityUnit unit = QuantityUnit.piece,
    int rate = 2000000,
    int discount = -100,
    int revision = 1,
    bool extras = true,
  }) {
    final rows = [
      ReceiptItemSnapshot(
        id: productRow,
        name: 'TEST',
        kind: LineKind.product,
        cents: BigInt.from(cents),
        quantityValue: quantity == null ? null : BigInt.from(quantity),
        quantityScale: quantity == null ? null : scale,
        quantityUnit: quantity == null ? null : unit,
        rateMicros: quantity == null ? null : BigInt.from(rate),
        product: ReceiptProductLink(
          id: productId,
          storeId: branch.id,
          revision: RevisionId(origin, BigInt.from(revision)),
        ),
      ),
      if (discount < 0)
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'SALE',
          kind: LineKind.discount,
          cents: BigInt.from(discount),
          parentItemId: productRow,
          discountScope: DiscountScope.item,
        ),
      if (extras) ...[
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'DEPOSIT',
          kind: LineKind.deposit,
          cents: BigInt.from(40),
          parentItemId: productRow,
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'RECEIPT SALE',
          kind: LineKind.discount,
          cents: BigInt.from(-10),
          discountScope: DiscountScope.receipt,
        ),
        ReceiptItemSnapshot(
          id: DurableId.generate(),
          name: 'ROUNDING',
          kind: LineKind.adjustment,
          cents: BigInt.one,
          adjustmentReason: 'Reviewed',
        ),
      ],
    ];
    return ProductPurchase.fromReceipt(
      ReceiptSnapshot(
        id: DurableId.generate(),
        branch: branch,
        date: StoredReceiptDate.parse('17.11.2026'),
        totalCents: rows.fold(BigInt.zero, (sum, r) => sum + r.cents),
        items: rows,
      ),
      productRow,
    );
  }

  test('linked item discounts only; deposits, receipt discounts and adjustments remain separate', () {
    final p = purchase();
    expect(p.row.cents, BigInt.from(400));
    expect(p.itemDiscountCents, BigInt.from(-100));
    expect(p.depositCents, BigInt.from(40));
    expect(p.receiptDiscountCents, BigInt.from(-10));
    expect(p.hasReceiptAdjustment, isTrue);
    expect(p.effectiveCents, BigInt.from(300));
    expect(p.row.rateMicros, BigInt.from(2000000));
    expect(p.effectiveUnitPrice!.euros, '1,5000');
  });
  test(
    'missing quantity, returns and over-discounted rows remain outside chart',
    () {
      expect(purchase(quantity: null).effectiveUnitPrice, isNull);
      expect(purchase(cents: -400, quantity: -2, discount: 0).isReturn, isTrue);
      expect(
        purchase(cents: -400, quantity: -2, discount: 0).comparisonGroup,
        isNull,
      );
      expect(purchase(discount: -401).effectiveUnitPrice, isNull);
      expect(purchase(discount: -400).effectiveUnitPrice!.euros, '0,0000');
    },
  );
  test('piece revisions separate; weight and volume units never merge', () {
    expect(
      purchase().comparisonGroup,
      isNot(purchase(revision: 2).comparisonGroup),
    );
    final kg = purchase(unit: QuantityUnit.kg);
    expect(
      kg.comparisonGroup,
      purchase(unit: QuantityUnit.kg, revision: 2).comparisonGroup,
    );
    expect(
      kg.comparisonGroup,
      isNot(purchase(unit: QuantityUnit.litre).comparisonGroup),
    );
    expect(
      purchase(
        cents: 150,
        quantity: 375,
        scale: 3,
        unit: QuantityUnit.kg,
        rate: 4000000,
        discount: 0,
      ).effectiveUnitPrice!.euros,
      '4,0000',
    );
  });
  test('fractional cent rounding preserves printed rate independently', () {
    final p = purchase(cents: 1, quantity: 3, rate: 3333, discount: 0);
    expect(p.effectiveUnitPrice!.euros, '0,0033');
    expect(p.row.rateMicros, BigInt.from(3333));
  });
  test(
    'exact comparison beyond double precision and display half away from zero',
    () {
      final a = UnitPrice.fromLine(
        BigInt.parse('9007199254740992'),
        BigInt.one,
        0,
      );
      final b = UnitPrice.fromLine(
        BigInt.parse('9007199254740993'),
        BigInt.one,
        0,
      );
      expect(a.compareTo(b), -1);
      expect(a.positionBetween(a, b), 0);
      expect(b.positionBetween(a, b), 1);
      expect(
        UnitPrice.fromLine(BigInt.one, BigInt.from(32), 0).euros,
        '0,0003',
      );
      expect(UnitPrice.fromLine(BigInt.one, BigInt.from(8), 0).euros, '0,0013');
      expect(
        UnitPrice.fromLine(-BigInt.one, BigInt.from(8), 0).euros,
        '-0,0013',
      );
      expect(
        UnitPrice.fromLine(BigInt.from(3), BigInt.from(2), 0).positionBetween(
          UnitPrice.fromLine(BigInt.one, BigInt.one, 0),
          UnitPrice.fromLine(BigInt.from(2), BigInt.one, 0),
        ),
        0.5,
      );
      expect(a.positionBetween(a, a), 0.5);
    },
  );
}
