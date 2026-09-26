import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DebtStore();
  await store.load();
  runApp(DebtApp(store));
}

enum TxKind { debt, payment }

class Tx {
  final String id, person, note;
  final double amount;
  final DateTime date;
  final bool lent;
  final TxKind kind;
  Tx({required this.id, required this.person, required this.amount, required this.date, required this.lent, required this.kind, this.note = ''});
  Map<String,dynamic> toJson()=>{'id':id,'person':person,'amount':amount,'date':date.toIso8601String(),'lent':lent,'kind':kind.name,'note':note};
  factory Tx.fromJson(Map<String,dynamic> j)=>Tx(id:'${j['id']}',person:j['person']??'',amount:(j['amount'] as num).toDouble(),date:DateTime.parse(j['date']),lent:j['lent']??true,kind:TxKind.values.firstWhere((x)=>x.name==(j['kind']??'debt'),orElse:()=>TxKind.debt),note:j['note']??'');
}

class DebtStore extends ChangeNotifier {
  final List<Tx> txs=[];
  SharedPreferences? prefs;
  Future<void> load() async {
    prefs=await SharedPreferences.getInstance();
    final raw=prefs!.getString('txs_v2');
    if(raw!=null){txs..clear()..addAll((jsonDecode(raw) as List).map((e)=>Tx.fromJson(Map<String,dynamic>.from(e))));}
    // Import the first-version data if it exists.
    if(txs.isEmpty){
      final old=prefs!.getString('debts');
      if(old!=null){
        try{for(final e in jsonDecode(old) as List){final j=Map<String,dynamic>.from(e);final id='${j['id']}';final person=j['person']??'';final amount=(j['amount'] as num).toDouble();final paid=((j['paid']??0) as num).toDouble();final date=DateTime.parse(j['date']);final lent=j['lent']??true;txs.add(Tx(id:'$id-d',person:person,amount:amount,date:date,lent:lent,kind:TxKind.debt,note:j['note']??''));if(paid>0)txs.add(Tx(id:'$id-p',person:person,amount:paid,date:date,lent:lent,kind:TxKind.payment,note:'پرداخت ثبت‌شده قبلی'));}await save();}catch(_){}}
    }
  }
  Future<void> save() async {txs.sort((a,b)=>b.date.compareTo(a.date));await prefs!.setString('txs_v2',jsonEncode(txs.map((x)=>x.toJson()).toList()));notifyListeners();}
  Future<void> add(Tx t) async {txs.add(t);await save();}
  Future<void> remove(String id) async {txs.removeWhere((x)=>x.id==id);await save();}
  List<String> people(){final s=txs.map((x)=>x.person.trim()).where((x)=>x.isNotEmpty).toSet().toList();s.sort();return s;}
  List<Tx> forPerson(String p)=>txs.where((x)=>x.person==p).toList()..sort((a,b)=>b.date.compareTo(a.date));
  double balance(String p){double b=0;for(final t in txs.where((x)=>x.person==p)){if(t.kind==TxKind.debt)b+=t.lent?t.amount:-t.amount;else b+=t.lent?-t.amount:t.amount;}return b;}
  Future<String> backup() async=>jsonEncode({'app':'ghard_app','version':2,'transactions':txs.map((x)=>x.toJson()).toList()});
  Future<bool> restore(String text) async{try{final list=jsonDecode(text)['transactions'] as List;txs..clear()..addAll(list.map((e)=>Tx.fromJson(Map<String,dynamic>.from(e))));await save();return true;}catch(_){return false;}}
}

class DebtApp extends StatelessWidget{final DebtStore store;const DebtApp(this.store,{super.key});@override Widget build(BuildContext c)=>AnimatedBuilder(animation:store,builder:(_,__)=>MaterialApp(debugShowCheckedModeBanner:false,title:'دفتر قرض',theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.indigo,scaffoldBackgroundColor:const Color(0xfff7f7fb)),home:Directionality(textDirection:TextDirection.rtl,child:Home(store))));}
String money(double n)=>n.abs().toStringAsFixed(0);
String dateText(DateTime d)=>'${d.year}/${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}';

