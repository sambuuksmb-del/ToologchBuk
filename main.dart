import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'firebase_options.dart';

// ✅ One shared inventory for everyone who logs in
const String kShopId = 'global';

// -------------------- FIRESTORE PATHS --------------------

DocumentReference<Map<String, dynamic>> _settingsDoc(String shopId) {
  return FirebaseFirestore.instance
      .collection('shops')
      .doc(shopId)
      .collection('settings')
      .doc('app');
}

CollectionReference<Map<String, dynamic>> _itemsCol(String shopId) {
  return FirebaseFirestore.instance
      .collection('shops')
      .doc(shopId)
      .collection('items');
}

// -------------------- STARTUP SAFE INIT --------------------

Future<void> _ensureSettingsExists() async {
  try {
    final ref = _settingsDoc(kShopId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set(<String, dynamic>{
        'darkMode': false,
        'lowStock': 5,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  } catch (e) {
    debugPrint('Firestore settings init error: $e');
    rethrow;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ DO NOT let Firestore failure blank the app
  try {
    await _ensureSettingsExists();
  } catch (e) {
    debugPrint('ensureSettingsExists failed: $e');
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint(details.toString());
  };

  runApp(const MyApp());
}

// -------------------- APP --------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: const Color(0xFF6C63FF),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  ThemeData _darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF6C63FF),
      scaffoldBackgroundColor: const Color(0xFF0E0F13),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF151823),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF151823),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF151823),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _settingsDoc(kShopId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final darkMode = (data['darkMode'] ?? false) as bool;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Shop Inventory',
          theme: _lightTheme(),
          darkTheme: _darkTheme(),
          themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
          home: const AuthGate(),
        );
      },
    );
  }
}

// -------------------- AUTH --------------------

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.hasData) {
          return const LoginScreen();
        }
        return const MainShell(shopId: kShopId);
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _login() async {
    setState(() => loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Login failed');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _signup() async {
    setState(() => loading = true);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Signup failed');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Sign in'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text(
                  'Shop Inventory (Global)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: loading ? null : _login,
                    child: loading
                        ? const CircularProgressIndicator()
                        : const Text('Login'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: loading ? null : _signup,
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- MAIN SHELL --------------------

class MainShell extends StatefulWidget {
  final String shopId;
  const MainShell({super.key, required this.shopId});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  void _goAdd() {
    setState(() => index = 1);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(shopId: widget.shopId, onGoAdd: _goAdd),
      AddPage(shopId: widget.shopId, onAdded: () => setState(() => index = 0)),
      StatsPage(shopId: widget.shopId),
      SettingsPage(shopId: widget.shopId),
    ];

    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.storefront), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.add_box), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// -------------------- COMMON UI --------------------

class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? trailing;
  final double height;

  const GradientAppBar({
    super.key,
    required this.title,
    this.trailing,
    this.height = 110,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: height,
      title: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
      ),
      actions: trailing == null
          ? null
          : <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 18, right: 12),
                child: trailing!,
              ),
            ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF6C63FF), Color(0xFF00D2FF)],
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(22),
          ),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const Pill({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? cs.primary.withValues(alpha: 0.18)
              : (isDark ? const Color(0xFF151823) : Colors.white),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.55)
                : cs.outline.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? cs.primary : null,
          ),
        ),
      ),
    );
  }
}

class CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  const CircleIconBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = danger
        ? (isDark ? const Color(0xFF2A1313) : const Color(0xFFFFE8E8))
        : (isDark ? const Color(0xFF1C2030) : const Color(0xFFEEF2FF));
    final fg = danger ? const Color(0xFFE53935) : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        height: 38,
        width: 38,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, color: fg, size: 20),
      ),
    );
  }
}

// -------------------- HELPERS --------------------

Stream<int> _lowStockStream(String shopId) {
  return _settingsDoc(shopId).snapshots().map((s) {
    final data = s.data() ?? <String, dynamic>{};
    return (data['lowStock'] ?? 5) as int;
  });
}

Future<void> _changeQty(String shopId, String itemId, int delta) async {
  final ref = _itemsCol(shopId).doc(itemId);

  await FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(ref);
    final current = (snap.data()?['qty'] ?? 0) as int;
    final next = current + delta;
    tx.update(ref, <String, dynamic>{
      'qty': next < 0 ? 0 : next,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });
}

Future<void> _deleteItem(
  String shopId,
  String itemId,
  String? storagePath,
) async {
  await _itemsCol(shopId).doc(itemId).delete();
  if (storagePath != null && storagePath.isNotEmpty) {
    try {
      await FirebaseStorage.instance.ref(storagePath).delete();
    } catch (_) {}
  }
}

// -------------------- HOME --------------------

class HomePage extends StatefulWidget {
  final String shopId;
  final VoidCallback onGoAdd;

