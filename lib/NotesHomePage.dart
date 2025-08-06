import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'NotesEditorPage.dart';
import 'main.dart';

class NotesHomePage extends StatelessWidget {
  const NotesHomePage({super.key});

  static const Map<String, Color> labelColors = {
    'Personal': Colors.green,
    'Todo': Colors.blue,
    'Important': Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text("User not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Your Notes"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final shouldLogout = await _confirmLogout(context);
              if (shouldLogout) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const MyHomePage(title: 'Welcome to Notes'),
                  ),
                      (route) => false,
                );

                Future.microtask(() async {
                  try {
                    await FirebaseAuth.instance.signOut();
                    await GoogleSignIn().signOut(); // Optional
                  } catch (e) {
                    debugPrint('Sign-out error: \$e');
                  }
                });
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('folders')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final folders = snapshot.data?.docs ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notes')
                    .where('userId', isEqualTo: userId)
                    .where('folderId', isNull: true)
                    .snapshots(),
                builder: (context, noteSnapshot) {
                  if (noteSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final notes = noteSnapshot.data?.docs ?? [];

                  if (notes.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Notes", style: TextStyle(fontWeight: FontWeight.bold)),
                      ...notes.map((noteDoc) {
                        final data = noteDoc.data() as Map<String, dynamic>;
                        final title = data['title'] ?? 'Untitled';
                        final label = data.containsKey('label') ? data['label'] as String : 'No label';

                        return ListTile(
                          leading: const Icon(Icons.sticky_note_2_sharp),
                          title: Text(title),
                          subtitle: label != 'No label'
                              ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: labelColors[label]!.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: labelColors[label],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                              : null,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NotesEditorPage(
                                  noteId: noteDoc.id,
                                  folderId: null,
                                ),
                              ),
                            );
                          },
                          onLongPress: () => _showNoteFolderOptions(context, noteDoc.id, userId, isNote: true, currentName: title),
                        );
                      }).toList(),
                      const Divider(),
                    ],
                  );
                },
              ),
              if (folders.isNotEmpty)
                const Text("Folders", style: TextStyle(fontWeight: FontWeight.bold)),
              if (folders.isNotEmpty)
                ...folders.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final folderName = data['name'] ?? 'Untitled';
                  final label = data.containsKey('label') ? data['label'] as String : 'No label';

                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(folderName),
                    subtitle: label != 'No label'
                        ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: labelColors[label]!.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: labelColors[label],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                        : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FolderNotesPage(
                            folderId: doc.id,
                            folderName: folderName,
                          ),
                        ),
                      );
                    },
                    onLongPress: () => _showNoteFolderOptions(context, doc.id, userId, isNote: false, currentName: folderName),
                  );
                }),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOptions(context, userId),
        label: const Text("New"),
        icon: const Icon(Icons.add),
      ),
    );
  }

  void _showAddOptions(BuildContext context, String userId) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text("Create Folder"),
            onTap: () async {
              Navigator.pop(ctx);
              final name = await _promptForName(context, 'Folder Name');
              if (name != null && name.trim().isNotEmpty) {
                await FirebaseFirestore.instance.collection('folders').add({
                  'userId': userId,
                  'name': name.trim(),
                  'createdAt': FieldValue.serverTimestamp(),
                });
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.sticky_note_2_sharp),
            title: const Text("Create Note"),
            onTap: () async {
              Navigator.pop(ctx);
              final title = await _promptForName(context, 'Note Title');
              if (title != null && title.trim().isNotEmpty) {
                final doc = await FirebaseFirestore.instance.collection('notes').add({
                  'userId': userId,
                  'title': title.trim(),
                  'content': '',
                  'folderId': null,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotesEditorPage(
                      noteId: doc.id,
                      folderId: null,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showNoteFolderOptions(BuildContext context, String docId, String userId, {required bool isNote, required String currentName}) async {
    final docRef = isNote
        ? FirebaseFirestore.instance.collection('notes').doc(docId)
        : FirebaseFirestore.instance.collection('folders').doc(docId);

    final docSnapshot = await docRef.get();
    final data = docSnapshot.data() as Map<String, dynamic>? ?? {};
    final currentLabel = data.containsKey('label') ? data['label'] as String : null;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text("Rename"),
                onTap: () async {
                  Navigator.pop(ctx);
                  final newName = await _promptForNameWithInitial(context, isNote ? "Note Title" : "Folder Name", currentName);
                  if (newName != null && newName.trim().isNotEmpty && newName.trim() != currentName) {
                    await docRef.update(isNote ? {'title': newName.trim()} : {'name': newName.trim()});
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Delete"),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await _confirmDelete(context, isNote ? "note" : "folder");
                  if (confirm) {
                    if (!isNote) {
                      // If folder, delete notes in folder first
                      final notesQuery = await FirebaseFirestore.instance
                          .collection('notes')
                          .where('folderId', isEqualTo: docId)
                          .get();
                      for (var noteDoc in notesQuery.docs) {
                        await noteDoc.reference.delete();
                      }
                    }
                    await docRef.delete();
                  }
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text("Set Label", style: Theme.of(context).textTheme.titleMedium),
              ),
              ...labelColors.entries.map((entry) {
                final labelName = entry.key;
                final color = entry.value;
                final selected = currentLabel == labelName;

                return ListTile(
                  leading: Icon(Icons.label, color: color),
                  title: Text(labelName),
                  trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await docRef.update({'label': labelName});
                  },
                );
              }).toList(),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.grey),
                title: const Text("Remove label"),
                onTap: () async {
                  Navigator.pop(ctx);
                  // Remove label field by setting it to FieldValue.delete()
                  await docRef.update({'label': FieldValue.delete()});
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text("Cancel"),
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _promptForName(BuildContext context, String label) async {
    String input = '';
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          autofocus: true,
          onChanged: (val) => input = val,
          decoration: InputDecoration(hintText: 'Enter $label'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, input), child: const Text("Create")),
        ],
      ),
    );
  }

  Future<String?> _promptForNameWithInitial(BuildContext context, String label, String initial) async {
    final controller = TextEditingController(text: initial);
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: 'Enter $label'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("Rename")),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String target) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Confirmation"),
        content: Text("Are you sure you want to delete this $target?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
        ],
      ),
    ) ??
        false;
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sign Out"),
        content: const Text("Are you sure you want to sign out?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Sign Out")),
        ],
      ),
    ) ?? false;
  }
}

