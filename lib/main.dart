import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class Message {
  final String text;
  final bool isUser;

  Message(this.text, this.isUser);
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<Message> _messages = [];
  bool _isLoading = false;

  late final model = GenerativeModel(
    model: 'gemini-2.0-flash',
    apiKey: dotenv.env['GEMINI_API_KEY']!,
    tools: tools,
  );

  late final miniModel = GenerativeModel(
    model: 'gemini-1.5-flash-8b',
    apiKey: dotenv.env['GEMINI_API_KEY']!,
  );

  late var chat = model.startChat();

  final List<Tool> tools = [
    Tool(
      functionDeclarations: [
        FunctionDeclaration(
          'getPetName',
          'When the user asks about a pet name, this function will return a name based on the type of pet.',
          Schema(
            SchemaType.object,
            properties: {
              'petType': Schema(
                SchemaType.string,
                description: 'The type of pet.',
                enumValues: ['Dog', 'Cat', 'Other'],
              ),
            },
          ),
        ),
        FunctionDeclaration(
          'aboutJS',
          'When the user asks about JavaScript (not other languages), this is the function that should be called. Read from the context of the message if it is about JavaScript. Do not call this function for other programming languages.',
          null,
        ),
      ],
    ),
  ];

  String aboutJS() => 'yikes!';

  String getPetName(String petType) {
    if (petType == "Dog") {
      return "Rexonator";
    } else if (petType == "Cat") {
      return "WhiskersSsS";
    } else {
      return "FluffyYyY";
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (_textController.text.trim().isNotEmpty && !_isLoading) {
      getGeminiResponse();
    }
  }

  void _scrollAndFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> getGeminiResponse() async {
    final userMessage = _textController.text;
    setState(() {
      _messages.add(Message(userMessage, true));
      _isLoading = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
    _textController.clear();

    try {
      var response = await chat.sendMessage(Content.text(userMessage));

      if (response.text?.isNotEmpty ?? false) {
        final checkToolFailure = await miniModel.generateContent([
          Content.text(
            'Check if the next message says something about not being able to provide information about this topic, and if it does, respond simply with "HOLLUP" and nothing else. Otherwise, do not respond.',
          ),
          Content.text(response.text!),
        ], tools: []);

        debugPrint('checkToolFailure text:  ${checkToolFailure.text}');

        if (checkToolFailure.text?.trim() == 'HOLLUP') {
          debugPrint('Retrying without tools!');
          response = await model.generateContent([
            Content.text(userMessage),
          ], tools: []);

          debugPrint(
            'New response text: ${(response.candidates.first.content.parts.first as TextPart).text}',
          );

          final historyWithoutToolError =
              chat.history.take(chat.history.length - 1).toList();

          chat = model.startChat(history: historyWithoutToolError);

          await chat.sendMessage(
            Content.model([
              TextPart(
                (response.candidates.first.content.parts.first as TextPart)
                    .text,
              ),
            ]),
          );

          final historyWithoutEmptyMsg =
              historyWithoutToolError
                  .take(historyWithoutToolError.length - 1)
                  .toList();

          chat = model.startChat(history: historyWithoutEmptyMsg);
        }
      }

      if (response.candidates.isNotEmpty) {
        for (final candidate in response.candidates) {
          for (final part in candidate.content.parts) {
            if (part is FunctionCall && part.name == 'getPetName') {
              final myFunctionResult = getPetName(
                part.args['petType'] as String,
              );

              final responseInner = await chat.sendMessage(
                Content.functionResponse(part.name, {'name': myFunctionResult}),
              );

              setState(() {
                _messages.add(
                  Message(responseInner.text ?? 'No response', false),
                );
                _isLoading = false;
              });
              _scrollAndFocus();
              printHistory();
              return;
            }

            if (part is FunctionCall && part.name == 'aboutJS') {
              debugPrint('Calling aboutJS function');
              final myFunctionResult = aboutJS();
              setState(() {
                _messages.add(Message(myFunctionResult, false));
                _isLoading = false;
              });
              _scrollAndFocus();
              printHistory();
              return;
            }
          }
        }

        setState(() {
          _messages.add(Message(response.text ?? 'No response', false));
          _isLoading = false;
        });
        _scrollAndFocus();
        printHistory();
      }
    } catch (e) {
      debugPrint('Error: $e');
      printHistory();
      setState(() {
        _messages.add(Message('Error: $e', false));
        _isLoading = false;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void printHistory() {
    debugPrint('Chat history:');
    for (final content in chat.history) {
      debugPrint('content role: ${content.role}');
      debugPrint('content runtype: ${content.parts.first.runtimeType}');
      if (content.parts.first is TextPart) {
        debugPrint('content text: ${(content.parts.first as TextPart).text}');
      }
      debugPrint('-----------------------------');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Align(
                    alignment:
                        message.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            message.isUser
                                ? Colors.blue[100]
                                : Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(message.text),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    enabled: !_isLoading,
                    controller: _textController,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      hintText: 'Enter your message...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onSubmitted: (_) => _handleSubmit(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSubmit,
                  child:
                      _isLoading
                          ? const CircularProgressIndicator()
                          : const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
