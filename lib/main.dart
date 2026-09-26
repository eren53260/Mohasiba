
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DebtStore();
  await store.load();
  runApp(DebtApp(store: store));
}

class Debt {
  String id;
  String person;
  double amount;
  double paid;
  DateTime date;
  String note;
  bool lent; // true: user lent money, false: user borrowed

  Debt({
    required this.id,
    required this.person,
    required this.amount,
    this.paid = 0,
    required this.date,
    this.note = '',
    required this.lent,
  });

  double get remaining => (amount - paid).clamp(0, double.infinity);

  Map<String, dynamic> toJson() => {
    'id': id, 'person': person, 'amount': amount, 'paid': paid,
    'date': date.toIso8601String(), 'note': note, 'lent': lent,
  };

  factory Debt.fromJson(Map<String, dynamic> j) => Debt(
    id: j['id'],
    person: j['person'] ?? '',
    amount: (j['amount'] as num).toDouble(),
    paid: ((j['paid'] ?? 0) as num).toDouble(),
    date: DateTime.parse(j['date']),
    note: j['note'] ?? '',
    lent: j['lent'] ?? true,
  );
}

class DebtStore extends ChangeNotifier {
  final List<Debt> debts = [];
  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString('debts');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      debts
        ..clear()
        ..addAll(list.map((e) => Debt.fromJson(Map<String, dynamic>.from(e))));
    }
  }

  Future<void> save() async {
    await _prefs!.setString('debts', jsonEncode(debts.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> add(Debt d) async { debts.insert(0, d); await save(); }
  Future<void> update(Debt d) async { 
    final i = debts.indexWhere((x) => x.id == d.id);
    if (i >= 0) debts[i] = d;
    await save();
  }
  Future<void> remove(String id) async { debts.removeWhere((x) => x.id == id); await save(); }

  Future<String> backupJson() async => jsonEncode({
    'app': 'ghard_app', 'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'debts': debts.map((e) => e.toJson()).toList(),
  });

  Future<bool> restoreFromJson(String text) async {
    try {
      final obj = jsonDecode(text);
      final list = (obj['debts'] as List).map((e) => Debt.fromJson(Map<String,dynamic>.from(e))).toList();
      debts..clear()..addAll(list);
      await save();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class DebtApp extends StatelessWidget {
  final DebtStore store;
  const DebtApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (_, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دفتر قرض',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xfff7f7fb),
      ),
      home: Directionality(textDirection: TextDirection.rtl, child: HomePage(store: store)),
    ),
  );
}

String money(double n) => n.toStringAsFixed(0);

class HomePage extends StatefulWidget {
  final DebtStore store;
  const HomePage({super.key, required this.store});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';

  List<Debt> get filtered {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return widget.store.debts;
    return widget.store.debts.where((d) =>
      d.person.toLowerCase().contains(q) || d.note.toLowerCase().contains(q)).toList();
  }

  double get totalLent => widget.store.debts.where((d) => d.lent).fold(0, (s,d)=>s+d.remaining);
  double get totalBorrowed => widget.store.debts.where((d) => !d.lent).fold(0, (s,d)=>s+d.remaining);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر قرض', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'backup') await backup();
              if (v == 'restore') await restore();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'backup', child: Text('پشتیبان‌گیری')),
              PopupMenuItem(value: 'restore', child: Text('بازیابی اطلاعات')),
            ],
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDebtForm(context),
        icon: const Icon(Icons.add),
        label: const Text('قرض جدید'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Expanded(child: _stat('طلب من', totalLent)),
            const SizedBox(width: 8),
            Expanded(child: _stat('بدهی من', totalBorrowed)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            textDirection: TextDirection.rtl,
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              hintText: 'جستجوی نام یا توضیحات...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
            ? const Center(child: Text('هنوز قرضی ثبت نشده است.'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _card(filtered[i]),
              ),
        ),
      ]),
    );
  }

  Widget _stat(String title, double value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Text(title, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 5),
        Text('${money(value)} افغانی', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      ]),
    ),
  );

  Widget _card(Debt d) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDebtDetails(context, d),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(child: Icon(d.lent ? Icons.arrow_upward : Icons.arrow_downward)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.person, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(d.lent ? 'طلب از شخص' : 'بدهی به شخص'),
              const SizedBox(height: 4),
              Text('مانده: ${money(d.remaining)} افغانی',
                style: TextStyle(fontWeight: FontWeight.bold,
                  color: d.remaining == 0 ? Colors.green : null)),
            ],
          )),
          const Icon(Icons.chevron_left),
        ]),
      ),
    ),
  );

  Future<void> showDebtForm(BuildContext context, {Debt? existing}) async {
    final person = TextEditingController(text: existing?.person ?? '');
    final amount = TextEditingController(text: existing == null ? '' : money(existing.amount));
    final note = TextEditingController(text: existing?.note ?? '');
    bool lent = existing?.lent ?? true;
    DateTime date = existing?.date ?? DateTime.now();

    await showDialog(context: context, builder: (_) => StatefulBuilder(
      builder: (context, setD) => AlertDialog(
        title: Text(existing == null ? 'قرض جدید' : 'ویرایش قرض'),
        content: SingleChildScrollView(child: Column(children: [
          TextField(controller: person, decoration: const InputDecoration(labelText: 'نام شخص')),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ (افغانی)')),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('من قرض دادم')),
              ButtonSegment(value: false, label: Text('من قرض گرفتم')),
            ],
            selected: {lent},
            onSelectionChanged: (s) => setD(() => lent = s.first),
          ),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تاریخ'),
            subtitle: Text('${date.year}/${date.month}/${date.day}'),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final x = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: date);
              if (x != null) setD(() => date = x);
            },
          ),
        ])),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () async {
            final p = person.text.trim();
            final a = double.tryParse(amount.text.replaceAll(',', '').trim());
            if (p.isEmpty || a == null || a <= 0) return;
            final d = existing ?? Debt(id: DateTime.now().microsecondsSinceEpoch.toString(), person: p, amount: a, date: date, lent: lent);
            d.person=p; d.amount=a; d.date=date; d.note=note.text.trim(); d.lent=lent;
            if (existing == null) await widget.store.add(d); else await widget.store.update(d);
            if (context.mounted) Navigator.pop(context);
          }, child: const Text('ذخیره')),
        ],
      ),
    ));
  }

  Future<void> showDebtDetails(BuildContext context, Debt d) async {
    await showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(d.person, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('مبلغ اصلی: ${money(d.amount)} افغانی'),
          Text('پرداخت‌شده: ${money(d.paid)} افغانی'),
          Text('مانده: ${money(d.remaining)} افغانی', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (d.note.isNotEmpty) Text('توضیحات: ${d.note}'),
          const SizedBox(height: 18),
          Wrap(spacing: 8, children: [
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final c = TextEditingController();
                await showDialog(context: context, builder: (_) => AlertDialog(
                  title: const Text('ثبت پرداخت'),
                  content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ پرداختی')),
                  actions: [
                    TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('انصراف')),
                    FilledButton(onPressed: () async {
                      final x = double.tryParse(c.text.replaceAll(',', '').trim());
                      if (x == null || x <= 0) return;
                      d.paid = (d.paid + x).clamp(0, d.amount);
                      await widget.store.update(d);
                      if (context.mounted) Navigator.pop(context);
                    }, child: const Text('ثبت')),
                  ],
                ));
              },
              icon: const Icon(Icons.payments), label: const Text('ثبت پرداخت'),
            ),
            OutlinedButton.icon(
              onPressed: () { Navigator.pop(context); showDebtForm(context, existing: d); },
              icon: const Icon(Icons.edit), label: const Text('ویرایش'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await widget.store.remove(d.id);
              },
              icon: const Icon(Icons.delete_outline), label: const Text('حذف'),
            ),
          ]),
          const SizedBox(height: 8),
        ])),
      ),
    ));
  }

  Future<void> backup() async {
    final text = await widget.store.backupJson();
    final result = await FilePicker.platform.saveFile(fileName: 'ghard_backup.json', bytes: utf8.encode(text));
    if (result != null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فایل پشتیبان ذخیره شد.')));
  }

  Future<void> restore() async {
    final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.single.bytes == null) return;
    final ok = await widget.store.restoreFromJson(utf8.decode(result.files.single.bytes!));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'اطلاعات بازیابی شد.' : 'فایل پشتیبان نامعتبر است.')));
  }
}