class Home extends StatefulWidget{final DebtStore store;const Home(this.store,{super.key});@override State<Home> createState()=>_HomeState();}
class _HomeState extends State<Home>{String q='';
  @override Widget build(BuildContext c){final names=widget.store.people().where((n)=>n.contains(q.trim())).toList();double owed=0,me=0;for(final n in widget.store.people()){final b=widget.store.balance(n);if(b>0)owed+=b;if(b<0)me+=-b;}
    return Scaffold(appBar:AppBar(title:const Text('دفتر قرض',style:TextStyle(fontWeight:FontWeight.bold)),actions:[PopupMenuButton<String>(onSelected:(v)async{if(v=='backup')await backup();else await restore();},itemBuilder:(_)=>const[PopupMenuItem(value:'backup',child:Text('پشتیبان‌گیری')),PopupMenuItem(value:'restore',child:Text('بازیابی اطلاعات'))])]),floatingActionButton:FloatingActionButton.extended(onPressed:()=>openForm(c),icon:const Icon(Icons.add),label:const Text('قرض جدید')),body:Column(children:[Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:Row(children:[Expanded(child:stat('طلب من',owed)),const SizedBox(width:8),Expanded(child:stat('بدهی من',me))])),Padding(padding:const EdgeInsets.all(12),child:TextField(onChanged:(v)=>setState(()=>q=v),decoration:InputDecoration(hintText:'جستجوی نام...',prefixIcon:const Icon(Icons.search),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none)))),Expanded(child:names.isEmpty?const Center(child:Text('هنوز شخصی ثبت نشده است.')):ListView.builder(padding:const EdgeInsets.fromLTRB(12,0,12,90),itemCount:names.length,itemBuilder:(_,i)=>card(c,names[i])))]));}
  Widget stat(String t,double v)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[Text(t),const SizedBox(height:4),Text('${money(v)} افغانی',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17))])));
  Widget card(BuildContext c,String n){final b=widget.store.balance(n);return Card(margin:const EdgeInsets.only(bottom:9),child:InkWell(onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>PersonPage(widget.store,n))),child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[CircleAvatar(child:Icon(b>=0?Icons.arrow_upward:Icons.arrow_downward)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(n,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),Text(b>0?'طلب از شخص':b<0?'بدهی من به شخص':'تسویه شده'),Text('مانده: ${money(b)} افغانی',style:const TextStyle(fontWeight:FontWeight.bold))])),const Icon(Icons.chevron_left)]))));}
  Future<void> openForm(BuildContext c,{Tx? edit})async{await showTxDialog(c,widget.store,edit:edit);}
  Future<void> backup()async{final r=await FilePicker.platform.saveFile(fileName:'ghard_backup_v2.json',bytes:utf8.encode(await widget.store.backup()));if(r!=null&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('پشتیبان ذخیره شد.')));}
  Future<void> restore()async{final r=await FilePicker.platform.pickFiles(withData:true,type:FileType.custom,allowedExtensions:['json']);if(r==null||r.files.single.bytes==null)return;final ok=await widget.store.restore(utf8.decode(r.files.single.bytes!));if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok?'اطلاعات بازیابی شد.':'فایل نامعتبر است.')));}
}

Future<void> showTxDialog(BuildContext c,DebtStore store,{Tx? edit,String? fixedPerson})async{
  final person=TextEditingController(text:fixedPerson??edit?.person??'');final amount=TextEditingController(text:edit==null?'':money(edit.amount));final note=TextEditingController(text:edit?.note??'');bool lent=edit?.lent??true;TxKind kind=edit?.kind??TxKind.debt;DateTime date=edit?.date??DateTime.now();
  await showDialog(context:c,builder:(_)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:Text(edit==null?'رکورد جدید':'ویرایش: افزودن رکورد جدید'),content:SingleChildScrollView(child:Column(children:[if(fixedPerson==null)TextField(controller:person,decoration:const InputDecoration(labelText:'نام شخص')),TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'مبلغ (افغانی)')),const SizedBox(height:10),SegmentedButton<TxKind>(segments:const[ButtonSegment(value:TxKind.debt,label:Text('قرض')),ButtonSegment(value:TxKind.payment,label:Text('پرداخت'))],selected:{kind},onSelectionChanged:(s)=>setD(()=>kind=s.first)),const SizedBox(height:8),SegmentedButton<bool>(segments:kind==TxKind.debt?const[ButtonSegment(value:true,label:Text('من قرض دادم')),ButtonSegment(value:false,label:Text('من قرض گرفتم'))]:const[ButtonSegment(value:true,label:Text('او پرداخت کرد')),ButtonSegment(value:false,label:Text('من پرداخت کردم'))],selected:{lent},onSelectionChanged:(s)=>setD(()=>lent=s.first)),TextField(controller:note,decoration:const InputDecoration(labelText:'توضیحات (اختیاری)')),ListTile(contentPadding:EdgeInsets.zero,title:const Text('تاریخ'),subtitle:Text(dateText(date)),trailing:const Icon(Icons.calendar_month),onTap:()async{final x=await showDatePicker(context:c,firstDate:DateTime(2000),lastDate:DateTime(2100),initialDate:date);if(x!=null)setD(()=>date=x);})])),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('انصراف')),FilledButton(onPressed:()async{final p=person.text.trim();final a=double.tryParse(amount.text.replaceAll(',','').trim());if(p.isEmpty||a==null||a<=0)return;await store.add(Tx(id:DateTime.now().microsecondsSinceEpoch.toString(),person:p,amount:a,date:date,lent:lent,kind:kind,note:note.text.trim()));if(c.mounted)Navigator.pop(c);},child:Text(edit==null?'ذخیره':'افزودن رکورد جدید'))]})));
}