  const HomePage({super.key, required this.shopId, required this.onGoAdd});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';
  String category = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Shop Inventory',
        trailing: IconButton(
          tooltip: 'Add item',
          onPressed: widget.onGoAdd,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _itemsCol(
          widget.shopId,
        ).orderBy('updatedAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          final set = <String>{};
          for (final d in docs) {
            final c = (d.data()['category'] ?? 'Other').toString().trim();
            if (c.isNotEmpty) set.add(c);
          }
          final categories = <String>['All', ...(set.toList()..sort())];

          final qLower = query.trim().toLowerCase();
          final filtered = docs.where((d) {
            final data = d.data();
            final name = (data['name'] ?? '').toString().toLowerCase();
            final cat = (data['category'] ?? 'Other').toString();
            final qOk = qLower.isEmpty || name.contains(qLower);
            final cOk = category == 'All' || cat == category;
            return qOk && cOk;
          }).toList();

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    hintText: 'Search items…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(() => query = ''),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              SizedBox(
                height: 46,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (context, idx) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final c = categories[i];
                    return Pill(
                      text: c,
                      selected: category == c,
                      onTap: () => setState(() => category = c),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            docs.isEmpty
                                ? 'No items yet.\nGo to Add and create your first product.'
                                : 'No results. Try another search.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.78,
                            ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          return InventoryTile(
                            shopId: widget.shopId,
                            doc: filtered[index],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class InventoryTile extends StatelessWidget {
  final String shopId;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const InventoryTile({super.key, required this.shopId, required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final name = (data['name'] ?? '').toString();
    final qty = (data['qty'] ?? 0) as int;
    final cat = (data['category'] ?? 'Other').toString();
    final imageUrl = data['imageUrl'] as String?;
    final storagePath = data['storagePath'] as String?;

    return StreamBuilder<int>(
      stream: _lowStockStream(shopId),
      builder: (context, snap) {
        final threshold = snap.data ?? 5;
        final isLow = qty <= threshold;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Card(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: <Color>[
                  isDark ? const Color(0xFF151823) : Colors.white,
                  isDark
                      ? const Color(0xFF151823).withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.95),
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: isDark
                            ? const Color(0xFF1C2030)
                            : const Color(0xFFF1F2FF),
                      ),
                      child: imageUrl == null
                          ? const Center(child: Icon(Icons.image, size: 34))
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(imageUrl, fit: BoxFit.cover),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: const Color(0xFFEEF2FF).withValues(alpha: 0.8),
                        ),
                        child: Text(
                          cat,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: isLow
                              ? const Color(0xFFFFE8E8)
                              : const Color(0xFFE7F7EE),
                        ),
                        child: Text(
                          'Stock: $qty',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: isLow
                                ? const Color(0xFFE53935)
                                : const Color(0xFF1B7F3B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      CircleIconBtn(
                        icon: Icons.remove,
                        onTap: () => _changeQty(shopId, doc.id, -1),
                      ),
                      Text(
                        '$qty',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      CircleIconBtn(
                        icon: Icons.add,
                        onTap: () => _changeQty(shopId, doc.id, 1),
                      ),
                      CircleIconBtn(
                        icon: Icons.delete_outline,
                        danger: true,
                        onTap: () async {
                          await _deleteItem(shopId, doc.id, storagePath);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Item deleted')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -------------------- ADD --------------------

class AddPage extends StatefulWidget {
  final String shopId;
  final VoidCallback onAdded;

  const AddPage({super.key, required this.shopId, required this.onAdded});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final picker = ImagePicker();
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final catCtrl = TextEditingController(text: 'Other');

  Uint8List? pickedBytes;
  String? pickedName;
  bool loading = false;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickImage() async {
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      pickedBytes = bytes;
      pickedName = picked.name;
    });
  }

  Future<void> _saveItem() async {
    final name = nameCtrl.text.trim();
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
    final cat = catCtrl.text.trim().isEmpty ? 'Other' : catCtrl.text.trim();

    if (name.isEmpty) {
      _toast("Name can't be empty");
      return;
    }

    setState(() => loading = true);
    try {
      final docRef = await _itemsCol(widget.shopId).add(<String, dynamic>{
        'name': name,
        'qty': qty < 0 ? 0 : qty,
        'category': cat,
        'imageUrl': null,
        'storagePath': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (pickedBytes != null) {
        final ext = (pickedName == null || pickedName!.isEmpty)
            ? '.jpg'
            : p.extension(pickedName!);
        final storagePath =
            'shops/${widget.shopId}/items/${docRef.id}/image$ext';
        final ref = FirebaseStorage.instance.ref(storagePath);

        await ref.putData(
          pickedBytes!,
          SettableMetadata(contentType: 'image/${ext.replaceAll(".", "")}'),
        );

        final url = await ref.getDownloadURL();

        await docRef.update(<String, dynamic>{
          'imageUrl': url,
          'storagePath': storagePath,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      nameCtrl.clear();
      qtyCtrl.text = '1';
      catCtrl.text = 'Other';
      setState(() {
        pickedBytes = null;
        pickedName = null;
      });

      _toast('Item added ✅');
      widget.onAdded();
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    catCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Add Item'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            GestureDetector(
              onTap: loading ? null : _pickImage,
              child: Container(
                height: 170,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF6C63FF), Color(0xFF00D2FF)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: isDark ? const Color(0xFF151823) : Colors.white,
                      child: pickedBytes == null
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 38,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Tap to add image',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ],
                            )
                          : Image.memory(pickedBytes!, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: catCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Category (e.g. Drinks)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: loading ? null : _saveItem,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  loading ? 'Saving...' : 'Save Item',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- STATS --------------------

class StatsPage extends StatelessWidget {
  final String shopId;
  const StatsPage({super.key, required this.shopId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Stats'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _itemsCol(shopId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          return StreamBuilder<int>(
            stream: _lowStockStream(shopId),
            builder: (context, lowSnap) {
              final threshold = lowSnap.data ?? 5;

              final totalProducts = docs.length;
              final totalStock = docs.fold<int>(
                0,
                (total, d) => total + ((d.data()['qty'] ?? 0) as int),
              );

              final lowItems =
                  docs
                      .map((d) => d.data())
                      .where((it) => ((it['qty'] ?? 0) as int) <= threshold)
                      .toList()
                    ..sort(
                      (a, b) => ((a['qty'] ?? 0) as int).compareTo(
                        (b['qty'] ?? 0) as int,
                      ),
                    );

              Map<String, dynamic>? mostStock;
              for (final d in docs) {
                final it = d.data();
                if (mostStock == null) {
                  mostStock = it;
                } else {
                  final q1 = (it['qty'] ?? 0) as int;
                  final q2 = (mostStock['qty'] ?? 0) as int;
                  if (q1 > q2) {
                    mostStock = it;
                  }
                }
              }

              return ListView(
                padding: const EdgeInsets.all(12),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _statCard(
                          context,
                          'Products',
                          '$totalProducts',
                          Icons.inventory_2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          context,
                          'Total Stock',
                          '$totalStock',
                          Icons.stacked_bar_chart,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _statCard(
                    context,
                    'Low Stock (≤ $threshold)',
                    '${lowItems.length}',
                    Icons.warning_amber,
                    danger: true,
                  ),
                  const SizedBox(height: 12),
                  if (mostStock != null)
                    _bigInfoCard(
                      context,
                      title: 'Most Stock',
                      subtitle: (mostStock['name'] ?? '').toString(),
                      trailing: 'Qty: ${(mostStock['qty'] ?? 0) as int}',
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Low stock items',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (lowItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'No low stock items 🎉',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    )
                  else
                    ...lowItems.take(20).map((it) {
                      final name = (it['name'] ?? '').toString();
                      final qty = (it['qty'] ?? 0) as int;
                      final cat = (it['category'] ?? 'Other').toString();
                      return Card(
                        child: ListTile(
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(cat),
                          trailing: Text(
                            '$qty',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = danger
        ? const Color(0xFFFFE8E8)
        : (isDark ? const Color(0xFF151823) : Colors.white);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: bg,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: cs.primary.withValues(alpha: 0.18),
            ),
            child: Icon(icon, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: danger ? const Color(0xFFE53935) : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigInfoCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF6C63FF), Color(0xFF00D2FF)],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            trailing,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- SETTINGS --------------------

class SettingsPage extends StatelessWidget {
  final String shopId;
  const SettingsPage({super.key, required this.shopId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Settings'),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _settingsDoc(shopId).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? <String, dynamic>{};
          final darkMode = (data['darkMode'] ?? false) as bool;
          final low = (data['lowStock'] ?? 5) as int;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
              Card(
                child: SwitchListTile(
                  title: const Text(
                    'Dark Mode',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: const Text('Looks cooler at night 😎'),
                  value: darkMode,
                  onChanged: (v) {
                    _settingsDoc(shopId).set(<String, dynamic>{
                      'darkMode': v,
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                  },
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  title: const Text(
                    'Low Stock Threshold',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('Items with stock ≤ $low will be marked low.'),
                  trailing: SizedBox(
                    width: 110,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        CircleIconBtn(
                          icon: Icons.remove,
                          onTap: () {
                            final next = (low - 1) < 1 ? 1 : (low - 1);
                            _settingsDoc(shopId).set(<String, dynamic>{
                              'lowStock': next,
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$low',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleIconBtn(
                          icon: Icons.add,
                          onTap: () {
                            _settingsDoc(shopId).set(<String, dynamic>{
                              'lowStock': low + 1,
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  title: const Text(
                    'Account',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    FirebaseAuth.instance.currentUser?.email ?? '',
                  ),
                  trailing: ElevatedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
