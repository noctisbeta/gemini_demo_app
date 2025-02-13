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

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _response = '';
  bool _isLoading = false;

  late final model = GenerativeModel(
    model: 'gemini-2.0-flash',
    apiKey: dotenv.env['GEMINI_API_KEY']!,
    tools: tools,
  );

  late final chat = model.startChat();

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
        FunctionDeclaration('noParameters', 'never', null),
      ],
    ),
  ];

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
    super.dispose();
  }

  Future<void> getGeminiResponse() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await chat.sendMessage(
        Content.text(_textController.text),
      );

      if (response.candidates.isNotEmpty) {
        for (final candidate in response.candidates) {
          debugPrint('Candidate: $candidate');
          debugPrint('Content: ${candidate.finishMessage}');
          debugPrint('Text: ${candidate.text}');
          for (final part in candidate.content.parts) {
            debugPrint('Part: $part');
            if (part is FunctionCall && part.name == 'getPetName') {
              debugPrint('Name: ${part.name}');
              debugPrint('Args: ${part.args.toString()}');

              final myFunctionResult = getPetName(
                part.args['petType'] as String,
              );

              final responseInner = await chat.sendMessage(
                Content.functionResponse(part.name, {'name': myFunctionResult}),
              );

              setState(() {
                _response = responseInner.text ?? 'No response';
                _isLoading = false;
              });

              _textController.clear();

              return;
            }
          }
        }

        debugPrint('outside for loop');
        setState(() {
          _response = response.text ?? 'No response';
          _isLoading = false;
        });

        _textController.clear();
      }
    } catch (e) {
      debugPrint('Error: $e');
      setState(() {
        _response = 'Error: $e';
        _isLoading = false;
      });
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
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Enter your message...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : getGeminiResponse,
              child:
                  _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Send to Gemini'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Text(_response),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