class FolderNotesPage extends StatelessWidget {
  final String folderId;
  final String folderName;

  static const Map<String, Color> labelColors = {
    'Personal': Colors.green,
    'Todo': Colors.blue,
    'Important': Colors.red,
  };

  const FolderNotesPage({super.key, required this.folderId, required this.folderName});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: Text(folderName)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notes')
            .where('userId', isEqualTo: userId)
            .where('folderId', isEqualTo: folderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notes = snapshot.data?.docs ?? [];

          return ListView(
            children: [
              if(notes.isNotEmpty)
                const Text("    Notes", style: TextStyle(fontWeight: FontWeight.bold)),
              ...notes.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final title = data['title'] ?? 'Untitled';
                final label = data.containsKey('label') ? data['label'] as String : 'No label';

                return ListTile(
                  leading: const Icon(Icons.sticky_note_2_sharp),
                  title: Text(title),
                  subtitle: label != 'No label'
                      ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: labelColors[label]!.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: labelColors[label],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                      : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NotesEditorPage(noteId: doc.id, folderId: folderId),
                      ),
                    );
                  },
                  onLongPress: () => _showNoteFolderOptions(context, doc.id, userId!, isNote: true, currentName: title),
                );
              }).toList(),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final title = await _promptForName(context, 'Note Title');
          if (title != null && title.trim().isNotEmpty) {
            final doc = await FirebaseFirestore.instance.collection('notes').add({
              'userId': userId,
              'title': title.trim(),
              'content': '',
              'folderId': folderId,
              'createdAt': FieldValue.serverTimestamp(),
            });
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotesEditorPage(
                  noteId: doc.id,
                  folderId: folderId,
                ),
              ),
            );
          }
        },
        child: const Icon(Icons.note_add_sharp),
      ),
    );
  }

  Future<void> _showNoteFolderOptions(BuildContext context, String docId, String userId, {required bool isNote, required String currentName}) async {
    final docRef = isNote
        ? FirebaseFirestore.instance.collection('notes').doc(docId)
        : FirebaseFirestore.instance.collection('folders').doc(docId);

    final docSnapshot = await docRef.get();
    final data = docSnapshot.data() as Map<String, dynamic>? ?? {};
    final currentLabel = data.containsKey('label') ? data['label'] as String : null;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text("Rename"),
                onTap: () async {
                  Navigator.pop(ctx);
                  final newName = await _promptForNameWithInitial(context, isNote ? "Note Title" : "Folder Name", currentName);
                  if (newName != null && newName.trim().isNotEmpty && newName.trim() != currentName) {
                    await docRef.update(isNote ? {'title': newName.trim()} : {'name': newName.trim()});
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Delete"),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await _confirmDelete(context, isNote ? "note" : "folder");
                  if (confirm) {
                    if (!isNote) {
                      final notesQuery = await FirebaseFirestore.instance
                          .collection('notes')
                          .where('folderId', isEqualTo: docId)
                          .get();
                      for (var noteDoc in notesQuery.docs) {
                        await noteDoc.reference.delete();
                      }
                    }
                    await docRef.delete();
                  }
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text("Set Label", style: Theme.of(context).textTheme.titleMedium),
              ),
              ...labelColors.entries.map((entry) {
                final labelName = entry.key;
                final color = entry.value;
                final selected = currentLabel == labelName;

                return ListTile(
                  leading: Icon(Icons.label, color: color),
                  title: Text(labelName),
                  trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await docRef.update({'label': labelName});
                  },
                );
              }).toList(),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.grey),
                title: const Text("Remove label"),
                onTap: () async {
                  Navigator.pop(ctx);
                  await docRef.update({'label': FieldValue.delete()});
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text("Cancel"),
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _promptForName(BuildContext context, String label) async {
    String input = '';
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          autofocus: true,
          onChanged: (val) => input = val,
          decoration: InputDecoration(hintText: 'Enter $label'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, input), child: const Text("Create")),
        ],
      ),
    );
  }

  Future<String?> _promptForNameWithInitial(BuildContext context, String label, String initial) async {
    final controller = TextEditingController(text: initial);
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: 'Enter $label'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("Rename")),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String target) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Confirmation"),
        content: Text("Are you sure you want to delete this $target?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete")),
        ],
      ),
    ) ??
        false;
  }
}
