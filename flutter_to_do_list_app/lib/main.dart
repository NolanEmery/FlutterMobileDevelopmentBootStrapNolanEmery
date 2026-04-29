import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter To-Do List',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const AuthPage();
        }

        return MyHomePage(
          onSignOut: FirebaseAuth.instance.signOut,
          userId: user.uid,
          userEmail: user.email ?? 'Signed in',
        );
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSignIn = true;
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorText = 'Email and password are required.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      if (_isSignIn) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorText = e.message ?? 'Authentication failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(_isSignIn ? 'Sign In' : 'Create Account'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Email',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Password',
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: Text(_isLoading
                    ? 'Please wait...'
                    : _isSignIn
                        ? 'Sign In'
                        : 'Create Account'),
              ),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _isSignIn = !_isSignIn;
                          _errorText = null;
                        });
                      },
                child: Text(_isSignIn
                    ? 'Need an account? Register'
                    : 'Already have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.onSignOut,
    required this.userId,
    required this.userEmail,
  });

  final Future<void> Function() onSignOut;
  final String userId;
  final String userEmail;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _textController = TextEditingController();
  bool _newItemHighPriority = false;
  final List<TodoItem> _items = [];
  final List<TodoItem> _deletedItems = [];
  int _selectedIndex = 0;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _activeItemsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _deletedItemsStream;

  CollectionReference<Map<String, dynamic>> get _activeItemsRef {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('todos');
  }

  CollectionReference<Map<String, dynamic>> get _deletedItemsRef {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('deleted_todos');
  }

  @override
  void initState() {
    super.initState();
    _activeItemsStream = _activeItemsRef.orderBy('createdAt').snapshots();
    _deletedItemsStream = _deletedItemsRef.orderBy('deletedAt', descending: true).snapshots();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _addItem(bool isHighPriority) async {
    final enteredText = _textController.text.trim();
    if (enteredText.isEmpty) {
      return;
    }

    try {
      await _activeItemsRef.add({
        'text': enteredText,
        'completed': false,
        'highPriority': isHighPriority,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to add item.')),
      );
    }
    _textController.clear();
    setState(() {
      _newItemHighPriority = false;
    });
  }

  Future<void> _toggleComplete(String itemId, bool isCompleted) async {
    try {
      await _activeItemsRef.doc(itemId).update({
        'completed': !isCompleted,
      });
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to update item.')),
      );
    }
  }

  Future<void> _deleteItem(String itemId) async {
    final itemIndex = _items.indexWhere((e) => e.id == itemId);
    if (itemIndex == -1) {
      return;
    }

    final deletedItem = _items[itemIndex];
    try {
      await _deletedItemsRef.add({
        'text': deletedItem.text,
        'completed': deletedItem.completed,
        'highPriority': deletedItem.highPriority,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      await _activeItemsRef.doc(itemId).delete();
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to delete item.')),
      );
    }
  }

  Future<void> _editItem(String itemId, String newText, bool isHighPriority) async {
    final updatedText = newText.trim();
    if (updatedText.isEmpty) {
      return;
    }

    try {
      await _activeItemsRef.doc(itemId).update({
        'text': updatedText,
        'highPriority': isHighPriority,
      });
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to edit item.')),
      );
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  BottomNavigationBar _buildBottomNavigationBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onTabTapped,
      type: BottomNavigationBarType.fixed,
      backgroundColor: colorScheme.surface,
      selectedItemColor: colorScheme.primary,
      unselectedItemColor: colorScheme.onSurface.withValues(alpha: 0.7),
      selectedFontSize: 14,
      unselectedFontSize: 12,
      iconSize: 28,
      showUnselectedLabels: true,
      elevation: 12,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.edit_note),
          label: 'Input',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.list),
          label: 'List',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.priority_high),
          label: 'High Priority',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.delete_sweep_outlined),
          label: 'Deleted',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeSnapshot = _activeItemsStream;
    final deletedSnapshot = _deletedItemsStream;
    if (activeSnapshot == null || deletedSnapshot == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: activeSnapshot,
      builder: (context, activeData) {
        final activeDocs = activeData.data?.docs ?? const [];
        _items
          ..clear()
          ..addAll(activeDocs.map(TodoItem.fromDoc));

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: deletedSnapshot,
          builder: (context, deletedData) {
            final deletedDocs = deletedData.data?.docs ?? const [];
            _deletedItems
              ..clear()
              ..addAll(deletedDocs.map(TodoItem.fromDoc));

    if (_selectedIndex == 0) {
      return InputPage(
        controller: _textController,
        isHighPriority: _newItemHighPriority,
        onHighPriorityChanged: (value) {
          setState(() {
            _newItemHighPriority = value;
          });
        },
        onAddItem: _addItem,
        userEmail: widget.userEmail,
        onSignOut: widget.onSignOut,
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    if (_selectedIndex == 1) {
      return ListPage(
        items: List.unmodifiable(_items),
        onToggleComplete: _toggleComplete,
        onEdit: _editItem,
        onDelete: _deleteItem,
        userEmail: widget.userEmail,
        onSignOut: widget.onSignOut,
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    if (_selectedIndex == 2) {
      return HighPriorityPage(
        items: List.unmodifiable(
          _items.where((item) => item.highPriority),
        ),
        onToggleComplete: _toggleComplete,
        onEdit: _editItem,
        onDelete: _deleteItem,
        userEmail: widget.userEmail,
        onSignOut: widget.onSignOut,
        bottomNavigationBar: _buildBottomNavigationBar(),
      );
    }

    return DeletedItemsPage(
      deletedItems: List.unmodifiable(_deletedItems),
      userEmail: widget.userEmail,
      onSignOut: widget.onSignOut,
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
          },
        );
      },
    );
  }
}

class InputPage extends StatelessWidget {
  const InputPage({
    super.key,
    required this.controller,
    required this.isHighPriority,
    required this.onHighPriorityChanged,
    required this.onAddItem,
    required this.userEmail,
    required this.onSignOut,
    required this.bottomNavigationBar,
  });

  final TextEditingController controller;
  final bool isHighPriority;
  final ValueChanged<bool> onHighPriorityChanged;
  final Future<void> Function(bool isHighPriority) onAddItem;
  final String userEmail;
  final Future<void> Function() onSignOut;
  final BottomNavigationBar bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Add Item ($userEmail)'),
        actions: [
          IconButton(
            onPressed: () async => onSignOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Enter item text',
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('High Priority'),
                value: isHighPriority,
                onChanged: onHighPriorityChanged,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async => onAddItem(isHighPriority),
                child: const Text('Add to List'),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class ListPage extends StatelessWidget {
  const ListPage({
    super.key,
    required this.items,
    required this.onToggleComplete,
    required this.onEdit,
    required this.onDelete,
    required this.userEmail,
    required this.onSignOut,
    required this.bottomNavigationBar,
  });

  final List<TodoItem> items;
  final Future<void> Function(String itemId, bool isCompleted) onToggleComplete;
  final Future<void> Function(String itemId, String newText, bool isHighPriority) onEdit;
  final Future<void> Function(String itemId) onDelete;
  final String userEmail;
  final Future<void> Function() onSignOut;
  final BottomNavigationBar bottomNavigationBar;

  Future<void> _showEditDialog(BuildContext context, TodoItem item) async {
    final controller = TextEditingController(text: item.text);
    var isHighPriority = item.highPriority;
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Edit Item'),
            content: StatefulBuilder(
              builder: (context, setDialogState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Item text',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('High Priority'),
                    value: isHighPriority,
                    onChanged: (value) {
                      setDialogState(() {
                        isHighPriority = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop({
                    'text': controller.text.trim(),
                    'highPriority': isHighPriority,
                  });
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (result == null) {
        return;
      }
      final updatedText = result['text'] as String? ?? '';
      final updatedPriority = result['highPriority'] as bool? ?? item.highPriority;
      if (updatedText.isEmpty ||
          (updatedText == item.text && updatedPriority == item.highPriority)) {
        return;
      }
      await onEdit(item.id, updatedText, updatedPriority);
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('To-Do List ($userEmail)'),
        actions: [
          IconButton(
            onPressed: () async => onSignOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Text('No items yet. Add one from the Input page.'),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Checkbox(
                    value: item.completed,
                    onChanged: (_) async {
                      await onToggleComplete(item.id, item.completed);
                    },
                  ),
                  title: Text(
                    item.text,
                    style: TextStyle(
                      decoration: item.completed
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  subtitle: item.highPriority
                      ? const Text('High Priority')
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () async => _showEditDialog(context, item),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async => onDelete(item.id),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class HighPriorityPage extends StatelessWidget {
  const HighPriorityPage({
    super.key,
    required this.items,
    required this.onToggleComplete,
    required this.onEdit,
    required this.onDelete,
    required this.userEmail,
    required this.onSignOut,
    required this.bottomNavigationBar,
  });

  final List<TodoItem> items;
  final Future<void> Function(String itemId, bool isCompleted) onToggleComplete;
  final Future<void> Function(String itemId, String newText, bool isHighPriority) onEdit;
  final Future<void> Function(String itemId) onDelete;
  final String userEmail;
  final Future<void> Function() onSignOut;
  final BottomNavigationBar bottomNavigationBar;

  Future<void> _showEditDialog(BuildContext context, TodoItem item) async {
    final controller = TextEditingController(text: item.text);
    var isHighPriority = item.highPriority;
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Edit Item'),
            content: StatefulBuilder(
              builder: (context, setDialogState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Item text',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('High Priority'),
                    value: isHighPriority,
                    onChanged: (value) {
                      setDialogState(() {
                        isHighPriority = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop({
                    'text': controller.text.trim(),
                    'highPriority': isHighPriority,
                  });
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (result == null) {
        return;
      }
      final updatedText = result['text'] as String? ?? '';
      final updatedPriority = result['highPriority'] as bool? ?? item.highPriority;
      if (updatedText.isEmpty ||
          (updatedText == item.text && updatedPriority == item.highPriority)) {
        return;
      }
      await onEdit(item.id, updatedText, updatedPriority);
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('High Priority ($userEmail)'),
        actions: [
          IconButton(
            onPressed: () async => onSignOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Text('No high priority items.'),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Checkbox(
                    value: item.completed,
                    onChanged: (_) async {
                      await onToggleComplete(item.id, item.completed);
                    },
                  ),
                  title: Text(
                    item.text,
                    style: TextStyle(
                      decoration: item.completed
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  subtitle: const Text('High Priority'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () async => _showEditDialog(context, item),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async => onDelete(item.id),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class DeletedItemsPage extends StatelessWidget {
  const DeletedItemsPage({
    super.key,
    required this.deletedItems,
    required this.userEmail,
    required this.onSignOut,
    required this.bottomNavigationBar,
  });

  final List<TodoItem> deletedItems;
  final String userEmail;
  final Future<void> Function() onSignOut;
  final BottomNavigationBar bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Deleted Items ($userEmail)'),
        actions: [
          IconButton(
            onPressed: () async => onSignOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: deletedItems.isEmpty
          ? const Center(
              child: Text('No deleted items yet.'),
            )
          : ListView.builder(
              itemCount: deletedItems.length,
              itemBuilder: (context, index) {
                final item = deletedItems[index];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    item.text,
                    style: TextStyle(
                      decoration: item.completed
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class TodoItem {
  const TodoItem({
    required this.id,
    required this.text,
    required this.completed,
    required this.highPriority,
  });

  final String id;
  final String text;
  final bool completed;
  final bool highPriority;

  factory TodoItem.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return TodoItem(
      id: doc.id,
      text: data['text'] as String? ?? '',
      completed: data['completed'] as bool? ?? false,
      highPriority: data['highPriority'] as bool? ?? false,
    );
  }
}
