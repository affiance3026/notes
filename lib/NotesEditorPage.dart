import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class NotesEditorPage extends StatefulWidget {
  final String noteId;
  final String? folderId;

  const NotesEditorPage({super.key, required this.noteId, this.folderId});

  @override
  State<NotesEditorPage> createState() => _NotesEditorPageState();
}

class _NotesEditorPageState extends State<NotesEditorPage> {
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _editorFocusNode = FocusNode();
  final List<String> _imagePaths = [];
  final List<String> _audioPaths = [];
  bool _isLoading = true;
  bool _isPreviewMode = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final doc = await FirebaseFirestore.instance.collection('notes').doc(widget.noteId).get();
    if (doc.exists) {
      final data = doc.data()!;
      _contentController.text = data['content'] ?? '';
      _imagePaths.clear();
      _audioPaths.clear();
      if (data['imagePaths'] != null) {
        _imagePaths.addAll(List<String>.from(data['imagePaths']));
      }
      if (data['audioPaths'] != null) {
        _audioPaths.addAll(List<String>.from(data['audioPaths']));
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveNote() async {
    await FirebaseFirestore.instance.collection('notes').doc(widget.noteId).update({
      'content': _contentController.text.trim(),
      'imagePaths': _imagePaths,
      'audioPaths': _audioPaths,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Note saved successfully")),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'image_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}.jpg';
      final savedImage = await File(picked.path).copy('${appDir.path}/$fileName');
      setState(() => _imagePaths.add(savedImage.path));
      await _saveNote();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Image added")),
      );
    }
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}.aac';
      final savedAudio = await file.copy('${appDir.path}/$fileName');
      setState(() => _audioPaths.add(savedAudio.path));
      await _saveNote();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Audio added")),
      );
    }
  }

  Future<void> _deleteImage(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Image"),
        content: const Text("Are you sure you want to delete this image?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
        ],
      ),
    ) ?? false;

    if (confirm) {
      final path = _imagePaths.removeAt(index);
      File(path).delete();
      setState(() {});
      _saveNote();
    }
  }

  Future<void> _deleteAudio(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Audio"),
        content: const Text("Are you sure you want to delete this audio clip?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
        ],
      ),
    ) ?? false;

    if (confirm) {
      final path = _audioPaths.removeAt(index);
      File(path).delete();
      setState(() {});
      _saveNote();
    }
  }

  void _insertMarkdown(String syntax) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final newText = text.replaceRange(selection.start, selection.end, syntax);
    _contentController.text = newText;
    _contentController.selection = TextSelection.collapsed(offset: selection.start + syntax.length);
  }

  @override
  void dispose() {
    _contentController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 8,
      children: [
        IconButton(onPressed: () => _insertMarkdown("**bold**"), icon: const Icon(Icons.format_bold)),
        IconButton(onPressed: () => _insertMarkdown("*italic*"), icon: const Icon(Icons.format_italic)),
        IconButton(onPressed: () => _insertMarkdown("### Heading\n"), icon: const Icon(Icons.title)),
        IconButton(onPressed: () => _insertMarkdown("* Bullet item\n"), icon: const Icon(Icons.format_list_bulleted)),
        IconButton(onPressed: () => _insertMarkdown("[Link](url)"), icon: const Icon(Icons.link)),
        IconButton(onPressed: () => _insertMarkdown("\n\n```\nCode block\n```\n\n"), icon: const Icon(Icons.code)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Note"),
        actions: [
          IconButton(
            icon: Icon(_isPreviewMode ? Icons.edit : Icons.remove_red_eye),
            onPressed: () {
              setState(() {
                _isPreviewMode = !_isPreviewMode;
                if (!_isPreviewMode) {
                  Future.delayed(Duration(milliseconds: 100), () {
                    final content = _contentController.text;
                    _contentController.selection = TextSelection.collapsed(
                      offset: content.isNotEmpty ? content.length : 0,
                    );
                    _editorFocusNode.requestFocus();
                  });
                }
              });
            },
          ),
          TextButton(
            onPressed: _saveNote,
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.blue, fontSize: 16),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
        onTap: () => _editorFocusNode.requestFocus(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isPreviewMode) _buildToolbar(),
                _isPreviewMode
                    ? MarkdownBody(
                  data: _contentController.text.replaceAll('\n', '  \n'),
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: const TextStyle(fontSize: 20),
                    h1: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    h2: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    h3: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    code: const TextStyle(fontSize: 18, fontFamily: 'monospace'),
                  ),
                )
                    : TextField(
                  focusNode: _editorFocusNode,
                  controller: _contentController,
                  maxLines: null,
                  decoration: const InputDecoration.collapsed(hintText: "Write here..."),
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 20),
                if (_imagePaths.isNotEmpty) const Text("Images:"),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_imagePaths.length, (index) {
                    return Stack(
                      children: [
                        GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                child: InteractiveViewer(
                                  child: Image.file(File(_imagePaths[index])),
                                ),
                              ),
                            );
                          },
                          child: Image.file(File(_imagePaths[index]), width: 100, height: 100, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: InkWell(
                            onTap: () => _deleteImage(index),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 20, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                const SizedBox(height: 20),
                if (_audioPaths.isNotEmpty) const Text("Audio Clips:"),
                Column(
                  children: List.generate(_audioPaths.length, (index) {
                    return Row(
                      children: [
                        Expanded(child: AudioPlayerWidget(filePath: _audioPaths[index])),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteAudio(index),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'image',
            onPressed: _pickImage,
            child: const Icon(Icons.image),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'audio',
            onPressed: _pickAudio,
            child: const Icon(Icons.audiotrack),
          ),
        ],
      ),
    );
  }
}

class AudioPlayerWidget extends StatefulWidget {
  final String filePath;

  const AudioPlayerWidget({super.key, required this.filePath});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _player.setFilePath(widget.filePath);
      _duration = _player.duration ?? Duration.zero;

      _player.positionStream.listen((pos) => setState(() => _position = pos));
      _player.playerStateStream.listen((state) => setState(() => _isPlaying = state.playing));
    } catch (e) {
      debugPrint("Audio error: $e");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    return '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Slider(
          min: 0,
          max: _duration.inMilliseconds.toDouble(),
          value: _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble(),
          onChanged: (value) {
            _player.seek(Duration(milliseconds: value.toInt()));
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_format(_position)),
            Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () async {
                    _isPlaying ? await _player.pause() : await _player.play();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: () async {
                    await _player.stop();
                    setState(() => _position = Duration.zero);
                  },
                ),
              ],
            ),
            Text(_format(_duration)),
          ],
        ),
      ],
    );
  }
}
