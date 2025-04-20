import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/idea.dart';

class TestPage extends StatelessWidget {
  final String code = '''
  class MyApp 
  ''';

  const TestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('代码高亮示例')),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              child: HighlightView(
                code,
                language: 'dart',
                theme: ideaTheme,
                padding: EdgeInsets.all(16),
                textStyle: TextStyle(fontFamily: 'JetBrainsMono'),
              ),
            ),
            Row(
              children: [
                Expanded(
                    child: Container(
                        decoration: BoxDecoration(color: Colors.red),
                        child: Text("Hello world")))
              ],
            ),
            Container(
              decoration: BoxDecoration(color: Colors.red),
              width: 32,
              height: 32,
              child: IconButton(
                icon: Icon(
                  Icons.wrap_text,
                  color: Colors.grey[400],
                ),
                padding: EdgeInsets.zero, onPressed: () {  },
                // constraints: const BoxConstraints(
                //   minWidth: 20,
                //   minHeight: 20,
                // ),
                // splashRadius: 16,
              ),
            )

          ],
        ));
  }
}
