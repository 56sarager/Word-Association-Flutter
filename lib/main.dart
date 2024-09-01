import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:simple_gradient_text/simple_gradient_text.dart';
import 'env.dart';

void main() {
  runApp(MyApp());
}

class WordCloudModel with ChangeNotifier {
  List<String> words = [];
  Set<String> uniqueWords = {}; // Set to keep track of unique words
  int score = 0;
  Random random = Random();
  bool isAutomatedWord = false;
  String lastDefinition = '';
  static const int maxWords = 45; // Maximum number of words in the cloud

  void addWord(String word, {bool automated = false}) {
    if (!uniqueWords.contains(word)) {
      if (words.length >= maxWords) {
        var oldestWord = words.removeAt(0); // Remove the oldest word
        //uniqueWords.remove(oldestWord); // Remove from unique words set
      }
      words.add(word);
      uniqueWords.add(word); // Add to unique words set
      if (!automated) {
        score += 1;
      }
      notifyListeners();
    } else {
      if (!automated) {
        score -= 1;
        notifyListeners();
      }
      throw Exception('Duplicate word');
    }
  }

  void invalidWord() {
    score -= 1;
    notifyListeners();
  }

  Future<String?> fetchDefinition(String word) async {
    final apiKey = Webster_API_key; // Replace with your Merriam-Webster API key
    final response = await http.get(
      Uri.parse('https://www.dictionaryapi.com/api/v3/references/collegiate/json/$word?key=$apiKey'),
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      if (jsonResponse.isNotEmpty && jsonResponse[0] is Map && jsonResponse[0]['shortdef'] != null) {
        lastDefinition = (jsonResponse[0]['shortdef'] as List).join(', ');
        return lastDefinition;
      } else {
        lastDefinition = 'No definition found.';
        return lastDefinition;
      }
    } else {
      throw Exception('Failed to load definition');
    }
  }

  void clearWords() {
    words.clear();
    uniqueWords.clear(); // Clear the set of unique words
    notifyListeners();
  }

  Future<String?> fetchSecondWord(String word) async {
    final response = await http.get(
      Uri.parse('https://api.datamuse.com/words?rel_trg=$word'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> jsonResponse = json.decode(response.body);
      final List<String> relatedWords = [];

      for (var item in jsonResponse) {
        relatedWords.add(item['word']);
      }

      if (relatedWords.isNotEmpty) {
        final randomWord = relatedWords[random.nextInt(relatedWords.length)];
        return randomWord;
      } else {
        return null; // Return null if no related word found
      }
    } else {
      throw Exception('Failed to fetch second word');
    }
  }
}


class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => WordCloudModel(),
      child: MaterialApp(
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: WordCloudScreen(),
      ),
    );
  }
}

class WordCloudScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final wordCloudModel = Provider.of<WordCloudModel>(context);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () async {
            if (wordCloudModel.words.isNotEmpty) {
              final lastWord = wordCloudModel.words.last;
              final definition = await wordCloudModel.fetchDefinition(lastWord);
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text(lastWord),
                    content: Text(definition ?? 'Loading...'), // Handle null case here
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('OK'),
                      ),
                    ],
                  );
                },
              );
            }
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GradientText(
                'Last Word: ${wordCloudModel.words.isNotEmpty ? wordCloudModel.words.last : ''}',
                style: TextStyle(
                  fontSize: 24.0,
                ),
                colors: [
                  Colors.green.shade400,
                  Colors.blue,
                  Colors.teal,
                ],
              ),
              GradientText(
                'Score: ${wordCloudModel.score}',
                style: TextStyle(
                  fontSize: 24.0,
                ),
                colors: [
                  Colors.green.shade400,
                  Colors.blue,
                  Colors.teal,
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextInputBox(),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return Stack(
                  children: [
                    Positioned.fill(
                      top: 0,
                      child: Center(
                        child: WordNetwork(words: wordCloudModel.words, constraints: constraints),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}



class TextInputBox extends StatefulWidget {
  @override
  _TextInputBoxState createState() => _TextInputBoxState();
}

class _TextInputBoxState extends State<TextInputBox> {
  final _controller = TextEditingController();
  bool isWaiting = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: 'Enter a word',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (String value) async {
        final isValid = await checkIfValidWord(value);
        if (value.isNotEmpty && isValid) {
          try {
            Provider.of<WordCloudModel>(context, listen: false).addWord(value);
            _controller.clear();

            setState(() {
              isWaiting = true;
            });

            Timer(Duration(seconds: 1), () async {
              final secondWord = await Provider.of<WordCloudModel>(context, listen: false).fetchSecondWord(value);
              setState(() {
                isWaiting = false;
              });

              if (secondWord != null) {
                Provider.of<WordCloudModel>(context, listen: false).addWord(secondWord, automated: true);
              } else {
                showFailedSecondWordMessage(context);
              }
            });
          } catch (e) {
            showDuplicateWordMessage(context);
          }
        } else {
          Provider.of<WordCloudModel>(context, listen: false).invalidWord();
          showInvalidWordMessage(context);
        }
      },
    );
  }

  void showInvalidWordMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Please enter a valid English word.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void showDuplicateWordMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Word already in word cloud.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void showFailedSecondWordMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to generate second word.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> checkIfValidWord(String word) async {
    final response = await http.get(
      Uri.parse('https://api.datamuse.com/words?sp=$word&max=1'),
    );

    if (response.statusCode == 200) {
      final List<dynamic> jsonResponse = json.decode(response.body);
      return jsonResponse.isNotEmpty && jsonResponse[0]['word'] == word;
    } else {
      throw Exception('Failed to check word validity');
    }
  }
}

class WordNetwork extends StatefulWidget {
  final List<String> words;
  final BoxConstraints constraints;

  WordNetwork({required this.words, required this.constraints});

  @override
  _WordNetworkState createState() => _WordNetworkState();
}

class _WordNetworkState extends State<WordNetwork>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
    _particles = List.generate(widget.words.length, (index) {
      return Particle(widget.words[index], widget.constraints);
    });

    _controller.addListener(() {
      setState(() {
        for (var particle in _particles) {
          particle.update();
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant WordNetwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _particles = List.generate(widget.words.length, (index) {
      return Particle(widget.words[index], widget.constraints);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ParticlePainter(_particles),
      child: Container(),
    );
  }
}

class Particle {
  static final Random _random = Random();
  final String word;
  double x, y;
  double dx, dy;
  final BoxConstraints constraints;

  Particle(this.word, this.constraints)
      : x = _random.nextDouble() * constraints.maxWidth,
        y = _random.nextDouble() * constraints.maxHeight,
        dx = (_random.nextDouble() - 0.5) * 4,
        dy = (_random.nextDouble() - 0.5) * 4;

  void update() {
    x += dx;
    y += dy;

    if (x < 0 || x > constraints.maxWidth) dx = -dx;
    if (y < 0 || y > constraints.maxHeight) dy = -dy;
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;

  ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final particlePaint = Paint()
      ..color = Colors.green.shade400
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw lines first
    for (var i = 1; i < particles.length; i++) {
      var particle = particles[i];
      var previousParticle = particles[i - 1];
      canvas.drawLine(
        Offset(previousParticle.x, previousParticle.y),
        Offset(particle.x, particle.y),
        linePaint,
      );
    }

    // Draw particles
    for (var particle in particles) {
      var wordWidth = particle.word.length * 10.0;
      var wordHeight = 20.0;
      var rect = Rect.fromLTWH(
          particle.x - wordWidth / 2, particle.y - wordHeight / 2, wordWidth, wordHeight);
      var rRect = RRect.fromRectAndRadius(rect, Radius.circular(8));
      canvas.drawRRect(rRect, particlePaint);
      _drawText(canvas, particle.word, Offset(particle.x, particle.y));
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
    );
    final textSpan = TextSpan(
      text: text,
      style: textStyle,
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(
      minWidth: 0,
      maxWidth: double.maxFinite,
    );
    final offsetAdjusted = Offset(
      offset.dx - textPainter.width / 2,
      offset.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, offsetAdjusted);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}