class PersonPage extends StatelessWidget{final DebtStore store;final String name;const PersonPage(this.store,this.name,{super.key});
  @override Widget build(BuildContext c)=>AnimatedBuilder(animation:store,builder:(_,__) {final txs=store.forPerson(name);final b=store.balance(name);double debts=0,pays=0;for(final t in txs){if(t.kind==TxKind.debt)debts+=t.amount;else pays+=t.amount;}return Scaffold(appBar:AppBar(title:Text(name,style:const TextStyle(fontWeight:FontWeight.bold)),actions:[IconButton(onPressed:()=>showTxDialog(c,store,fixedPerson:name),icon:const Icon(Icons.add_circle_outline))]),body:Column(children:[Card(margin:const EdgeInsets.fromLTRB(12,8,12,10),child:Padding(padding:const EdgeInsets.all(15),child:Column(children:[Row(children:[Expanded(child:sum('مجموع قرض',debts)),Expanded(child:sum('مجموع پرداخت',pays))]),const Divider(),Text(b>0?'او به شما بدهکار است':b<0?'شما به او بدهکار هستید':'حساب تسویه شده',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),Text('${money(b)} افغانی',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:22))]))),Expanded(child:ListView.builder(padding:const EdgeInsets.fromLTRB(12,0,12,20),itemCount:txs.length,itemBuilder:(_,i)=>txCard(c,txs[i])))]);});
  Widget sum(String t,double v)=>Padding(padding:const EdgeInsets.all(5),child:Column(children:[Text(t),Text('${money(v)} افغانی',style:const TextStyle(fontWeight:FontWeight.bold))]));
  Widget txCard(BuildContext c,Tx t){final title=t.kind==TxKind.debt?(t.lent?'قرض دادم':'قرض گرفتم'):(t.lent?'او پرداخت کرد':'من پرداخت کردم');final icon=t.kind==TxKind.debt?(t.lent?Icons.arrow_upward:Icons.arrow_downward):Icons.payments;return Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(leading:CircleAvatar(child:Icon(icon)),title:Text(title,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${dateText(t.date)}${t.note.isEmpty?'':'\n${t.note}'}'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${money(t.amount)} افغانی',style:const TextStyle(fontWeight:FontWeight.bold)),Row(mainAxisSize:MainAxisSize.min,children:[IconButton(tooltip:'ویرایش؛ رکورد جدید اضافه می‌شود',onPressed:()=>showTxDialog(c,store,edit:t,fixedPerson:name),icon:const Icon(Icons.edit,size:19)),IconButton(tooltip:'حذف',onPressed:()=>store.remove(t.id),icon:const Icon(Icons.delete_outline,size:19))])])));}
}
'''
Path('/mnt/data/ghard_v2/lib/main.dart').write_text(main,encoding='utf-8')
# ensure pubspec deps match
cat > /mnt/data/ghard_v2/.github/workflows/build-apk.yml <<'YAML'
name: Build Android APK
on:
  workflow_dispatch:
  push:
    branches: [ "main" ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.35.2'
          channel: stable
          cache: true
      - name: Create standard Android project
        run: |
          rm -rf android
          flutter create --platforms=android .
      - name: Get dependencies
        run: flutter pub get
      - name: Build APK
        run: flutter build apk --release
      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: ghard-app-v2-release
          path: build/app/outputs/flutter-apk/app-release.apk
YAML
cat > /mnt/data/ghard_v2/README.md <<'EOF'
# دفتر قرض نسخه 2

این نسخه برای هر شخص دفتر حساب جداگانه دارد: هر قرض و هر پرداخت با تاریخ و مبلغ به صورت رکورد مستقل ذخیره می‌شود. با ورود به شخص، مجموع قرض، مجموع پرداخت، مانده و اینکه چه کسی بدهکار است نمایش داده می‌شود.

نکته: دکمه «ویرایش» رکورد قبلی را حذف یا تغییر نمی‌دهد؛ فرم را با اطلاعات قبلی باز می‌کند و با ذخیره، یک رکورد جدید به تاریخچه اضافه می‌شود.
