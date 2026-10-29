import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/decision_analytics.dart';
import 'package:solid_waste_operations/core/services/supply_chain_analytics.dart';

DecisionAnalytics snapshot({List<DecisionRow> cycles = const []}) => DecisionAnalytics.calculate(
  operations: [
    {'id':'g','_entity':'group','name':'أ'},
    {'id':'other','_entity':'group','name':'ب'},
  ], users: [], containers: [
    {'id':'c','groupId':'g','status':'full'},
    {'id':'c2','groupId':'other','status':'empty'},
  ], dumpsites: [], trips: [
    {'id':'old','groupId':'g','status':'completed','createdAt':'2026-10-18T12:00:00','weightTons':5},
    {'id':'new','groupId':'g','status':'completed','createdAt':'2026-10-25T12:00:00','quantity':500,'unit':'kg'},
    {'id':'unitless','groupId':'g','status':'completed','createdAt':'2026-10-26T12:00:00','quantity':8},
    {'id':'pending','groupId':'g','status':'pending','createdAt':'2026-10-27T12:00:00','weightTons':4},
    {'id':'today','groupId':'g','status':'completed','createdAt':'2026-10-29T09:00:00','weightTons':8},
    {'id':'other','groupId':'other','status':'completed','createdAt':'2026-10-25T12:00:00','weightTons':3},
  ], cycles: cycles, now: DateTime(2026,10,29,10), shiftText:'08:00 - 16:00');

void main() {
  test('compares equal complete days and preserves known weight coverage', () {
    final d = SupplyChainAnalytics.from(snapshot(), groupId:'g');
    expect(d.trend.length,7);
    expect(d.recorded,3);
    expect(d.completed,2);
    expect(d.previous,1);
    expect(d.change,1);
    expect(d.tons,.5);
    expect(d.weighed,1);
    expect(d.completion,2/3);
    expect(d.distribution['full'],1);
    expect(d.distribution['empty'],0);
  });
  test('all groups and missing baseline do not invent a percentage', () {
    final all = SupplyChainAnalytics.from(snapshot());
    expect(all.completed,3);
    expect(all.tons,3.5);
    final long = SupplyChainAnalytics.from(snapshot(),days:30);
    expect(long.historyCovered,isFalse);
    expect(long.currentCovered,isFalse);
    expect(long.change,isNull);
    final empty = SupplyChainAnalytics.from(snapshot(),groupId:'missing');
    expect(empty.completion,isNull);
    expect(empty.tons,isNull);
    expect(empty.change,isNull);
  });
  test('cycle start marks a truncated baseline unavailable', () {
    final d = SupplyChainAnalytics.from(snapshot(cycles:[{
      'id':'cycle','status':'active','startDate':'2026-10-23', 'endDate':'2026-11-01',
    }]));
    expect(d.historyCovered,isFalse);
    expect(d.change,isNull);
    expect(() => SupplyChainAnalytics.from(snapshot(),days:0),throwsArgumentError);
  });
}
