/*
文件路径: test/widget_test.dart
创建时间: 2026-04-07
上次修改时间: 2026-04-07
开发者: aidaox
*/

import 'package:flutter_test/flutter_test.dart';

import 'package:nuwa_bridge/main.dart';

/// 测试入口函数。
void main() {
  testWidgets('应用启动后显示人物页标题', (WidgetTester tester) async {
    /// 挂载应用根组件。
    await tester.pumpWidget(const NuwaBridgeApp());
    /// 等待异步初始化完成。
    await tester.pumpAndSettle();
    /// 断言人物页标题存在。
    expect(find.text('人物选择'), findsOneWidget);
  });
}
